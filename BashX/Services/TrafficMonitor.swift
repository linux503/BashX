import Foundation

struct TrafficSample: Equatable {
    var up: Int64
    var down: Int64
    var at: Date
}

struct ConnectionRow: Identifiable, Equatable {
    let id: String
    let host: String
    let network: String
    let process: String
    let chain: String
    let rule: String
    let upload: Int64
    let download: Int64
    let start: Date?
}

private func trafficInt64(_ any: Any?) -> Int64 {
    if let n = any as? NSNumber { return n.int64Value }
    if let i = any as? Int64 { return i }
    if let i = any as? Int { return Int64(i) }
    if let d = any as? Double { return Int64(d) }
    return 0
}


/// Panel-only rates — separate object so updating badges does not redraw MenuBarExtra.
@MainActor
final class PanelRateStore: ObservableObject {
    /// Adaptive compact rate (e.g. `1.7K`, `12M`) — not mega-only (that stuck at `0.0` for normal browsing).
    @Published private(set) var downMbps = "0.0K"
    @Published private(set) var upMbps = "0.0K"
    @Published private(set) var downTotal: Int64 = 0
    @Published private(set) var upTotal: Int64 = 0
    @Published private(set) var isLive = false
    @Published private(set) var samples: [TrafficSample] = []
    /// Skip chart sample array when panel is closed — saves memory + SwiftUI churn.
    var chartSamplesEnabled = false

    func clear() {
        if downMbps != "0.0K" { downMbps = "0.0K" }
        if upMbps != "0.0K" { upMbps = "0.0K" }
        if downTotal != 0 { downTotal = 0 }
        if upTotal != 0 { upTotal = 0 }
        if isLive { isLive = false }
        if !samples.isEmpty { samples = [] }
    }

    func update(down: Int64, up: Int64, downTotal: Int64, upTotal: Int64, live: Bool) {
        let pd = ByteFormat.menuBarCompact(down)
        let pu = ByteFormat.menuBarCompact(up)
        if downMbps != pd { downMbps = pd }
        if upMbps != pu { upMbps = pu }
        if self.downTotal != downTotal { self.downTotal = downTotal }
        if self.upTotal != upTotal { self.upTotal = upTotal }
        if isLive != live { isLive = live }

        if live, chartSamplesEnabled {
            var next = samples
            next.append(TrafficSample(up: up, down: down, at: Date()))
            if next.count > 28 { next.removeFirst(next.count - 28) }
            samples = next
        }
    }
}

/// Separate from TrafficMonitor so MenuBarExtra label is NOT redrawn when
/// connections/logs publish (that flicker is the status-item bug).
@MainActor
final class MenuBarRateStore: ObservableObject {
    /// Fixed 4-char rates; published together so the status item only redraws once.
    @Published private(set) var menuDown = "0.0K"
    @Published private(set) var menuUp = "0.0K"
    @Published private(set) var help = "BashX · 未连接"
    /// Mirrors core so MenuBarExtra label only observes this store.
    @Published private(set) var coreRunning = false
    /// Observed by panel top bar only (not by menu-bar label).
    let panel = PanelRateStore()
    /// Called after menu-bar strings are committed (objectWillChange fires too early for chrome).
    var onRatesUpdated: (() -> Void)?

    private var lastMenuPublish = Date.distantPast
    private var lastPanelPublish = Date.distantPast

    func setCoreRunning(_ running: Bool) {
        let changed = coreRunning != running
        if changed { coreRunning = running }
        if !running { clearRatesOnly() }
        if changed { onRatesUpdated?() }
    }

    func clear() {
        clearRatesOnly()
        panel.clear()
        onRatesUpdated?()
    }

    private func clearRatesOnly() {
        var changed = false
        if menuDown != "0.0K" || menuUp != "0.0K" {
            menuDown = "0.0K"
            menuUp = "0.0K"
            changed = true
        }
        if help != "BashX · 未连接" {
            help = "BashX · 未连接"
            changed = true
        }
        if changed { onRatesUpdated?() }
    }

    /// Panel ~1Hz via `panel`; menu bar ~0.6s for live ↓/↑.
    func update(down: Int64, up: Int64, downTotal: Int64 = 0, upTotal: Int64 = 0, live: Bool = true, trackPanelChart: Bool = false) {
        let now = Date()
        let hasTraffic = down > 0 || up > 0

        if hasTraffic || now.timeIntervalSince(lastPanelPublish) >= 1.0 {
            lastPanelPublish = now
            panel.chartSamplesEnabled = trackPanelChart
            panel.update(
                down: down,
                up: up,
                downTotal: downTotal,
                upTotal: upTotal,
                live: live
            )
        }

        if !hasTraffic && now.timeIntervalSince(lastMenuPublish) < 0.6 { return }
        if hasTraffic || now.timeIntervalSince(lastMenuPublish) >= 0.6 {
            lastMenuPublish = now
        } else {
            return
        }

        let nd = ByteFormat.menuBarFixed(down)
        let nu = ByteFormat.menuBarFixed(up)
        let h = "下行 \(ByteFormat.menuBarCompact(down))/s · 上行 \(ByteFormat.menuBarCompact(up))/s"
        guard menuDown != nd || menuUp != nu || help != h else { return }
        menuDown = nd
        menuUp = nu
        help = h
        onRatesUpdated?()
    }
}

@MainActor
final class TrafficMonitor: ObservableObject {
    @Published var upRate: Int64 = 0
    @Published var downRate: Int64 = 0
    @Published var upTotal: Int64 = 0
    @Published var downTotal: Int64 = 0
    @Published var samples: [TrafficSample] = []
    @Published var connections: [ConnectionRow] = []
    @Published var logLines: [String] = []
    @Published var isLive = false
    @Published var connectionCount = 0

    /// Updated without republishing this object to App scene.
    weak var menuBarRates: MenuBarRateStore?
    /// When false, skip chart sample array (saves SwiftUI churn while panel is closed / other tab).
    var chartSamplesEnabled = false
    /// True while main panel window is open — enables sidebar traffic chart samples.
    var panelChartEnabled = false

    private var trafficTask: Task<Void, Never>?
    private var lastConnTotals: (up: Int64, down: Int64, at: Date)?
    private var streamFailStreak = 0
    private var connectionsTask: Task<Void, Never>?
    private var logsTask: Task<Void, Never>?
    private var controller = ""
    private var secret = ""
    private let apiSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 3
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
    /// Throttle UI publishes so menu-bar item doesn't flicker/resize every packet.
    private var lastRateUIPublish = Date.distantPast
    private var lastSampleUIPublish = Date.distantPast
    private var pendingUp: Int64 = 0
    private var pendingDown: Int64 = 0
    private var pendingUpTotal: Int64 = 0
    private var pendingDownTotal: Int64 = 0
    private var pendingLogLines: [String] = []
    private var lastLogUIPublish = Date.distantPast

    func configure(controller: String, secret: String) {
        let trimmedController = controller.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = self.controller != trimmedController || self.secret != trimmedSecret
        self.controller = trimmedController
        self.secret = trimmedSecret
        if changed {
            trafficTask?.cancel()
            trafficTask = nil
            lastConnTotals = nil
            streamFailStreak = 0
        }
    }

    func startTraffic() {
        guard !controller.isEmpty else { return }
        if let task = trafficTask, !task.isCancelled { return }
        trafficTask?.cancel()
        trafficTask = nil
        isLive = true
        trafficTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let streamed = await self.runTrafficStream()
                if streamed {
                    self.streamFailStreak = 0
                } else {
                    self.streamFailStreak += 1
                    await self.pollTrafficViaConnections()
                    let backoff = min(2.0 + Double(self.streamFailStreak) * 0.5, 6.0)
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }
    }

    func stopTrafficOnly() {
        trafficTask?.cancel()
        trafficTask = nil
        lastConnTotals = nil
        streamFailStreak = 0
        upRate = 0
        downRate = 0
        menuBarRates?.clear()
        isLive = connectionsTask != nil || logsTask != nil
    }

    func startConnectionsAndLogs() {
        chartSamplesEnabled = true
        startConnections()
        startLogs()
    }

    func stopConnectionsAndLogs() {
        connectionsTask?.cancel()
        connectionsTask = nil
        logsTask?.cancel()
        logsTask = nil
        pendingLogLines.removeAll()
        chartSamplesEnabled = false
    }

    func stopAll() {
        trafficTask?.cancel()
        trafficTask = nil
        stopConnectionsAndLogs()
        isLive = false
    }

    func closeAllConnections() async {
        guard let url = URL(string: "http://\(controller)/connections") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "DELETE"
        applyAuth(&req)
        _ = try? await apiSession.data(for: req)
        await refreshConnectionsOnce()
    }

    func closeConnection(id: String) async {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "http://\(controller)/connections/\(enc)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "DELETE"
        applyAuth(&req)
        _ = try? await apiSession.data(for: req)
        await refreshConnectionsOnce()
    }

    // MARK: - Private

    private func startConnections() {
        guard connectionsTask == nil else { return }
        connectionsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshConnectionsOnce()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func startLogs() {
        guard logsTask == nil else { return }
        logsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runLogStream()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    /// Returns true when at least one valid traffic frame was received.
    private func runTrafficStream() async -> Bool {
        guard let url = URL(string: "http://\(controller)/traffic") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 60)
        applyAuth(&req)
        var received = false
        do {
            let (bytes, response) = try await apiSession.bytes(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return false
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if json["message"] != nil, json["up"] == nil, json["down"] == nil { break }
                let up = trafficInt64(json["up"])
                let down = trafficInt64(json["down"])
                let upT = trafficInt64(json["upTotal"])
                let downT = trafficInt64(json["downTotal"])
                pendingUp = up
                pendingDown = down
                if upT > 0 { pendingUpTotal = upT }
                if downT > 0 { pendingDownTotal = downT }
                publishTrafficUIIfNeeded()
                received = true
            }
        } catch {
            if !Task.isCancelled { isLive = false }
        }
        return received
    }

    /// Fallback when `/traffic` SSE fails (auth mismatch, stream drop, etc.).
    private func pollTrafficViaConnections() async {
        guard let url = URL(string: "http://\(controller)/connections") else { return }
        var req = URLRequest(url: url, timeoutInterval: 4)
        applyAuth(&req)
        do {
            let (data, response) = try await apiSession.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let upT = trafficInt64(json["uploadTotal"])
            let downT = trafficInt64(json["downloadTotal"])
            let now = Date()
            if let last = lastConnTotals {
                let dt = now.timeIntervalSince(last.at)
                if dt >= 0.35 {
                    let upRate = Int64(Double(max(0, upT - last.up)) / dt)
                    let downRate = Int64(Double(max(0, downT - last.down)) / dt)
                    pendingUp = upRate
                    pendingDown = downRate
                    publishTrafficUIIfNeeded(force: true)
                }
            }
            lastConnTotals = (upT, downT, now)
            if upT > 0 { pendingUpTotal = upT }
            if downT > 0 { pendingDownTotal = downT }
            isLive = true
        } catch {
            if !Task.isCancelled { isLive = false }
        }
    }

    private func publishTrafficUIIfNeeded(force: Bool = false) {
        let now = Date()
        // ~2Hz for menu bar; MenuBarRateStore throttles menu digits separately.
        guard force || now.timeIntervalSince(lastRateUIPublish) >= 0.5 else { return }
        lastRateUIPublish = now

        menuBarRates?.update(
            down: pendingDown,
            up: pendingUp,
            downTotal: pendingDownTotal,
            upTotal: pendingUpTotal,
            live: true,
            trackPanelChart: panelChartEnabled
        )

        let publishMonitor = chartSamplesEnabled || connectionsTask != nil || logsTask != nil
        guard publishMonitor else { return }

        if upRate != pendingUp { upRate = pendingUp }
        if downRate != pendingDown { downRate = pendingDown }
        if pendingUpTotal > 0, upTotal != pendingUpTotal { upTotal = pendingUpTotal }
        if pendingDownTotal > 0, downTotal != pendingDownTotal { downTotal = pendingDownTotal }
        if !isLive { isLive = true }

        if now.timeIntervalSince(lastSampleUIPublish) >= 1.0 {
            lastSampleUIPublish = now
            var next = samples
            next.append(TrafficSample(up: pendingUp, down: pendingDown, at: now))
            if next.count > 48 { next.removeFirst(next.count - 48) }
            samples = next
        }
    }

    private func runLogStream() async {
        guard var components = URLComponents(string: "http://\(controller)/logs") else { return }
        components.queryItems = [URLQueryItem(name: "level", value: "info")]
        guard let url = components.url else { return }
        var req = URLRequest(url: url, timeoutInterval: 60)
        applyAuth(&req)
        do {
            let (bytes, _) = try await apiSession.bytes(for: req)
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                var text = trimmed
                if let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = json["payload"] as? String {
                    let type = json["type"] as? String ?? ""
                    text = type.isEmpty ? payload : "[\(type)] \(payload)"
                }
                pendingLogLines.append(text)
                publishLogsIfNeeded(force: pendingLogLines.count >= 40)
            }
        } catch {
            // reconnect loop handles
        }
    }

    private func publishLogsIfNeeded(force: Bool = false) {
        guard !pendingLogLines.isEmpty else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastLogUIPublish) >= 0.5 else { return }
        lastLogUIPublish = now
        var lines = logLines
        lines.append(contentsOf: pendingLogLines)
        pendingLogLines.removeAll(keepingCapacity: true)
        if lines.count > 100 { lines.removeFirst(lines.count - 100) }
        logLines = lines
    }

    private func refreshConnectionsOnce() async {
        guard let url = URL(string: "http://\(controller)/connections") else { return }
        var req = URLRequest(url: url, timeoutInterval: 4)
        applyAuth(&req)
        do {
            let (data, _) = try await apiSession.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if let upT = json["uploadTotal"] as? NSNumber { upTotal = upT.int64Value }
            if let downT = json["downloadTotal"] as? NSNumber { downTotal = downT.int64Value }
            let raw = json["connections"] as? [[String: Any]] ?? []
            connectionCount = raw.count
            let rows: [ConnectionRow] = raw.prefix(80).compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                let meta = item["metadata"] as? [String: Any] ?? [:]
                let host = (meta["host"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (meta["destinationIP"] as? String)
                    ?? "-"
                let port = meta["destinationPort"] as? String ?? ""
                let displayHost = port.isEmpty ? host : "\(host):\(port)"
                let network = (meta["network"] as? String ?? meta["type"] as? String ?? "").uppercased()
                let process = meta["process"] as? String ?? meta["processPath"] as? String ?? ""
                let shortProcess = (process as NSString).lastPathComponent
                let chains = (item["chains"] as? [String]) ?? []
                let chain = chains.reversed().joined(separator: " → ")
                let ruleType = item["rule"] as? String ?? ""
                let rulePayload = item["rulePayload"] as? String ?? ""
                let rule = rulePayload.isEmpty ? ruleType : "\(ruleType)(\(rulePayload))"
                let start: Date? = {
                    guard let s = item["start"] as? String else { return nil }
                    return ISO8601DateFormatter().date(from: s)
                        ?? ISO8601DateFormatter().date(from: s.replacingOccurrences(of: "Z", with: "+0000"))
                }()
                return ConnectionRow(
                    id: id,
                    host: displayHost,
                    network: network,
                    process: shortProcess,
                    chain: chain.isEmpty ? "-" : chain,
                    rule: rule.isEmpty ? "-" : rule,
                    upload: trafficInt64(item["upload"]),
                    download: trafficInt64(item["download"]),
                    start: start
                )
            }
            .sorted { ($0.download + $0.upload) > ($1.download + $1.upload) }
            connections = rows
        } catch {
            // ignore transient errors
        }
    }

    private func applyAuth(_ req: inout URLRequest) {
        if !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
    }
}
