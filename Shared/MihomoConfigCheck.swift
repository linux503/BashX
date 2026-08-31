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
        scrubStaleGeoDatabases()
        if !Paths.usesAppGroup {
            return "App Group 不可用，VPN 无法与主程序共享配置（请检查签名/描述文件）"
        }
        #else
        if !GeoDataBootstrap.isReady() {
            return "地理数据库未就绪"
        }
        #endif
        if let err = validateFile() { return err }
        if let err = detectMissingProxyGroups() { return err }
        return detectProxyGroupLoop()
    }

    #if os(iOS)
    /// Remove geo DBs that make mihomo hang downloading GitHub inside the NE.
    static func scrubStaleGeoDatabases() {
        let fm = FileManager.default
        let home = Paths.mihomoHomeDir
        for name in ["geoip.metadb", "geosite.dat", "GeoSite.dat", "country.mmdb", "GeoLite2-Country.mmdb"] {
            let url = home.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }
    #endif

    /// Mihomo rejects configs when a group lists a member that was never defined.
    static func detectMissingProxyGroups(at url: URL = Paths.mihomoConfigURL) -> String? {
        guard let yaml = try? String(contentsOf: url, encoding: .utf8), !yaml.isEmpty else { return nil }
        var defined = Set<String>()
        var references: [(group: String, member: String)] = []
        var current: String?
        var inProxies = false
        for raw in yaml.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- name:") || line.hasPrefix("name:") {
                let name = line
                    .replacingOccurrences(of: "- name:", with: "")
                    .replacingOccurrences(of: "name:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                current = name
                defined.insert(name)
                inProxies = false
                continue
            }
            guard let cur = current else { continue }
            if line == "proxies:" || line.hasPrefix("proxies:") {
                inProxies = true
                continue
            }
            if !inProxies { continue }
            if line.hasPrefix("- ") {
                let member = line.dropFirst(2)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                references.append((cur, member))
            } else if !line.isEmpty && !line.hasPrefix("#") {
                inProxies = false
            }
        }
        let reserved: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS"]
        for ref in references where !reserved.contains(ref.member) {
            if !defined.contains(ref.member) {
                return "策略组 \(ref.group) 引用了不存在的 \(ref.member)，请更新订阅后重连"
            }
        }
        return nil
    }

    /// Mihomo refuses configs where select groups reference each other (e.g. PROXY↔AI).
    static func detectProxyGroupLoop(at url: URL = Paths.mihomoConfigURL) -> String? {
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let groups = ["PROXY", "GOOGLE", "AI", "AUTO", "BALANCE", "FALLBACK", "JP", "HK", "US", "TW", "TELEGRAM", "APNS", "CURSOR", "OPENAI", "ANTHROPIC", "GOOGLE-AUTO", "TELEGRAM-AUTO"]
        var edges: [String: Set<String>] = [:]
        let lines = yaml.components(separatedBy: .newlines)
        var current: String?
        var inProxies = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- name:") || line.hasPrefix("name:") {
                let name = line
                    .replacingOccurrences(of: "- name:", with: "")
                    .replacingOccurrences(of: "name:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                current = groups.contains(name) ? name : nil
                inProxies = false
                continue
            }
            guard let cur = current else { continue }
            if line == "proxies:" || line.hasPrefix("proxies:") {
                inProxies = true
                continue
            }
            if !inProxies { continue }
            if line.hasPrefix("- ") {
                let member = line.dropFirst(2)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if groups.contains(member) {
                    edges[cur, default: []].insert(member)
                }
            } else if !line.isEmpty && !line.hasPrefix("#") {
                // Next group field — stop collecting members.
                inProxies = false
            }
        }
        // Detect 2-cycles (most common) and simple self-loops.
        for (a, outs) in edges {
            if outs.contains(a) { return "策略组自引用：\(a)" }
            for b in outs where edges[b]?.contains(a) == true {
                return "策略组互相引用（\(a)↔\(b)），请更新订阅后重连"
            }
        }
        return nil
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
