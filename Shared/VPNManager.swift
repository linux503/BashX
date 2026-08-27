import Foundation
import NetworkExtension
import Combine
import UIKit

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?
    @Published private(set) var uploadBytes: Int64 = 0
    @Published private(set) var downloadBytes: Int64 = 0

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var trafficTask: Task<Void, Never>?
    private var connectWatchTask: Task<Void, Never>?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let conn = note.object as? NEVPNConnection else { return }
            Task { @MainActor in
                self?.status = conn.status
                self?.syncTrafficPolling()
                if conn.status == .connected || conn.status == .disconnected || conn.status == .invalid {
                    self?.connectWatchTask?.cancel()
                    self?.connectWatchTask = nil
                }
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
        case .invalid: return "未配置"
        case .disconnected: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .reasserting: return "重连中…"
        case .disconnecting: return "断开中…"
        @unknown default: return "未知"
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
            } else {
                manager = nil
                status = .invalid
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
        do {
            guard FileManager.default.fileExists(atPath: Paths.mihomoConfigURL.path) else {
                lastError = "请先更新订阅并选择节点"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            if !GeoDataBootstrap.isReady() {
                lastError = "正在准备地理数据库，请稍候再试"
                return
            }
            let mgr = try await ensureManager()
            mgr.isEnabled = true
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
                            self.lastError = TunnelLogReader.lastErrorHint() ?? "VPN 连接失败"
                        }
                    }
                    return
                }
                if tick >= 44 {
                    await MainActor.run {
                        self.lastError = TunnelLogReader.lastErrorHint() ?? "连接超时，请检查网络后重试"
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

    private func syncTrafficPolling() {
        trafficTask?.cancel()
        guard status == .connected else {
            uploadBytes = 0
            downloadBytes = 0
            return
        }
        trafficTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTraffic()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
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
                    let up = (json["upload"] as? NSNumber)?.int64Value ?? 0
                    let down = (json["download"] as? NSNumber)?.int64Value ?? 0
                    Task { @MainActor in
                        self?.uploadBytes = up
                        self?.downloadBytes = down
                    }
                }
            } catch {
                cont.resume()
            }
        }
    }
}
