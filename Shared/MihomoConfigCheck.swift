import Foundation

enum MihomoConfigCheck {
    static func validateFile(at url: URL = Paths.mihomoConfigURL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "配置文件不存在"
        }
        guard let yaml = try? String(contentsOf: url, encoding: .utf8), !yaml.isEmpty else {
            return "配置文件为空"
        }
        if !yaml.contains("proxies:") {
            return "配置缺少节点（proxies）"
        }

        let tunnelCapture = isTunnelCaptureEnabled()
        if tunnelCapture {
            if !yaml.contains("tun:") {
                return "配置缺少 TUN 段"
            }
        } else {
            // HTTP 代理实验：无 tun:，但必须有可用 mixed-port。
            if !hasPositiveMixedPort(yaml) {
                return "HTTP 代理模式配置缺少 mixed-port"
            }
        }
        return nil
    }

    static func preflight() -> String? {
        #if os(iOS)
        if !Paths.usesAppGroup {
            return "App Group 不可用，VPN 无法与主程序共享配置（请检查签名/描述文件）"
        }
        #else
        if !GeoDataBootstrap.isReady() {
            return "地理数据库未就绪"
        }
        #endif
        return validateFile()
    }

    /// Default true (TUN). Explicit App Group false → HTTP-proxy-only experiment.
    private static func isTunnelCaptureEnabled() -> Bool {
        #if os(iOS)
        let ud = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        if ud?.object(forKey: AppConstants.iosTunnelCaptureKey) == nil { return true }
        return ud?.bool(forKey: AppConstants.iosTunnelCaptureKey) ?? true
        #else
        return true
        #endif
    }

    private static func hasPositiveMixedPort(_ yaml: String) -> Bool {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("mixed-port:") else { continue }
            let value = trimmed
                .dropFirst("mixed-port:".count)
                .trimmingCharacters(in: .whitespaces)
            if let port = Int(value), port > 0 { return true }
        }
        return false
    }
}
