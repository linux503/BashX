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
    /// Prefer `setEnabledAsync` from UI — `networksetup` can take hundreds of ms per service.
    static func setEnabled(_ enabled: Bool, host: String = "127.0.0.1", port: Int) {
        let services = listServices()
        guard !services.isEmpty else { return }

        if enabled {
            if loadSnapshot() == nil {
                saveSnapshot(capture(services: services))
            }
            for service in services {
                _ = run("/usr/sbin/networksetup", ["-setwebproxy", service, host, "\(port)"])
                _ = run("/usr/sbin/networksetup", ["-setsecurewebproxy", service, host, "\(port)"])
                _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxy", service, host, "\(port)"])
                _ = run("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"])
                _ = run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"])
                _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "on"])
            }
        } else {
            restoreFromSnapshot(fallbackServices: services)
        }
    }

    /// Off-main-thread wrapper so toggles stay responsive.
    @discardableResult
    static func setEnabledAsync(_ enabled: Bool, host: String = "127.0.0.1", port: Int) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            setEnabled(enabled, host: host, port: port)
            if enabled {
                return isEnabled(port: port)
            }
            return true
        }.value
    }

    /// Restore saved proxy settings (also usable after crash / next launch).
    @discardableResult
    static func restoreFromSnapshot(fallbackServices: [String]? = nil) -> Bool {
        guard let snaps = loadSnapshot(), !snaps.isEmpty else {
            // No backup — only turn off (legacy behavior).
            for service in fallbackServices ?? listServices() {
                _ = run("/usr/sbin/networksetup", ["-setwebproxystate", service, "off"])
                _ = run("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "off"])
                _ = run("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "off"])
            }
            return false
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
