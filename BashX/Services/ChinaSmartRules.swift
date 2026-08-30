import Foundation

enum ChinaSmartRules {
    /// Bump when bundled rule set changes so existing installs auto-upgrade.
    static let version = 24

    /// Published rules list (also shipped at Resources/rules/bashx-smart-rules.txt).
    static let rules: [String] = loadBundledRules()

    /// CDN / website mirror of the bundled rules file (for docs & manual import).
    static let publishedRulesURL = "https://cdn.jsdelivr.net/gh/BashX/BashX@main/Resources/rules/bashx-smart-rules.txt"
    static let manifestURL = "https://cdn.jsdelivr.net/gh/BashX/BashX@main/Resources/rules/manifest.json"

    static func parseRulesText(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func loadBundledRules() -> [String] {
        if let url = findBundledRulesFileURL(),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let parsed = parseRulesText(text)
            if !parsed.isEmpty { return parsed }
        }
        return embeddedFallback
    }

    private static func findBundledRulesFileURL() -> URL? {
        for sub in ["rules", "Resources/rules"] {
            if let url = Bundle.main.url(forResource: "bashx-smart-rules", withExtension: "txt", subdirectory: sub) {
                return url
            }
        }
        return Bundle.main.url(forResource: "bashx-smart-rules", withExtension: "txt")
    }

    /// Minimal fallback if Resources/rules missing (dev/tests).
    private static let embeddedFallback: [String] = [
        "DOMAIN-SUFFIX,local,REJECT",
        "DOMAIN-SUFFIX,localhost,DIRECT",
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "GEOSITE,category-ads-all,REJECT",
        "GEOSITE,cn,DIRECT",
        "GEOSITE,private,DIRECT",
        "GEOSITE,gfw,PROXY",
        "GEOSITE,geolocation-!cn,PROXY",
        "GEOIP,CN,DIRECT,no-resolve",
        "GEOIP,!CN,PROXY,no-resolve",
        "MATCH,PROXY"
    ]

    static func looksLikeLegacy(_ rules: [String]) -> Bool {
        guard rules.count <= 12 else { return false }
        let set = Set(rules)
        return set.contains("MATCH,PROXY")
            && (set.contains("DOMAIN-SUFFIX,local,REJECT") || set.contains("DOMAIN-SUFFIX,local,DIRECT"))
            && !set.contains(where: { $0.hasPrefix("GEOSITE,") })
    }

    /// Broken / outdated smart sets that should be replaced.
    static func needsUpgrade(_ rules: [String], storedVersion: Int?) -> Bool {
        if (storedVersion ?? 0) < version { return true }
        if looksLikeLegacy(rules) { return true }
        if rules.contains(where: { $0.hasPrefix("GEOSITE,gmail") }) { return true }
        if rules.contains(where: { $0.hasPrefix("DOMAIN,www.gstatic.com,DIRECT") }) { return true }
        if rules.contains(where: { $0.uppercased() == "DOMAIN-SUFFIX,LOCAL,DIRECT" }) { return true }
        // v7: fix GeoSite tags missing from MetaCubeX GeoSite.dat (core fatal on startup)
        if rules.contains(where: { GeoSiteRules.isKnownBroken($0) }) { return true }
        if rules.contains(where: { $0.contains("category-media-!cn") }) { return true }
        if rules.contains(where: { $0.contains("category-crypto-!cn") }) { return true }
        if rules.contains(where: { $0.contains("category-entertainment-!cn") }) { return true }
        if rules.contains(where: { GeoSiteRules.rule($0, usesSite: "stackoverflow") }) { return true }
        if !rules.contains(where: { $0.contains("telegram-cdn.org") }) { return true }
        if !rules.contains(where: { $0.contains("graph.org") }) { return true }
        // v13: Telegram dedicated group + DC CIDRs
        if !rules.contains(where: { $0.contains(",TELEGRAM") }) { return true }
        if !rules.contains(where: { $0.contains("149.154.160.0/20") }) { return true }
        // v15: translate-pa API must be listed before category-ads-all
        if !rules.contains(where: { $0.contains("translate-pa.googleapis.com") }) { return true }
        // v16: full Telegram DC block 91.108.0.0/16 (partial /22 lists miss DCs → spinning)
        if !rules.contains(where: { $0.contains("91.108.0.0/16") }) { return true }
        // v17: drop GeoSite tags missing from MetaCubeX dat (core restart loop)
        if rules.contains(where: { $0.contains("category-education-!cn") }) { return true }
        if rules.contains(where: { $0.contains("category-ecommerce-!cn") }) { return true }
        // v18: Telegra2.app PROCESS-PATH (masqueraded Telegram installs)
        if !rules.contains(where: { $0.contains("Telegra2") }) { return true }
        // v19: Shadowrocket-Rules inspired — AI sticky + Apple Push proxy + HK banks/brokers
        if !rules.contains(where: { $0.contains(",CURSOR") || $0.contains("cursor.sh") }) { return true }
        if !rules.contains(where: { $0.contains("hsbc.com.hk") }) { return true }
        if !rules.contains(where: { $0.contains("push.apple.com,PROXY") }) { return true }
        // v20: Cursor Electron helpers + CDN/VM must stick to CURSOR (not PROXY/AUTO thrash)
        if !rules.contains(where: { $0.contains("Cursor Helper") }) { return true }
        if !rules.contains(where: { $0.contains("cursor-cdn.com") }) { return true }
        // v22: GEOIP,!CN + centralized geo tail (Shadowrocket/Surge/Clash Verge)
        if !rules.contains(where: { $0.uppercased().hasPrefix("GEOIP,!CN,") }) { return true }
        // v23: Shadowrocket DEST-PORT → mihomo DST-PORT
        if rules.contains(where: { $0.contains("DEST-PORT,") }) { return true }
        // v24: .tv PROXY + drop broad .tv QUIC REJECT
        if rules.contains(where: { $0.contains("DOMAIN-SUFFIX,tv,(NETWORK,UDP)") || $0.contains("((DOMAIN-SUFFIX,tv),(NETWORK,UDP)") }) { return true }
        return false
    }

    /// Copy bundled rules to support dir for user inspection / external tools.
    static func publishRulesToDisk() {
        let url = findBundledRulesFileURL() ?? Paths.supportDir.appendingPathComponent("bashx-smart-rules.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? rules.joined(separator: "\n")
        try? text.write(to: Paths.rulesURL, atomically: true, encoding: .utf8)
    }
}
