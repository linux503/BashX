import Foundation
import Darwin
import CryptoKit

/// Root LaunchDaemon: accepts start/stop of BashX mihomo over a local Unix socket.
/// Only the UID recorded at install time may connect (checked via getpeereid).
///
/// Security: never exec the user-writable Application Support binary as root.
/// Copy → hash-verify → install under helper support dir (root:wheel 755) → exec that copy.

enum HelperPaths {
    static let socket = "/var/run/com.bashx.tunhelper.sock"
    static let uidFile = "/Library/Application Support/com.bashx.tunhelper/allowed_uid"
    static let logFile = "/Library/Application Support/com.bashx.tunhelper/helper.log"
    static let supportDir = "/Library/Application Support/com.bashx.tunhelper"
    static let trustedBinary = "/Library/Application Support/com.bashx.tunhelper/mihomo"
}

func log(_ msg: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: HelperPaths.logFile) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: HelperPaths.logFile, contents: data)
        }
    }
}

func ensureSupportDir() {
    try? FileManager.default.createDirectory(atPath: HelperPaths.supportDir, withIntermediateDirectories: true)
}

func allowedUID() -> uid_t? {
    guard let raw = try? String(contentsOfFile: HelperPaths.uidFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let value = UInt32(raw) else { return nil }
    return uid_t(value)
}

func peerUID(fd: Int32) -> uid_t? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    if getpeereid(fd, &uid, &gid) != 0 { return nil }
    return uid
}

func isSafeMihomoPath(_ path: String) -> Bool {
    let std = (path as NSString).standardizingPath
    if std.contains("..") { return false }
    let marker = "/Library/Application Support/BashX/mihomo"
    return std.hasSuffix(marker)
}

func isSafeConfigDir(_ path: String) -> Bool {
    var std = (path as NSString).standardizingPath
    // Strip accidental protocol pollution from old/new START framing.
    if let pipe = std.firstIndex(of: "|") {
        std = String(std[..<pipe])
    }
    if std.hasSuffix("/") { std = String(std.dropLast()) }
    if std.contains("..") { return false }
    let marker = "/Library/Application Support/BashX"
    return std == marker || std.hasSuffix(marker)
}

func sha256Hex(ofFile path: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Copy user binary into helper-owned path after hash match (closes TOCTOU race).
func installTrustedBinary(from source: String, expectedSHA256: String) -> String? {
    let expected = expectedSHA256.lowercased()
    guard expected.count == 64, expected.allSatisfy({ $0.isHexDigit }) else {
        return "内核哈希无效"
    }
    guard isSafeMihomoPath(source) else { return "非法内核路径" }
    guard FileManager.default.isExecutableFile(atPath: source) else { return "内核不可执行" }

    ensureSupportDir()
    let tmp = HelperPaths.supportDir + "/mihomo.tmp.\(getpid())"
    let final = HelperPaths.trustedBinary
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    do {
        if FileManager.default.fileExists(atPath: tmp) {
            try FileManager.default.removeItem(atPath: tmp)
        }
        try FileManager.default.copyItem(atPath: source, toPath: tmp)
    } catch {
        return "复制内核失败：\(error.localizedDescription)"
    }

    // Hash the *copy*, not the live user path — replaces after copy cannot affect this bytes.
    guard let actual = sha256Hex(ofFile: tmp)?.lowercased(), actual == expected else {
        return "内核完整性校验失败"
    }

    // Root-only executable.
    chmod(tmp, 0o755)
    chown(tmp, 0, 0)

    if FileManager.default.fileExists(atPath: final) {
        try? FileManager.default.removeItem(atPath: final)
    }
    do {
        try FileManager.default.moveItem(atPath: tmp, toPath: final)
    } catch {
        // Fallback rename via POSIX.
        if rename(tmp, final) != 0 {
            return "安装可信内核失败"
        }
    }
    chmod(final, 0o755)
    chown(final, 0, 0)
    return nil
}

@discardableResult
func runShell(_ command: String) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", command]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    } catch {
        return -1
    }
}

func stopMihomo(configDir: String) {
    let stop = (configDir as NSString).appendingPathComponent("core.stop")
    let pidf = (configDir as NSString).appendingPathComponent("core.pid")
    FileManager.default.createFile(atPath: stop, contents: Data())
    if let pidText = try? String(contentsOfFile: pidf, encoding: .utf8),
       let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) {
        kill(pid, SIGTERM)
        usleep(400_000)
        kill(pid, SIGKILL)
    }
    _ = runShell("pkill -9 -f 'Application Support/BashX/mihomo' 2>/dev/null || true")
    _ = runShell("pkill -9 -f 'com.bashx.tunhelper/mihomo' 2>/dev/null || true")
    try? FileManager.default.removeItem(atPath: stop)
    try? FileManager.default.removeItem(atPath: pidf)
}

func startMihomo(sourceBinary: String, configDir: String, expectedSHA256: String) -> String? {
    guard isSafeConfigDir(configDir) else { return "非法配置目录" }
    if let err = installTrustedBinary(from: sourceBinary, expectedSHA256: expectedSHA256) {
        return err
    }
    let binary = HelperPaths.trustedBinary
    guard FileManager.default.isExecutableFile(atPath: binary) else { return "可信内核不可执行" }

    stopMihomo(configDir: configDir)

    let logPath = (configDir as NSString).appendingPathComponent("core.log")
    let pidPath = (configDir as NSString).appendingPathComponent("core.pid")
    let stopPath = (configDir as NSString).appendingPathComponent("core.stop")
    try? FileManager.default.removeItem(atPath: stopPath)
    try? FileManager.default.removeItem(atPath: pidPath)

    // Restrict core.log so other local users cannot read node/connection data.
    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil, attributes: [.posixPermissions: 0o600])
    } else {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logPath)
    }

    let escapedBin = binary.replacingOccurrences(of: "'", with: "'\\''")
    let escapedDir = configDir.replacingOccurrences(of: "'", with: "'\\''")
    let escapedLog = logPath.replacingOccurrences(of: "'", with: "'\\''")
    let escapedPid = pidPath.replacingOccurrences(of: "'", with: "'\\''")
    let escapedStop = stopPath.replacingOccurrences(of: "'", with: "'\\''")

    let script = """
    BIN='\(escapedBin)'; DIR='\(escapedDir)'; LOG='\(escapedLog)'; PIDF='\(escapedPid)'; STOP='\(escapedStop)'; \
    "$BIN" -d "$DIR" >>"$LOG" 2>&1 & BPID=$!; echo "$BPID" > "$PIDF"; \
    while kill -0 "$BPID" 2>/dev/null; do \
      if [ -f "$STOP" ]; then kill -TERM "$BPID" 2>/dev/null || true; sleep 0.4; kill -KILL "$BPID" 2>/dev/null || true; rm -f "$STOP" "$PIDF"; exit 0; fi; \
      sleep 0.35; \
    done; rm -f "$PIDF"
    """
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = ["-c", "(\(script)) >/dev/null 2>&1 &"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? nil : "启动失败"
    } catch {
        return "启动失败：\(error.localizedDescription)"
    }
}

func handle(line: String) -> String {
    // Allow up to 4 fields: START|bin|dir|sha256 (sha optional for legacy clients).
    // PROXY_RESTORE|base64 may contain no extra pipes after decode.
    let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
    guard let cmd = parts.first?.uppercased() else { return "ERR|空命令" }
    switch cmd {
    case "PING":
        return "PONG|v3"
    case "STOP":
        _ = runShell("pkill -9 -f 'Application Support/BashX/mihomo' 2>/dev/null || true")
        _ = runShell("pkill -9 -f 'com.bashx.tunhelper/mihomo' 2>/dev/null || true")
        return "OK"
    case "START":
        // START|srcBinary|configDir[|sha256]
        guard parts.count >= 3 else { return "ERR|参数不足" }
        let src = parts[1]
        let dir = parts[2]
        if parts.count >= 4, !parts[3].isEmpty {
            if let err = startMihomo(sourceBinary: src, configDir: dir, expectedSHA256: parts[3]) {
                return "ERR|\(err)"
            }
        } else {
            // Legacy 3-arg: still hash the source ourselves then install trusted copy.
            guard let hash = sha256Hex(ofFile: src) else { return "ERR|无法计算内核哈希" }
            if let err = startMihomo(sourceBinary: src, configDir: dir, expectedSHA256: hash) {
                return "ERR|\(err)"
            }
        }
        return "OK"
    case "PROXY_SET":
        // PROXY_SET|host|port — only loopback hosts allowed.
        guard parts.count >= 3 else { return "ERR|参数不足" }
        if let err = proxySet(host: parts[1], port: parts[2]) {
            return "ERR|\(err)"
        }
        return "OK"
    case "PROXY_OFF":
        if let err = proxyOff() {
            return "ERR|\(err)"
        }
        return "OK"
    case "PROXY_RESTORE":
        // PROXY_RESTORE|<base64 JSON array of snapshots>
        guard parts.count >= 2 else { return "ERR|参数不足" }
        if let err = proxyRestore(base64: parts[1]) {
            return "ERR|\(err)"
        }
        return "OK"
    default:
        return "ERR|未知命令"
    }
}

// MARK: - System proxy (root networksetup)

private let proxyBypass = [
    "localhost", "127.0.0.1", "*.local", "*.lan",
    "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "169.254.0.0/16",
]

private struct ProxySnap: Codable {
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

func listNetworkServices() -> [String] {
    let skip = ["shadowrocket", "stash", "clash", "wireguard", "tailscale", "zerotier", "vpn", "ipsec", "utun", "tun"]
    let output = runCapture("/usr/sbin/networksetup", ["-listallnetworkservices"]) ?? ""
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

@discardableResult
func runCapture(_ launchPath: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

@discardableResult
func runNetworkSetup(_ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func isLoopbackHost(_ host: String) -> Bool {
    let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return h == "127.0.0.1" || h == "localhost" || h == "::1"
}

func proxySet(host: String, port: String) -> String? {
    guard isLoopbackHost(host) else { return "仅允许本机代理地址" }
    guard let p = Int(port), (1...65535).contains(p) else { return "端口无效" }
    let services = listNetworkServices()
    guard !services.isEmpty else { return "无可用网络服务" }
    var okCount = 0
    for service in services {
        let h = host
        let pt = "\(p)"
        _ = runNetworkSetup(["-setwebproxy", service, h, pt])
        _ = runNetworkSetup(["-setsecurewebproxy", service, h, pt])
        _ = runNetworkSetup(["-setsocksfirewallproxy", service, h, pt])
        let a = runNetworkSetup(["-setwebproxystate", service, "on"])
        let b = runNetworkSetup(["-setsecurewebproxystate", service, "on"])
        let c = runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
        _ = runNetworkSetup(["-setproxybypassdomains", service] + proxyBypass)
        if a || b || c { okCount += 1 }
    }
    guard okCount > 0 else { return "networksetup 写入失败" }
    log("PROXY_SET \(host):\(port) services=\(okCount)")
    return nil
}

func proxyOff() -> String? {
    let services = listNetworkServices()
    guard !services.isEmpty else { return "无可用网络服务" }
    for service in services {
        _ = runNetworkSetup(["-setwebproxystate", service, "off"])
        _ = runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        _ = runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
    }
    log("PROXY_OFF services=\(services.count)")
    return nil
}

func proxyRestore(base64: String) -> String? {
    guard let data = Data(base64Encoded: base64) else { return "还原数据无效" }
    let snaps: [ProxySnap]
    do {
        snaps = try JSONDecoder().decode([ProxySnap].self, from: data)
    } catch {
        return "还原解析失败"
    }
    for snap in snaps {
        let service = snap.service
        guard !service.isEmpty, !service.contains(".."), !service.contains(";") else { continue }
        if snap.webEnabled, !snap.webHost.isEmpty, !snap.webPort.isEmpty {
            _ = runNetworkSetup(["-setwebproxy", service, snap.webHost, snap.webPort])
            _ = runNetworkSetup(["-setwebproxystate", service, "on"])
        } else {
            _ = runNetworkSetup(["-setwebproxystate", service, "off"])
        }
        if snap.secureEnabled, !snap.secureHost.isEmpty, !snap.securePort.isEmpty {
            _ = runNetworkSetup(["-setsecurewebproxy", service, snap.secureHost, snap.securePort])
            _ = runNetworkSetup(["-setsecurewebproxystate", service, "on"])
        } else {
            _ = runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        }
        if snap.socksEnabled, !snap.socksHost.isEmpty, !snap.socksPort.isEmpty {
            _ = runNetworkSetup(["-setsocksfirewallproxy", service, snap.socksHost, snap.socksPort])
            _ = runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
        } else {
            _ = runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        }
    }
    log("PROXY_RESTORE count=\(snaps.count)")
    return nil
}

func serveClient(_ fd: Int32, allowed: uid_t) {
    defer { close(fd) }
    guard let peer = peerUID(fd: fd) else {
        log("reject: no peer uid")
        return
    }
    guard peer == allowed else {
        log("reject: uid \(peer) != allowed \(allowed)")
        let msg = "ERR|未授权用户\n"
        _ = msg.withCString { write(fd, $0, strlen($0)) }
        return
    }

    // PROXY_RESTORE payloads can be a few KB.
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    let n = read(fd, &buffer, buffer.count)
    guard n > 0 else { return }
    let raw = String(bytes: buffer[0..<n], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let reply = handle(line: raw) + "\n"
    _ = reply.withCString { write(fd, $0, strlen($0)) }
}

func runServer() {
    ensureSupportDir()
    guard let allowed = allowedUID() else {
        log("fatal: missing allowed_uid")
        fputs("BashXTunHelper: missing allowed_uid\n", stderr)
        exit(1)
    }

    unlink(HelperPaths.socket)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        log("fatal: socket() failed")
        exit(1)
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = HelperPaths.socket
    let pathBytes = path.utf8CString
    precondition(pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path))
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            for (i, b) in pathBytes.enumerated() { dest[i] = b }
        }
    }

    let bindSize = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bindOK: Bool = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
            bind(fd, sap, bindSize) == 0
        }
    }
    guard bindOK else {
        log("fatal: bind failed errno=\(errno)")
        exit(1)
    }

    chmod(HelperPaths.socket, 0o666)
    guard listen(fd, 16) == 0 else {
        log("fatal: listen failed")
        exit(1)
    }

    log("listening uid=\(allowed) sock=\(HelperPaths.socket)")

    while true {
        let client = accept(fd, nil, nil)
        if client < 0 {
            if errno == EINTR { continue }
            log("accept error errno=\(errno)")
            usleep(200_000)
            continue
        }
        serveClient(client, allowed: allowed)
    }
}

runServer()
