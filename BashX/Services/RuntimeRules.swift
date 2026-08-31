import Foundation

/// Build the rule list actually written into mihomo config (shared Mac / iOS logic).
enum RuntimeRules {
    /// Clash Verge Merge/Prepend: `prepend` always comes first and survives smart-rule / subscription upgrades.
    static func effective(
        base: [String],
        prepend: [String] = [],
        appRouting: [AppRoutingRule] = [],
        videoAdBlockEnabled: Bool,
        enabledPluginIds: [String] = [],
        telegramPushEnabled: Bool = true
    ) -> [String] {
        #if os(macOS)
        let appRules = AppRoutingRules.clashRules(from: appRouting)
        #else
        let appRules: [String] = []
        #endif
        let cleanedPrepend = prepend
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .filter { !$0.uppercased().hasPrefix("MATCH,") }
        let withPrepend = appRules + cleanedPrepend + base
        let mergedAds = VideoAdBlock.merge(into: withPrepend, enabled: videoAdBlockEnabled)
        let merged = PluginEngine.merge(into: mergedAds, enabledIds: enabledPluginIds)
        // Shadowrocket-aligned + GEOIP tail: 国内 DIRECT → 漏网之鱼 PROXY
        // https://github.com/LingJingMaster/Shadowrocket-Rules
        let built = IosRoutingRules.build(fromBase: adaptForPlatform(merged))
        return applyTelegramPushRouting(built, enabled: telegramPushEnabled)
    }

    /// When off: APNs stays DIRECT (system path). When on: push domains + APNs CIDRs → APNS.
    private static func applyTelegramPushRouting(_ rules: [String], enabled: Bool) -> [String] {
        guard !enabled else { return rules }
        let apnsCIDRPrefixes = [
            "IP-CIDR,17.249.",
            "IP-CIDR,17.252.",
            "IP-CIDR,17.57.144.",
            "IP-CIDR,17.188.128.",
            "IP-CIDR,17.188.20.",
            "IP-CIDR6,2620:149:A44:",
            "IP-CIDR6,2403:300:A42:",
            "IP-CIDR6,2403:300:A51:",
            "IP-CIDR6,2A01:B740:A42:",
        ]
        return rules.map { rule in
            let u = rule.uppercased()
            let isPushDomain = u.contains("PUSH.APPLE") || u.contains("PUSH-APPLE.COM")
            let isAPNsCIDR = apnsCIDRPrefixes.contains { u.hasPrefix($0.uppercased()) || rule.uppercased().hasPrefix($0.uppercased()) }
            guard isPushDomain || isAPNsCIDR else { return rule }
            let parts = rule.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { return rule }
            let policy = parts[2].uppercased()
            guard policy == "APNS" || policy == "PROXY" else { return rule }
            var next = parts
            next[2] = "DIRECT"
            return next.joined(separator: ",")
        }
    }

    /// iOS Packet Tunnel cannot match per-process rules; strip heavy geo DBs.
    /// Mac keeps PROCESS-NAME / GEOSITE / GEOIP.
    private static func adaptForPlatform(_ rules: [String]) -> [String] {
        #if os(iOS)
        rules.compactMap { rule in
            let trimmed = rule.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("PROCESS-NAME,") || upper.hasPrefix("PROCESS-PATH,") { return nil }
            if upper.hasPrefix("GEOSITE,") { return nil }
            if upper.hasPrefix("GEOIP,") { return nil }
            return rule
        }
        #else
        rules
        #endif
    }
}
