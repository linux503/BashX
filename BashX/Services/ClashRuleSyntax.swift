import Foundation

/// Lightweight Clash/mihomo rule line helpers for the Rules editor.
enum ClashRuleSyntax {
    static let knownTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX",
        "GEOSITE", "GEOIP", "IP-CIDR", "IP-CIDR6",
        "PROCESS-NAME", "PROCESS-PATH", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX",
        "RULE-SET", "MATCH",
        "SRC-IP-CIDR", "SRC-IP-CIDR6", "SRC-PORT", "DST-PORT",
        "IN-TYPE", "IN-USER", "IN-NAME",
        "NETWORK", "UID", "AND", "OR", "NOT", "SUB-RULE",
    ]

    static let knownPolicies: Set<String> = [
        "PROXY", "AUTO", "GOOGLE", "TELEGRAM", "DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE",
    ]

    static func parseLines(_ text: String) -> [String] {
        ChinaSmartRules.parseRulesText(text)
    }

    /// Human-readable issues for the editor (empty = OK).
    static func validate(_ text: String) -> [String] {
        var issues: [String] = []
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hasMatch = false
        for (idx, raw) in rawLines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let n = idx + 1
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard let type = parts.first?.uppercased(), !type.isEmpty else {
                issues.append("第 \(n) 行：空规则")
                continue
            }
            if !knownTypes.contains(type) {
                issues.append("第 \(n) 行：未知类型 \(parts[0])")
            }
            if type == "MATCH" {
                hasMatch = true
                if parts.count < 2 {
                    issues.append("第 \(n) 行：MATCH 需要策略（如 MATCH,PROXY）")
                }
                continue
            }
            if parts.count < 3 {
                issues.append("第 \(n) 行：格式应为 类型,值,策略")
                continue
            }
            if parts[2].isEmpty {
                issues.append("第 \(n) 行：缺少策略")
            }
            if type == "GEOSITE", GeoSiteRules.isKnownBroken(line) {
                issues.append("第 \(n) 行：GEOSITE 标签无效，保存时会自动移除")
            }
        }
        if !hasMatch, !parseLines(text).isEmpty {
            issues.append("建议末尾保留 MATCH,PROXY 作为兜底")
        }
        return issues
    }
}
