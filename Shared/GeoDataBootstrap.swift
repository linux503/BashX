import Foundation

/// Prefetch mihomo geo databases into the App Group before VPN starts (avoids NE hang on first connect).
enum GeoDataBootstrap {
    private static let geoipURL = URL(string: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb")!
    private static let geositeURL = URL(string: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat")!

    static var geoipFile: URL { Paths.mihomoHomeDir.appendingPathComponent("geoip.metadb") }
    static var geositeFile: URL { Paths.mihomoHomeDir.appendingPathComponent("geosite.dat") }

    static func isReady() -> Bool {
        let fm = FileManager.default
        guard let geo = try? fm.attributesOfItem(atPath: geoipFile.path)[.size] as? Int64,
              let site = try? fm.attributesOfItem(atPath: geositeFile.path)[.size] as? Int64 else {
            return false
        }
        return geo > 64 * 1024 && site > 64 * 1024
    }

    static func ensurePresent(onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        _ = Paths.mihomoHomeDir
        onProgress?("正在准备 geoip…")
        try await downloadIfNeeded(url: geoipURL, to: geoipFile, label: "geoip")
        onProgress?("正在准备 geosite…")
        try await downloadIfNeeded(url: geositeURL, to: geositeFile, label: "geosite")
        onProgress?("地理库就绪")
    }

    private static func downloadIfNeeded(url: URL, to dest: URL, label: String) async throws {
        if let size = try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64,
           size > 64 * 1024 {
            return
        }
        let (tmp, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "GeoDataBootstrap", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(label) 下载失败"
            ])
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}

enum TunnelLogReader {
    static func lastLines(_ count: Int = 8) -> String {
        guard let text = try? String(contentsOf: Paths.tunnelLogURL, encoding: .utf8) else {
            return ""
        }
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }

    static func lastErrorHint() -> String? {
        let tail = lastLines(12)
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
