import Foundation

enum ChinaSmartRules {
    /// Bump when bundled rule set changes so existing installs auto-upgrade.
    static let version = 52

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
        "DOMAIN-SUFFIX,local,DIRECT",
        "DOMAIN-SUFFIX,localhost,DIRECT",
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "GEOSITE,category-ads-all,REJECT",
        "GEOSITE,cn,DIRECT",
        "GEOSITE,private,DIRECT",
        "GEOSITE,gfw,PROXY",
        "GEOSITE,geolocation-!cn,PROXY",
        "GEOIP,CN,DIRECT,no-resolve",
        "MATCH,PROXY",
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
        if !rules.contains(where: {
            $0.contains("push.apple.com,APNS") || $0.contains("push.apple.com,PROXY")
        }) { return true }
        // v20: Cursor Electron helpers + CDN/VM must stick to CURSOR (not PROXY/AUTO thrash)
        if !rules.contains(where: { $0.contains("Cursor Helper") }) { return true }
        if !rules.contains(where: { $0.contains("cursor-cdn.com") }) { return true }
        // v23: Shadowrocket DEST-PORT → mihomo DST-PORT
        if rules.contains(where: { $0.contains("DEST-PORT,") }) { return true }
        // v24: .tv PROXY + drop broad .tv QUIC REJECT
        if rules.contains(where: { $0.contains("DOMAIN-SUFFIX,tv,(NETWORK,UDP)") || $0.contains("((DOMAIN-SUFFIX,tv),(NETWORK,UDP)") }) { return true }
        // v25: 政务/银行直连 + 微信 HTTPDNS 直连
        if !rules.contains(where: { $0.contains("DOMAIN-SUFFIX,bank,DIRECT") }) { return true }
        if rules.contains(where: { $0.uppercased().contains("DNS.WEIXIN.QQ.COM") && $0.uppercased().contains("REJECT") }) { return true }
        // v27: 国内 App 默认直连 + Cursor Network helper + 勿泛匹配 .org
        if rules.contains(where: { $0.uppercased().contains("BILIBILI.COM,BILIBILI") }) { return true }
        if rules.contains(where: { $0.uppercased().contains("DOUYIN.COM,DOUYIN") }) { return true }
        if rules.contains(where: { $0.uppercased() == "DOMAIN-SUFFIX,ORG,DIRECT" }) { return true }
        if rules.contains(where: { $0.uppercased() == "DOMAIN-SUFFIX,LOCAL,REJECT" }) { return true }
        if !rules.contains(where: { $0.contains("Cursor Helper (Network)") }) { return true }
        if !rules.contains(where: { $0.contains("api2.cursor.sh") }) { return true }
        if !rules.contains(where: { $0.contains("wikipedia.org,PROXY") }) { return true }
        // v28: force rewrite — prior builds re-injected GEOSITE/PROCESS into iOS yaml (core start fail)
        if (storedVersion ?? 0) < 28 { return true }
        // v29: drop Cursor PROCESS-NAME hijack (forces all IDE egress via US sticky → busy/broken)
        if rules.contains(where: {
            let u = $0.uppercased()
            return u.hasPrefix("PROCESS-NAME,CURSOR") || u.hasPrefix("PROCESS-PATH,*CURSOR")
        }) { return true }
        if (storedVersion ?? 0) < 29 { return true }
        // v30: APNs via dedicated APNS group + Apple push CIDRs (fix DIRECT 17.249 conflict)
        if !rules.contains(where: { $0.contains("push.apple.com,APNS") }) { return true }
        if !rules.contains(where: { $0.contains("17.249.0.0/16,APNS") }) { return true }
        if (storedVersion ?? 0) < 30 { return true }
        // v31: Asia-first APNS + APNs IPv6 CIDRs (avoid US PROXY pin / Happy-Eyeballs stall)
        if !rules.contains(where: { $0.contains("2620:149:a44::/48,APNS") || $0.contains("IP-CIDR6,2620:149:a44::/48,APNS") }) { return true }
        if (storedVersion ?? 0) < 31 { return true }
        // v35: AdsPower / SunBrowser must DIRECT (own proxy stack + CN CDN for app.adspower.net)
        if !rules.contains(where: { $0.contains("adspower.net,DIRECT") || $0.contains("AdsPower Global,DIRECT") }) { return true }
        if (storedVersion ?? 0) < 35 { return true }
        // v36 was MATCH,DIRECT; v46 restored MATCH,PROXY + GEOIP,!CN (Clash Verge).
        // Do not treat those as stale — they are required on Mac TUN.
        if (storedVersion ?? 0) < 36 { return true }
        // v37: Binance sticky PROXY (trading WS)
        if !rules.contains(where: { $0.contains("binance.com,PROXY") }) { return true }
        if (storedVersion ?? 0) < 37 { return true }
        // v38: Huobi / HTX sticky PROXY (trading WS)
        if !rules.contains(where: { $0.contains("htx.com,PROXY") || $0.contains("huobi.com,PROXY") }) { return true }
        if (storedVersion ?? 0) < 38 { return true }
        // v39: Binance CDN / vision / nftstatic sticky PROXY
        if !rules.contains(where: { $0.contains("binance.vision,PROXY") || $0.contains("nftstatic.com,PROXY") || $0.contains("ficus.cc,PROXY") }) { return true }
        if (storedVersion ?? 0) < 39 { return true }
        // v40–v43: historical TikTok domain / group migrations (skip if already past)
        if (storedVersion ?? 0) < 43 { return true }
        // v44: 大陆抖音 snssdk.com 必须 DIRECT；国际 TikTok 用 isnssdk / tiktok*
        if rules.contains(where: { $0.contains("snssdk.com,TIKTOK") || $0.contains("snssdk.com,PROXY") }) { return true }
        if !rules.contains(where: { $0.contains("snssdk.com,DIRECT") }) { return true }
        if !rules.contains(where: { $0.contains("isnssdk.com,TIKTOK") || $0.contains("tiktok.com,TIKTOK") }) { return true }
        if (storedVersion ?? 0) < 44 { return true }
        // v45 historical; v46 Mac MATCH,PROXY + GEOIP,!CN
        if (storedVersion ?? 0) < 46 { return true }
        // v47 historical process-DIRECT for Ads — superseded by v49 domain-only
        if (storedVersion ?? 0) < 47 { return true }
        // v48: IPFoxy purchase / gate must PROXY (Aliyun HK IP often GEOIP,CN → region blocked)
        if !rules.contains(where: { $0.contains("ipfoxy.com,PROXY") }) { return true }
        if (storedVersion ?? 0) < 48 { return true }
        // v49: drop AdsPower/SunBrowser process DIRECT (blocks IPFoxy S5 chain)
        if rules.contains(where: {
            let u = $0.uppercased()
            let isProc = u.hasPrefix("PROCESS-NAME,") || u.hasPrefix("PROCESS-PATH,")
                || u.hasPrefix("PROCESS-NAME-REGEX,") || u.hasPrefix("PROCESS-PATH-REGEX,")
            return isProc && (u.contains("ADSPOWER") || u.contains("SUNBROWSER"))
        }) { return true }
        if !rules.contains(where: { $0.contains("adspower.net,") }) { return true }
        if (storedVersion ?? 0) < 49 { return true }
        // v50: AdsPower control-plane must PROXY (ip-scan DIRECT → false「连接测试失败」)
        if rules.contains(where: { $0.contains("adspower.net,DIRECT") }) { return true }
        if !rules.contains(where: { $0.contains("adspower.net,PROXY") }) { return true }
        if (storedVersion ?? 0) < 50 { return true }
        // v51: drop GEOIP,!CN — ACL4SSR / 小火箭都不写；漏网之鱼用 MATCH
        if rules.contains(where: { $0.uppercased().contains("GEOIP,!CN") }) { return true }
        if (storedVersion ?? 0) < 51 { return true }
        if (storedVersion ?? 0) < 52 { return true }
        return false
    }

    /// Copy bundled rules to support dir for user inspection / external tools.
    static func publishRulesToDisk() {
        let url = findBundledRulesFileURL() ?? Paths.supportDir.appendingPathComponent("bashx-smart-rules.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? rules.joined(separator: "\n")
        try? text.write(to: Paths.rulesURL, atomically: true, encoding: .utf8)
    }
}
