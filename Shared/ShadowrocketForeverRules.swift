import Foundation

/// [Shadowrocket-ADBlock-Rules-Forever](https://github.com/Johnshall/Shadowrocket-ADBlock-Rules-Forever)
/// — daily-updated SR rules → mihomo local `RULE-SET` (Mac + iOS).
enum ShadowrocketForeverRules {
    static let cdnBase = "https://johnshall.github.io/Shadowrocket-ADBlock-Rules-Forever/"
    static let adOnlyURL = URL(string: cdnBase + "sr_ad_only.conf")!
    static let banlistURL = URL(string: cdnBase + "sr_top500_banlist_ad.conf")!

    static let rejectProvider = "SR-REJECT"
    static let proxyProvider = "SR-PROXY"

    private static let refreshInterval: TimeInterval = 24 * 3600
    private static let metaFileName = "sr-forever-meta.json"

    private struct Meta: Codable {
        var fetchedAt: Date
        var rejectCount: Int
        var proxyCount: Int
    }

    private static var metaURL: URL {
        Paths.supportDir.appendingPathComponent(metaFileName)
    }

    /// Mac: `supportDir/mihomo` is the core binary — never nest under it.
    /// iOS: App Group home is a real directory; keep rules beside other mihomo data.
    private static var rulesDir: URL {
        #if os(macOS)
        let dir = Paths.supportDir.appendingPathComponent("rules", isDirectory: true)
        #else
        let dir = Paths.mihomoHomeDir.appendingPathComponent("rules", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var rejectFile: URL {
        rulesDir.appendingPathComponent("sr-reject.classical")
    }

    private static var proxyFile: URL {
        rulesDir.appendingPathComponent("sr-proxy.classical")
    }

    static var isReady: Bool {
        guard let meta = loadMeta() else { return false }
        return meta.rejectCount > 0
            && FileManager.default.fileExists(atPath: rejectFile.path)
            && FileManager.default.fileExists(atPath: proxyFile.path)
    }

    /// Short label for rules editor / status bar.
    static var statusLine: String? {
        guard let meta = loadMeta(), isReady else { return nil }
        return "Shadowrocket 去广告 \(meta.rejectCount) · GFW 代理 \(meta.proxyCount)"
    }

    /// Prepend after WeChat / plugin REJECT hoists.
    static func headerRules() -> [String] {
        guard isReady else { return [] }
        return [
            "RULE-SET,\(rejectProvider),REJECT",
            "RULE-SET,\(proxyProvider),PROXY",
        ]
    }

    static func ruleProvidersBlock() -> [String: Any] {
        guard isReady else { return [:] }
        return [
            rejectProvider: [
                "type": "file",
                "behavior": "classical",
                "format": "text",
                "path": rejectFile.path,
            ],
            proxyProvider: [
                "type": "file",
                "behavior": "classical",
                "format": "text",
                "path": proxyFile.path,
            ],
        ]
    }

    static func isLocalRuleSet(_ name: String) -> Bool {
        name == rejectProvider || name == proxyProvider
    }

    static func ensurePresent(progress: ((String) -> Void)? = nil) async throws {
        if let meta = loadMeta() {
            if Date().timeIntervalSince(meta.fetchedAt) < refreshInterval { return }
            Task.detached(priority: .utility) {
                try? await refresh(progress: progress)
            }
            return
        }
        try await refresh(progress: progress)
    }

    @discardableResult
    static func refresh(progress: ((String) -> Void)? = nil) async throws -> (reject: Int, proxy: Int) {
        progress?("正在更新 Shadowrocket 规则…")
        async let adData = URLSession.shared.data(from: adOnlyURL)
        async let banData = URLSession.shared.data(from: banlistURL)
        let (adPayload, _) = try await adData
        let (banPayload, _) = try await banData
        guard let adText = String(data: adPayload, encoding: .utf8),
              let banText = String(data: banPayload, encoding: .utf8) else {
            throw NSError(domain: "ShadowrocketForeverRules", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Shadowrocket 规则下载失败",
            ])
        }

        let rejectRules = parseRuleSection(adText, policies: ["REJECT"])
        let proxyRules = parseRuleSection(banText, policies: ["PROXY"])
        guard !rejectRules.isEmpty else {
            throw NSError(domain: "ShadowrocketForeverRules", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Shadowrocket 去广告规则为空",
            ])
        }

        try writeClassical(rejectRules, to: rejectFile)
        try writeClassical(proxyRules, to: proxyFile)
        let meta = Meta(fetchedAt: Date(), rejectCount: rejectRules.count, proxyCount: proxyRules.count)
        try saveMeta(meta)
        progress?("Shadowrocket 规则已更新（广告 \(meta.rejectCount) · 代理 \(meta.proxyCount)）")
        return (meta.rejectCount, meta.proxyCount)
    }

    // MARK: - Parse SR .conf [Rule]

    private static func parseRuleSection(_ text: String, policies wanted: Set<String>) -> [String] {
        var inRule = false
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(wanted.contains("REJECT") ? 60_000 : 35_000)

        for raw in text.split(whereSeparator: \.isNewline) {
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            if line == "[Rule]" {
                inRule = true
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inRule = false
                continue
            }
            guard inRule else { continue }
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if let hash = line.range(of: " #") {
                line = String(line[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            guard let rule = clashRule(from: line, wanted: wanted) else { continue }
            guard !seen.contains(rule) else { continue }
            seen.insert(rule)
            out.append(rule)
        }
        return out
    }

    private static func clashRule(from line: String, wanted: Set<String>) -> String? {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 3 else { return nil }
        let type = parts[0].uppercased()
        if type == "RULE-SET" || type == "USER-AGENT" || type == "URL-REGEX" { return nil }
        guard let policy = normalizePolicy(parts[2]) else { return nil }
        guard wanted.contains(policy) else { return nil }

        switch type {
        case "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX":
            return "\(type),\(parts[1]),\(policy)"
        case "IP-CIDR", "IP-CIDR6":
            let suffix = parts.count > 3 && parts[3].lowercased() == "no-resolve" ? ",no-resolve" : ""
            return "\(type),\(parts[1]),\(policy)\(suffix)"
        case "GEOIP":
            return "\(type),\(parts[1]),\(policy)"
        default:
            return nil
        }
    }

    private static func normalizePolicy(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespaces).uppercased() {
        case "REJECT", "REJECT-DROP", "REJECT-NO-DROP": return "REJECT"
        case "PROXY", "代理": return "PROXY"
        case "DIRECT", "直连": return "DIRECT"
        default: return nil
        }
    }

    private static func writeClassical(_ rules: [String], to url: URL) throws {
        let body = rules.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }

    private static func saveMeta(_ meta: Meta) throws {
        try FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaURL, options: .atomic)
    }
}
