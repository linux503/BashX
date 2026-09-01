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
        "PROXY", "AUTO", "GOOGLE", "TELEGRAM", "APNS", "DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE",
        "OPENAI", "ANTHROPIC", "COPILOT", "AI", "CURSOR",
        "NETFLIX", "BILIBILI", "DOUYIN", "TIKTOK", "TWITTER", "WHATSAPP",
        "MICROSOFT", "APPLE", "STEAM", "JP", "HK", "TW", "US",
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
            issues.append("建议末尾保留 MATCH,DIRECT 或 MATCH,PROXY 作为兜底")
        }
        return issues
    }

    /// Build a clash rule from a pasted IP / CIDR / domain. Returns nil if unusable.
    static func quickRule(from raw: String, policy: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let policy = policy.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let target = policy.isEmpty ? "PROXY" : policy

        // Already a full rule line
        if let type = trimmed.split(separator: ",", maxSplits: 1).first.map({ String($0).uppercased() }),
           knownTypes.contains(type),
           trimmed.contains(",") {
            return trimmed
        }

        // IPv6 CIDR or literal
        if trimmed.contains(":") {
            if trimmed.contains("/") {
                return "IP-CIDR6,\(trimmed),\(target),no-resolve"
            }
            return "IP-CIDR6,\(trimmed)/128,\(target),no-resolve"
        }

        // IPv4 / CIDR
        let ipv4 = #"^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$"#
        if trimmed.range(of: ipv4, options: .regularExpression) != nil {
            if trimmed.contains("/") {
                return "IP-CIDR,\(trimmed),\(target),no-resolve"
            }
            return "IP-CIDR,\(trimmed)/32,\(target),no-resolve"
        }

        // Domain
        let host = trimmed
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
            .split(separator: "/").first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            ?? ""
        guard !host.isEmpty, host.contains(".") else { return nil }
        if host.hasPrefix("*.") {
            return "DOMAIN-SUFFIX,\(String(host.dropFirst(2))),\(target)"
        }
        let labels = host.split(separator: ".")
        if labels.count >= 3 {
            return "DOMAIN-SUFFIX,\(host),\(target)"
        }
        return "DOMAIN-SUFFIX,\(host),\(target)"
    }

    /// First matcher wins (Clash / 小火箭). Same DOMAIN/GEOIP/PROCESS payload keeps the earlier policy.
    /// MATCH is always last and unique.
    static func dedupeKeepingFirst(_ rules: [String]) -> [String] {
        var seen = Set<String>()
        var match: String?
        var out: [String] = []
        out.reserveCapacity(rules.count)
        for raw in rules {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { continue }
            if t.uppercased().hasPrefix("MATCH,") {
                if match == nil { match = t }
                continue
            }
            let key = matcherKey(t)
            if seen.insert(key).inserted {
                out.append(t)
            }
        }
        if let match { out.append(match) }
        return out
    }

    /// Type + payload, ignoring policy / no-resolve so duplicates collapse.
    static func matcherKey(_ rule: String) -> String {
        let parts = rule.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard let type = parts.first?.uppercased(), !type.isEmpty else {
            return rule.uppercased()
        }
        if type == "AND" || type == "OR" || type == "NOT" || type == "SUB-RULE" {
            return rule.uppercased()
        }
        if type == "MATCH" { return "MATCH" }
        let payload = parts.count >= 2 ? parts[1].uppercased() : ""
        return "\(type)|\(payload)"
    }
}
