import Foundation

enum AppConstants {
    static let appGroupIdentifier = "group.com.bashx.app"
    static let appBundleIdentifier = "com.bashx.app.ios"
    static let tunnelBundleIdentifier = "com.bashx.app.ios.PacketTunnel"

    /// Mihomo REST API inside the Network Extension process.
    static let externalController = "127.0.0.1:19090"
    static let mixedPort = 17890
    /// Mihomo DNS must bind a real local address. 198.18.0.2 is only the NE DNS
    /// target (hijacked into TUN) — binding it fails (BaoLianDeng / Clash Meta iOS).
    static let dnsListen = "127.0.0.1:1053"

    static let tunAddress = "198.18.0.1"
    static let tunSubnetMask = "255.255.0.0"
    static let tunDNS = "198.18.0.2"
    static let tunIPv6Address = "fdfe:dcba:9876::1"
    static let tunIPv6PrefixLength = 126
    static let defaultMTU = 1280

    /// App Group: full TUN capture (default) vs HTTP-proxy-only experiment.
    static let iosTunnelCaptureKey = "iosTunnelCapture"

    /// Strategy groups in menu bar / iOS home — Shadowrocket.conf order:
    /// 谷歌(JP) → 电报 → AI(US) → 日本/香港/台湾/美国 区域组（不含 AUTO）。
    /// Ref: https://raw.githubusercontent.com/LingJingMaster/Shadowrocket-Rules/refs/heads/main/Shadowrocket.conf
    static let menuProxyGroups: [String] = [
        "GOOGLE", "TELEGRAM", "AI", "JP", "HK", "TW", "US",
    ]

    /// Human labels for strategy rows (Shadowrocket-style).
    static func groupDisplayName(_ group: String) -> String {
        switch group.uppercased() {
        case "GOOGLE": return "谷歌"
        case "TELEGRAM": return "电报"
        case "TELEGRAM-FAILOVER": return "电报故障转移"
        case "TELEGRAM-AUTO": return "电报自动"
        case "CURSOR": return "Cursor"
        case "CURSOR-FAILOVER": return "Cursor故障转移"
        case "CURSOR-AUTO": return "Cursor自动"
        case "AI": return "AI"
        case "JP": return "日本"
        case "HK": return "香港"
        case "TW": return "台湾"
        case "US": return "美国"
        case "AUTO": return "自动"
        case "PROXY": return "节点"
        default: return group
        }
    }

    static func shortProxyLabel(_ name: String, limit: Int = 18) -> String {
        let cleaned = sanitizedProxyLabel(name)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(max(1, limit - 1))) + "…"
    }

    /// Strip leading decorative symbols / broken glyphs so menu rows align cleanly.
    static func sanitizedProxyLabel(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\u{FFFD}", with: "")
        s = s.replacingOccurrences(of: "☒", with: "")
        s = s.replacingOccurrences(of: "□", with: "")
        while let first = s.unicodeScalars.first {
            let v = first.value
            let isRegional = (0x1F1E6...0x1F1FF).contains(v)
            let isEmoji = (0x1F300...0x1FAFF).contains(v) || (0x2600...0x27BF).contains(v)
            let isJoin = v == 0x200D || v == 0xFE0F || v == 0x20E3
            if isRegional || isEmoji || isJoin || first.properties.isEmojiModifier {
                s = String(s.unicodeScalars.dropFirst())
                continue
            }
            break
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Aligned menu title: business (left) + route (right), tab-aligned like ClashX/Surge.
    static func groupMenuTitle(group: String, now: String, limit: Int = 16) -> String {
        let business = groupDisplayName(group)
        let line = groupSelectionLabel(now, limit: limit)
        return "\(business)\t\(line)"
    }

    /// Human-readable label for a group's current member (hub name or leaf node).
    static func groupSelectionLabel(_ now: String, limit: Int = 18) -> String {
        let raw = now.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "—" }
        let upper = raw.uppercased()
        let knownGroups: Set<String> = [
            "GOOGLE", "TELEGRAM", "AI", "JP", "HK", "TW", "US", "AUTO", "PROXY", "DIRECT",
            "TELEGRAM-FAILOVER", "TELEGRAM-AUTO", "CURSOR", "CURSOR-FAILOVER", "CURSOR-AUTO",
            "GOOGLE-AUTO", "OPENAI", "ANTHROPIC",
        ]
        if knownGroups.contains(upper) {
            return groupDisplayName(raw)
        }
        return shortProxyLabel(raw, limit: limit)
    }
}
