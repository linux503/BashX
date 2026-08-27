import Foundation

/// Keeps GEOSITE rules compatible with MetaCubeX GeoSite.dat (mihomo crashes on unknown lists).
enum GeoSiteRules {
    /// Deprecated rule tags → current names in GeoSite.dat.
    private static let renames: [String: String] = [
        "category-media-!cn": "category-media",
        "category-crypto-!cn": "category-cryptocurrency",
        "category-entertainment-!cn": "category-entertainment",
    ]

    /// Lists that must never appear (crash or renamed away).
    private static let blockedSites: Set<String> = [
        "category-ads-cn",
        "category-media-!cn",
        "category-crypto-!cn",
        "category-entertainment-!cn",
        // Not present in current MetaCubeX GeoSite.dat (mihomo fatal)
        "stackoverflow",
        "bbc",
        "cnn",
        "ubi",
        "aws",
    ]

    static func sanitize(_ rules: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        out.reserveCapacity(rules.count)
        seen.reserveCapacity(rules.count)
        for raw in rules {
            guard let fixed = sanitizeOne(raw) else { continue }
            if seen.insert(fixed).inserted {
                out.append(fixed)
            }
        }
        return out
    }

    static func isKnownBroken(_ rule: String) -> Bool {
        guard let site = geositeName(in: rule) else { return false }
        return blockedSites.contains(site)
    }

    static func rule(_ rule: String, usesSite site: String) -> Bool {
        geositeName(in: rule)?.lowercased() == site.lowercased()
    }

    /// Parse mihomo log: `list category-media-!cn not found in GeoSite.dat`
    static func parseMissingGeoSite(from log: String) -> String? {
        guard let start = log.range(of: "list ") else { return nil }
        let tail = log[start.upperBound...]
        guard let end = tail.range(of: " not found") else { return nil }
        let name = String(tail[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: - Private

    private static func sanitizeOne(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        guard trimmed.uppercased().hasPrefix("GEOSITE,") else { return trimmed }

        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return trimmed }

        var site = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        if blockedSites.contains(site) { return nil }
        if let renamed = renames[site] { site = renamed }

        let rest = parts.dropFirst(2).map { $0.trimmingCharacters(in: .whitespaces) }
        return (["GEOSITE", site] + rest).joined(separator: ",")
    }

    private static func geositeName(in rule: String) -> String? {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        guard trimmed.uppercased().hasPrefix("GEOSITE,") else { return nil }
        let parts = trimmed.split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces).lowercased()
    }
}
