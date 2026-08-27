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


/// Panel-only rates — separate object so updating M/s badges does not redraw MenuBarExtra.
@MainActor
final class PanelRateStore: ObservableObject {
    @Published private(set) var downMbps = "0.0"
    @Published private(set) var upMbps = "0.0"

    func clear() {
        if downMbps != "0.0" { downMbps = "0.0" }
        if upMbps != "0.0" { upMbps = "0.0" }
    }

    func update(down: Int64, up: Int64) {
        let pd = ByteFormat.fixedMegaNumber(down)
        let pu = ByteFormat.fixedMegaNumber(up)
        if downMbps != pd { downMbps = pd }
        if upMbps != pu { upMbps = pu }
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

    private var lastMenuPublish = Date.distantPast
    private var lastPanelPublish = Date.distantPast

    func setCoreRunning(_ running: Bool) {
        if coreRunning != running { coreRunning = running }
        if !running { clearRatesOnly() }
    }

    func clear() {
        clearRatesOnly()
        panel.clear()
    }

    private func clearRatesOnly() {
        if menuDown != "0.0K" || menuUp != "0.0K" {
            menuDown = "0.0K"
            menuUp = "0.0K"
        }
        if help != "BashX · 未连接" { help = "BashX · 未连接" }
    }

    /// Panel ~1Hz via `panel`; menu bar ~0.8s so status item feels live without jitter.
    func update(down: Int64, up: Int64) {
        let now = Date()

        if now.timeIntervalSince(lastPanelPublish) >= 1.0 {
            lastPanelPublish = now
            panel.update(down: down, up: up)
        }

        guard now.timeIntervalSince(lastMenuPublish) >= 0.8 else { return }
        lastMenuPublish = now

        let nd = ByteFormat.menuBarFixed(down)
        let nu = ByteFormat.menuBarFixed(up)
        let h = "下行 \(ByteFormat.menuBarCompact(down))/s · 上行 \(ByteFormat.menuBarCompact(up))/s"
        guard menuDown != nd || menuUp != nu || help != h else { return }
        menuDown = nd
        menuUp = nu
        help = h
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

    private var trafficTask: Task<Void, Never>?
    private var connectionsTask: Task<Void, Never>?
    private var logsTask: Task<Void, Never>?
    private var controller = ""
    private var secret = ""
    private let apiSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 6
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
        let changed = self.controller != controller || self.secret != secret
        self.controller = controller
        self.secret = secret
        if changed {
            trafficTask?.cancel()
            trafficTask = nil
        }
    }

    func startTraffic() {
        guard !controller.isEmpty else { return }
        if trafficTask != nil { return }
        isLive = true
        trafficTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runTrafficStream()
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func stopTrafficOnly() {
        trafficTask?.cancel()
        trafficTask = nil
        upRate = 0
        downRate = 0
        menuBarRates?.clear()
        isLive = connectionsTask != nil || logsTask != nil
    }

    func startConnectionsAndLogs() {
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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

    private func runTrafficStream() async {
        let controller = controller
        let secret = secret
        await Task.detached(priority: .utility) { [weak self] in
            guard let url = URL(string: "http://\(controller)/traffic") else { return }
            var req = URLRequest(url: url, timeoutInterval: 60)
            if !secret.isEmpty {
                req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
            let session = URLSession(configuration: .ephemeral)
            do {
                let (bytes, _) = try await session.bytes(for: req)
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let up = trafficInt64(json["up"])
                    let down = trafficInt64(json["down"])
                    let upT = trafficInt64(json["upTotal"])
                    let downT = trafficInt64(json["downTotal"])
                    await MainActor.run {
                        guard let self else { return }
                        self.pendingUp = up
                        self.pendingDown = down
                        if upT > 0 { self.pendingUpTotal = upT }
                        if downT > 0 { self.pendingDownTotal = downT }
                        self.publishTrafficUIIfNeeded()
                    }
                }
            } catch {
                await MainActor.run { self?.isLive = false }
            }
        }.value
    }

    private func publishTrafficUIIfNeeded() {
        let now = Date()
        // ~1.2Hz for panel; menu bar throttles separately inside MenuBarRateStore.
        guard now.timeIntervalSince(lastRateUIPublish) >= 0.85 else { return }
        lastRateUIPublish = now

        menuBarRates?.update(down: pendingDown, up: pendingUp)

        guard chartSamplesEnabled else { return }

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
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
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
