import Foundation
import Darwin
import CryptoKit

enum CoreInstaller {
    enum InstallError: LocalizedError {
        case unsupportedArch
        case downloadFailed
        case extractFailed
        case checksumMismatch
        case versionMismatch(got: String)
        case embeddedMissing

        var errorDescription: String? {
            switch self {
            case .unsupportedArch: return "不支持当前 CPU 架构"
            case .downloadFailed: return "下载 mihomo 失败"
            case .extractFailed: return "解压 mihomo 失败"
            case .checksumMismatch: return "内核校验失败（SHA-256 不匹配），已中止安装"
            case .versionMismatch(let got): return "内核版本不匹配（期望 \(pinnedVersion)，得到 \(got)）"
            case .embeddedMissing: return "App 内未找到内置内核"
            }
        }
    }

    /// Pinned MetaCubeX release + SHA-256 of the *uncompressed* binary.
    static let pinnedVersion = "v1.19.30"
    private static let expectedSHA256: [String: String] = [
        "arm64": "e80c6334b4e3aae53dfbc86cddd4434cec1565a61d4483931fac2ae12fec6d30",
        "amd64": "a53762909e742b99abf6a2e49a1064ebc54f08a57cc57e553c233bb8f4b10029"
    ]

    /// Writable runtime copy (TUN / elevation checks expect this path).
    static var bundledPath: URL {
        Paths.supportDir.appendingPathComponent("mihomo")
    }

    /// Copy embedded core into Application Support on first launch (sync, no network).
    @discardableResult
    static func seedEmbeddedCoreIfNeeded() -> String? {
        if FileManager.default.isExecutableFile(atPath: bundledPath.path),
           binaryRuns(at: bundledPath.path),
           verifyInstalledBinary(at: bundledPath.path) {
            return bundledPath.path
        }
        return (try? installFromEmbeddedBundle()) ?? nil
    }

    static func ensureInstalled(progress: (@MainActor (String) -> Void)? = nil) async throws -> String {
        if let existing = seedEmbeddedCoreIfNeeded() {
            return existing
        }

        // Fallback: online install when embedded core missing (dev builds / corrupted bundle).
        if FileManager.default.fileExists(atPath: bundledPath.path) {
            try? FileManager.default.removeItem(at: bundledPath)
        }
        await progress?("正在下载 mihomo \(pinnedVersion)…")
        let arch = hostArch
        guard let expected = expectedSHA256[arch] else { throw InstallError.unsupportedArch }

        let file = "mihomo-darwin-\(arch)-\(pinnedVersion).gz"
        let official = "https://github.com/MetaCubeX/mihomo/releases/download/\(pinnedVersion)/\(file)"
        let mirror = "https://ghfast.top/https://github.com/MetaCubeX/mihomo/releases/download/\(pinnedVersion)/\(file)"

        var gzData: Data?
        var source = "GitHub"
        do {
            gzData = try await download(urlString: official)
            source = "GitHub"
        } catch {
            await progress?("官方源失败，尝试镜像…")
            gzData = try await download(urlString: mirror)
            source = "镜像"
        }
        guard let gz = gzData, !gz.isEmpty else { throw InstallError.downloadFailed }

        await progress?("正在校验并安装内核（\(source)）…")
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BashX-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let tmpGZ = tmpDir.appendingPathComponent(file)
        try gz.write(to: tmpGZ, options: .atomic)

        let binary = try gunzip(tmpGZ)
        try installVerifiedBinary(binary, expectedSHA256: expected)
        await progress?("内核已安装 \(pinnedVersion) · SHA-256 校验通过")
        return bundledPath.path
    }

    private static func installFromEmbeddedBundle() throws -> String {
        let binary = try loadEmbeddedBinary()
        guard let expected = expectedSHA256[hostArch] else { throw InstallError.unsupportedArch }
        try installVerifiedBinary(binary, expectedSHA256: expected)
        return bundledPath.path
    }

    /// Embedded core as gzip (~16MB) or legacy uncompressed binary.
    private static func loadEmbeddedBinary() throws -> Data {
        guard let src = embeddedCoreURL() else { throw InstallError.embeddedMissing }
        let raw = try Data(contentsOf: src)
        if src.pathExtension == "gz" || src.lastPathComponent.hasSuffix(".gz") {
            return try gunzipData(raw)
        }
        return raw
    }

    private static func gunzipData(_ gz: Data) throws -> Data {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BashX-gz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let tmpGZ = tmpDir.appendingPathComponent("core.gz")
        try gz.write(to: tmpGZ, options: .atomic)
        return try gunzip(tmpGZ)
    }

    private static func installVerifiedBinary(_ binary: Data, expectedSHA256 expected: String) throws {
        let hex = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        guard hex == expected else { throw InstallError.checksumMismatch }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BashX-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let tmpBin = tmpDir.appendingPathComponent("mihomo")
        try binary.write(to: tmpBin, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpBin.path)

        let ver = binaryVersion(at: tmpBin.path) ?? ""
        let want = pinnedVersion.hasPrefix("v") ? String(pinnedVersion.dropFirst()) : pinnedVersion
        guard ver.contains(want) else {
            throw InstallError.versionMismatch(got: ver.isEmpty ? "未知" : ver)
        }

        if FileManager.default.fileExists(atPath: bundledPath.path) {
            try? FileManager.default.removeItem(at: bundledPath)
        }
        try FileManager.default.copyItem(at: tmpBin, to: bundledPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledPath.path)
        stripQuarantine(at: bundledPath.path)
        try? hex.write(to: Paths.coreHashURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.coreHashURL.path)
    }

    private static func embeddedCoreURL() -> URL? {
        let gzName = hostArch == "amd64" ? "mihomo-amd64.gz" : "mihomo-arm64.gz"
        let plainName = hostArch == "amd64" ? "mihomo-amd64" : "mihomo-arm64"
        return Bundle.main.url(forResource: gzName, withExtension: nil, subdirectory: "Core")
            ?? Bundle.main.url(forResource: plainName, withExtension: "gz", subdirectory: "Core")
            ?? Bundle.main.url(forResource: plainName, withExtension: nil, subdirectory: "Core")
            ?? Bundle.main.url(forResource: plainName, withExtension: nil)
    }

    private static var embeddedResourceName: String {
        hostArch == "amd64" ? "mihomo-amd64" : "mihomo-arm64"
    }

    /// True if installed binary matches pinned hash (or recorded hash file).
    static func verifyInstalledBinary(at path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else { return false }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expected = expectedSHA256[hostArch], hex == expected { return true }
        if let recordedRaw = try? String(contentsOf: Paths.coreHashURL, encoding: .utf8) {
            let recorded = recordedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !recorded.isEmpty, hex == recorded {
                return true
            }
        }
        return false
    }

    static func sha256Hex(ofFile path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func download(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw InstallError.downloadFailed }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw InstallError.downloadFailed
        }
        guard data.count <= 40 * 1024 * 1024 else { throw InstallError.downloadFailed }
        return data
    }

    private static func gunzip(_ url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let binary = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !binary.isEmpty else { throw InstallError.extractFailed }
        return binary
    }

    private static var hostArch: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
            return "arm64"
        }
        switch String(cString: machine) {
        case "x86_64": return "amd64"
        case "arm64": return "arm64"
        default: return "arm64"
        }
    }

    private static func binaryRuns(at path: String) -> Bool {
        binaryVersion(at: path) != nil
    }

    /// Remove Gatekeeper quarantine so mihomo can run on other Macs after copy/extract.
    private static func stripQuarantine(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func binaryVersion(at path: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-v"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}

enum PortProbe {
    static func isListening(port: Int) -> Bool {
        isListening(host: "127.0.0.1", port: port)
    }

    static func isListening(host: String, port: Int) -> Bool {
        guard port > 0, port <= 65535 else { return false }
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        let portStr = "\(port)"
        guard getaddrinfo(host, portStr, &hints, &info) == 0, let first = info else { return false }
        defer { freeaddrinfo(info) }

        let fd = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 0, tv_usec: 150_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return connect(fd, first.pointee.ai_addr, first.pointee.ai_addrlen) == 0
    }

    static func firstFreePort(from start: Int, limit: Int) -> Int? {
        let base = max(1024, min(start, 65535))
        for offset in 0..<max(1, limit) {
            let p = base + offset
            guard p <= 65535 else { break }
            if !isListening(port: p) { return p }
        }
        return nil
    }
}
