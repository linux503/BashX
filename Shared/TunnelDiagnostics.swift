import Foundation

/// Share last Packet Tunnel error with the main app via App Group UserDefaults.
enum TunnelDiagnostics {
    private static let errorKey = "lastTunnelError"
    private static let successKey = "lastTunnelSuccessAt"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)
    }

    static func recordFailure(_ message: String) {
        defaults?.set(message, forKey: errorKey)
    }

    static func recordSuccess() {
        defaults?.removeObject(forKey: errorKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: successKey)
    }

    static func lastFailureMessage() -> String? {
        defaults?.string(forKey: errorKey)
    }
}

enum TunnelLogReader {
    /// Enough history for diagnosing NE start / bridge / select-node.
    static let defaultLineCount = 300
    static let maxFileBytes = 512 * 1024

    static func lastLines(_ count: Int = defaultLineCount) -> String {
        let url = Paths.tunnelLogURL
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return (try? String(contentsOf: url, encoding: .utf8))
                .map { trimLines($0, count: count) } ?? ""
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window = UInt64(min(Int(size), maxFileBytes))
        let start = size > window ? size - window : 0
        do {
            try handle.seek(toOffset: start)
            guard let data = try handle.readToEnd(),
                  var text = String(data: data, encoding: .utf8) else { return "" }
            if start > 0, let nl = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: nl)...])
            }
            return trimLines(text, count: count)
        } catch {
            return ""
        }
    }

    private static func trimLines(_ text: String, count: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(count).joined(separator: "\n")
    }

    static func lastErrorHint() -> String? {
        if let saved = TunnelDiagnostics.lastFailureMessage(), !saved.isEmpty {
            return saved
        }
        let tail = lastLines(40)
        if tail.contains("configNotFound") || tail.contains("未找到 config") {
            return "未找到配置文件，请先更新订阅"
        }
        if tail.contains("start failed") || tail.contains("parse config") {
            return "核心启动失败，请查看规则或重试"
        }
        if tail.contains("tunFDNotFound") || tail.contains("TUN fd") {
            return "TUN 初始化失败，请重试"
        }
        if tail.isEmpty { return nil }
        if let line = tail.split(separator: "\n").last(where: { $0.contains("failed") }) {
            return String(line.prefix(120))
        }
        return nil
    }
}
