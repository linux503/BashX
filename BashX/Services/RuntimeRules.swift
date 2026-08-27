import Foundation

/// Build the rule list actually written into mihomo config (shared Mac / iOS logic).
enum RuntimeRules {
    static func effective(base: [String], videoAdBlockEnabled: Bool) -> [String] {
        let merged = VideoAdBlock.merge(into: base, enabled: videoAdBlockEnabled)
        #if os(iOS)
        return GeoSiteRules.sanitize(insertIosProxyRules(into: adaptForPlatform(merged)))
        #else
        return GeoSiteRules.sanitize(adaptForPlatform(merged))
        #endif
    }

    #if os(iOS)
    private static func insertIosProxyRules(into rules: [String]) -> [String] {
        var body = rules.filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("MATCH,") }
        body.append(contentsOf: IosDirectDomains.rules)
        body.append(contentsOf: IosProxyDomains.rules)
        // Final catch-all PROXY — MATCH,DIRECT sent Google/Telegram to DIRECT (0 PROXY hits in tunnel logs).
        body.append("MATCH,PROXY")
        return body
    }
    #endif

    /// iOS Packet Tunnel cannot match per-process rules; strip them (GEOSITE covers the same apps).
    private static func adaptForPlatform(_ rules: [String]) -> [String] {
        #if os(iOS)
        rules.filter { rule in
            let upper = rule.trimmingCharacters(in: .whitespaces).uppercased()
            if upper.hasPrefix("PROCESS-NAME,") { return false }
            // NE memory budget: skip geosite/geoip (multi-MB DB load crashes extension).
            if upper.hasPrefix("GEOSITE,") { return false }
            if upper.hasPrefix("GEOIP,") { return false }
            return true
        }
        #else
        rules
        #endif
    }
}
