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
    static let profileDisplayName = "Apple"
    static let profileServerAddress = "Apple Inc."
    private static let userWantsConnectedKey = "vpnUserWantsConnected"

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
    private var reconnectTask: Task<Void, Never>?
    private var userInitiatedDisconnect = false
    /// Soft reconnect is stopping the tunnel on purpose — do not treat as unexpected drop.
    private var softRestartInProgress = false
    private var reconnectAttempt = 0
    /// Cooldown so on-demand + app reconnect cannot thrash the tunnel.
    private var lastAutoReconnectAt: Date = .distantPast
    private var lastTrafficTotals: (up: Int64, down: Int64, at: Date)?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let conn = note.object as? NEVPNConnection else { return }
            Task { @MainActor in
                guard let self else { return }
                // CRITICAL: NEVPNStatusDidChange fires for EVERY VPN (IKEv2 / other apps).
                // Ignoring foreign sessions prevents false "drop → reconnect" loops.
                if let ours = self.manager?.connection, conn !== ours {
                    return
                }
                let previous = self.status
                self.status = conn.status
                self.updateConnectedSince(for: conn.status)
                self.syncTrafficPolling()
                if conn.status == .connected || conn.status == .disconnected || conn.status == .invalid {
                    self.connectWatchTask?.cancel()
                    self.connectWatchTask = nil
                }
                // Unexpected drop after we were up (connected or reasserting).
                let wasUp = previous == .connected || previous == .reasserting
                if wasUp,
                   conn.status == .disconnected || conn.status == .invalid {
                    let soft = self.softRestartInProgress
                    if !soft,
                       self.lastError == nil,
                       let hint = TunnelDiagnostics.lastFailureMessage(), !hint.isEmpty {
                        self.lastError = hint
                    }
                    if !soft, !self.userInitiatedDisconnect {
                        self.scheduleAutoReconnect()
                    }
                    if !soft {
                        self.userInitiatedDisconnect = false
                    }
                }
                if conn.status == .connected {
                    self.lastError = nil
                    self.reconnectAttempt = 0
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

    /// Soft busy: only connecting/reasserting — UI can still cancel.
    var isConnectingOrReasserting: Bool {
        status == .connecting || status == .reasserting
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
                let active = status == .connected || status == .connecting
                    || status == .reasserting || status == .disconnecting
                // Saving protocol prefs while the tunnel is up can make iOS tear it down
                // and restart — looks like frequent disconnect/reconnect.
                if !active, refreshProfileMetadata(existing) {
                    try? await existing.saveToPreferences()
                }
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
            _ = refreshProfileMetadata(existing)
            return existing
        }
        let created = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
        proto.serverAddress = Self.profileServerAddress
        proto.providerConfiguration = ["appGroup": AppConstants.appGroupIdentifier]
        Self.applyExclusiveProtocolOptions(proto)
        created.protocolConfiguration = proto
        created.localizedDescription = Self.profileDisplayName
        created.isEnabled = true
        try await created.saveToPreferences()
        try await created.loadFromPreferences()
        manager = created
        return created
    }

    /// User explicitly wants VPN up — cleared on manual disconnect.
    static func userWantsConnection() -> Bool {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .bool(forKey: userWantsConnectedKey) ?? false
    }

    private func setUserWantsConnection(_ wants: Bool) {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(wants, forKey: Self.userWantsConnectedKey)
    }

    /// Reconnect after foreground / unexpected drop when the user had VPN enabled.
    func recoverIfNeeded() async {
        guard Self.userWantsConnection(), !isConnected, !isBusyConnecting else { return }
        let onDemand = manager?.isOnDemandEnabled == true || SettingsStore.load().iosOnDemandEnabled
        if onDemand {
            // On-Demand alone often leaves a stuck state: wantsConnected=true, tunnel
            // down, lastStop=user (Control Center / profile rewrite / brief NE bounce).
            // iOS may never re-arm — nudge connect() once after a short cooldown.
            let stopLabel = (TunnelDiagnostics.lastStopLabel() ?? "").lowercased()
            let successAt = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .double(forKey: "lastTunnelSuccessAt") ?? 0
            let downFor = successAt > 0
                ? Date().timeIntervalSince1970 - successAt
                : 60
            let stuck = stopLabel == "user" || stopLabel.isEmpty || downFor >= 8
            guard stuck, Date().timeIntervalSince(lastAutoReconnectAt) >= 6 else { return }
            lastAutoReconnectAt = Date()
        }
        await connect()
    }

    private func refreshProfileMetadata(_ mgr: NETunnelProviderManager) -> Bool {
        var changed = false
        if mgr.localizedDescription != Self.profileDisplayName {
            mgr.localizedDescription = Self.profileDisplayName
            changed = true
        }
        if let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol {
            let oldServer = proto.serverAddress
            let oldIncludeAll: Bool = {
                if #available(iOS 14.2, *) { return proto.includeAllNetworks }
                return false
            }()
            // applyExclusiveProtocolOptions already sets the correct serverAddress
            // (real node host when Telegram push / includeAllNetworks is on).
            // Never force "Apple Inc." — that loops node dials into utun and drops VPN.
            Self.applyExclusiveProtocolOptions(proto)
            mgr.protocolConfiguration = proto
            let newIncludeAll: Bool = {
                if #available(iOS 14.2, *) { return proto.includeAllNetworks }
                return false
            }()
            if oldServer != proto.serverAddress || oldIncludeAll != newIncludeAll {
                changed = true
            }
        }
        return changed
    }

    private func applyOnDemand(to mgr: NETunnelProviderManager, enabled: Bool) {
        if enabled {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            mgr.onDemandRules = [rule]
            mgr.isOnDemandEnabled = true
        } else {
            mgr.onDemandRules = []
            mgr.isOnDemandEnabled = false
        }
    }

    func connect() async {
        lastError = nil
        userInitiatedDisconnect = false
        reconnectTask?.cancel()
        connectWatchTask?.cancel()
        connectWatchTask = nil
        conflictVPNHint = nil
        // Fresh user connect — reset failure budget so we don't inherit a give-up state.
        if reconnectAttempt >= 3 {
            reconnectAttempt = 0
        }
        do {
            #if os(iOS)
            let prepared = IOSConfigWriter.prepareForConnect()
            if !prepared {
                lastError = MihomoConfigCheck.preflight()
                    ?? "请先更新订阅后再连接"
                setUserWantsConnection(false)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            #endif
            if let issue = MihomoConfigCheck.preflight() {
                lastError = issue
                setUserWantsConnection(false)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // Stop other VPN profiles we can reach, then claim the tunnel.
            let foreign = await Self.prepareExclusiveTunnel()
            if let foreign {
                conflictVPNHint = foreign
            }
            // prepareForConnect already wrote the resolved leaf into App Group.
            // Do NOT re-apply settings.selectedNodeName here — it can be a stale
            // "懒人" name that was remapped, and would poison PROXY again.
            Self.syncSelectedNodeServerToDefaults()
            let mgr = try await ensureManager()
            mgr.isEnabled = true
            if let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol {
                Self.applyExclusiveProtocolOptions(proto)
                mgr.protocolConfiguration = proto
            }
            _ = refreshProfileMetadata(mgr)
            // On-demand only when user opted in — always-on Connect caused fail/retry storms.
            let onDemand = SettingsStore.load().iosOnDemandEnabled
            applyOnDemand(to: mgr, enabled: onDemand)
            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()
            try mgr.connection.startVPNTunnel()
            setUserWantsConnection(true)
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.set(onDemand, forKey: "iosOnDemandEnabled")
            status = mgr.connection.status
            beginConnectWatch()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            syncTrafficPolling()
        } catch {
            lastError = error.localizedDescription
            setUserWantsConnection(false)
            if let mgr = manager {
                applyOnDemand(to: mgr, enabled: false)
                Task { try? await mgr.saveToPreferences() }
            }
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
        proto.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
        proto.disconnectOnSleep = false

        let wantPush = telegramPushEnabledFromDefaults()
        let nodeServer = selectedNodeServerFromDefaults()
        // includeAllNetworks requires a literal IP that iOS can exclude from the tunnel.
        // Hostnames (e.g. oss-xxx.com) often fail exclusion → dials loop into utun →
        // no network → jetsam/On-Demand flap (looks like auto-disconnect).
        let literalIP = nodeServer.flatMap { Self.literalIPAddress($0) }
        let canIncludeAll = wantPush && literalIP != nil
        if canIncludeAll, let literalIP {
            proto.serverAddress = literalIP
        } else {
            proto.serverAddress = profileServerAddress
        }

        if #available(iOS 14.2, *) {
            proto.includeAllNetworks = canIncludeAll
            proto.excludeLocalNetworks = true
        }
        if #available(iOS 16.4, *) {
            // excludeAPNs only applies when includeAllNetworks is true.
            proto.excludeAPNs = !canIncludeAll
            proto.excludeCellularServices = true
        }
        if #available(iOS 17.4, *) {
            proto.excludeDeviceCommunication = true
        }
    }

    /// True only for IPv4/IPv6 literals suitable as NE serverAddress exclusions.
    private static func literalIPAddress(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        if s.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 { return s }
        if s.withCString({ inet_pton(AF_INET6, $0, &sin6.sin6_addr) }) == 1 { return s }
        return nil
    }

    /// App Group / settings: Telegram message push (include APNs in tunnel).
    private static func telegramPushEnabledFromDefaults() -> Bool {
        let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if ud?.object(forKey: AppConstants.iosTelegramPushKey) != nil {
            return ud?.bool(forKey: AppConstants.iosTelegramPushKey) ?? true
        }
        return SettingsStore.load().iosTelegramPushEnabled
    }

    private static func selectedNodeServerFromDefaults() -> String? {
        let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if let s = ud?.string(forKey: AppConstants.selectedNodeServerKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return syncSelectedNodeServerToDefaults()
    }

    /// Resolve selected node host/IP into App Group (needed before includeAllNetworks connect).
    @discardableResult
    static func syncSelectedNodeServerToDefaults() -> String? {
        let settings = SettingsStore.load()
        guard let name = settings.selectedNodeName, !name.isEmpty else {
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .removeObject(forKey: AppConstants.selectedNodeServerKey)
            return nil
        }
        for sub in settings.subscriptions where sub.enabled {
            let url = Paths.subscriptionCacheURL(id: sub.id)
            guard let data = try? Data(contentsOf: url),
                  let parsed = try? ClashConfigParser.parse(data),
                  let node = parsed.nodes.first(where: { $0.name == name }),
                  !node.server.isEmpty else { continue }
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(node.server, forKey: AppConstants.selectedNodeServerKey)
            return node.server
        }
        return UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: AppConstants.selectedNodeServerKey)
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
            // Fail fast: 35s is enough for NE + mihomo; longer feels like a dead loop.
            for tick in 0..<40 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let s = self.status
                if s == .connected {
                    await MainActor.run {
                        self.lastError = nil
                        self.reconnectAttempt = 0
                    }
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
                    // On-Demand will re-arm; app-side reconnect races it.
                    let onDemand = self.manager?.isOnDemandEnabled == true
                        || SettingsStore.load().iosOnDemandEnabled
                    if !onDemand, Self.userWantsConnection(), !self.userInitiatedDisconnect {
                        self.scheduleAutoReconnect()
                    }
                    return
                }
                if tick >= 35 {
                    await MainActor.run {
                        self.lastError = TunnelLogReader.lastErrorHint() ?? L10n.t("vpn.timeout")
                    }
                    self.connectWatchTask?.cancel()
                    self.connectWatchTask = nil
                    // Give up this attempt cleanly — disable on-demand so system doesn't re-arm.
                    await self.abortConnectingAttempt(scheduleRetry: true)
                    return
                }
            }
        }
    }

    /// Stop a stuck connecting state without looking like a user disconnect (unless giving up).
    private func abortConnectingAttempt(scheduleRetry: Bool) async {
        if let mgr = manager {
            applyOnDemand(to: mgr, enabled: false)
            try? await mgr.saveToPreferences()
            mgr.connection.stopVPNTunnel()
        }
        // Wait until NE leaves connecting/disconnecting so reconnect isn't a no-op.
        for _ in 0..<20 {
            if status == .disconnected || status == .invalid { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let st = manager?.connection.status {
                status = st
            }
        }
        if scheduleRetry, Self.userWantsConnection(), !userInitiatedDisconnect {
            scheduleAutoReconnect()
        }
    }

    func disconnect() {
        userInitiatedDisconnect = true
        setUserWantsConnection(false)
        reconnectTask?.cancel()
        connectWatchTask?.cancel()
        connectWatchTask = nil
        reconnectAttempt = 0
        if let mgr = manager {
            applyOnDemand(to: mgr, enabled: false)
            Task {
                try? await mgr.saveToPreferences()
            }
        }
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnected
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        syncTrafficPolling()
    }

    /// Sync on-demand rules with settings without starting/stopping the tunnel.
    func syncOnDemandPreference(enabled: Bool) async {
        var mgr = manager
        if mgr == nil {
            mgr = try? await ensureManager()
        }
        guard let mgr else { return }
        if isConnected || isBusyConnecting {
            applyOnDemand(to: mgr, enabled: enabled)
        } else {
            applyOnDemand(to: mgr, enabled: false)
        }
        try? await mgr.saveToPreferences()
    }

    /// Apply Telegram push (APNs-in-tunnel) preference; reconnect if already connected.
    func syncTelegramPushPreference(enabled: Bool) async {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(enabled, forKey: AppConstants.iosTelegramPushKey)
        var mgr = manager
        if mgr == nil {
            mgr = try? await ensureManager()
        }
        guard let mgr else { return }
        if let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol {
            Self.applyExclusiveProtocolOptions(proto)
            mgr.protocolConfiguration = proto
        }
        try? await mgr.saveToPreferences()
        try? await mgr.loadFromPreferences()
        if status == .connected || status == .connecting || status == .reasserting {
            await reconnect()
        }
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

    /// Select a member inside strategy groups (GOOGLE / TELEGRAM / AUTO / AI / regions).
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

    /// Snapshot strategy groups from the NE (same order as Mac menu bar).
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
        guard isConnected || status == .connecting || status == .reasserting else {
            await connect()
            return
        }
        // Soft restart — do NOT call disconnect() (it clears userWants + on-demand → VPN stays off).
        reconnectTask?.cancel()
        connectWatchTask?.cancel()
        connectWatchTask = nil
        userInitiatedDisconnect = false
        softRestartInProgress = true
        setUserWantsConnection(true)
        defer { softRestartInProgress = false }
        if let mgr = manager {
            applyOnDemand(to: mgr, enabled: SettingsStore.load().iosOnDemandEnabled)
            if let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol {
                Self.applyExclusiveProtocolOptions(proto)
                mgr.protocolConfiguration = proto
            }
            try? await mgr.saveToPreferences()
            mgr.connection.stopVPNTunnel()
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        await connect()
    }

    private func scheduleAutoReconnect() {
        reconnectTask?.cancel()
        guard Self.userWantsConnection() else { return }
        guard !softRestartInProgress, !userInitiatedDisconnect else { return }
        let stopLabel = (TunnelDiagnostics.lastStopLabel() ?? "").lowercased()
        // App disconnect() clears wantsConnected. A "user" stop with wants still true
        // usually means Control Center / Settings / profile bounce — do not give up.
        if stopLabel.contains("superced") {
            return
        }
        if stopLabel == "user", userInitiatedDisconnect {
            return
        }
        // On-Demand already tells iOS to bring the tunnel back. App-side connect()
        // racing it is the main "连上又断、断了又连" loop — unless we're already stuck
        // disconnected with wantsConnected (On-Demand never fired).
        if manager?.isOnDemandEnabled == true || SettingsStore.load().iosOnDemandEnabled {
            let successAt = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .double(forKey: "lastTunnelSuccessAt") ?? 0
            let downFor = successAt > 0
                ? Date().timeIntervalSince1970 - successAt
                : 60
            if downFor < 12 {
                return
            }
        }
        let now = Date()
        if now.timeIntervalSince(lastAutoReconnectAt) < 8 {
            return
        }
        reconnectAttempt = min(reconnectAttempt + 1, 6)
        // Cap retries — endless connecting is worse than asking the user to tap again.
        if reconnectAttempt >= 3 {
            setUserWantsConnection(false)
            if let mgr = manager {
                applyOnDemand(to: mgr, enabled: false)
                Task { try? await mgr.saveToPreferences() }
            }
            if lastError == nil {
                lastError = TunnelLogReader.lastErrorHint() ?? L10n.t("vpn.fail")
            }
            return
        }
        lastAutoReconnectAt = now
        let base: UInt64 = {
            if stopLabel == "sleep" || stopLabel == "idletimeout" || stopLabel == "nonetwork" {
                return 2_000_000_000
            }
            if stopLabel.contains("providerfailed") || stopLabel.contains("connectionfailed") {
                return 4_000_000_000
            }
            return 2_500_000_000
        }()
        let delay = base * UInt64(max(1, reconnectAttempt))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: min(delay, 15_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard !self.userInitiatedDisconnect, Self.userWantsConnection() else { return }
            guard !self.softRestartInProgress else { return }
            // Wait out disconnecting so we don't no-op on isBusyConnecting.
            for _ in 0..<25 {
                if !self.isBusyConnecting { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            // Re-read from NE — stale @Published status caused phantom reconnects.
            if let live = self.manager?.connection.status {
                self.status = live
            }
            guard !self.isConnected, !self.isBusyConnecting else { return }
            guard !self.userInitiatedDisconnect, Self.userWantsConnection() else { return }
            await self.connect()
        }
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
                let interval: UInt64 = {
                    #if os(iOS)
                    return UIApplication.shared.applicationState == .active
                        ? 1_000_000_000
                        : 3_000_000_000
                    #else
                    return 1_000_000_000
                    #endif
                }()
                try? await Task.sleep(nanoseconds: interval)
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

    /// Clash Verge-style node latency: URLTest each leaf inside the NE mihomo core.
    /// Returns name → delayMs (-1 = timeout / unreachable). Nil when VPN is not connected.
    func testNodeDelays(
        names: [String],
        testURL: String,
        timeoutMs: Int,
        concurrency: Int
    ) async -> [String: Int]? {
        guard status == .connected,
              !names.isEmpty,
              let session = manager?.connection as? NETunnelProviderSession else {
            return nil
        }
        let payload: [String: Any] = [
            "action": "test_delays",
            "names": names,
            "url": testURL,
            "timeout_ms": timeoutMs,
            "concurrency": concurrency,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let response: Data? = await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(data) { response in
                    cont.resume(returning: response)
                }
            } catch {
                cont.resume(returning: nil)
            }
        }
        guard let response,
              let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let rows = json["results"] as? [[String: Any]] else {
            return nil
        }
        var out: [String: Int] = [:]
        for row in rows {
            guard let name = row["name"] as? String else { continue }
            let delay: Int = {
                if let v = row["delay"] as? Int { return v }
                if let v = row["delay"] as? NSNumber { return v.intValue }
                return -1
            }()
            out[name] = delay
        }
        return out
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
