import Foundation

/// High-priority REJECT rules for ads: video sites, app splash/interstitial SDKs,
/// ecommerce redirect / affiliate jumps (JD / Tmall / Taobao / PDD etc.).
/// Domain-level only — cannot strip ads served from the same CDN as content itself.
enum VideoAdBlock {
    static let rules: [String] = loadBundledRules()

    /// Extra geosite categories lifted to the front (before CN DIRECT).
    /// Only use lists that exist in MetaCubeX GeoSite.dat (category-ads-cn does NOT).
    private static let geositePriority: [String] = [
        "GEOSITE,category-ads-all,REJECT",
    ]

    /// Known-bad / renamed geosite rules that crash mihomo on startup.
    static let brokenGeositeRules: Set<String> = [
        "GEOSITE,category-ads-cn,REJECT",
        "GEOSITE,category-ads-cn,DIRECT",
        "GEOSITE,category-ads-cn,PROXY",
    ]

    /// Prepend ad REJECT rules (high priority). Removes previous copies to avoid dupes.
    static func merge(into base: [String], enabled: Bool) -> [String] {
        let adDomains = Set(rules)
        var cleaned = base.filter { rule in
            let trimmed = rule.trimmingCharacters(in: .whitespaces)
            if adDomains.contains(trimmed) { return false }
            if isBrokenGeosite(trimmed) { return false }
            let upper = trimmed.uppercased()
            if upper.hasPrefix("GEOSITE,CATEGORY-ADS") { return false }
            return true
        }
        guard enabled else { return cleaned }
        return geositePriority + rules + cleaned
    }

    static func isBrokenGeosite(_ rule: String) -> Bool {
        let upper = rule.trimmingCharacters(in: .whitespaces).uppercased()
        if brokenGeositeRules.contains(where: { $0.uppercased() == upper }) { return true }
        return upper.hasPrefix("GEOSITE,CATEGORY-ADS-CN,")
    }

    static var ruleCount: Int { geositePriority.count + rules.count }

    private static func loadBundledRules() -> [String] {
        for sub in ["rules", "Resources/rules"] {
            if let url = Bundle.main.url(forResource: "bashx-adblock", withExtension: "txt", subdirectory: sub),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                let parsed = parse(text)
                if !parsed.isEmpty { return parsed }
            }
        }
        if let url = Bundle.main.url(forResource: "bashx-adblock", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let parsed = parse(text)
            if !parsed.isEmpty { return parsed }
        }
        return embeddedFallback
    }

    private static func parse(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Minimal fallback if the bundled list is missing (dev / tests).
    private static let embeddedFallback: [String] = [
        "DOMAIN-SUFFIX,doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,googleadservices.com,REJECT",
        "DOMAIN-SUFFIX,googlesyndication.com,REJECT",
        "DOMAIN-SUFFIX,adservice.google.com,REJECT",
        "DOMAIN-KEYWORD,pagead,REJECT",
        "DOMAIN-KEYWORD,doubleclick,REJECT",
        "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
        "DOMAIN-SUFFIX,cupid.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,atm.youku.com,REJECT",
        "DOMAIN-SUFFIX,l.qq.com,REJECT",
        "DOMAIN-SUFFIX,e.qq.com,REJECT",
        "DOMAIN-SUFFIX,pgdt.gtimg.cn,REJECT",
        "DOMAIN-SUFFIX,umeng.com,REJECT",
        "DOMAIN-SUFFIX,tanx.com,REJECT",
        "DOMAIN-SUFFIX,sigmob.com,REJECT",
        "DOMAIN-SUFFIX,applovin.com,REJECT",
        "DOMAIN-SUFFIX,unityads.unity3d.com,REJECT",
        "DOMAIN,s.click.taobao.com,REJECT",
        "DOMAIN,u.jd.com,REJECT",
        "DOMAIN,union-click.jd.com,REJECT",
        "DOMAIN-SUFFIX,duomai.com,REJECT",
    ]
}
