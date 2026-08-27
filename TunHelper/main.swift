import Foundation
import Darwin

/// Root LaunchDaemon: accepts start/stop of BashX mihomo over a local Unix socket.
/// Only the UID recorded at install time may connect (checked via getpeereid).

enum HelperPaths {
    static let socket = "/var/run/com.bashx.tunhelper.sock"
    static let uidFile = "/Library/Application Support/com.bashx.tunhelper/allowed_uid"
    static let logFile = "/Library/Application Support/com.bashx.tunhelper/helper.log"
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
    let dir = "/Library/Application Support/com.bashx.tunhelper"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
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
    // Must be the BashX Application Support binary — never arbitrary paths.
    return std.hasSuffix("/Library/Application Support/BashX/mihomo")
        && !std.contains("..")
}

func isSafeConfigDir(_ path: String) -> Bool {
    let std = (path as NSString).standardizingPath
    return std.hasSuffix("/Library/Application Support/BashX")
        && !std.contains("..")
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
    try? FileManager.default.removeItem(atPath: stop)
    try? FileManager.default.removeItem(atPath: pidf)
}

func startMihomo(binary: String, configDir: String) -> String? {
    guard isSafeMihomoPath(binary) else { return "非法内核路径" }
    guard isSafeConfigDir(configDir) else { return "非法配置目录" }
    guard FileManager.default.isExecutableFile(atPath: binary) else { return "内核不可执行" }

    // Refuse world/group-writable binaries.
    if let attrs = try? FileManager.default.attributesOfItem(atPath: binary),
       let perms = attrs[.posixPermissions] as? NSNumber,
       perms.uint16Value & 0o022 != 0 {
        return "内核文件权限不安全"
    }

    stopMihomo(configDir: configDir)

    let logPath = (configDir as NSString).appendingPathComponent("core.log")
    let pidPath = (configDir as NSString).appendingPathComponent("core.pid")
    let stopPath = (configDir as NSString).appendingPathComponent("core.stop")
    try? FileManager.default.removeItem(atPath: stopPath)
    try? FileManager.default.removeItem(atPath: pidPath)

    // Background watcher: same behavior as former osascript elevate path.
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
    // Spawn watcher in background so this request returns immediately.
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
    let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
    guard let cmd = parts.first?.uppercased() else { return "ERR|空命令" }
    switch cmd {
    case "PING":
        return "PONG"
    case "STOP":
        // Best-effort stop for any BashX mihomo.
        _ = runShell("pkill -9 -f 'Application Support/BashX/mihomo' 2>/dev/null || true")
        return "OK"
    case "START":
        guard parts.count == 3 else { return "ERR|参数不足" }
        if let err = startMihomo(binary: parts[1], configDir: parts[2]) {
            return "ERR|\(err)"
        }
        return "OK"
    default:
        return "ERR|未知命令"
    }
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

    var buffer = [UInt8](repeating: 0, count: 4096)
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

    // World-connectable; authorization is getpeereid + allowed_uid.
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
