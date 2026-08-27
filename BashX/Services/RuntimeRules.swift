import Foundation

/// Build the rule list actually written into mihomo config (shared Mac / iOS logic).
enum RuntimeRules {
    static func effective(base: [String], videoAdBlockEnabled: Bool) -> [String] {
        let merged = VideoAdBlock.merge(into: base, enabled: videoAdBlockEnabled)
        return GeoSiteRules.sanitize(adaptForPlatform(merged))
    }

    /// iOS Packet Tunnel cannot match per-process rules; strip them (GEOSITE covers the same apps).
    private static func adaptForPlatform(_ rules: [String]) -> [String] {
        #if os(iOS)
        rules.filter { rule in
            let upper = rule.trimmingCharacters(in: .whitespaces).uppercased()
            return !upper.hasPrefix("PROCESS-NAME,")
        }
        #else
        rules
        #endif
    }
}
