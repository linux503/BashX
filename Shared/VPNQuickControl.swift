import Foundation
import NetworkExtension
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Lightweight VPN start/stop for Control Center / Shortcuts (no UIKit).
enum VPNQuickControl {
    private static let profileDisplayName = "Apple"
    private static let profileServerAddress = "Apple Inc."
    private static let onDemandEnabledKey = "iosOnDemandEnabled"

    enum ControlError: LocalizedError {
        case notConfigured
        case configMissing(String)
        case startFailed(String)
        case stateTimeout

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "请先打开 BashX 完成一次 VPN 授权"
            case .configMissing(let msg):
                return msg
            case .startFailed(let msg):
                return msg
            case .stateTimeout:
                return "VPN 状态切换超时"
            }
        }
    }

    static let controlKind = "com.bashx.app.ios.vpnToggle"
    private static let controlOnKey = "vpnControlOn"
    private static let controlPendingUntilKey = "vpnControlPendingUntil"

    /// Control toggle ON when connected or still connecting.
    static func isConnected() async -> Bool {
        if let pending = readPendingControlOn() {
            return pending
        }
        guard let mgr = await loadManager() else { return false }
        return controlOn(for: mgr.connection.status)
    }

    static func statusText() async -> String {
        guard let mgr = await loadManager() else { return "未连接" }
        switch mgr.connection.status {
        case .connected: return "已连接"
        case .connecting, .reasserting: return "连接中"
        case .disconnecting: return "断开中"
        case .disconnected, .invalid: return "未连接"
        @unknown default: return "未知"
        }
    }

    static func setConnected(_ on: Bool) async throws {
        setPendingControlOn(on, ttl: on ? 55 : 12)
        do {
            if on {
                try await connect()
                try await waitForControlState(on: true, timeout: 50)
            } else {
                await disconnect()
                try await waitForControlState(on: false, timeout: 12)
            }
        } catch {
            clearPendingControlOn()
            reloadControlWidget()
            throw error
        }
        clearPendingControlOn()
        reloadControlWidget()
    }

    static func toggle() async throws -> Bool {
        let connected = await isConnected()
        try await setConnected(!connected)
        return !connected
    }

    static func reloadControlWidget() {
        #if canImport(WidgetKit)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: Self.controlKind)
        }
        #endif
    }

    // MARK: - Private

    private static func loadManager() async -> NETunnelProviderManager? {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        return managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == AppConstants.tunnelBundleIdentifier
        }) ?? managers.first
    }

    private static func connect() async throws {
        // Controls extension cannot link ClashConfigParser / IOSConfigWriter — scrub + rule mode only.
        // Full rewrite happens in-app via VPNManager → IOSConfigWriter.prepareForConnect().
        MihomoConfigCheck.scrubStaleGeoDatabases()
        if UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "proxyMode") == "global" {
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set("rule", forKey: "proxyMode")
        }
        if let issue = MihomoConfigCheck.preflight() {
            throw ControlError.configMissing(issue)
        }
        if let name = UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .string(forKey: "selectedNode"), !name.isEmpty {
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(name, forKey: "selectedNode")
        }

        guard let mgr = await loadManager() else {
            throw ControlError.notConfigured
        }
        mgr.isEnabled = true
        if let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol {
            proto.serverAddress = profileServerAddress
            proto.providerBundleIdentifier = AppConstants.tunnelBundleIdentifier
            proto.disconnectOnSleep = false
            if #available(iOS 14.2, *) {
                proto.includeAllNetworks = false
                proto.excludeLocalNetworks = true
            }
            mgr.protocolConfiguration = proto
        }
        if mgr.localizedDescription != profileDisplayName {
            mgr.localizedDescription = profileDisplayName
        }
        // Always arm on-demand while connected so sleep / Wi‑Fi flips auto-recover.
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        mgr.onDemandRules = [rule]
        mgr.isOnDemandEnabled = true
        try await mgr.saveToPreferences()
        try await mgr.loadFromPreferences()
        do {
            try mgr.connection.startVPNTunnel()
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.set(true, forKey: "vpnUserWantsConnected")
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.set(true, forKey: onDemandEnabledKey)
        } catch {
            throw ControlError.startFailed(error.localizedDescription)
        }
    }

    private static func disconnect() async {
        guard let mgr = await loadManager() else { return }
        mgr.onDemandRules = []
        mgr.isOnDemandEnabled = false
        try? await mgr.saveToPreferences()
        mgr.connection.stopVPNTunnel()
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?.set(false, forKey: "vpnUserWantsConnected")
    }

    private static func controlOn(for status: NEVPNStatus) -> Bool {
        switch status {
        case .connected, .connecting, .reasserting:
            return true
        default:
            return false
        }
    }

    private static func waitForControlState(on: Bool, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await actualControlOn() == on {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw ControlError.stateTimeout
    }

    private static func actualControlOn() async -> Bool {
        guard let mgr = await loadManager() else { return false }
        return controlOn(for: mgr.connection.status)
    }

    private static func setPendingControlOn(_ on: Bool, ttl: TimeInterval) {
        guard let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else { return }
        ud.set(on, forKey: controlOnKey)
        ud.set(Date().addingTimeInterval(ttl), forKey: controlPendingUntilKey)
    }

    private static func readPendingControlOn() -> Bool? {
        guard let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier),
              let until = ud.object(forKey: controlPendingUntilKey) as? Date,
              until > Date(),
              ud.object(forKey: controlOnKey) != nil else {
            return nil
        }
        return ud.bool(forKey: controlOnKey)
    }

    private static func clearPendingControlOn() {
        guard let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else { return }
        ud.removeObject(forKey: controlOnKey)
        ud.removeObject(forKey: controlPendingUntilKey)
    }
}
