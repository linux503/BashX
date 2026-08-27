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
        if !yaml.contains("tun:") {
            return "配置缺少 TUN 段"
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
}
