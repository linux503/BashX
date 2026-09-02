import AppKit
import Foundation

/// Persistent launch / bootstrap log for Settings when startup fails.
enum LaunchDiagnostics {
    static var logURL: URL { Paths.supportDir.appendingPathComponent("launch.log") }
    private static let maxLogBytes = 512 * 1024
    private static var lastErrorLine = ""
    private static var lastErrorTime: TimeInterval = 0

    static func beginSession() {
        append("=== BashX \(AppVersion.display) · \(ISO8601DateFormatter().string(from: Date())) ===")
    }

    static func info(_ message: String) {
        append("[INFO] \(message)")
    }

    static func error(_ message: String) {
        let now = Date().timeIntervalSince1970
        if message == lastErrorLine, now - lastErrorTime < 12 { return }
        lastErrorLine = message
        lastErrorTime = now
        append("[ERROR] \(message)")
    }

    static func lastSessionHadError() -> Bool {
        guard let text = tail(of: logURL, maxBytes: 16_384) else { return false }
        let block = text.components(separatedBy: "===").last ?? text
        return block.localizedCaseInsensitiveContains("[error]")
    }

    static func isStartupFailure(statusText: String, coreRunning: Bool, coreConnecting: Bool) -> Bool {
        if coreConnecting { return false }
        if !coreRunning, matchesFailureHint(statusText) { return true }
        return lastSessionHadError() && !coreRunning
    }

    static func buildReport(statusText: String, coreRunning: Bool) -> String {
        var parts: [String] = []
        parts.append("BashX \(AppVersion.display)")
        parts.append("状态: \(statusText)")
        parts.append("内核: \(coreRunning ? "运行中" : "未运行")")
        parts.append("配置目录: \(Paths.supportDir.path)")
        parts.append("geoip: \(FileManager.default.fileExists(atPath: GeoDataBootstrap.geoipFile.path) ? "有" : "缺")")
        parts.append("geosite: \(FileManager.default.fileExists(atPath: GeoDataBootstrap.geositeFile.path) ? "有" : "缺")")
        if let cfgErr = MihomoConfigCheck.validateFile() {
            parts.append("配置检查: \(cfgErr)")
        }
        parts.append("")
        parts.append("—— launch.log ——")
        parts.append(tail(of: logURL, maxBytes: 12_288) ?? "(空)")
        parts.append("")
        parts.append("—— core.log ——")
        parts.append(tail(of: Paths.supportDir.appendingPathComponent("core.log"), maxBytes: 12_288) ?? "(空)")
        return parts.joined(separator: "\n")
    }

    static func copyReport(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func revealLogFile() {
        let url = logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            append("[INFO] log file created on reveal")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private

    private static func append(_ line: String) {
        let row = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let data = row.data(using: .utf8) else { return }
        let fm = FileManager.default
        let url = logURL
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            trimIfNeeded(url)
        } catch {}
    }

    private static func trimIfNeeded(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxLogBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let keep = maxLogBytes / 2
        try? handle.seek(toOffset: UInt64(size.intValue - keep))
        let tail = handle.readDataToEndOfFile()
        try? tail.write(to: url, options: .atomic)
    }

    private static func tail(of url: URL, maxBytes: Int) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let text = String(data: handle.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func matchesFailureHint(_ status: String) -> Bool {
        let hints = [
            "配置仍异常", "配置异常", "配置生成失败", "配置校验失败",
            "内核启动失败", "内核安装失败", "地理库下载失败",
            "启动失败", "内核未运行", "内核不可执行",
        ]
        return hints.contains { status.localizedCaseInsensitiveContains($0) }
    }
}
