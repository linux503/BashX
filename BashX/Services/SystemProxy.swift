import Foundation

/// Snapshot of one network service's proxy settings before BashX takes over.
struct SavedProxySnapshot: Codable, Equatable {
    var service: String
    var webEnabled: Bool
    var webHost: String
    var webPort: String
    var secureEnabled: Bool
    var secureHost: String
    var securePort: String
    var socksEnabled: Bool
    var socksHost: String
    var socksPort: String
}

enum SystemProxy {
    private static let snapshotURL = Paths.supportDir.appendingPathComponent("proxy-backup.json")

    /// Last elevated-proxy error for UI (password cancel / helper failure).
    private(set) static var lastError: String?

    /// ClashX-style LAN / loopback bypass when system proxy is on.
    /// WhatsApp Mac: HTTP/SOCKS system proxy breaks WebSocket QR (`wss://…/ws/chat`).
    /// Bypass → dial via TUN (fake-ip domain map) so PROCESS/DOMAIN rules apply.
    private static let bypassDomains = [
        "localhost",
        "127.0.0.1",
        "*.local",
        "*.lan",
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "169.254.0.0/16",
        "*.whatsapp.com",
        "*.whatsapp.net",
        "*.whatsapp.biz",
        "web.whatsapp.com",
        "api.whatsapp.net",
        "g.whatsapp.net",
        "v.whatsapp.net",
        "*.fbcdn.net",
        "*.facebook.com",
        "graph.facebook.com",
        // AdsPower / IPFoxy: system SOCKS + app SOCKS stacks = 连接测试失败.
        // Bypass → raw dial via TUN (same as WhatsApp).
        "*.ipfoxy.io",
        "*.ipfoxy.com",
        "ipfoxy.io",
        "ipfoxy.com",
        "gate.ipfoxy.io",
        "gate-sg.ipfoxy.io",
        "gate-us.ipfoxy.io",
    ]

    static func listServices() -> [String] {
        let skip = ["shadowrocket", "stash", "clash", "wireguard", "tailscale", "zerotier", "vpn", "ipsec", "utun", "tun"]
        let output = run("/usr/sbin/networksetup", ["-listallnetworkservices"]) ?? ""
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty,
                      !line.hasPrefix("An asterisk"),
                      !line.hasPrefix("*") else { return false }
                let lower = line.lowercased()
                return !skip.contains { lower.contains($0) }
            }
    }

    /// Enable BashX proxy after saving prior settings; disable restores the backup.
    /// - Parameter allowPrivilegePrompt: only `true` for explicit UI toggles.
    ///   Background auto-apply must NOT pop the admin password sheet on every launch.
    static func setEnabled(
        _ enabled: Bool,
        host: String = "127.0.0.1",
        port: Int,
        allowPrivilegePrompt: Bool = false
    ) {
        lastError = nil
        let services = listServices()
        guard !services.isEmpty else {
            lastError = "无可用网络服务"
            return
        }

        if enabled {
            if loadSnapshot() == nil {
                saveSnapshot(capture(services: services))
            }
            if applyElevatedSet(host: host, port: port, allowPrompt: allowPrivilegePrompt) {
                for service in services {
                    applyBypass(for: service)
                }
                return
            }
            // Fallback: unprivileged (works on some admin sessions).
            for service in services {
                _ = run("/usr/sbin/networksetup", ["-setwebproxy", service, host, "\(port)"])
                _ = run("/usr/sbin/networksetup", ["-setsecurewebproxy", service, host, "\(port)"])
                _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxy", service, host, "\(port)"])
                _ = run("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"])
                _ = run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"])
                _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "on"])
                applyBypass(for: service)
            }
            if !isEnabled(port: port), lastError == nil {
                lastError = allowPrivilegePrompt
                    ? "系统代理写入失败（请在弹窗中输入管理员密码）"
                    : "系统代理未授权（请在设置里手动开一次系统代理并输入密码）"
            }
        } else {
            let snaps = loadSnapshot()
            if applyElevatedOff(restore: snaps, allowPrompt: allowPrivilegePrompt) {
                clearSnapshot()
                return
            }
            restoreFromSnapshot(fallbackServices: services, allowPrivilegePrompt: allowPrivilegePrompt)
        }
    }

    /// Off-main-thread wrapper so toggles stay responsive.
    @discardableResult
    static func setEnabledAsync(
        _ enabled: Bool,
        host: String = "127.0.0.1",
        port: Int,
        allowPrivilegePrompt: Bool = false
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            setEnabled(enabled, host: host, port: port, allowPrivilegePrompt: allowPrivilegePrompt)
            if enabled {
                return isEnabled(port: port)
            }
            return true
        }.value
    }

    // MARK: - Elevated (TunHelper root daemon)

    private static func applyElevatedSet(host: String, port: Int, allowPrompt: Bool) -> Bool {
        do {
            try TunPrivilege.runProxyCommand("PROXY_SET|\(host)|\(port)", allowInstall: allowPrompt)
            usleep(200_000)
            return true
        } catch let error as TunPrivilege.PrivilegeError {
            // notReady without prompt is expected on cold launch — stay quiet.
            if case .notReady = error, !allowPrompt {
                return false
            }
            lastError = error.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private static func applyElevatedOff(restore snaps: [SavedProxySnapshot]?, allowPrompt: Bool) -> Bool {
        do {
            if let snaps, !snaps.isEmpty,
               let data = try? JSONEncoder().encode(snaps) {
                let b64 = data.base64EncodedString()
                try TunPrivilege.runProxyCommand("PROXY_RESTORE|\(b64)", allowInstall: allowPrompt)
            } else {
                try TunPrivilege.runProxyCommand("PROXY_OFF", allowInstall: allowPrompt)
            }
            return true
        } catch let error as TunPrivilege.PrivilegeError {
            if case .notReady = error, !allowPrompt {
                return false
            }
            lastError = error.errorDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Restore saved proxy settings (also usable after crash / next launch).
    @discardableResult
    static func restoreFromSnapshot(
        fallbackServices: [String]? = nil,
        allowPrivilegePrompt: Bool = true
    ) -> Bool {
        guard let snaps = loadSnapshot(), !snaps.isEmpty else {
            if applyElevatedOff(restore: nil, allowPrompt: allowPrivilegePrompt) {
                return false
            }
            for service in fallbackServices ?? listServices() {
                _ = run("/usr/sbin/networksetup", ["-setwebproxystate", service, "off"])
                _ = run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "off"])
                _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "off"])
            }
            return false
        }

        if applyElevatedOff(restore: snaps, allowPrompt: allowPrivilegePrompt) {
            clearSnapshot()
            return true
        }

        for snap in snaps {
            apply(snap)
        }
        clearSnapshot()
        return true
    }

    static func hasSnapshot() -> Bool {
        loadSnapshot()?.isEmpty == false
    }

    /// Best-effort: true if any service has web proxy on pointing at our port.
    static func isEnabled(port: Int) -> Bool {
        for service in listServices() {
            let info = run("/usr/sbin/networksetup", ["-getwebproxy", service]) ?? ""
            let enabled = info.contains("Enabled: Yes")
            let hasPort = info.contains("Port: \(port)")
            if enabled && hasPort { return true }
        }
        return false
    }

    /// First enabled HTTP/SOCKS system-proxy port (any service), if any.
    static func activeEnabledPort() -> Int? {
        for service in listServices() {
            for args in [["-getwebproxy"], ["-getsocksfirewallproxy"]] as [[String]] {
                let info = run("/usr/sbin/networksetup", args + [service]) ?? ""
                let parsed = parseProxy(info)
                guard parsed.enabled, let port = Int(parsed.port), port > 0 else { continue }
                return port
            }
        }
        return nil
    }

    /// True when OS proxy is on but points at a foreign local VPN (e.g. Stash:7890).
    static func isForeignProxyActive(ourPort: Int) -> Bool {
        guard let active = activeEnabledPort() else { return false }
        return active != ourPort
    }

    // MARK: - Capture / restore

    private static func capture(services: [String]) -> [SavedProxySnapshot] {
        services.map { service in
            let web = parseProxy(run("/usr/sbin/networksetup", ["-getwebproxy", service]) ?? "")
            let secure = parseProxy(run("/usr/sbin/networksetup", ["-getsecurewebproxy", service]) ?? "")
            let socks = parseProxy(run("/usr/sbin/networksetup", ["-getsocksfirewallproxy", service]) ?? "")
            return SavedProxySnapshot(
                service: service,
                webEnabled: web.enabled,
                webHost: web.host,
                webPort: web.port,
                secureEnabled: secure.enabled,
                secureHost: secure.host,
                securePort: secure.port,
                socksEnabled: socks.enabled,
                socksHost: socks.host,
                socksPort: socks.port
            )
        }
    }

    private static func applyBypass(for service: String) {
        _ = run("/usr/sbin/networksetup", ["-setproxybypassdomains", service] + bypassDomains)
    }

    private static func apply(_ snap: SavedProxySnapshot) {
        let service = snap.service
        if snap.webEnabled, !snap.webHost.isEmpty, !snap.webPort.isEmpty {
            _ = run("/usr/sbin/networksetup", ["-setwebproxy", service, snap.webHost, snap.webPort])
            _ = run("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"])
        } else {
            _ = run("/usr/sbin/networksetup", ["-setwebproxystate", service, "off"])
        }
        if snap.secureEnabled, !snap.secureHost.isEmpty, !snap.securePort.isEmpty {
            _ = run("/usr/sbin/networksetup", ["-setsecurewebproxy", service, snap.secureHost, snap.securePort])
            _ = run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"])
        } else {
            _ = run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "off"])
        }
        if snap.socksEnabled, !snap.socksHost.isEmpty, !snap.socksPort.isEmpty {
            _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxy", service, snap.socksHost, snap.socksPort])
            _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "on"])
        } else {
            _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "off"])
        }
    }

    private static func parseProxy(_ info: String) -> (enabled: Bool, host: String, port: String) {
        var enabled = false
        var host = ""
        var port = ""
        for line in info.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("Enabled:") {
                enabled = s.contains("Yes")
            } else if s.hasPrefix("Server:") {
                host = s.replacingOccurrences(of: "Server:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if s.hasPrefix("Port:") {
                port = s.replacingOccurrences(of: "Port:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return (enabled, host, port)
    }

    private static func saveSnapshot(_ snaps: [SavedProxySnapshot]) {
        guard let data = try? JSONEncoder().encode(snaps) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
    }

    private static func loadSnapshot() -> [SavedProxySnapshot]? {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snaps = try? JSONDecoder().decode([SavedProxySnapshot].self, from: data) else {
            return nil
        }
        return snaps
    }

    private static func clearSnapshot() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
