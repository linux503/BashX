import Foundation

/// Build the rule list actually written into mihomo config (shared Mac / iOS logic).
enum RuntimeRules {
    /// Clash Verge Merge/Prepend: `prepend` always comes first and survives smart-rule / subscription upgrades.
    static func effective(
        base: [String],
        prepend: [String] = [],
        appRouting: [AppRoutingRule] = [],
        videoAdBlockEnabled: Bool
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
        let merged = VideoAdBlock.merge(into: withPrepend, enabled: videoAdBlockEnabled)
        // Shadowrocket-aligned + GEOIP tail: 国内 DIRECT → 漏网之鱼 PROXY
        // https://github.com/LingJingMaster/Shadowrocket-Rules
        return IosRoutingRules.build(fromBase: adaptForPlatform(merged))
    }

    /// iOS Packet Tunnel cannot match per-process rules; strip heavy geo DBs.
    /// Mac keeps PROCESS-NAME / GEOSITE / GEOIP.
    private static func adaptForPlatform(_ rules: [String]) -> [String] {
        #if os(iOS)
        rules.compactMap { rule in
            let trimmed = rule.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("PROCESS-NAME,") { return nil }
            if upper.hasPrefix("GEOSITE,") { return nil }
            if upper.hasPrefix("GEOIP,") { return nil }
            return rule
        }
        #else
        rules
        #endif
    }
}
