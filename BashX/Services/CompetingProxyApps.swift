import AppKit
import Darwin
import Foundation

/// Quit other local proxy / VPN clients so BashX can own mixed-port, TUN, and system proxy.
enum CompetingProxyApps {
    private struct Target: Sendable {
        let bundleId: String
        let label: String
    }

    /// GUI apps — matched by bundle id (never includes BashX).
    private static let bundleTargets: [Target] = [
        Target(bundleId: "com.west2online.ClashX", label: "ClashX"),
        Target(bundleId: "com.west2online.ClashXPro", label: "ClashX Pro"),
        Target(bundleId: "com.github.clash-verge", label: "Clash Verge"),
        Target(bundleId: "io.github.clash-verge-rev.clash-verge-rev", label: "Clash Verge Rev"),
        Target(bundleId: "ws.stash.app.mac", label: "Stash"),
        Target(bundleId: "com.nssurge.surge-mac", label: "Surge"),
        Target(bundleId: "com.nssurge.surge-mac3", label: "Surge"),
        Target(bundleId: "com.yanue.V2rayU", label: "V2rayU"),
        Target(bundleId: "com.qiuyuzhou.v2rayU", label: "V2rayU"),
        Target(bundleId: "app.hiddify.com", label: "Hiddify"),
        Target(bundleId: "com.follow.clash", label: "Clash Mi"),
        Target(bundleId: "com.metacubex.ClashX", label: "ClashX Meta"),
        Target(bundleId: "com.proxifier.Proxifier", label: "Proxifier"),
        Target(bundleId: "com.proxyman.NSProxy", label: "Proxyman"),
    ]

    /// Headless cores / helpers — path fragments under Application Support or .config.
    /// Must not match BashX (`Application Support/BashX` is excluded explicitly).
    private static let corePathMarkers: [String] = [
        "Application Support/ClashX",
        "Application Support/clash_win",
        "Application Support/Stash",
        "Application Support/com.nssurge.surge-mac",
        "Application Support/io.github.clash-verge",
        "Application Support/clash-verge",
        "Application Support/V2rayU",
        "Application Support/v2rayU",
        "Application Support/hiddify",
        "Application Support/ShadowsocksX-NG",
        "Application Support/ShadowsocksX",
        ".config/clash",
        ".config/mihomo",
        ".config/v2ray",
    ]

    /// Force-quit competing apps and stray cores. Returns human labels that were stopped.
    static func quitAllOnLaunch() async -> [String] {
        let gui = await MainActor.run { quitGUIApps() }
        let cores = await Task.detached(priority: .userInitiated) {
            killForeignCoreProcesses()
        }.value
        var seen = Set<String>()
        return (gui + cores).filter { seen.insert($0).inserted }
    }

    @MainActor
    private static func quitGUIApps() -> [String] {
        let ours = Bundle.main.bundleIdentifier ?? "com.bashx.app"
        var quit: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, bid != ours else { continue }
            guard let target = bundleTargets.first(where: { $0.bundleId == bid }) else { continue }
            guard !app.isTerminated else { continue }
            app.forceTerminate()
            quit.append(target.label)
        }
        return quit
    }

    private static func killForeignCoreProcesses() -> [String] {
        var quit: [String] = []
        for marker in corePathMarkers {
            guard !marker.localizedCaseInsensitiveContains("bashx") else { continue }
            if pkill(pattern: marker) {
                quit.append(shortLabel(for: marker))
            }
        }
        // Common standalone names when not under Application Support/BashX.
        for pattern in ["mihomo -d", "clash-meta -d", "clash -d"] {
            if pkillExcludingBashX(pattern: pattern) {
                quit.append("代理内核")
            }
        }
        return quit
    }

    private static func pkillExcludingBashX(pattern: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", pattern]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = raw.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return false }

        var killed = false
        for pid in pids {
            guard let cmd = commandLine(for: pid)?.lowercased(), !cmd.contains("application support/bashx") else { continue }
            kill(pid, SIGKILL)
            killed = true
        }
        return killed
    }

    private static func pkill(pattern: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-9", "-f", pattern]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func commandLine(for pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func shortLabel(for marker: String) -> String {
        if marker.localizedCaseInsensitiveContains("stash") { return "Stash 内核" }
        if marker.localizedCaseInsensitiveContains("surge") { return "Surge 内核" }
        if marker.localizedCaseInsensitiveContains("clash") { return "Clash 内核" }
        if marker.localizedCaseInsensitiveContains("v2ray") { return "V2ray 内核" }
        if marker.localizedCaseInsensitiveContains("shadowsocks") { return "Shadowsocks 内核" }
        if marker.localizedCaseInsensitiveContains("hiddify") { return "Hiddify 内核" }
        if marker.localizedCaseInsensitiveContains("mihomo") { return "mihomo 内核" }
        return "代理内核"
    }
}
