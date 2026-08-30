import Foundation
import AppKit
import Darwin

/// One-time admin install of a root LaunchDaemon that starts TUN without re-entering the password.
enum TunPrivilege {
    static let helperLabel = "com.bashx.tunhelper"
    static let helperInstallPath = "/Library/PrivilegedHelperTools/com.bashx.tunhelper"
    static let plistInstallPath = "/Library/LaunchDaemons/com.bashx.tunhelper.plist"
    static let supportDir = "/Library/Application Support/com.bashx.tunhelper"
    static let uidFile = "/Library/Application Support/com.bashx.tunhelper/allowed_uid"
    static let socketPath = "/var/run/com.bashx.tunhelper.sock"

    enum PrivilegeError: LocalizedError {
        case helperMissingInApp
        case installCancelled
        case installFailed(String)
        case notReady
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissingInApp: return "App 内缺少 TUN 助手，请重装 BashX"
            case .installCancelled: return "已取消管理员授权"
            case .installFailed(let s): return "TUN 权限安装失败：\(s)"
            case .notReady: return "TUN 权限未安装"
            case .startFailed(let s): return s
            }
        }
    }

    /// Bundled helper binary inside the app.
    static var bundledHelperURL: URL? {
        let candidates: [URL?] = [
            Bundle.main.url(forAuxiliaryExecutable: "BashXTunHelper"),
            Bundle.main.url(forResource: "BashXTunHelper", withExtension: nil),
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/BashXTunHelper"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BashXTunHelper"),
        ]
        for url in candidates {
            guard let url, FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            return url
        }
        return nil
    }

    static var isInstalledOnDisk: Bool {
        FileManager.default.isExecutableFile(atPath: helperInstallPath)
            && FileManager.default.fileExists(atPath: plistInstallPath)
    }

    /// True when the daemon answers PING (ready for password-free TUN start).
    static var isReady: Bool {
        guard let reply = try? send("PING") else { return false }
        return reply == "PONG" || reply.hasPrefix("PONG")
    }

    static var statusText: String {
        if isReady { return "已授权（开 TUN 无需再输密码）" }
        if isInstalledOnDisk { return "已安装但未运行，可点「修复授权」" }
        return "未授权（首次开 TUN 或点下方按钮，输一次管理员密码）"
    }

    /// Install / repair LaunchDaemon (prompts for admin password once).
    static func install() throws {
        guard let helper = bundledHelperURL,
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw PrivilegeError.helperMissingInApp
        }

        bringFront()

        let uid = getuid()
        let helperSrc = shQuote(helper.path)
        let helperDst = shQuote(helperInstallPath)
        let plistPath = shQuote(plistInstallPath)
        let support = shQuote(supportDir)
        let uidPath = shQuote(uidFile)
        let label = helperLabel

        // LaunchDaemon plist (Program runs installed helper as root).
        let plistBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(helperInstallPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>/Library/Application Support/com.bashx.tunhelper/stdout.log</string>
          <key>StandardErrorPath</key>
          <string>/Library/Application Support/com.bashx.tunhelper/stderr.log</string>
        </dict>
        </plist>
        """

        let tmpPlist = (NSTemporaryDirectory() as NSString).appendingPathComponent("com.bashx.tunhelper.plist")
        try plistBody.write(toFile: tmpPlist, atomically: true, encoding: .utf8)
        let tmpPlistQ = shQuote(tmpPlist)

        let shell = """
        set -e
        mkdir -p \(support)
        echo \(uid) > \(uidPath)
        chmod 644 \(uidPath)
        cp \(helperSrc) \(helperDst)
        chown root:wheel \(helperDst)
        chmod 755 \(helperDst)
        cp \(tmpPlistQ) \(plistPath)
        chown root:wheel \(plistPath)
        chmod 644 \(plistPath)
        launchctl bootout system/\(label) 2>/dev/null || true
        launchctl bootstrap system \(plistPath)
        launchctl enable system/\(label)
        launchctl kickstart -k system/\(label)
        """

        try runAdminShell(shell)

        // Wait until socket answers.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if isReady { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw PrivilegeError.installFailed("助手已安装但未响应，请重试或重启 Mac")
    }

    static func uninstall() throws {
        bringFront()
        let shell = """
        launchctl bootout system/\(helperLabel) 2>/dev/null || true
        rm -f \(shQuote(helperInstallPath)) \(shQuote(plistInstallPath)) \(shQuote(socketPath))
        rm -rf \(shQuote(supportDir))
        """
        try runAdminShell(shell)
    }

    /// Ensure helper is ready (install once if needed), then start mihomo as root
    /// via a hash-verified copy owned by the helper (never exec the user-writable path).
    static func startElevated(binary: String, configDir: URL) throws {
        if !isReady {
            try install()
        }
        guard let hash = CoreInstaller.sha256Hex(ofFile: binary), !hash.isEmpty else {
            throw PrivilegeError.startFailed("无法计算内核哈希")
        }
        let dir = configDir.path
        // New helper: START|src|dir|sha256. Old helper (≤Aug 27) only accepts START|src|dir —
        // with 4 args it treats "dir|hash" as the config path →「非法配置目录」.
        let reply4 = try send("START|\(binary)|\(dir)|\(hash)")
        if reply4 == "OK" { return }
        let err4 = reply4.hasPrefix("ERR|") ? String(reply4.dropFirst(4)) : reply4
        if isLegacyProtocolMismatch(err4) {
            let reply3 = try send("START|\(binary)|\(dir)")
            if reply3 == "OK" {
                // Old helper started OK; ask user to refresh helper when convenient.
                UserDefaults.standard.set(true, forKey: "bashx.tunHelperNeedsUpgrade")
                return
            }
            let err3 = reply3.hasPrefix("ERR|") ? String(reply3.dropFirst(4)) : reply3
            throw PrivilegeError.startFailed(err3.isEmpty ? err4 : err3)
        }
        // Helper likely outdated / broken — try reinstall once, then 4-arg again.
        if err4.contains("非法") || err4.contains("参数") || err4.contains("未授权") {
            try install()
            let retry = try send("START|\(binary)|\(dir)|\(hash)")
            if retry == "OK" { return }
            if retry.hasPrefix("ERR|") {
                throw PrivilegeError.startFailed(String(retry.dropFirst(4)))
            }
            throw PrivilegeError.startFailed(retry.isEmpty ? "助手无响应" : retry)
        }
        throw PrivilegeError.startFailed(err4.isEmpty ? "助手无响应" : err4)
    }

    /// Old helper mis-parses the 4-arg START line.
    private static func isLegacyProtocolMismatch(_ err: String) -> Bool {
        err.contains("非法配置目录")
            || err.contains("参数不足")
            || err.localizedCaseInsensitiveContains("illegal")
    }

    // MARK: - Socket client

    private static func send(_ command: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PrivilegeError.notReady }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketPath
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, b) in pathBytes.enumerated() { dest[i] = b }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected: Bool = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
                Darwin.connect(fd, sap, size) == 0
            }
        }
        guard connected else { throw PrivilegeError.notReady }

        let payload = command + "\n"
        guard payload.withCString({ write(fd, $0, strlen($0)) }) > 0 else {
            throw PrivilegeError.notReady
        }

        var buf = [UInt8](repeating: 0, count: 2048)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { throw PrivilegeError.notReady }
        return String(bytes: buf[0..<n], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Admin shell (password once for install/uninstall only)

    private static func runAdminShell(_ shell: String) throws {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            let cancelled = errText.localizedCaseInsensitiveContains("user canceled")
                || errText.localizedCaseInsensitiveContains("user cancelled")
                || errText.contains("-128")
            if cancelled { throw PrivilegeError.installCancelled }
            throw PrivilegeError.installFailed(errText.isEmpty ? "需要管理员密码" : errText)
        }
    }

    private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func bringFront() {
        let work = {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                AppActivation.applyPolicy()
                AppActivation.refreshAfterWindowClosed()
            }
        }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.sync(execute: work) }
    }
}
