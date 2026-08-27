import Foundation
import NetworkExtension
import Combine
import UIKit
import Darwin
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?
    @Published private(set) var conflictVPNHint: String?
    @Published private(set) var uploadBytes: Int64 = 0
    @Published private(set) var downloadBytes: Int64 = 0
    @Published private(set) var uploadRate: Int64 = 0
    @Published private(set) var downloadRate: Int64 = 0
    @Published private(set) var trafficSamples: [TrafficSample] = []
    @Published private(set) var connectedSince: Date?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var trafficTask: Task<Void, Never>?
    private var connectWatchTask: Task<Void, Never>?
    private var lastTrafficTotals: (up: Int64, down: Int64, at: Date)?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let conn = note.object as? NEVPNConnection else { return }
            Task { @MainActor in
                self?.status = conn.status
                self?.updateConnectedSince(for: conn.status)
                self?.syncTrafficPolling()
                if conn.status == .connected || conn.status == .disconnected || conn.status == .invalid {
                    self?.connectWatchTask?.cancel()
                    self?.connectWatchTask = nil
                }
                VPNQuickControl.reloadControlWidget()
            }
        }
        Task { await reload() }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        trafficTask?.cancel()
    }

    var isConnected: Bool {
        status == .connected
    }

    var isBusyConnecting: Bool {
        status == .connecting || status == .reasserting || status == .disconnecting
    }

    var statusText: String {
        switch status {
        case .invalid: return L10n.t("vpn.disconnected")
        case .disconnected: return L10n.t("vpn.disconnected")
        case .connecting: return L10n.t("vpn.connecting")
        case .connected: return L10n.t("vpn.connected")
        case .reasserting: return L10n.t("vpn.reconnecting")
        case .disconnecting: return L10n.t("vpn.disconnecting")
        @unknown default: return L10n.t("vpn.unknown")
        }
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == AppConstants.tunnelBundleIdentifier
            }) ?? managers.first {
                manager = existing
                status = existing.connection.status
                updateConnectedSince(for: status)
            } else {
                manager = nil
                status = .invalid
                connectedSince = nil
            }
            syncTrafficPolling()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func ensureManager() async throws -> NETunnelProviderManager {
        if let manager { return manager }
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == AppConstants.tunnelBundleIdentifier
        }) ?? managers.first {
            manager = existing
            return existing
        }
        let created = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
        proto.serverAddress = "BashX"
        proto.providerConfiguration = ["appGroup": AppConstants.appGroupIdentifier]
        Self.applyExclusiveProtocolOptions(proto)
        created.protocolConfiguration = proto
        created.localizedDescription = "BashX"
        created.isEnabled = true
        try await created.saveToPreferences()
        try await created.loadFromPreferences()
        manager = created
        return created
    }

    func connect() async {
        lastError = nil
        conflictVPNHint = nil
        do {
            if let issue = MihomoConfigCheck.preflight() {
                lastError = issue
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // Stop other VPN profiles we can reach, then claim the tunnel.
            let foreign = await Self.prepareExclusiveTunnel()
            if let foreign {
                conflictVPNHint = foreign
            }
            if let name = SettingsStore.load().selectedNodeName, !name.isEmpty {
                UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                    .set(name, forKey: "selectedNode")
            }
            let mgr = try await ensureManager()
            mgr.isEnabled = true
            if let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol {
                Self.applyExclusiveProtocolOptions(proto)
                mgr.protocolConfiguration = proto
            }
            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()
            try mgr.connection.startVPNTunnel()
            status = mgr.connection.status
            beginConnectWatch()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            syncTrafficPolling()
        } catch {
            lastError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Disconnect personal VPN + duplicate BashX managers; return a user hint if another VPN IF remains.
    private static func prepareExclusiveTunnel() async -> String? {
        // 1) System personal VPN (IKEv2 / IPSec profiles the user added in Settings).
        let personal = NEVPNManager.shared()
        do {
            try await personal.loadFromPreferences()
            let st = personal.connection.status
            if st == .connected || st == .connecting || st == .reasserting {
                personal.connection.stopVPNTunnel()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            if personal.isEnabled {
                personal.isEnabled = false
                try? await personal.saveToPreferences()
            }
        } catch {
            // Ignore — may be empty profile.
        }

        // 2) Our Packet Tunnel managers: keep one BashX, stop extras / disable orphans.
        if let managers = try? await NETunnelProviderManager.loadAllFromPreferences() {
            var kept: NETunnelProviderManager?
            for mgr in managers {
                let bid = (mgr.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier
                let isOurs = bid == AppConstants.tunnelBundleIdentifier
                if isOurs {
                    if kept == nil {
                        kept = mgr
                        continue
                    }
                }
                // Extra / foreign-looking manager in our sandbox — tear down.
                if mgr.connection.status == .connected
                    || mgr.connection.status == .connecting
                    || mgr.connection.status == .reasserting {
                    mgr.connection.stopVPNTunnel()
                }
                if mgr.isEnabled {
                    mgr.isEnabled = false
                    try? await mgr.saveToPreferences()
                }
            }
        }

        try? await Task.sleep(nanoseconds: 350_000_000)

        // 3) Detect leftover VPN interfaces we cannot stop (other apps). iOS forbids killing them.
        if hasForeignVPNInterface() {
            return L10n.t("vpn.otherVpn")
        }
        return nil
    }

    private static func applyExclusiveProtocolOptions(_ proto: NETunnelProviderProtocol) {
        proto.serverAddress = "BashX"
        proto.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
        // Do NOT set includeAllNetworks — it re-captures mihomo DIRECT/DoH dials into utun
        // (baidu DIAG jumped from ~50ms to 4.5s; core down≈0). Default IPv4 default-route is enough.
        if #available(iOS 14.2, *) {
            proto.includeAllNetworks = false
            proto.excludeLocalNetworks = true
        }
    }

    /// Heuristic: multiple utun / ipsec interfaces with non-BashX addresses while disconnected from us.
    private static func hasForeignVPNInterface() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }
        var vpnNames: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") else { continue }
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = String(cString: host)
            // Our tunnel uses 198.18.0.1; Apple system utuns often use 192.0.0.6 — ignore those.
            if ip.hasPrefix("198.18.") || ip.hasPrefix("192.0.0.") || ip.hasPrefix("127.")
                || ip.hasPrefix("169.254.") {
                continue
            }
            vpnNames.append("\(name)=\(ip)")
        }
        // Leftover utun/ipsec with a routable address → likely WireGuard / another client.
        return !vpnNames.isEmpty
    }

    private func beginConnectWatch() {
        connectWatchTask?.cancel()
        connectWatchTask = Task { [weak self] in
            for tick in 0..<50 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let s = self.status
                if s == .connected {
                    await MainActor.run { self.lastError = nil }
                    return
                }
                if s == .disconnected || s == .invalid {
                    await MainActor.run {
                        if self.lastError == nil {
                            self.lastError = TunnelLogReader.lastErrorHint()
                                ?? MihomoConfigCheck.validateFile()
                                ?? L10n.t("vpn.fail")
                        }
                    }
                    return
                }
                if tick >= 44 {
                    await MainActor.run {
                        self.lastError = TunnelLogReader.lastErrorHint() ?? L10n.t("vpn.timeout")
                    }
                    self.disconnect()
                    return
                }
            }
        }
    }

    func disconnect() {
        connectWatchTask?.cancel()
        connectWatchTask = nil
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnected
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        syncTrafficPolling()
    }

    func toggle() async {
        if status == .connected || status == .connecting || status == .reasserting {
            disconnect()
        } else {
            await connect()
        }
    }

    func selectNode(_ name: String) async {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(name, forKey: "selectedNode")
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else { return }
        let payload: [String: Any] = ["action": "select_node", "node": name]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? session.sendProviderMessage(data) { _ in }
    }

    /// Select a member inside GOOGLE / TELEGRAM / AUTO / PROXY (hot while tunnel is up).
    func selectGroupProxy(group: String, name: String) async {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else { return }
        let payload: [String: Any] = ["action": "select_group", "group": group, "node": name]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? session.sendProviderMessage(data) { _ in }
    }

    struct ProxyGroupSnapshot: Identifiable, Equatable, Sendable {
        var id: String { name }
        var name: String
        var now: String
        var all: [String]
    }

    /// Snapshot GOOGLE / TELEGRAM / AUTO from the NE (mihomo API).
    func fetchProxyGroups() async -> [ProxyGroupSnapshot] {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession,
              let payload = try? JSONSerialization.data(withJSONObject: ["action": "get_proxy_groups"]) else {
            return []
        }
        let raw: Data? = await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(payload) { data in
                    cont.resume(returning: data)
                }
            } catch {
                cont.resume(returning: nil)
            }
        }
        guard let raw,
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let rows = json["groups"] as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { row in
            guard let name = row["name"] as? String,
                  let all = row["all"] as? [String],
                  !all.isEmpty else { return nil }
            return ProxyGroupSnapshot(
                name: name,
                now: row["now"] as? String ?? "",
                all: all
            )
        }
    }

    /// Hot-patch Clash mode while tunnel is up (rule / global / direct).
    func setProxyMode(_ mode: String) {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else { return }
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(mode, forKey: "proxyMode")
        let payload: [String: Any] = ["action": "set_mode", "mode": mode]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? session.sendProviderMessage(data) { _ in }
    }

    var connectionDuration: TimeInterval {
        guard let connectedSince, isConnected else { return 0 }
        return Date().timeIntervalSince(connectedSince)
    }

    private func updateConnectedSince(for status: NEVPNStatus) {
        switch status {
        case .connected:
            if connectedSince == nil { connectedSince = Date() }
        case .disconnected, .invalid:
            connectedSince = nil
        default:
            break
        }
    }

    func reconnect() async {
        guard isConnected || status == .connecting else {
            await connect()
            return
        }
        disconnect()
        try? await Task.sleep(nanoseconds: 600_000_000)
        await connect()
    }

    private func syncTrafficPolling() {
        trafficTask?.cancel()
        guard status == .connected else {
            clearTrafficHistory()
            return
        }
        trafficTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTraffic()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func clearTrafficHistory() {
        uploadBytes = 0
        downloadBytes = 0
        uploadRate = 0
        downloadRate = 0
        trafficSamples = []
        lastTrafficTotals = nil
        connectedSince = nil
    }

    private func recordTrafficTotals(up: Int64, down: Int64) {
        let now = Date()
        if let last = lastTrafficTotals {
            let dt = now.timeIntervalSince(last.at)
            if dt >= 0.35 {
                let upRate = Int64(Double(max(0, up - last.up)) / dt)
                let downRate = Int64(Double(max(0, down - last.down)) / dt)
                uploadRate = upRate
                downloadRate = downRate

                var next = trafficSamples
                next.append(TrafficSample(up: upRate, down: downRate, at: now))
                if next.count > 48 { next.removeFirst(next.count - 48) }
                trafficSamples = next
            }
        }
        lastTrafficTotals = (up, down, now)
        uploadBytes = up
        downloadBytes = down
    }

    func fetchOutboundIPViaTunnel() async -> String? {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else { return nil }
        let payload = try? JSONSerialization.data(withJSONObject: ["action": "get_outbound_ip"])
        guard let payload else { return nil }
        return await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(payload) { data in
                    guard let data,
                          let ip = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !ip.isEmpty else {
                        cont.resume(returning: nil)
                        return
                    }
                    cont.resume(returning: ip)
                }
            } catch {
                cont.resume(returning: nil)
            }
        }
    }

    /// Live tunnel.log from the Network Extension (falls back to App Group file).
    func fetchTunnelLog() async -> String? {
        if status == .connected,
           let session = manager?.connection as? NETunnelProviderSession,
           let payload = try? JSONSerialization.data(withJSONObject: ["action": "get_log"]) {
            let live: String? = await withCheckedContinuation { cont in
                do {
                    try session.sendProviderMessage(payload) { data in
                        guard let data,
                              let text = String(data: data, encoding: .utf8),
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            cont.resume(returning: nil)
                            return
                        }
                        cont.resume(returning: text)
                    }
                } catch {
                    cont.resume(returning: nil)
                }
            }
            if let live { return live }
        }
        let disk = TunnelLogReader.lastLines()
        return disk.isEmpty ? nil : disk
    }

    private func refreshTraffic() async {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let payload = try? JSONSerialization.data(withJSONObject: ["action": "get_traffic"])
        guard let payload else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            do {
                try session.sendProviderMessage(payload) { [weak self] data in
                    defer { cont.resume() }
                    guard let data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                    let up = Self.int64Value(json["upload"])
                    let down = Self.int64Value(json["download"])
                    Task { @MainActor in
                        self?.recordTrafficTotals(up: up, down: down)
                    }
                }
            } catch {
                cont.resume()
            }
        }
    }

    private static func int64Value(_ any: Any?) -> Int64 {
        if let n = any as? NSNumber { return n.int64Value }
        if let i = any as? Int64 { return i }
        if let i = any as? Int { return Int64(i) }
        if let d = any as? Double { return Int64(d) }
        if let s = any as? String, let i = Int64(s) { return i }
        return 0
    }

    /// VPN 已连接：优先走 NE 内 mihomo `/proxies/{group}/delay`（与节点测速同路径）；失败再回退 URLSession。
    /// 未连接：直连探测（国内可测百度；Google/TG 等预期可能失败）。
    func probeWebsites(
        targets: [WebsiteProbe.Target] = WebsiteProbe.defaults,
        timeoutMs: Int = 10_000
    ) async -> [String: WebsiteProbe.Status] {
        let timeout = TimeInterval(max(timeoutMs, 1000)) / 1000
        guard status == .connected else {
            return await WebsiteProbe.probeAllDirect(targets: targets, timeout: timeout)
        }

        if let viaTunnel = await probeWebsitesViaTunnel(targets: targets, timeoutMs: timeoutMs),
           !viaTunnel.isEmpty {
            var merged = viaTunnel
            let needFallback = targets.filter { target in
                guard let status = merged[target.id] else { return true }
                if case .fail = status { return true }
                return false
            }
            if !needFallback.isEmpty {
                let fallback = await WebsiteProbe.probeAllViaVPN(targets: needFallback, timeout: timeout)
                for (id, status) in fallback {
                    if case .ok = status {
                        merged[id] = status
                    } else if merged[id] == nil {
                        merged[id] = status
                    }
                }
            }
            return merged
        }
        return await WebsiteProbe.probeAllViaVPN(targets: targets, timeout: timeout)
    }

    private func probeWebsitesViaTunnel(
        targets: [WebsiteProbe.Target],
        timeoutMs: Int
    ) async -> [String: WebsiteProbe.Status]? {
        guard let session = manager?.connection as? NETunnelProviderSession,
              let payload = try? JSONSerialization.data(
                withJSONObject: WebsiteProbe.payloadForTunnel(targets: targets, timeoutMs: timeoutMs)
              ) else {
            return nil
        }
        let data: Data? = await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(payload) { response in
                    cont.resume(returning: response)
                }
            } catch {
                cont.resume(returning: nil)
            }
        }
        guard let data else { return nil }
        let parsed = WebsiteProbe.parseTunnelResponse(data)
        return parsed.isEmpty ? nil : parsed
    }
}
