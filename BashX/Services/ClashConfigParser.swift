import Foundation
import Yams

enum ConfigError: LocalizedError {
    case empty
    case invalidYAML
    case noProxies

    var errorDescription: String? {
        switch self {
        case .empty: return "订阅内容为空"
        case .invalidYAML: return "无法解析订阅内容"
        case .noProxies: return "未找到可用节点"
        }
    }
}

enum ClashConfigParser {
    static func parse(_ data: Data) throws -> (nodes: [ProxyNode], rawRoot: [String: Any]) {
        guard !data.isEmpty else { throw ConfigError.empty }
        let text = try normalizeToText(data)

        if looksLikeURIList(text) {
            let proxies = ShareLinkParser.parseLines(text)
            guard !proxies.isEmpty else { throw ConfigError.noProxies }
            return (nodesFromProxies(proxies), ["proxies": proxies])
        }

        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw ConfigError.invalidYAML
        }

        let proxyList = collectProxies(from: root)

        guard !proxyList.isEmpty else { throw ConfigError.noProxies }
        return (nodesFromProxies(proxyList), root)
    }

    static func buildConfig(
        nodes: [ProxyNode],
        selectedName: String?,
        mixedPort: Int,
        controller: String,
        secret: String,
        rules: [String],
        tunEnabled: Bool,
        tunStack: String,
        mode: ProxyMode = .rule,
        allowLan: Bool = false,
        turboMode: Bool = true,
        domainSniffing: Bool = true,
        dnsPreference: DnsPreference = .smart,
        forIOS: Bool = false
    ) -> String {
        let proxies: [[String: Any]] = nodes.map { node in
            var dict: [String: Any] = [:]
            for (k, v) in node.raw {
                dict[k] = unwrap(v.value)
            }
            dict["name"] = node.name
            dict["type"] = node.type
            if !node.server.isEmpty { dict["server"] = node.server }
            if node.port > 0 { dict["port"] = node.port }
            // Mac Telegram / QUIC need UDP; subscription nodes often omit `udp: true`.
            normalizeProxyUDP(&dict)
            return dict
        }

        let names = nodes.map(\.name)
        let selected = selectedName.flatMap { names.contains($0) ? $0 : nil }
        let baseRules = (rules.isEmpty ? AppSettings.defaultRules : rules)
        let rewrittenRules = Self.normalizeGoogleRules(Self.normalizeTelegramRules(baseRules))
        let finalRules = rewrittenRules.isEmpty ? AppSettings.defaultRules : rewrittenRules

        let proxyGroupList: [String] = {
            var list: [String]
            if names.isEmpty {
                list = ["DIRECT"]
            } else {
                // GOOGLE url-test first — avoids AUTO picking dead nodes for Google/Translate.
                list = ["GOOGLE", "AUTO"] + names + ["DIRECT"]
            }
            if let selected {
                list.removeAll { $0 == selected }
                list.insert(selected, at: 0)
            }
            return list
        }()

        // Prefer Asia hubs for TELEGRAM/GOOGLE url-test; cap so health checks finish.
        // iOS NE has a tight RAM budget: keep pools small or jetsam kills the tunnel.
        let urlTestLimit = forIOS ? 12 : 36
        // iOS NE: no url-test health checks — periodic batch dials spike RAM and trigger jetsam.
        let iosPickerLimit = 8
        let telegramProxies: [String] = {
            if names.isEmpty { return ["DIRECT"] }
            if forIOS {
                return Self.urlTestPool(from: names, selected: selected, limit: iosPickerLimit)
            }
            return Self.urlTestPool(from: names, selected: selected, limit: urlTestLimit)
        }()

        let googleProxies: [String] = {
            if names.isEmpty { return ["DIRECT"] }
            if forIOS {
                return Self.urlTestPool(from: names, selected: selected, limit: iosPickerLimit)
            }
            return Self.urlTestPool(from: names, selected: selected, limit: urlTestLimit)
        }()

        let autoProxies: [String] = {
            if names.isEmpty { return ["DIRECT"] }
            if forIOS {
                return Self.urlTestPool(from: names, selected: selected, limit: iosPickerLimit)
            }
            return names
        }()

        let auxiliaryGroups: [[String: Any]] = {
            if forIOS {
                return [
                    Self.iosSelectGroup(name: "AUTO", proxies: autoProxies),
                    Self.iosSelectGroup(name: "GOOGLE", proxies: googleProxies),
                ] + Self.telegramGroups(proxies: telegramProxies, forIOS: true)
            }
            return [
                [
                    "name": "AUTO",
                    "type": "url-test",
                    "proxies": autoProxies,
                    "url": "https://www.gstatic.com/generate_204",
                    "interval": turboMode ? 600 : 300,
                    "tolerance": turboMode ? 80 : 50,
                    "lazy": true
                ],
                [
                    "name": "GOOGLE",
                    "type": "url-test",
                    "proxies": googleProxies,
                    "url": GoogleReliability.probeURL,
                    "interval": 180,
                    "tolerance": 50,
                    "lazy": false,
                    "expected-status": "200/204"
                ],
            ] + Self.telegramGroups(proxies: telegramProxies, forIOS: false)
        }()

        let iosMixedPort = forIOS && !tunEnabled ? mixedPort : (forIOS ? 0 : mixedPort)
        let bindAddress: String = {
            // iOS HTTP-proxy experiment: mixed-port on loopback so NEProxySettings
            // (127.0.0.1) reaches mihomo without entering packetFlow.
            if forIOS && !tunEnabled { return "127.0.0.1" }
            return allowLan ? "*" : "127.0.0.1"
        }()

        var root: [String: Any] = [
            "mixed-port": iosMixedPort,
            "allow-lan": allowLan,
            "bind-address": bindAddress,
            "mode": mode.rawValue,
            "log-level": forIOS ? "warning" : "warning",
            "external-controller": controller,
            "secret": secret,
            "ipv6": false,
            // Same as Clash Verge / Meta — one delay per proxy instead of per hop.
            "unified-delay": true,
            "dns": forIOS
                ? DnsPreference.iosDnsBlock(for: dnsPreference)
                : DnsPreference.dnsBlock(for: dnsPreference),
            "proxies": proxies,
            "proxy-groups": [
                [
                    "name": "PROXY",
                    "type": "select",
                    "proxies": proxyGroupList
                ],
                [
                    "name": "GLOBAL",
                    "type": "select",
                    "proxies": proxyGroupList
                ],
            ] + auxiliaryGroups,
            "rules": finalRules
        ]

        if forIOS {
            // iOS NE: never auto-download geo DBs during tunnel start (deadlocks under utun).
            // Rules already strip GEOSITE/GEOIP; DNS also avoids geo filters.
            root["geodata-mode"] = false
            root["geo-auto-update"] = false
        } else {
            root["geodata-mode"] = false
            root["geo-auto-update"] = false
            root["geo-update-interval"] = 168
            root["geox-url"] = [
                "geoip": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb",
                "geosite": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat",
                "mmdb": "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
            ]
        }

        if turboMode && !forIOS {
            root["unified-delay"] = true
        }

        if !forIOS {
            root["tcp-concurrent"] = true
            root["keep-alive-interval"] = 15
            // `always` so PROCESS-NAME,Telegram matches under system proxy (strict often skips).
            root["find-process-mode"] = "always"
            if domainSniffing {
                root["sniffer"] = snifferBlock
            }
        } else {
            root["find-process-mode"] = "off"
            root["tcp-concurrent"] = true
            // Sniffer off on iOS NE — TLS/DNS sniffing adds CPU/RAM under real traffic.
        }

        if tunEnabled {
            root["tun"] = [
                "enable": true,
                "stack": tunStack.isEmpty ? "mixed" : tunStack,
                "auto-route": true,
                "auto-detect-interface": true,
                "dns-hijack": ["any:53"],
                "strict-route": false
            ]
        }

        return (try? Yams.dump(object: root)) ?? ""
    }

    private static let snifferBlock: [String: Any] = [
        "enable": true,
        "force-dns-mapping": true,
        "parse-pure-ip": true,
        // Clash Verge / ClashX: do not rewrite destination — breaks Google Translate & banking.
        "override-destination": false,
        "sniff": [
            "HTTP": ["ports": [80, 8080, 8880]],
            "TLS": ["ports": [443, 8443]],
            "QUIC": ["ports": [443, 8443]]
        ],
        "skip-domain": [
            "Mijia Cloud",
            "+.push.apple.com",
            "+.google.com",
            "+.googleapis.com",
            "+.translate.goog",
            "+.gstatic.com",
            "+.googleusercontent.com",
            "+.youtube.com",
            "+.apple.com",
            "+.icloud.com",
            "+.qq.com",
            "+.weixin.qq.com"
        ]
    ]

    /// iOS NE: sniff for DOMAIN rules, but keep original destination (WeChat-safe).
    private static let iosSnifferBlock: [String: Any] = [
        "enable": true,
        "force-dns-mapping": true,
        "parse-pure-ip": true,
        "override-destination": false,
        "sniff": [
            "TLS": ["ports": [443, 8443]],
            "HTTP": ["ports": [80, 8080]],
            "QUIC": ["ports": [443]]
        ],
        "skip-domain": [
            "+.push.apple.com",
            "+.apple.com",
            "+.icloud.com",
        ]
    ]

    /// iOS NE: manual select only — url-test batch health checks exhaust the ~50MB jetsam budget.
    private static func iosSelectGroup(name: String, proxies: [String]) -> [String: Any] {
        let list = proxies.isEmpty ? ["DIRECT"] : proxies
        return ["name": name, "type": "select", "proxies": list]
    }

    /// Clash Verge style: Mac uses select(TELEGRAM) → url-test(TELEGRAM-AUTO);
    /// iOS uses select(TELEGRAM) only (no background url-test).
    private static func telegramGroups(proxies: [String], forIOS: Bool) -> [[String: Any]] {
        if forIOS {
            return [iosSelectGroup(name: "TELEGRAM", proxies: proxies)]
        }
        let auto: [String: Any] = [
            "name": "TELEGRAM-AUTO",
            "type": "url-test",
            "proxies": proxies,
            "url": "https://api.telegram.org",
            "interval": 60,
            "tolerance": 80,
            "lazy": false,
            "expected-status": "200/301/302/404"
        ]
        let selectMembers = ["TELEGRAM-AUTO"] + proxies.filter { $0 != "DIRECT" }
        return [
            auto,
            [
                "name": "TELEGRAM",
                "type": "select",
                "proxies": selectMembers.isEmpty ? ["TELEGRAM-AUTO", "DIRECT"] : selectMembers
            ]
        ]
    }

    /// Prefer low-latency hubs for url-test groups (Telegram / Google / AUTO fallback).
    static func preferredRegionNodes(from names: [String]) -> [String] {
        let keys = [
            "香港", "HK", "Hong Kong",
            "台湾", "TW", "Taiwan",
            "新加坡", "SG", "Singapore",
            "日本", "JP", "Japan", "东京", "大阪",
            "韩国", "KR", "Korea", "首尔",
            "马来", "MY", "Malaysia",
            "美国", "US", "USA", "Los Angeles", "San Jose", "Seattle",
            "英国", "UK", "London",
            "德国", "DE", "Frankfurt",
            "荷兰", "NL", "Amsterdam"
        ]
        let preferred = names.filter { name in
            keys.contains { name.localizedCaseInsensitiveContains($0) }
        }
        if preferred.count >= 4 { return preferred }
        return names
    }

    /// Selected PROXY node first, then the rest — so TELEGRAM/GOOGLE follow user pick.
    static func groupProxiesPreferringSelected(names: [String], selected: String?) -> [String] {
        guard let selected, names.contains(selected) else { return names }
        var list = names.filter { $0 != selected }
        list.insert(selected, at: 0)
        return list
    }

    /// Compact url-test pool: Asia hubs first, capped so TELEGRAM health checks finish quickly.
    static func urlTestPool(from names: [String], selected: String?, limit: Int) -> [String] {
        let preferred = preferredRegionNodes(from: names)
        let pool = preferred.isEmpty ? names : preferred
        let priorityKeys = ["香港", "HK", "Hong Kong", "新加坡", "SG", "Singapore", "日本", "JP", "Japan", "台湾", "TW", "Taiwan"]
        var top = pool.filter { name in
            priorityKeys.contains { name.localizedCaseInsensitiveContains($0) }
        }
        if top.count < 8 { top = pool }
        var limited = Array(top.prefix(max(8, limit)))
        if let selected, pool.contains(selected) {
            limited.removeAll { $0 == selected }
            limited.insert(selected, at: 0)
            if limited.count > limit { limited = Array(limited.prefix(limit)) }
        }
        return limited.isEmpty ? names : limited
    }

    /// Route Google / YouTube traffic through GOOGLE url-test (not dead AUTO nodes).
    private static func normalizeGoogleRules(_ rules: [String]) -> [String] {
        var out = rules.map { rewriteGooglePolicy($0) }
        let hasGoogle = out.contains { line in
            let u = line.uppercased()
            return u.contains(",GOOGLE") || u.contains("GEOSITE,GOOGLE")
        }
        if !hasGoogle {
            let inject = [
                "DOMAIN-SUFFIX,translate.google.com,GOOGLE",
                "DOMAIN-SUFFIX,translate.googleapis.com,GOOGLE",
                "DOMAIN-SUFFIX,translate-pa.googleapis.com,GOOGLE",
                "DOMAIN-SUFFIX,content-translate.googleapis.com,GOOGLE",
                "DOMAIN-SUFFIX,translate.goog,GOOGLE",
                "DOMAIN-SUFFIX,google.com,GOOGLE",
                "DOMAIN-SUFFIX,google.com.hk,GOOGLE",
                "DOMAIN-SUFFIX,googleapis.com,GOOGLE",
                "DOMAIN-SUFFIX,gstatic.com,GOOGLE",
                "DOMAIN-SUFFIX,googleusercontent.com,GOOGLE",
                "DOMAIN-KEYWORD,google,GOOGLE",
                "GEOSITE,google,GOOGLE",
                "GEOSITE,youtube,GOOGLE",
            ]
            if let idx = out.firstIndex(where: { $0.uppercased().hasPrefix("GEOSITE,GOOGLE,") }) {
                out.insert(contentsOf: inject.filter { !out.contains($0) }, at: idx)
            } else if let idx = out.firstIndex(where: { $0.uppercased().hasPrefix("GEOSITE,CN") }) {
                out.insert(contentsOf: inject, at: idx)
            } else {
                out.insert(contentsOf: inject, at: min(20, out.count))
            }
        }
        return out
    }

    private static func rewriteGooglePolicy(_ rule: String) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return rule }
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return rule }
        let type = parts[0].uppercased()
        let payload = parts[1].lowercased()
        let policy = parts[2].uppercased()
        guard policy == "PROXY" || policy == "AUTO" else { return rule }

        let isGoogle: Bool = {
            if type == "GEOSITE" {
                return payload == "google" || payload == "youtube"
            }
            if type == "DOMAIN-SUFFIX" || type == "DOMAIN" || type == "DOMAIN-KEYWORD" {
                return payload.contains("google")
                    || payload.contains("translate.goog")
                    || payload.contains("gstatic")
                    || payload.contains("googleapis")
                    || payload.contains("googlevideo")
                    || payload.contains("ggpht")
                    || payload.contains("gvt1")
                    || payload.contains("gvt2")
                    || payload.contains("youtube")
                    || payload.contains("youtu.be")
                    || payload.contains("ytimg")
            }
            return false
        }()
        guard isGoogle else { return rule }
        var next = parts
        next[2] = "GOOGLE"
        return next.joined(separator: ",")
    }

    /// Prefer low-latency Asia hubs for Telegram url-test (falls back to all nodes).
    private static func telegramPreferredNodes(from names: [String]) -> [String] {
        preferredRegionNodes(from: names)
    }

    /// Point Telegram process / domain / DC IP / geosite rules at TELEGRAM group.
    private static func normalizeTelegramRules(_ rules: [String]) -> [String] {
        var out = rules.map { rewriteTelegramPolicy($0) }
        let hasDC = out.contains { $0.contains("149.154.160.0/20") && $0.contains("TELEGRAM") }
        let hasBroad91 = out.contains { $0.contains("91.108.0.0/16") && $0.contains("TELEGRAM") }
        if !hasBroad91, hasDC {
            if let idx = out.firstIndex(where: { $0.contains("149.154.160.0/20") && $0.contains("TELEGRAM") }) {
                out.insert("IP-CIDR,91.108.0.0/16,TELEGRAM,no-resolve", at: idx + 1)
            }
        }
        if !hasDC {
            let inject = [
                "PROCESS-NAME,Telegram,TELEGRAM",
                "PROCESS-NAME,org.telegram.desktop,TELEGRAM",
                "PROCESS-PATH,*Telegra2.app/Contents/MacOS/Telegram,TELEGRAM",
                "PROCESS-PATH,*Telegram.app/Contents/MacOS/Telegram,TELEGRAM",
                "IP-CIDR,149.154.160.0/20,TELEGRAM,no-resolve",
                "IP-CIDR,91.108.0.0/16,TELEGRAM,no-resolve",
                "IP-CIDR,91.105.192.0/23,TELEGRAM,no-resolve",
                "IP-CIDR,185.76.151.0/24,TELEGRAM,no-resolve",
                "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
                "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
                "DOMAIN-SUFFIX,cdn-telegram.org,TELEGRAM",
                "DOMAIN-SUFFIX,telesco.pe,TELEGRAM",
                "DOMAIN-SUFFIX,t.me,TELEGRAM",
                "DOMAIN-KEYWORD,telegram,TELEGRAM",
                "GEOIP,telegram,TELEGRAM,no-resolve",
            ]
            // Insert after LAN block — before first GEOSITE/cn if possible.
            if let idx = out.firstIndex(where: { $0.uppercased().hasPrefix("GEOSITE,CN") || $0.uppercased().hasPrefix("DOMAIN-SUFFIX,CN,") }) {
                out.insert(contentsOf: inject, at: idx)
            } else {
                out.insert(contentsOf: inject, at: min(20, out.count))
            }
        }
        return out
    }

    private static func rewriteTelegramPolicy(_ rule: String) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return rule }
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return rule }
        let type = parts[0].uppercased()
        let payload = parts[1].lowercased()
        let policy = parts[2].uppercased()
        guard policy == "PROXY" || policy == "AUTO" else { return rule }

        let isTelegram: Bool = {
            if type == "GEOIP" || type == "GEOSITE" { return payload == "telegram" }
            if type == "PROCESS-NAME" {
                return payload.contains("telegram")
            }
            if type == "DOMAIN-SUFFIX" || type == "DOMAIN" || type == "DOMAIN-KEYWORD" {
                return payload.contains("telegram")
                    || payload == "t.me" || payload == "tx.me"
                    || payload == "telesco.pe" || payload == "graph.org"
                    || payload == "tdesktop.com" || payload == "telegra.ph"
            }
            if type == "IP-CIDR" || type == "IP-CIDR6" {
                return payload.hasPrefix("149.154.")
                    || payload.hasPrefix("91.108.")
                    || payload.hasPrefix("91.105.192")
                    || payload.hasPrefix("185.76.151")
                    || payload.hasPrefix("2001:67c:4e8")
                    || payload.hasPrefix("2001:b28:f23")
            }
            return false
        }()
        guard isTelegram else { return rule }
        var next = parts
        next[2] = "TELEGRAM"
        return next.joined(separator: ",")
    }

    // MARK: - Private

    private static let nonProxyTypes: Set<String> = [
        "direct", "reject", "select", "url-test", "fallback", "load-balance", "relay", "pass", "dns", "block"
    ]

    /// Collect proxy dicts from proxies / Proxy / proxy-providers / inline proxy-groups.
    private static func collectProxies(from root: [String: Any]) -> [[String: Any]] {
        var list: [[String: Any]] = []
        if let proxies = root["proxies"] as? [[String: Any]] { list.append(contentsOf: proxies) }
        if let proxies = root["Proxy"] as? [[String: Any]] { list.append(contentsOf: proxies) }
        if let proxies = root["proxy"] as? [[String: Any]] { list.append(contentsOf: proxies) }

        if let providers = root["proxy-providers"] as? [String: Any] {
            for (_, value) in providers {
                guard let dict = value as? [String: Any] else { continue }
                if let inline = dict["proxies"] as? [[String: Any]] {
                    list.append(contentsOf: inline)
                }
            }
        }

        if let groups = root["proxy-groups"] as? [[String: Any]] {
            for group in groups {
                guard let items = group["proxies"] as? [Any] else { continue }
                for item in items {
                    guard let dict = item as? [String: Any],
                          dict["type"] != nil,
                          dict["name"] != nil else { continue }
                    list.append(dict)
                }
            }
        }

        return list.filter(isProxyDict)
    }

    private static func isProxyDict(_ item: [String: Any]) -> Bool {
        guard let type = (item["type"] as? String)?.lowercased(), !type.isEmpty else { return false }
        if nonProxyTypes.contains(type) { return false }
        guard let name = item["name"] as? String, !name.isEmpty else { return false }
        if name.uppercased() == "DIRECT" || name.uppercased() == "REJECT" { return false }
        return true
    }

    /// Skip airport traffic / expiry banner nodes — they are not real outbound proxies.
    static func isSpeedTestable(_ node: ProxyNode) -> Bool {
        let type = node.type.lowercased()
        if nonProxyTypes.contains(type) { return false }
        if node.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if node.port <= 0 || node.port > 65535 { return false }
        let upper = node.name.uppercased()
        if upper == "DIRECT" || upper == "REJECT" { return false }
        let infoNeedles = [
            "剩余流量", "套餐到期", "距离下次", "Traffic:", "Expire:", "GB /", "GB/", "流量：", "流量:",
            "重置剩余", "套餐剩余", "已用流量", "到期时间",
        ]
        if infoNeedles.contains(where: { node.name.contains($0) }) { return false }
        return true
    }

    private static func normalizeToText(_ data: Data) throws -> String {
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            throw ConfigError.empty
        }

        if raw.contains("proxies:") || raw.contains("Proxy:")
            || raw.contains("proxy-providers:") || looksLikeURIList(raw) {
            return raw
        }

        if let decoded = decodeFlexibleBase64(raw),
           let text = String(data: decoded, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return raw
    }

    private static func looksLikeURIList(_ text: String) -> Bool {
        let sample = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(5)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !sample.isEmpty else { return false }
        let prefixes = ["ss://", "ssr://", "vmess://", "vless://", "trojan://", "hysteria2://", "hy2://", "tuic://"]
        return sample.contains { line in prefixes.contains(where: { line.lowercased().hasPrefix($0) }) }
    }

    private static func decodeFlexibleBase64(_ raw: String) -> Data? {
        let cleaned = raw
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        return Data(base64Encoded: padded)
    }

    private static func nodesFromProxies(_ proxyList: [[String: Any]]) -> [ProxyNode] {
        var nodes: [ProxyNode] = []
        nodes.reserveCapacity(proxyList.count)
        var usedNames = Set<String>()

        for item in proxyList {
            guard var name = item["name"] as? String,
                  let type = item["type"] as? String else { continue }

            if usedNames.contains(name) {
                var i = 2
                while usedNames.contains("\(name) (\(i))") { i += 1 }
                name = "\(name) (\(i))"
            }
            usedNames.insert(name)

            let server = stringValue(item["server"]) ?? ""
            let port = intValue(item["port"]) ?? 0
            var rawItem = item
            rawItem["name"] = name
            let raw = rawItem.mapValues { AnyCodable($0) }
            nodes.append(ProxyNode(name: name, type: type, server: server, port: port, raw: raw))
        }
        return nodes
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let p = value as? Int { return p }
        if let p = value as? Int64 { return Int(p) }
        if let p = value as? String { return Int(p) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let s = value as? NSString { return s as String }
        return nil
    }

    private static func unwrap(_ value: Any) -> Any {
        if let nested = value as? AnyCodable {
            return unwrap(nested.value)
        }
        if let array = value as? [Any] {
            return array.map(unwrap)
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues(unwrap)
        }
        if let dict = value as? [String: AnyCodable] {
            return dict.mapValues { unwrap($0.value) }
        }
        return value
    }

    /// Telegram MTProto / Safari QUIC need UDP. Subscription nodes often omit `udp: true`,
    /// then groups report "UDP is not supported" and fall back to DIRECT.
    private static func normalizeProxyUDP(_ dict: inout [String: Any]) {
        let type = (dict["type"] as? String)?.lowercased() ?? ""
        let udpCapable = ["vmess", "vless", "trojan", "ss", "ssr", "hysteria", "hysteria2", "tuic"]
        guard udpCapable.contains(type) else { return }
        if dict["udp"] == nil {
            dict["udp"] = true
        }
    }
}

enum ShareLinkParser {
    static func parseLines(_ text: String) -> [[String: Any]] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { parseURI(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func parseURI(_ line: String) -> [String: Any]? {
        let lower = line.lowercased()
        if lower.hasPrefix("ss://") { return parseShadowsocks(line) }
        if lower.hasPrefix("trojan://") { return parseTrojan(line) }
        return nil
    }

    // SIP002: ss://base64(method:password)@host:port/?plugin=...#name
    // Legacy: ss://base64(method:password@host:port)#name
    private static func parseShadowsocks(_ line: String) -> [String: Any]? {
        let withoutScheme = String(line.dropFirst(5))
        let hashParts = withoutScheme.split(separator: "#", maxSplits: 1).map(String.init)
        let main = hashParts[0]
        let name = hashParts.count > 1
            ? (hashParts[1].removingPercentEncoding ?? hashParts[1])
            : "SS"

        if let at = main.firstIndex(of: "@") {
            let user = String(main[..<at])
            var hostPart = String(main[main.index(after: at)...])
            var query: String?
            if let q = hostPart.firstIndex(of: "?") {
                query = String(hostPart[hostPart.index(after: q)...])
                hostPart = String(hostPart[..<q])
            }
            hostPart = hostPart.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // host:port or [ipv6]:port
            guard let colon = hostPart.lastIndex(of: ":"),
                  let port = Int(hostPart[hostPart.index(after: colon)...]) else { return nil }
            let host = String(hostPart[..<colon])
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard let methodPass = decodeUserInfo(user) else { return nil }
            let parts = methodPass.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            var dict: [String: Any] = [
                "name": name,
                "type": "ss",
                "server": host,
                "port": port,
                "cipher": parts[0],
                "password": parts[1]
            ]
            if let query {
                applySSPlugin(fromQuery: query, into: &dict)
            }
            return dict
        }

        // Legacy whole-body base64 after ss://
        guard let decoded = decodeFlexibleBase64(main),
              let decodedText = String(data: decoded, encoding: .utf8) else { return nil }
        guard let at = decodedText.lastIndex(of: "@") else { return nil }
        let userInfo = String(decodedText[..<at])
        let hostPort = String(decodedText[decodedText.index(after: at)...])
        let mp = userInfo.split(separator: ":", maxSplits: 1).map(String.init)
        let hp = hostPort.split(separator: ":", maxSplits: 1).map(String.init)
        guard mp.count == 2, hp.count == 2, let port = Int(hp[1]) else { return nil }
        return [
            "name": name,
            "type": "ss",
            "server": hp[0],
            "port": port,
            "cipher": mp[0],
            "password": mp[1]
        ]
    }

    private static func applySSPlugin(fromQuery query: String, into dict: inout [String: Any]) {
        let items = query.split(separator: "&").compactMap { pair -> (String, String)? in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            return (kv[0], kv[1].removingPercentEncoding ?? kv[1])
        }
        guard let pluginValue = items.first(where: { $0.0 == "plugin" })?.1 else { return }

        // simple-obfs;obfs=http;obfs-host=xxx
        let parts = pluginValue.split(separator: ";").map(String.init)
        guard let pluginName = parts.first?.lowercased() else { return }

        var opts: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { opts[kv[0]] = kv[1] }
        }

        if pluginName.contains("obfs") {
            dict["plugin"] = "obfs"
            var pluginOpts: [String: Any] = [:]
            if let mode = opts["obfs"] { pluginOpts["mode"] = mode }
            if let host = opts["obfs-host"] { pluginOpts["host"] = host }
            dict["plugin-opts"] = pluginOpts
        } else if pluginName.contains("v2ray") {
            dict["plugin"] = "v2ray-plugin"
            var pluginOpts: [String: Any] = [:]
            if let mode = opts["mode"] { pluginOpts["mode"] = mode }
            if let host = opts["host"] { pluginOpts["host"] = host }
            if opts["tls"] == "true" || opts.keys.contains("tls") { pluginOpts["tls"] = true }
            dict["plugin-opts"] = pluginOpts
        }
    }

    private static func parseTrojan(_ line: String) -> [String: Any]? {
        guard let url = URLComponents(string: line),
              let host = url.host,
              let port = url.port,
              let password = url.user?.removingPercentEncoding else { return nil }
        let name = url.fragment.flatMap { $0.removingPercentEncoding } ?? "Trojan"
        var dict: [String: Any] = [
            "name": name,
            "type": "trojan",
            "server": host,
            "port": port,
            "password": password
        ]
        if let sni = url.queryItems?.first(where: { $0.name == "sni" || $0.name == "peer" })?.value {
            dict["sni"] = sni
        }
        return dict
    }

    private static func decodeUserInfo(_ user: String) -> String? {
        if user.contains(":") { return user.removingPercentEncoding }
        guard let data = decodeFlexibleBase64(user),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func decodeFlexibleBase64(_ raw: String) -> Data? {
        let cleaned = raw
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        return Data(base64Encoded: padded)
    }
}
