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
        forIOS: Bool = false,
        stableAINodeName: String? = nil,
        excludedNodeNames: Set<String> = []
    ) -> String {
        let exportNodes: [ProxyNode] = {
            guard forIOS else { return nodes }
            let real = nodes.filter { Self.isSpeedTestable($0) }
            let pool = real.isEmpty
                ? nodes.filter { !Self.isPlaceholderNodeName($0.name) }
                : real
            guard !pool.isEmpty else { return nodes }
            let cap = 32
            let selected = selectedName.flatMap { name in pool.first(where: { $0.name == name }) }
            var names = Self.urlTestPool(from: pool.map(\.name), selected: selected?.name, limit: cap)
            if names.isEmpty { names = Array(pool.prefix(cap).map(\.name)) }
            let picked = Set(names)
            return pool.filter { picked.contains($0.name) }
        }()

        let proxies: [[String: Any]] = exportNodes.map { node in
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

        let names = exportNodes.map(\.name)
        let realNames = names.filter { !Self.isPlaceholderNodeName($0) }
        let selected = selectedName.flatMap { name in
            realNames.contains(name) ? name : nil
        }
        // url-test pools skip circuit-broken nodes; PROXY select lists real hubs only.
        let healthyNames = realNames.filter { !excludedNodeNames.contains($0) }
        let poolSource = healthyNames.isEmpty ? realNames : healthyNames
        let baseRules = (rules.isEmpty ? AppSettings.defaultRules : rules)
        let rewrittenRules = Self.normalizeServiceRules(
            Self.normalizeAIRules(
                Self.normalizeGoogleRules(Self.normalizeTelegramRules(baseRules))
            )
        )
        let finalRules = rewrittenRules.isEmpty ? AppSettings.defaultRules : rewrittenRules

        let proxyGroupList: [String] = {
            var list: [String]
            if names.isEmpty {
                list = ["DIRECT"]
            } else {
                // Leaf hubs only — never nest GOOGLE/AI here (they may reference PROXY → loop).
                // iOS must only list region groups that are actually emitted below (incl. TW).
                // Cap leaf nodes on iOS — full airport lists blow NE memory and jetsam the tunnel.
                let leaves: [String]
                if forIOS {
                    leaves = Self.urlTestPool(from: poolSource, selected: selected, limit: 32)
                } else {
                    leaves = poolSource
                }
                list = ["AUTO", "JP", "HK", "US", "TW"] + leaves + ["DIRECT"]
            }
            if let selected {
                list.removeAll { $0 == selected }
                list.insert(selected, at: 0)
            }
            // Deduplicate while preserving order.
            var seen = Set<String>()
            return list.filter { seen.insert($0).inserted }
        }()

        // Prefer Asia hubs for TELEGRAM/GOOGLE url-test; cap so health checks finish.
        // iOS NE has a tight RAM budget: keep pools small or jetsam kills the tunnel.
        let urlTestLimit = forIOS ? 8 : 36
        // iOS NE: no url-test health checks — periodic batch dials spike RAM and trigger jetsam.
        let iosPickerLimit = 6
        let telegramProxies: [String] = {
            if poolSource.isEmpty { return ["DIRECT"] }
            // Telegram needs low-latency Asia hubs; keep pool tight so url-test finishes.
            let asia = Self.regionPool(
                from: poolSource,
                keys: ["香港", "HK", "Hong Kong", "新加坡", "SG", "Singapore", "日本", "JP", "Japan", "台湾", "TW", "Taiwan"],
                selected: nil,
                limit: forIOS ? iosPickerLimit : 16
            )
            let pool = (asia == ["DIRECT"] || asia.isEmpty)
                ? Self.urlTestPool(from: poolSource, selected: selected, limit: forIOS ? iosPickerLimit : 16)
                : asia
            // Never pin traffic/expiry placeholder names into TELEGRAM-AUTO.
            return pool.filter { !Self.isPlaceholderNodeName($0) }
        }()

        let googleProxies: [String] = {
            if poolSource.isEmpty { return ["DIRECT"] }
            if forIOS {
                return Self.urlTestPool(from: poolSource, selected: selected, limit: iosPickerLimit)
            }
            return Self.urlTestPool(from: poolSource, selected: selected, limit: urlTestLimit)
        }()

        let autoProxies: [String] = {
            if poolSource.isEmpty { return ["DIRECT"] }
            if forIOS {
                return Self.urlTestPool(from: poolSource, selected: selected, limit: iosPickerLimit)
            }
            // Cap AUTO like TELEGRAM/GOOGLE — full-list url-test burns CPU/battery on large airports.
            return Self.urlTestPool(from: poolSource, selected: selected, limit: urlTestLimit)
        }()

        let aiPinned = stableAINodeName.flatMap { realNames.contains($0) ? $0 : nil } ?? selected
        let jpProxies = Self.regionPool(from: poolSource, keys: ["日本", "JP", "Japan", "东京", "大阪", "Tokyo"], selected: selected, limit: urlTestLimit)
        let hkProxies = Self.regionPool(from: poolSource, keys: ["香港", "HK", "Hong Kong", "深港", "沪港"], selected: selected, limit: urlTestLimit)
        let usProxies = Self.regionPool(from: poolSource, keys: ["美国", "US", "USA", "America", "Los Angeles", "San Jose", "西雅图", "纽约", "凤凰城"], selected: selected, limit: urlTestLimit)
        let twProxies = Self.regionPool(from: poolSource, keys: ["台湾", "台灣", "TW", "Taiwan", "Taipei"], selected: selected, limit: urlTestLimit)
        let aiGroups = Self.aiStableGroups(
            names: poolSource.isEmpty ? realNames : poolSource,
            pinned: aiPinned,
            usProxies: usProxies,
            forIOS: forIOS
        )
        let cursorGroups = Self.cursorGroups(
            usProxies: usProxies,
            allProxies: poolSource.isEmpty ? realNames : poolSource,
            pinned: aiPinned,
            forIOS: forIOS
        )
        let regionGroups: [[String: Any]] = forIOS ? [] : [
            Self.regionUrlTest(name: "JP", proxies: jpProxies, interval: 600),
            Self.regionUrlTest(name: "HK", proxies: hkProxies, interval: 600),
            Self.regionUrlTest(name: "US", proxies: usProxies, interval: 600),
            Self.regionUrlTest(name: "TW", proxies: twProxies, interval: 600),
        ]

        let serviceGroups = Self.serviceSelectGroups(
            poolSource: poolSource,
            jpProxies: jpProxies,
            hkProxies: hkProxies,
            usProxies: usProxies,
            twProxies: twProxies,
            forIOS: forIOS
        )

        let auxiliaryGroups: [[String: Any]] = {
            if forIOS {
                // Must include every hub listed in PROXY/GLOBAL (TW was missing → mihomo reject).
                return [
                    Self.iosSelectGroup(name: "AUTO", proxies: autoProxies),
                    Self.iosSelectGroup(name: "GOOGLE", proxies: googleProxies),
                    Self.iosSelectGroup(name: "JP", proxies: jpProxies),
                    Self.iosSelectGroup(name: "HK", proxies: hkProxies),
                    Self.iosSelectGroup(name: "US", proxies: usProxies),
                    Self.iosSelectGroup(name: "TW", proxies: twProxies),
                ] + Self.telegramGroups(proxies: telegramProxies, forIOS: true)
                    + cursorGroups + aiGroups + serviceGroups
            }
            // Shadowrocket-style: GOOGLE prefers JP, then HK, then GOOGLE-AUTO / PROXY.
            // Do not nest PROXY inside GOOGLE if PROXY may list GOOGLE — PROXY is leaf+region only.
            let googleSelect: [String: Any] = [
                "name": "GOOGLE",
                "type": "select",
                "proxies": {
                    var list: [String] = []
                    if !jpProxies.isEmpty && jpProxies != ["DIRECT"] { list.append("JP") }
                    if !hkProxies.isEmpty && hkProxies != ["DIRECT"] { list.append("HK") }
                    list.append("GOOGLE-AUTO")
                    list.append("PROXY")
                    list.append("DIRECT")
                    return list
                }()
            ]
            let googleAuto: [String: Any] = [
                "name": "GOOGLE-AUTO",
                "type": "url-test",
                "proxies": googleProxies,
                "url": GoogleReliability.probeURL,
                "interval": 180,
                "tolerance": 50,
                "lazy": true,
                "expected-status": "200/204"
            ]
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
                googleAuto,
                googleSelect,
            ] + regionGroups + Self.telegramGroups(proxies: telegramProxies, forIOS: false)
                + cursorGroups + aiGroups + serviceGroups
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
            root["keep-alive-interval"] = 30
            // `strict` is enough for PROCESS-NAME under most Mac setups and costs far less CPU.
            root["find-process-mode"] = "strict"
            if domainSniffing {
                root["sniffer"] = snifferBlock
            }
        } else {
            root["find-process-mode"] = "off"
            // Concurrent dials + large proxy graphs spike RAM → iOS jetsam kills the NE.
            root["tcp-concurrent"] = false
            root["keep-alive-interval"] = 30
            // Lightweight sniffer: WeChat/CDN often dial by real IP; SNI restores DOMAIN→DIRECT.
            if domainSniffing {
                root["sniffer"] = iosSnifferBlock
            }
        }

        if tunEnabled {
            var tun: [String: Any] = [
                "enable": true,
                "stack": tunStack.isEmpty ? "mixed" : tunStack,
                "auto-route": true,
                "auto-detect-interface": true,
                "dns-hijack": ["any:53"],
                "strict-route": false
            ]
            if forIOS {
                // Bypass TUN entirely for WeChat/QQ CDN — gVisor DIRECT still slows 发图.
                tun["mtu"] = 1400
                tun["route-exclude-address"] = [
                    "1.12.0.0/14",
                    "14.17.0.0/16", "14.18.0.0/16", "14.19.0.0/16", "14.116.0.0/16",
                    "43.154.0.0/16",
                    "58.247.0.0/16", "58.251.0.0/16", "59.37.0.0/16",
                    "101.32.0.0/16", "101.226.0.0/16", "101.227.0.0/16",
                    "109.244.0.0/16", "111.30.0.0/16",
                    "113.96.0.0/12",
                    "119.147.0.0/16", "121.51.0.0/16", "129.226.0.0/16",
                    "140.207.0.0/16", "157.255.0.0/16",
                    "180.101.0.0/16", "180.163.0.0/16", "182.254.0.0/16",
                    "183.3.0.0/16", "183.36.0.0/16", "183.47.0.0/16",
                    "183.57.0.0/16", "183.60.0.0/16",
                    "183.192.0.0/16", "183.232.0.0/16",
                    "203.205.128.0/19", "211.95.0.0/16",
                ]
            }
            root["tun"] = tun
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

    /// iOS NE: sniff SNI so bare-IP WeChat CDN hits DOMAIN→DIRECT (do NOT skip weixin/qpic).
    private static let iosSnifferBlock: [String: Any] = [
        "enable": true,
        "force-dns-mapping": true,
        "parse-pure-ip": true,
        "override-destination": false,
        "sniff": [
            "TLS": ["ports": [443, 8443, 8080, 80]],
            "HTTP": ["ports": [80, 8080, 8880, 8000]],
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

    /// Manual policy groups for Netflix / TikTok / social / domestic services (Shadowrocket-style).
    /// Never nest these into PROXY — PROXY may only list leaf hubs (AUTO/JP/HK/…) to avoid loops.
    private static func serviceSelectGroups(
        poolSource: [String],
        jpProxies: [String],
        hkProxies: [String],
        usProxies: [String],
        twProxies: [String],
        forIOS: Bool
    ) -> [[String: Any]] {
        let leafCap = forIOS ? 6 : 24
        let leaves = Array(poolSource.filter { $0 != "DIRECT" && !Self.isPlaceholderNodeName($0) }.prefix(leafCap))

        func hasHub(_ proxies: [String]) -> Bool {
            !proxies.isEmpty && proxies != ["DIRECT"]
        }

        func members(
            hubs: [String],
            preferDirect: Bool,
            includeProxy: Bool,
            proxyFirst: Bool = false
        ) -> [String] {
            var list: [String] = []
            if preferDirect { list.append("DIRECT") }
            if proxyFirst { list.append("PROXY") }
            for hub in hubs where !list.contains(hub) { list.append(hub) }
            for leaf in leaves where !list.contains(leaf) { list.append(leaf) }
            if includeProxy, !proxyFirst, !list.contains("PROXY") { list.append("PROXY") }
            if !preferDirect, !list.contains("DIRECT") { list.append("DIRECT") }
            return list.isEmpty ? ["DIRECT"] : list
        }

        var streamingHubs: [String] = []
        if hasHub(jpProxies) { streamingHubs.append("JP") }
        if hasHub(hkProxies) { streamingHubs.append("HK") }
        if hasHub(twProxies) { streamingHubs.append("TW") }

        var socialHubs: [String] = []
        if hasHub(jpProxies) { socialHubs.append("JP") }
        if hasHub(hkProxies) { socialHubs.append("HK") }
        if hasHub(usProxies) { socialHubs.append("US") }

        var tiktokHubs: [String] = []
        if hasHub(jpProxies) { tiktokHubs.append("JP") }
        if hasHub(hkProxies) { tiktokHubs.append("HK") }

        return [
            iosSelectGroup(name: "NETFLIX", proxies: members(hubs: streamingHubs, preferDirect: false, includeProxy: true)),
            iosSelectGroup(name: "TIKTOK", proxies: members(hubs: tiktokHubs, preferDirect: false, includeProxy: true)),
            iosSelectGroup(name: "TWITTER", proxies: members(hubs: socialHubs, preferDirect: false, includeProxy: true)),
            iosSelectGroup(name: "WHATSAPP", proxies: members(hubs: socialHubs, preferDirect: false, includeProxy: true)),
            iosSelectGroup(name: "STEAM", proxies: members(hubs: [], preferDirect: false, includeProxy: false, proxyFirst: true)),
            iosSelectGroup(name: "MICROSOFT", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
            iosSelectGroup(name: "APPLE", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
            iosSelectGroup(name: "BILIBILI", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
            iosSelectGroup(name: "DOUYIN", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
        ]
    }

    /// High-availability Telegram path (Shadowrocket 电报消息 + mihomo failover):
    /// TELEGRAM-AUTO (url-test Asia) → TELEGRAM-FAILOVER (fallback chain) → TELEGRAM (select).
    /// iOS: select only (no background url-test — jetsam).
    private static func telegramGroups(proxies: [String], forIOS: Bool) -> [[String: Any]] {
        let leaves = proxies.filter {
            $0 != "DIRECT" && $0 != "PROXY" && !$0.hasPrefix("TELEGRAM")
        }
        if forIOS {
            // Prefer concrete Asia leaves; include region hubs for manual failover.
            // Only reference hubs we actually emit on iOS (JP/HK/TW/US) — SG was missing → mihomo reject.
            var iosMembers = leaves
            for hub in ["HK", "JP", "TW", "US"] where !iosMembers.contains(hub) {
                iosMembers.append(hub)
            }
            if iosMembers.isEmpty { iosMembers = ["DIRECT"] }
            else if !iosMembers.contains("DIRECT") { iosMembers.append("DIRECT") }
            return [iosSelectGroup(name: "TELEGRAM", proxies: Array(iosMembers.prefix(16)))]
        }

        let autoProxies = leaves.isEmpty ? ["DIRECT"] : leaves
        let auto: [String: Any] = [
            "name": "TELEGRAM-AUTO",
            "type": "url-test",
            "proxies": autoProxies,
            "url": "https://t.me",
            "interval": 90,
            "tolerance": 120,
            "lazy": false,
            "expected-status": "200/301/302/404",
        ]

        // Failover chain: auto → regional url-test hubs → PROXY → DIRECT.
        // mihomo `fallback` picks the first healthy member — true HA without app thrash.
        var failoverMembers: [String] = ["TELEGRAM-AUTO"]
        for hub in ["HK", "JP", "TW", "US"] where !failoverMembers.contains(hub) {
            failoverMembers.append(hub)
        }
        failoverMembers.append("PROXY")
        if !failoverMembers.contains("DIRECT") {
            failoverMembers.append("DIRECT")
        }
        let failover: [String: Any] = [
            "name": "TELEGRAM-FAILOVER",
            "type": "fallback",
            "proxies": failoverMembers,
            "url": "https://t.me",
            "interval": 60,
            "lazy": false,
            "expected-status": "200/301/302/404",
        ]

        // Select defaults to FAILOVER so Desktop always has auto recovery;
        // user can still pin a concrete leaf / PROXY from the menu.
        var selectMembers: [String] = ["TELEGRAM-FAILOVER", "TELEGRAM-AUTO"]
        for leaf in leaves where !selectMembers.contains(leaf) {
            selectMembers.append(leaf)
        }
        if !selectMembers.contains("PROXY") { selectMembers.append("PROXY") }
        if !selectMembers.contains("DIRECT") { selectMembers.append("DIRECT") }

        return [
            auto,
            failover,
            [
                "name": "TELEGRAM",
                "type": "select",
                "proxies": selectMembers,
            ],
        ]
    }

    /// High-availability Cursor path (US-first, kernel failover — no app-side thrash):
    /// CURSOR-AUTO (url-test US) → CURSOR-FAILOVER → CURSOR (select).
    private static func cursorGroups(
        usProxies: [String],
        allProxies: [String],
        pinned: String?,
        forIOS: Bool
    ) -> [[String: Any]] {
        var leaves = usProxies.filter {
            $0 != "DIRECT" && !$0.hasPrefix("CURSOR") && !Self.isPlaceholderNodeName($0)
        }
        if leaves.isEmpty {
            leaves = allProxies.filter {
                $0 != "DIRECT" && !$0.hasPrefix("CURSOR") && !Self.isPlaceholderNodeName($0)
            }
        }
        if let pinned, leaves.contains(pinned) {
            leaves.removeAll { $0 == pinned }
            leaves.insert(pinned, at: 0)
        } else if let pinned, allProxies.contains(pinned), !leaves.contains(pinned) {
            leaves.insert(pinned, at: 0)
        }
        if forIOS {
            var iosMembers = leaves
            if !iosMembers.contains("US") { iosMembers.insert("US", at: 0) }
            for hub in ["AI"] where !iosMembers.contains(hub) { iosMembers.append(hub) }
            if iosMembers.isEmpty { iosMembers = ["DIRECT"] }
            else if !iosMembers.contains("DIRECT") { iosMembers.append("DIRECT") }
            return [iosSelectGroup(name: "CURSOR", proxies: Array(iosMembers.prefix(16)))]
        }

        let autoProxies = leaves.isEmpty ? ["DIRECT"] : leaves
        let auto: [String: Any] = [
            "name": "CURSOR-AUTO",
            "type": "url-test",
            "proxies": autoProxies,
            "url": CursorReliability.probeURL,
            "interval": 90,
            "tolerance": 120,
            "lazy": false,
            "expected-status": "200/301/302/404",
        ]

        var failoverMembers: [String] = ["CURSOR-AUTO", "US", "AI", "PROXY"]
        if !failoverMembers.contains("DIRECT") { failoverMembers.append("DIRECT") }
        let failover: [String: Any] = [
            "name": "CURSOR-FAILOVER",
            "type": "fallback",
            "proxies": failoverMembers,
            "url": CursorReliability.probeURL,
            "interval": 60,
            "lazy": false,
            "expected-status": "200/301/302/404",
        ]

        var selectMembers: [String] = ["CURSOR-FAILOVER", "CURSOR-AUTO", "US"]
        for leaf in leaves where !selectMembers.contains(leaf) { selectMembers.append(leaf) }
        if !selectMembers.contains("AI") { selectMembers.append("AI") }
        if !selectMembers.contains("PROXY") { selectMembers.append("PROXY") }
        if !selectMembers.contains("DIRECT") { selectMembers.append("DIRECT") }

        return [
            auto,
            failover,
            [
                "name": "CURSOR",
                "type": "select",
                "proxies": selectMembers,
            ],
        ]
    }

    /// Sticky select groups for OpenAI / Anthropic — CURSOR uses kernel FAILOVER separately.
    private static func aiStableGroups(
        names: [String],
        pinned: String?,
        usProxies: [String],
        forIOS: Bool
    ) -> [[String: Any]] {
        // Prefer US hubs for Cursor / OpenAI / Anthropic — long-lived HTTPS streams hate url-test thrash.
        var sticky = usProxies.filter { $0 != "DIRECT" }
        if sticky.isEmpty {
            sticky = names.filter { $0 != "DIRECT" }
        }
        if let pinned, sticky.contains(pinned) {
            sticky.removeAll { $0 == pinned }
            sticky.insert(pinned, at: 0)
        } else if let pinned, names.contains(pinned) {
            sticky.insert(pinned, at: 0)
        }
        if sticky.count > (forIOS ? 10 : 36) {
            sticky = Array(sticky.prefix(forIOS ? 10 : 36))
        }
        if sticky.isEmpty { sticky = ["DIRECT"] }
        else if !sticky.contains("DIRECT") { sticky.append("DIRECT") }

        var groups: [[String: Any]] = ["OPENAI", "ANTHROPIC", "COPILOT"].map { name in
            var members = sticky
            if !forIOS, !usProxies.isEmpty, usProxies != ["DIRECT"], !members.contains("US") {
                members.insert("US", at: 0)
            }
            return ["name": name, "type": "select", "proxies": members]
        }

        // Shadowrocket AI 默认美国节点：其它 AI 域名走 AI 组。
        var aiSelect = usProxies.filter { $0 != "DIRECT" }
        if aiSelect.isEmpty { aiSelect = sticky.filter { $0 != "DIRECT" } }
        if let pinned, aiSelect.contains(pinned) {
            aiSelect.removeAll { $0 == pinned }
            aiSelect.insert(pinned, at: 0)
        }
        if !forIOS, !usProxies.isEmpty, usProxies != ["DIRECT"] {
            aiSelect.insert("US", at: 0)
        }
        if aiSelect.isEmpty { aiSelect = ["DIRECT"] }
        else if !aiSelect.contains("DIRECT") { aiSelect.append("DIRECT") }
        // Never nest PROXY here — PROXY may list AI and mihomo rejects the loop.
        let aiCap = forIOS ? 10 : 40
        groups.append(["name": "AI", "type": "select", "proxies": Array(aiSelect.prefix(aiCap))])
        return groups
    }

    /// Route Cursor / OpenAI / Anthropic / other AI (Shadowrocket AI.list).
    private static func normalizeAIRules(_ rules: [String]) -> [String] {
        var out = rules
        let inject = [
            // Cursor IDE + Electron helpers — pin whole process tree to sticky CURSOR group.
            "PROCESS-NAME,Cursor,CURSOR",
            "PROCESS-NAME,Cursor Helper,CURSOR",
            "PROCESS-NAME,Cursor Helper (GPU),CURSOR",
            "PROCESS-NAME,Cursor Helper (Renderer),CURSOR",
            "PROCESS-NAME,Cursor Helper (Plugin),CURSOR",
            "PROCESS-NAME,Cursor Helper (Network),CURSOR",
            "PROCESS-PATH,*Cursor.app/Contents/Frameworks/Cursor Helper*,CURSOR",
            "PROCESS-PATH,*Cursor.app/Contents/MacOS/*,CURSOR",
            "PROCESS-PATH,*Cursor Helper*.app/Contents/MacOS/*,CURSOR",
            // Cursor cloud backends (docs.cursor.com enterprise allowlist)
            "DOMAIN-SUFFIX,cursor.sh,CURSOR",
            "DOMAIN-SUFFIX,cursor.com,CURSOR",
            "DOMAIN-SUFFIX,cursorapi.com,CURSOR",
            "DOMAIN-SUFFIX,cursor-cdn.com,CURSOR",
            "DOMAIN-SUFFIX,cursorvm.com,CURSOR",
            "DOMAIN-SUFFIX,anysphere.co,CURSOR",
            "DOMAIN-SUFFIX,anysphere.com,CURSOR",
            "DOMAIN-SUFFIX,anysphere.tech,CURSOR",
            "DOMAIN,api2.cursor.sh,CURSOR",
            "DOMAIN,api3.cursor.sh,CURSOR",
            "DOMAIN,api4.cursor.sh,CURSOR",
            "DOMAIN,repo42.cursor.sh,CURSOR",
            "DOMAIN,downloads.cursor.com,CURSOR",
            "DOMAIN,marketplace.cursorapi.com,CURSOR",
            "DOMAIN-KEYWORD,cursor.sh,CURSOR",
            "DOMAIN-KEYWORD,gcpp.cursor,CURSOR",
            "DOMAIN-KEYWORD,anysphere,CURSOR",
            "DOMAIN-SUFFIX,openai.com,OPENAI",
            "DOMAIN-SUFFIX,chatgpt.com,OPENAI",
            "DOMAIN-SUFFIX,chat.com,OPENAI",
            "DOMAIN-SUFFIX,oaiusercontent.com,OPENAI",
            "DOMAIN-SUFFIX,oaistatic.com,OPENAI",
            "DOMAIN-SUFFIX,anthropic.com,ANTHROPIC",
            "DOMAIN-SUFFIX,claude.ai,ANTHROPIC",
            "DOMAIN-SUFFIX,claude.com,ANTHROPIC",
            "DOMAIN-SUFFIX,grok.com,AI",
            "DOMAIN-SUFFIX,x.ai,AI",
            "DOMAIN-SUFFIX,openrouter.ai,AI",
            "DOMAIN-SUFFIX,perplexity.ai,AI",
            "DOMAIN,copilot.microsoft.com,COPILOT",
            "DOMAIN,sydney.bing.com,COPILOT",
            "DOMAIN-SUFFIX,githubcopilot.com,COPILOT",
        ]

        let missing = inject.filter { rule in
            let needle = rule.split(separator: ",").prefix(2).joined(separator: ",").uppercased()
            return !out.contains { $0.uppercased().contains(needle) }
        }
        guard !missing.isEmpty else { return out }
        if let idx = out.firstIndex(where: { $0.uppercased().hasPrefix("GEOSITE,CN") }) {
            out.insert(contentsOf: missing, at: idx)
        } else {
            out.insert(contentsOf: missing, at: min(12, out.count))
        }
        return out
    }

    /// Ensure Netflix / TikTok / social / MS / Apple / domestic groups have rule coverage.
    private static func normalizeServiceRules(_ rules: [String]) -> [String] {
        var out = rules
        let inject = [
            "GEOSITE,netflix,NETFLIX",
            "GEOSITE,tiktok,TIKTOK",
            "GEOSITE,twitter,TWITTER",
            "GEOSITE,whatsapp,WHATSAPP",
            "DOMAIN-SUFFIX,steampowered.com,STEAM",
            "DOMAIN-SUFFIX,steamcommunity.com,STEAM",
            "DOMAIN-SUFFIX,microsoft.com,MICROSOFT",
            "DOMAIN-SUFFIX,apple.com,APPLE",
            "DOMAIN-SUFFIX,bilibili.com,DIRECT",
            "DOMAIN-SUFFIX,hdslb.com,DIRECT",
            "DOMAIN-SUFFIX,douyin.com,DIRECT",
            "DOMAIN-SUFFIX,bytedance.com,DIRECT",
        ]
        let missing = inject.filter { rule in
            let needle = rule.split(separator: ",").prefix(2).joined(separator: ",").uppercased()
            return !out.contains { $0.uppercased().contains(needle) }
        }
        guard !missing.isEmpty else { return out }
        if let idx = out.firstIndex(where: { $0.uppercased().hasPrefix("GEOSITE,CN") }) {
            out.insert(contentsOf: missing, at: idx)
        } else {
            out.insert(contentsOf: missing, at: min(12, out.count))
        }
        return out
    }

    private static func regionUrlTest(name: String, proxies: [String], interval: Int) -> [String: Any] {
        let list = proxies.isEmpty ? ["DIRECT"] : proxies
        return [
            "name": name,
            "type": "url-test",
            "proxies": list,
            "url": "https://www.gstatic.com/generate_204",
            "interval": interval,
            "tolerance": 50,
            "lazy": true
        ]
    }

    static func regionPool(from names: [String], keys: [String], selected: String?, limit: Int) -> [String] {
        let matched = names.filter { name in
            keys.contains { name.localizedCaseInsensitiveContains($0) }
        }
        let pool = matched.isEmpty ? Array(names.prefix(max(8, limit))) : matched
        var limited = Array(pool.prefix(max(8, limit)))
        if let selected, names.contains(selected), !limited.contains(selected),
           keys.contains(where: { selected.localizedCaseInsensitiveContains($0) }) {
            limited.insert(selected, at: 0)
            if limited.count > limit { limited = Array(limited.prefix(limit)) }
        }
        return limited.isEmpty ? ["DIRECT"] : limited
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

    /// Traffic / expiry / remark rows that are not real proxies.
    static func isPlaceholderNodeName(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("expire") || n.contains("到期") || n.contains("剩余") { return true }
        if n.contains("流量") || n.contains("traffic") || n.contains("重置") { return true }
        if n.contains("官网") || n.contains("套餐") || n.contains("通知") { return true }
        if n.hasPrefix("http://") || n.hasPrefix("https://") { return true }
        return false
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
            if type == "PROCESS-PATH" {
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

/// When OpenClash (router) and BashX (Mac) run together, OpenClash must DIRECT BashX node
/// endpoints — otherwise traffic is double-proxied and long-lived apps time out.
enum OpenClashDirectRules {
    static var exportURL: URL {
        Paths.supportDir.appendingPathComponent("openclash-bashx-direct.txt")
    }

    static var readmeURL: URL {
        Paths.supportDir.appendingPathComponent("OPENCLASH-README.txt")
    }

    static func publish(nodes: [ProxyNode]) {
        var domains = Set<String>()
        var ips = Set<String>()
        for node in nodes {
            let host = node.server.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { continue }
            if looksLikeIPv4(host) || looksLikeIPv6(host) {
                ips.insert(host)
            } else {
                domains.insert(host.lowercased())
            }
        }

        var lines: [String] = [
            "# BashX → OpenClash coexistence",
            "# Prefer ONE primary proxy: either OpenClash OR BashX.",
            "# If both must run: paste rules below into OpenClash custom rules (near top), policy DIRECT.",
            "# Regenerated whenever BashX rewrites config.yaml.",
            "#",
        ]
        for d in domains.sorted() {
            lines.append("DOMAIN,\(d),DIRECT")
        }
        for ip in ips.sorted() {
            if looksLikeIPv6(ip) {
                lines.append("IP-CIDR6,\(ip)/128,DIRECT,no-resolve")
            } else {
                lines.append("IP-CIDR,\(ip)/32,DIRECT,no-resolve")
            }
        }
        if domains.isEmpty && ips.isEmpty {
            lines.append("# (no node endpoints yet)")
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: exportURL, atomically: true, encoding: .utf8)

        let note = """
        BashX ↔ OpenClash
        =================
        推荐：二选一作为主代理（路由器 OpenClash 或本机 BashX）。

        若必须并存：
        1. 打开 \(exportURL.path)
        2. 将 DOMAIN / IP-CIDR 规则粘贴到 OpenClash「自定义规则」靠前位置，策略 DIRECT
        3. 避免 BashX 节点被 OpenClash 再次代理（双层代理会导致 Cursor/Telegram 超时）

        BashX 已为 Cursor / OpenAI / Anthropic 使用独立稳定策略组，自动测速不会牵动这些长连接。
        """
        try? note.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    private static func looksLikeIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { UInt8($0) != nil }
    }

    private static func looksLikeIPv6(_ s: String) -> Bool {
        s.contains(":") && s.filter { $0 == ":" }.count >= 2
    }
}
