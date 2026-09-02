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
        excludedNodeNames: Set<String> = [],
        proxyHubMode: ProxyHubMode = .smart
    ) -> String {
        let exportNodes: [ProxyNode] = {
            guard forIOS else { return nodes }
            let real = nodes.filter { Self.isSpeedTestable($0) }
            let pool = real.isEmpty
                ? nodes.filter { !Self.isPlaceholderNodeName($0.name) }
                : real
            guard !pool.isEmpty else { return nodes }
            // Keep NE under ~50MB jetsam budget — 24 leaves + sniffer was killing tunnels (80MB+).
            let cap = 12
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
            // Residential SOCKS (IPFoxy) must dial via overseas front hop from CN.
            normalizeResidentialDialer(&dict)
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
                Self.normalizeGoogleRules(Self.normalizeTelegramRules(baseRules)),
                forIOS: forIOS
            ),
            forIOS: forIOS
        )
        // iOS NE: never ship PROCESS / GEOSITE / GEOIP — no process matcher, no geo DB
        // (normalize* used to re-inject them → mihomo Parse hang / start fail).
        let scrubbed = forIOS ? Self.scrubIOSIncompatibleRules(rewrittenRules) : rewrittenRules
        let finalRules: [String] = {
            let base = scrubbed.isEmpty ? AppSettings.defaultRules : scrubbed
            guard forIOS else { return base }
            // Prepend DNS / APNS / WeChat / 电商 DIRECT so MATCH,PROXY cannot hijack.
            // APNS rules must sit ABOVE any apple.com DIRECT/APPLE suffix or CIDR leftovers.
            var out = IosDirectDomains.dnsBootstrapDirectRules
            out.append(contentsOf: IosRoutingRules.apnsPriorityRules)
            out.append(contentsOf: IosDirectDomains.wechatPriorityRules)
            out.append(contentsOf: IosDirectDomains.tiktokRulesForPlatform(forIOS: true))
            out.append(contentsOf: IosDirectDomains.ecommercePriorityRules)
            out.append(contentsOf: IosDirectDomains.xiaohongshuPriorityRules)
            out.append(contentsOf: IosDirectDomains.bankPriorityRules)
            out.append(contentsOf: IosDirectDomains.douyinPriorityRules)
            out.append(contentsOf: IosProxyDomains.rules)
            let head = base.filter { !$0.uppercased().hasPrefix("MATCH,") }
            // Drop duplicate APNS lines already prepended (base from RuntimeRules also has them).
            let apnsMarkers = ["PUSH.APPLE.COM", "17.249.", "17.252.", "17.57.144.", "17.188.128.", "17.188.20.", "PUSH-APPLE.COM"]
            let filteredHead = head.filter { line in
                let u = line.uppercased()
                return !apnsMarkers.contains { u.contains($0) }
            }
            out.append(contentsOf: filteredHead)
            out.append("MATCH,DIRECT")
            return out
        }()

        // ACL4SSR / Clash Verge style hub names used by PROXY select & 策略组 panel.
        let autoHubName = "AUTO"
        let balanceHubName = "BALANCE"
        let fallbackHubName = "FALLBACK"

        // Always keep PROXY as select with strategy hubs + DIRECT escape hatch.
        // Hub chips (smart/LB/FO) pick AUTO/BALANCE/FALLBACK inside PROXY — never rewrite PROXY
        // into url-test of leaves only (that blackholes the whole machine when all nodes die).
        let proxyGroupList: [String] = {
            var list: [String]
            if names.isEmpty {
                list = ["DIRECT"]
            } else if forIOS {
                // iOS: real nodes first (NE cannot nest url-test). Prefer leaf so MATCH,PROXY works.
                // BALANCE/FALLBACK are lazy — no probing unless the user actually picks them.
                let leaves = Self.urlTestPool(from: poolSource, selected: selected, limit: 32)
                list = leaves + [autoHubName, balanceHubName, fallbackHubName, "JP", "HK", "US", "TW", "DIRECT"]
            } else {
                let hubFirst: String = {
                    switch proxyHubMode {
                    case .smart: return autoHubName
                    case .loadBalance: return balanceHubName
                    case .failover: return fallbackHubName
                    case .manual: return autoHubName
                    }
                }()
                list = [hubFirst, autoHubName, balanceHubName, fallbackHubName, "JP", "HK", "US", "TW"]
                    + poolSource + ["DIRECT"]
            }
            if let selected, proxyHubMode == .manual || forIOS {
                list.removeAll { $0 == selected }
                list.insert(selected, at: 0)
            }
            var seen = Set<String>()
            return list.filter { seen.insert($0).inserted }
        }()

        let proxyHubGroup: [String: Any] = [
            "name": "PROXY",
            "type": "select",
            "proxies": proxyGroupList,
        ]
        let probeURL = "https://www.gstatic.com/generate_204"
        let hubInterval = turboMode ? 300 : 180
        let hubTolerance = turboMode ? 50 : 40
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
                selected: selected,
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
                // Follow PROXY (user node) first — same reliability as Telegram.
                var list = Self.urlTestPool(from: poolSource, selected: selected, limit: iosPickerLimit)
                list.removeAll { $0 == "PROXY" }
                list.insert("PROXY", at: 0)
                if !list.contains("DIRECT") { list.append("DIRECT") }
                return list
            }
            return Self.urlTestPool(from: poolSource, selected: selected, limit: urlTestLimit)
        }()

        let autoProxies: [String] = {
            if poolSource.isEmpty { return ["DIRECT"] }
            if forIOS {
                return Self.urlTestPool(from: poolSource, selected: selected, limit: iosPickerLimit)
            }
            // Cap AUTO like TELEGRAM/GOOGLE — full-list url-test burns CPU/battery on large airports.
            var pool = Self.urlTestPool(from: poolSource, selected: selected, limit: urlTestLimit)
            if !pool.contains("DIRECT") { pool.append("DIRECT") }
            return pool
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
                    // 负载均衡 / 故障转移: lazy so health checks only run if actively selected (jetsam-safe).
                    [
                        "name": balanceHubName,
                        "type": "load-balance",
                        "proxies": autoProxies,
                        "url": probeURL,
                        "interval": 300,
                        "strategy": "consistent-hashing",
                        "lazy": true,
                    ],
                    [
                        "name": fallbackHubName,
                        "type": "fallback",
                        "proxies": autoProxies,
                        "url": probeURL,
                        "interval": 300,
                        "lazy": true,
                    ],
                    Self.iosSelectGroup(name: "GOOGLE", proxies: googleProxies),
                    Self.iosSelectGroup(name: "JP", proxies: jpProxies),
                    Self.iosSelectGroup(name: "HK", proxies: hkProxies),
                    Self.iosSelectGroup(name: "US", proxies: usProxies),
                    Self.iosSelectGroup(name: "TW", proxies: twProxies),
                ] + Self.telegramGroups(proxies: telegramProxies, forIOS: true)
                    + Self.apnsGroups(proxies: telegramProxies, selected: selected, forIOS: true)
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
                    "name": autoHubName,
                    "type": "url-test",
                    "proxies": autoProxies,
                    "url": probeURL,
                    "interval": turboMode ? 300 : 180,
                    "tolerance": hubTolerance,
                    "lazy": true
                ],
                [
                    "name": balanceHubName,
                    "type": "load-balance",
                    "proxies": autoProxies,
                    "url": probeURL,
                    "interval": hubInterval,
                    "strategy": "consistent-hashing",
                    "lazy": true
                ],
                [
                    "name": fallbackHubName,
                    "type": "fallback",
                    "proxies": autoProxies,
                    "url": probeURL,
                    "interval": hubInterval,
                    "lazy": true
                ],
                googleAuto,
                googleSelect,
            ] + regionGroups + Self.telegramGroups(proxies: telegramProxies, forIOS: false)
                + Self.apnsGroups(proxies: telegramProxies, selected: selected, forIOS: false)
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
            // Mac + TUN: disable IPv6 stack — Meta Happy-Eyeballs dials AAAA:5222 and QR WebSocket dies.
            // iOS NE still needs v6 for Telegram DC literals when utun is on.
            "ipv6": forIOS && tunEnabled,
            // Same as Clash Verge / Meta — one delay per proxy instead of per hop.
            "unified-delay": true,
            "dns": forIOS
                ? DnsPreference.iosDnsBlock(for: dnsPreference)
                : DnsPreference.dnsBlock(for: dnsPreference),
            "proxies": proxies,
            "proxy-groups": [
                proxyHubGroup,
                [
                    "name": "GLOBAL",
                    "type": "select",
                    "proxies": proxyGroupList
                ],
            ] + auxiliaryGroups,
            "rules": finalRules
        ]

        mergeShadowrocketRuleProviders(into: &root)

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
            // TUN + PROCESS-NAME (AdsPower S5 by IP) needs always — `strict` often misses helper processes.
            root["find-process-mode"] = "always"
            if domainSniffing {
                root["sniffer"] = snifferBlock
            }
        } else {
            root["find-process-mode"] = "off"
            // Concurrent dials + large proxy graphs spike RAM → iOS jetsam kills the NE.
            root["tcp-concurrent"] = false
            // Longer keep-alive for Binance / trading WebSockets (10s was too chatty + flappy).
            root["keep-alive-interval"] = 25
            // Sniffer OFF — enabling it in 1.0.48 jetsam'd the NE so TikTok (and often all
            // tunnel traffic) could not open. Domain rules + fake-ip-filter cover named hosts.
            root["sniffer"] = ["enable": false]
            root["profile"] = ["store-selected": true, "store-fake-ip": false]
        }

        if tunEnabled {
            root["tun"] = Self.tunBlock(stack: tunStack, forIOS: forIOS)
        }

        return (try? Yams.dump(object: root)) ?? ""
    }

    /// True when the subscription YAML already defines policy groups (Clash Verge / Stash style).
    static func isCompleteProfile(_ root: [String: Any]) -> Bool {
        if let groups = root["proxy-groups"] as? [Any], !groups.isEmpty { return true }
        if let groups = root["Proxy Group"] as? [Any], !groups.isEmpty { return true }
        return false
    }

    /// Keep subscription `proxies` / `proxy-groups` / `rules` / providers; only inject
    /// ports, TUN, controller (and platform-safe DNS fallback). Clash Verge / Stash pattern.
    static func buildPassthroughConfig(
        from rawRoot: [String: Any],
        mixedPort: Int,
        controller: String,
        secret: String,
        tunEnabled: Bool,
        tunStack: String,
        mode: ProxyMode = .rule,
        allowLan: Bool = false,
        dnsPreference: DnsPreference = .smart,
        forIOS: Bool = false,
        domainSniffing: Bool = true,
        selectedName: String? = nil,
        proxyHubMode: ProxyHubMode = .smart,
        turboMode: Bool = true
    ) -> String {
        var root = deepNativeDict(rawRoot)

        // Runtime knobs owned by the app — never keep airport copies.
        for key in [
            "mixed-port", "port", "socks-port", "redir-port", "tproxy-port",
            "allow-lan", "bind-address", "mode", "log-level",
            "external-controller", "secret", "external-ui", "external-ui-name", "external-ui-url",
            "tun"
        ] {
            root.removeValue(forKey: key)
        }

        let iosMixedPort = forIOS && !tunEnabled ? mixedPort : (forIOS ? 0 : mixedPort)
        let bindAddress: String = {
            if forIOS && !tunEnabled { return "127.0.0.1" }
            return allowLan ? "*" : "127.0.0.1"
        }()

        root["mixed-port"] = iosMixedPort
        root["allow-lan"] = allowLan
        root["bind-address"] = bindAddress
        root["mode"] = mode.rawValue
        root["log-level"] = "warning"
        root["external-controller"] = controller
        root["secret"] = secret
        // TUN needs IPv6 stack for Telegram DC literals; dns.ipv6 stays false — no AAAA pollution.
        if forIOS || tunEnabled {
            root["ipv6"] = true
        } else if root["ipv6"] == nil {
            root["ipv6"] = false
        }
        if root["unified-delay"] == nil { root["unified-delay"] = true }

        if var proxies = root["proxies"] as? [[String: Any]] {
            for i in proxies.indices {
                normalizeProxyUDP(&proxies[i])
            }
            root["proxies"] = proxies
        }

        if forIOS {
            // Airport DNS often needs geosite DB; we disable geo on NE → Google/Telegram
            // resolve fails while WeChat (.cn policy) still works. Always use BashX iOS DNS.
            root["dns"] = DnsPreference.iosDnsBlock(for: dnsPreference)
            // url-test health checks + RULE-SET downloads blow the NE jetsam budget.
            sanitizeIOSPassthroughGroups(&root)
            applyPassthroughSelectedNode(&root, selectedName: selectedName)
            let scrubbed = scrubIOSIncompatibleRules(stringList(root["rules"]) ?? [])
            root["rules"] = patchIOSPassthroughRules(scrubbed, groupNames: proxyGroupNames(in: root))
            root["geodata-mode"] = false
            root["geo-auto-update"] = false
            root["find-process-mode"] = "off"
            root["tcp-concurrent"] = false
            root["keep-alive-interval"] = 25
            root["sniffer"] = ["enable": false]
            root["profile"] = ["store-selected": true, "store-fake-ip": false]
        } else {
            root["find-process-mode"] = "always"
            if root["tcp-concurrent"] == nil { root["tcp-concurrent"] = true }
            if root["keep-alive-interval"] == nil { root["keep-alive-interval"] = 30 }
            if domainSniffing, root["sniffer"] == nil {
                root["sniffer"] = snifferBlock
            }
            // Always BashX DNS — airport DNS often lacks telegram/cursor fake-ip-filter → MTProto/agent hang.
            root["dns"] = DnsPreference.dnsBlock(for: dnsPreference)
            injectMacReliabilityStack(
                &root,
                selectedName: selectedName,
                proxyHubMode: proxyHubMode,
                turboMode: turboMode
            )
            applyPassthroughSelectedNode(&root, selectedName: selectedName)
            applyPassthroughHubMode(&root, mode: proxyHubMode, turboMode: turboMode)
        }

        mergeShadowrocketRuleProviders(into: &root)

        if tunEnabled {
            root["tun"] = tunBlock(stack: tunStack, forIOS: forIOS)
        }

        return (try? Yams.dump(object: root)) ?? ""
    }

    /// Exposed for runtime TUN hot-patch (must match written config).
    static func tunConfigBlock(stack: String, forIOS: Bool = false) -> [String: Any] {
        tunBlock(stack: stack, forIOS: forIOS)
    }

    private static func tunBlock(stack: String, forIOS: Bool) -> [String: Any] {
        var tun: [String: Any] = [
            "enable": true,
            "stack": stack.isEmpty ? "mixed" : stack,
            "auto-route": true,
            "auto-detect-interface": true,
            "dns-hijack": ["any:53"],
            "strict-route": !forIOS
        ]
        if forIOS {
            tun["mtu"] = 1400
            // Exclude domestic CDN CIDRs so chat/video media bypasses gVisor (RSS).
            // ByteDance: mainland Douyin CDN only — do NOT add byteoversea/TikTok overseas.
            tun["route-exclude-address"] = [
                // Tencent / WeChat
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
                // Alibaba / 淘宝 / 天猫
                "42.120.0.0/16", "42.156.0.0/16",
                "47.92.0.0/14", "47.96.0.0/13", "47.104.0.0/13",
                "59.82.0.0/15",
                "101.37.0.0/16", "106.11.0.0/16", "110.75.0.0/16",
                "114.55.0.0/16", "115.124.0.0/16",
                "118.31.0.0/16", "118.178.0.0/16",
                "120.26.0.0/15", "120.55.0.0/16", "121.40.0.0/13",
                "139.196.0.0/16", "139.224.0.0/16", "140.205.0.0/16",
                "182.92.0.0/16", "203.119.128.0/17", "205.204.96.0/19",
                "223.4.0.0/15", "223.6.0.0/16",
                // 抖音 / 头条 mainland CDN
                "49.51.0.0/16", "58.33.0.0/16", "101.89.0.0/16",
                "111.202.0.0/15", "111.206.0.0/16", "116.63.0.0/16",
                "123.125.0.0/16", "180.97.0.0/16", "180.149.0.0/16",
                "182.61.0.0/16", "220.181.0.0/16", "220.243.0.0/16",
                "221.194.0.0/16", "223.109.0.0/16", "223.111.0.0/16",
            ]
        }
        // Mac: do NOT set inet4-route-address. Restricting to 198.18/16 + Telegram DCs
        // drops WhatsApp when system DNS returns real Meta IPs (bypass/DoH) — those
        // dials never enter TUN → DIRECT → QR WebSocket never opens.
        // Full auto-route + strict-route: destination IPs enter TUN, then
        // GEOIP CN/PRIVATE → DIRECT；其余 MATCH,PROXY（ACL4SSR 漏网之鱼）.
        return tun
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let arr = value as? [Any] else { return nil }
        let out = arr.compactMap { item -> String? in
            if let s = item as? String { return s }
            return nil
        }
        return out
    }

    private static func deepNativeDict(_ value: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in value {
            out[k] = deepNative(v)
        }
        return out
    }

    private static func deepNative(_ value: Any) -> Any {
        let v = unwrap(value)
        if let dict = v as? [String: Any] {
            return dict.mapValues { deepNative($0) }
        }
        if let arr = v as? [Any] {
            return arr.map { deepNative($0) }
        }
        if let dict = v as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, val) in dict {
                guard let key = k as? String else { continue }
                out[key] = deepNative(val)
            }
            return out
        }
        if let arr = v as? NSArray {
            return arr.map { deepNative($0) }
        }
        return v
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

    /// iOS NE: sniff SNI so bare-IP TikTok/WeChat CDN hits DOMAIN rules (not MATCH,DIRECT).
    private static let iosSnifferBlock: [String: Any] = [
        "enable": true,
        "force-dns-mapping": true,
        "parse-pure-ip": true,
        "override-destination": false,
        "sniff": [
            "TLS": ["ports": [443, 8443]],
            "HTTP": ["ports": [80, 8080]],
        ],
        "skip-domain": [
            "+.push.apple.com",
            "+.apple.com",
            "+.icloud.com",
            "+.cdn-apple.com",
            "+.mzstatic.com",
            "+.qq.com",
            "+.weixin.qq.com",
            "+.baidu.com",
            "+.alicdn.com",
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
        if hasHub(usProxies) { tiktokHubs.append("US") }

        // iOS: prefer one JP/SG leaf as TIKTOK default (TikTok geo-blocks many US/ME exits),
        // then PROXY. No nested JP/HK hubs (those broke NE boot on Air).
        let tiktokMembers: [String] = {
            if !forIOS {
                return members(hubs: tiktokHubs, preferDirect: false, includeProxy: true)
            }
            let preferKeys = ["日本", "JP", "Japan", "东京", "大阪", "新加坡", "SG", "Singapore"]
            let preferred = leaves.first { name in
                preferKeys.contains(where: { name.localizedCaseInsensitiveContains($0) })
            }
            var list: [String] = []
            if let preferred { list.append(preferred) }
            list.append("PROXY")
            list.append("DIRECT")
            return list
        }()

        return [
            iosSelectGroup(name: "NETFLIX", proxies: members(hubs: streamingHubs, preferDirect: false, includeProxy: true)),
            iosSelectGroup(name: "TIKTOK", proxies: tiktokMembers),
            iosSelectGroup(name: "TWITTER", proxies: members(hubs: socialHubs, preferDirect: false, includeProxy: true, proxyFirst: true)),
        ]
        + whatsappGroups(
            socialHubs: socialHubs,
            leaves: leaves,
            iosMembers: members(hubs: socialHubs, preferDirect: false, includeProxy: true, proxyFirst: true),
            forIOS: forIOS
        )
        + [
            iosSelectGroup(name: "STEAM", proxies: members(hubs: [], preferDirect: false, includeProxy: false, proxyFirst: true)),
            iosSelectGroup(name: "MICROSOFT", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
            iosSelectGroup(name: "APPLE", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
        ] + (forIOS ? [] : [
            // Mac only — iOS rules hard-DIRECT 哔哩/抖音; extra groups waste NE RAM.
            iosSelectGroup(name: "BILIBILI", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
            iosSelectGroup(name: "DOUYIN", proxies: members(hubs: [], preferDirect: true, includeProxy: true)),
        ])
    }

    /// Mac: WHATSAPP-AUTO url-tests `web.whatsapp.com` (login + `/ws/chat` share the host).
    /// PROXY's gstatic health-check often stays green while WhatsApp WebSocket is DPI-killed.
    private static func whatsappGroups(
        socialHubs: [String],
        leaves: [String],
        iosMembers: [String],
        forIOS: Bool
    ) -> [[String: Any]] {
        if forIOS {
            return [iosSelectGroup(name: "WHATSAPP", proxies: iosMembers)]
        }
        let pool = Array(leaves.prefix(20))
        let autoProxies = pool.isEmpty ? ["PROXY"] : pool
        let auto: [String: Any] = [
            "name": "WHATSAPP-AUTO",
            "type": "url-test",
            "proxies": autoProxies,
            "url": "https://web.whatsapp.com",
            "interval": 300,
            "tolerance": 150,
            "lazy": true,
            "expected-status": "200"
        ]
        var selectMembers = ["WHATSAPP-AUTO", "PROXY"]
        for hub in socialHubs where !selectMembers.contains(hub) { selectMembers.append(hub) }
        for leaf in pool where !selectMembers.contains(leaf) { selectMembers.append(leaf) }
        if !selectMembers.contains("DIRECT") { selectMembers.append("DIRECT") }
        return [
            auto,
            iosSelectGroup(name: "WHATSAPP", proxies: selectMembers)
        ]
    }

    /// High-availability Telegram path (Shadowrocket 电报消息 + mihomo failover):
    /// TELEGRAM-AUTO (url-test Asia) → TELEGRAM-FAILOVER (fallback chain) → TELEGRAM (select).
    /// iOS: select only (no background url-test — jetsam). Default follows PROXY (user's node).
    private static func telegramGroups(proxies: [String], forIOS: Bool) -> [[String: Any]] {
        let leaves = proxies.filter {
            $0 != "DIRECT" && $0 != "PROXY" && !$0.hasPrefix("TELEGRAM")
                && $0 != "HK" && $0 != "JP" && $0 != "TW" && $0 != "US"
                && !Self.isPlaceholderNodeName($0)
        }
        if forIOS {
            // Follow main node first — Asia-only leaf pools often pick a dead node while
            // PROXY (user selection) still works. Do NOT nest empty JP/HK hubs → DIRECT.
            var iosMembers: [String] = ["PROXY"]
            for leaf in leaves where !iosMembers.contains(leaf) {
                iosMembers.append(leaf)
            }
            if !iosMembers.contains("DIRECT") { iosMembers.append("DIRECT") }
            return [iosSelectGroup(name: "TELEGRAM", proxies: Array(iosMembers.prefix(12)))]
        }

        let autoProxies = leaves.isEmpty ? ["DIRECT"] : leaves
        let auto: [String: Any] = [
            "name": "TELEGRAM-AUTO",
            "type": "url-test",
            "proxies": autoProxies,
            "url": TelegramReliability.probeURL,
            "interval": 120,
            "tolerance": 150,
            "lazy": true,
            "expected-status": "200/301/302/404",
        ]

        // Failover: follow user's PROXY first (usually already working), then AUTO / hubs.
        var failoverMembers: [String] = ["PROXY", "TELEGRAM-AUTO"]
        for hub in ["HK", "JP", "TW", "US"] where !failoverMembers.contains(hub) {
            failoverMembers.append(hub)
        }
        if !failoverMembers.contains("DIRECT") {
            failoverMembers.append("DIRECT")
        }
        let failover: [String: Any] = [
            "name": "TELEGRAM-FAILOVER",
            "type": "fallback",
            "proxies": failoverMembers,
            "url": TelegramReliability.probeURL,
            "interval": 90,
            "lazy": true,
            "expected-status": "200/301/302/404",
        ]

        // PROXY first — user's working node; FAILOVER/AUTO as recovery.
        var selectMembers: [String] = ["PROXY", "TELEGRAM-FAILOVER", "TELEGRAM-AUTO"]
        for leaf in leaves where !selectMembers.contains(leaf) {
            selectMembers.append(leaf)
        }
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

    /// Low-latency Apple Push (APNs) — follow the user's working PROXY first (v1 behavior that
    /// actually delivered Telegram notifications), then Asia leaves as backup.
    private static func apnsGroups(proxies: [String], selected: String?, forIOS: Bool) -> [[String: Any]] {
        let leaves = proxies.filter {
            $0 != "DIRECT" && $0 != "PROXY" && !$0.hasPrefix("TELEGRAM") && !$0.hasPrefix("APNS")
                && $0 != "HK" && $0 != "JP" && $0 != "TW" && $0 != "US"
                && !Self.isPlaceholderNodeName($0)
        }
        var members: [String] = ["PROXY"]
        if let selected, leaves.contains(selected), !members.contains(selected) {
            members.insert(selected, at: 0)
        }
        for hub in ["HK", "JP", "TW"] where !members.contains(hub) {
            members.append(hub)
        }
        for leaf in leaves where !members.contains(leaf) {
            members.append(leaf)
        }
        if !members.contains("DIRECT") { members.append("DIRECT") }
        let cap = forIOS ? 8 : 18
        return [iosSelectGroup(name: "APNS", proxies: Array(members.prefix(cap)))]
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
            "interval": 180,
            "tolerance": 150,
            "lazy": true,
            "expected-status": "200/301/302/404",
        ]

        // PROXY first — follow user's working node; US-only auto often dead while PROXY works.
        var failoverMembers: [String] = ["PROXY", "CURSOR-AUTO", "US", "AI"]
        if !failoverMembers.contains("DIRECT") { failoverMembers.append("DIRECT") }
        let failover: [String: Any] = [
            "name": "CURSOR-FAILOVER",
            "type": "fallback",
            "proxies": failoverMembers,
            "url": CursorReliability.probeURL,
            "interval": 120,
            "lazy": true,
            "expected-status": "200/301/302/404",
        ]

        var selectMembers: [String] = ["PROXY", "CURSOR-FAILOVER", "CURSOR-AUTO", "US"]
        for leaf in leaves where !selectMembers.contains(leaf) { selectMembers.append(leaf) }
        if !selectMembers.contains("AI") { selectMembers.append("AI") }
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

    /// Drop rule types that crash or hang mihomo inside the iOS Network Extension.
    private static func scrubIOSIncompatibleRules(_ rules: [String]) -> [String] {
        rules.compactMap { raw in
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            let u = t.uppercased()
            if u.hasPrefix("PROCESS-NAME,") || u.hasPrefix("PROCESS-PATH,")
                || u.hasPrefix("PROCESS-NAME-REGEX,") || u.hasPrefix("PROCESS-PATH-REGEX,") {
                return nil
            }
            if u.hasPrefix("GEOSITE,") || u.hasPrefix("GEOIP,") { return nil }
            // RULE-SET needs rule-providers — keep bundled SR local sets only.
            if u.hasPrefix("RULE-SET,") {
                let parts = t.split(separator: ",").map(String.init)
                if parts.count >= 2, ShadowrocketForeverRules.isLocalRuleSet(parts[1]) {
                    return t
                }
                return nil
            }
            if u.hasPrefix("SUB-RULE,") { return nil }
            return t
        }
    }

    private static func proxyGroupNames(in root: [String: Any]) -> Set<String> {
        let groups = (root["proxy-groups"] as? [[String: Any]]) ?? []
        return Set(groups.compactMap { $0["name"] as? String })
    }

    private static func proxyLeafNames(in root: [String: Any]) -> [String] {
        let proxies = (root["proxies"] as? [[String: Any]]) ?? []
        return proxies.compactMap { item -> String? in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            if isPlaceholderNodeName(name) { return nil }
            return name
        }
    }

    /// Pick the airport's main outbound group (ACL4SSR / Verge naming).
    private static func resolvePrimaryProxyGroupName(in groups: [[String: Any]]) -> String? {
        let names = groups.compactMap { $0["name"] as? String }
        let preferred = [
            "PROXY", "Proxy", "proxy",
            "节点选择", "🚀 节点选择", "手动选择", "Proxy",
            "选择节点", "全球代理", "国外流量",
        ]
        for key in preferred where names.contains(key) { return key }
        // First select group that lists real proxies (skip DIRECT-only helpers).
        for g in groups {
            guard let name = g["name"] as? String,
                  (g["type"] as? String)?.lowercased() == "select" else { continue }
            let members = (g["proxies"] as? [Any])?.compactMap { $0 as? String } ?? []
            if members.contains(where: { $0 != "DIRECT" && $0 != "REJECT" }) {
                return name
            }
        }
        return names.first
    }

    /// iOS NE: flatten health-check groups to select; ensure PROXY / GOOGLE / TELEGRAM exist
    /// and prefer the primary proxy group (user's node) so Telegram/Google don't stick on a dead leaf.
    private static func sanitizeIOSPassthroughGroups(_ root: inout [String: Any]) {
        var groups = (root["proxy-groups"] as? [[String: Any]]) ?? []
        let leaves = Array(proxyLeafNames(in: root).prefix(16))
        let fallbackMembers: [String] = {
            var list = leaves
            if list.isEmpty { list = ["DIRECT"] }
            else if !list.contains("DIRECT") { list.append("DIRECT") }
            return list
        }()

        for i in groups.indices {
            let type = (groups[i]["type"] as? String)?.lowercased() ?? ""
            if type == "url-test" || type == "fallback" || type == "load-balance" {
                groups[i]["type"] = "select"
                for key in ["url", "interval", "tolerance", "lazy", "strategy", "expected-status"] {
                    groups[i].removeValue(forKey: key)
                }
            }
        }

        let primary = resolvePrimaryProxyGroupName(in: groups) ?? "PROXY"
        var existing = Set(groups.compactMap { $0["name"] as? String })

        func ensureAlias(_ name: String) {
            guard !existing.contains(name) else { return }
            var members: [String] = []
            if primary != name { members.append(primary) }
            for leaf in fallbackMembers where !members.contains(leaf) {
                members.append(leaf)
            }
            if members.isEmpty { members = ["DIRECT"] }
            groups.append(["name": name, "type": "select", "proxies": members])
            existing.insert(name)
        }

        /// Even when the airport already defines TELEGRAM/GOOGLE, force primary first.
        func preferPrimary(_ name: String) {
            if let idx = groups.firstIndex(where: { ($0["name"] as? String) == name }) {
                var members = (groups[idx]["proxies"] as? [Any])?.compactMap { $0 as? String } ?? []
                members.removeAll { $0 == primary || $0 == name }
                if primary != name { members.insert(primary, at: 0) }
                if members.isEmpty { members = fallbackMembers }
                if !members.contains("DIRECT") { members.append("DIRECT") }
                // Avoid defaulting to DIRECT when real proxies exist.
                if members.first == "DIRECT", members.count > 1 {
                    members.removeFirst()
                    members.append("DIRECT")
                }
                groups[idx]["type"] = "select"
                groups[idx]["proxies"] = members
                for key in ["url", "interval", "tolerance", "lazy", "strategy", "expected-status"] {
                    groups[idx].removeValue(forKey: key)
                }
                return
            }
            ensureAlias(name)
        }

        ensureAlias("PROXY")
        preferPrimary("GOOGLE")
        preferPrimary("TELEGRAM")
        // Do NOT preferPrimary(APNS) — that pins US PROXY into APNs and adds multi-second delay.
        root["proxy-groups"] = groups
    }

    /// After scrubbing GEOSITE/GEOIP, inject domain + Telegram DC rules so Google/TG work.
    private static func patchIOSPassthroughRules(_ rules: [String], groupNames: Set<String>) -> [String] {
        let googleTarget = groupNames.contains("GOOGLE") ? "GOOGLE" : "PROXY"
        let telegramTarget = groupNames.contains("TELEGRAM") ? "TELEGRAM" : "PROXY"
        let tiktokTarget = groupNames.contains("TIKTOK") ? "TIKTOK" : "PROXY"
        let proxyTarget = groupNames.contains("PROXY") ? "PROXY" : (groupNames.sorted().first ?? "PROXY")

        func retarget(_ line: String) -> String {
            line
                .replacingOccurrences(of: ",GOOGLE", with: ",\(googleTarget)")
                .replacingOccurrences(of: ",TELEGRAM", with: ",\(telegramTarget)")
                .replacingOccurrences(of: ",TIKTOK", with: ",\(tiktokTarget)")
                .replacingOccurrences(of: ",PROXY", with: ",\(proxyTarget)")
        }

        var inject = ShadowrocketForeverRules.headerRules()
        inject.append(contentsOf: IosDirectDomains.wechatPriorityRules.map(retarget))
        inject.append(contentsOf: IosDirectDomains.tiktokRulesForPlatform(forIOS: true).map(retarget))
        inject.append(contentsOf: IosDirectDomains.ecommercePriorityRules.map(retarget))
        inject.append(contentsOf: IosDirectDomains.xiaohongshuPriorityRules.map(retarget))
        inject.append(contentsOf: IosDirectDomains.bankPriorityRules.map(retarget))
        inject.append(contentsOf: IosDirectDomains.douyinPriorityRules.map(retarget))
        // DNS bootstrap MUST be DIRECT — MATCH,PROXY would send 223.5.5.5 DoH via node
        // (chicken/egg → 502 → every foreign site dies).
        inject.append(contentsOf: IosDirectDomains.dnsBootstrapDirectRules)
        inject.append(contentsOf: IosProxyDomains.rules.map(retarget))
        // Foreign DoH only after a working node exists.
        inject.append(contentsOf: [
            "IP-CIDR,8.8.8.8/32,\(proxyTarget),no-resolve",
            "IP-CIDR,8.8.4.4/32,\(proxyTarget),no-resolve",
            "IP-CIDR,1.1.1.1/32,\(proxyTarget),no-resolve",
            "IP-CIDR,1.0.0.1/32,\(proxyTarget),no-resolve",
            "IP-CIDR,9.9.9.9/32,\(proxyTarget),no-resolve",
        ])
        let head = rules.filter { !$0.uppercased().hasPrefix("MATCH,") }
        // Unmatched (bare IP / unknown host) → DIRECT; domain PROXY rules still cover GFW/Google/TG.
        let match = "MATCH,DIRECT"
        var out = inject + head
        out.append(match)
        return out
    }

    /// Pin the user's node as first member of PROXY / primary / GOOGLE / TELEGRAM selects.
    private static func applyPassthroughSelectedNode(_ root: inout [String: Any], selectedName: String?) {
        guard let selectedName, !selectedName.isEmpty,
              !isPlaceholderNodeName(selectedName),
              proxyLeafNames(in: root).contains(selectedName) else { return }
        var groups = (root["proxy-groups"] as? [[String: Any]]) ?? []
        guard !groups.isEmpty else { return }

        let primary = resolvePrimaryProxyGroupName(in: groups) ?? "PROXY"
        // Never pin APNS to the user's global node — APNS must stay Asia-first for ≤3s delivery.
        let targets = Set(["PROXY", primary, "GOOGLE", "TELEGRAM"])

        for i in groups.indices {
            guard let name = groups[i]["name"] as? String, targets.contains(name) else { continue }
            var members = (groups[i]["proxies"] as? [Any])?.compactMap { $0 as? String } ?? []
            members.removeAll { $0 == selectedName }
            members.insert(selectedName, at: 0)
            // Never leave DIRECT as the default when a real leaf is selected.
            if members.first == "DIRECT", members.count > 1 {
                members.removeFirst()
                members.append("DIRECT")
            }
            groups[i]["proxies"] = members
            groups[i]["type"] = "select"
        }
        root["proxy-groups"] = groups
    }

    /// Mac passthrough: airport YAML often has TELEGRAM/CURSOR select groups that reference
    /// missing AUTO/FAILOVER hubs — that blackholes Telegram/Cursor. Inject BashX stacks.
    private static func injectMacReliabilityStack(
        _ root: inout [String: Any],
        selectedName: String?,
        proxyHubMode: ProxyHubMode,
        turboMode: Bool
    ) {
        let allLeaves = proxyLeafNames(in: root)
        guard !allLeaves.isEmpty else { return }

        let probeURL = "https://www.gstatic.com/generate_204"
        let hubInterval = turboMode ? 300 : 180
        let hubTolerance = turboMode ? 50 : 40
        let pool = urlTestPool(from: allLeaves, selected: selectedName, limit: 36)
        var autoPool = pool
        if !autoPool.contains("DIRECT") { autoPool.append("DIRECT") }

        let jp = regionPool(from: allLeaves, keys: ["日本", "JP", "Japan", "东京", "大阪", "Tokyo"], selected: selectedName, limit: 24)
        let hk = regionPool(from: allLeaves, keys: ["香港", "HK", "Hong Kong", "深港", "沪港"], selected: selectedName, limit: 24)
        let us = regionPool(from: allLeaves, keys: ["美国", "US", "USA", "America", "Los Angeles", "San Jose", "西雅图", "纽约"], selected: selectedName, limit: 24)
        let tw = regionPool(from: allLeaves, keys: ["台湾", "台灣", "TW", "Taiwan", "Taipei"], selected: selectedName, limit: 24)
        let asia = regionPool(
            from: allLeaves,
            keys: ["香港", "HK", "Hong Kong", "新加坡", "SG", "Singapore", "日本", "JP", "Japan", "台湾", "TW", "Taiwan"],
            selected: selectedName,
            limit: 16
        )
        let telegramLeaves = (asia == ["DIRECT"] || asia.isEmpty) ? Array(pool.prefix(16)) : asia

        var groups = (root["proxy-groups"] as? [[String: Any]]) ?? []

        func upsert(_ group: [String: Any]) {
            guard let name = group["name"] as? String else { return }
            if let idx = groups.firstIndex(where: { ($0["name"] as? String) == name }) {
                groups[idx] = group
            } else {
                groups.append(group)
            }
        }

        func regionUrlTestLocal(name: String, proxies: [String]) -> [String: Any] {
            var p = proxies.filter { $0 != "DIRECT" && !isPlaceholderNodeName($0) }
            if p.isEmpty { p = autoPool.filter { $0 != "DIRECT" } }
            if p.isEmpty { p = ["DIRECT"] }
            else if !p.contains("DIRECT") { p.append("DIRECT") }
            return [
                "name": name,
                "type": "url-test",
                "proxies": p,
                "url": probeURL,
                "interval": 600,
                "tolerance": 100,
                "lazy": true,
            ]
        }

        upsert([
            "name": "AUTO",
            "type": "url-test",
            "proxies": autoPool,
            "url": probeURL,
            "interval": hubInterval,
            "tolerance": hubTolerance,
            "lazy": true,
        ])
        upsert([
            "name": "BALANCE",
            "type": "load-balance",
            "proxies": autoPool,
            "url": probeURL,
            "interval": hubInterval,
            "strategy": "consistent-hashing",
            "lazy": true,
        ])
        upsert([
            "name": "FALLBACK",
            "type": "fallback",
            "proxies": autoPool,
            "url": probeURL,
            "interval": hubInterval,
            "lazy": true,
        ])
        upsert(regionUrlTestLocal(name: "JP", proxies: jp))
        upsert(regionUrlTestLocal(name: "HK", proxies: hk))
        upsert(regionUrlTestLocal(name: "US", proxies: us))
        upsert(regionUrlTestLocal(name: "TW", proxies: tw))

        for g in telegramGroups(proxies: telegramLeaves, forIOS: false) { upsert(g) }
        for g in cursorGroups(usProxies: us, allProxies: allLeaves, pinned: selectedName, forIOS: false) {
            upsert(g)
        }

        // Ensure PROXY is a select with strategy hubs + DIRECT (never dangling AUTO refs).
        let hubFirst: String = {
            switch proxyHubMode {
            case .smart: return "AUTO"
            case .loadBalance: return "BALANCE"
            case .failover: return "FALLBACK"
            case .manual: return "AUTO"
            }
        }()
        var proxyMembers = [hubFirst, "AUTO", "BALANCE", "FALLBACK", "JP", "HK", "US", "TW"] + allLeaves + ["DIRECT"]
        if let selectedName, proxyHubMode == .manual {
            proxyMembers.removeAll { $0 == selectedName }
            proxyMembers.insert(selectedName, at: 0)
        }
        var seen = Set<String>()
        proxyMembers = proxyMembers.filter { seen.insert($0).inserted }
        upsert([
            "name": "PROXY",
            "type": "select",
            "proxies": proxyMembers,
        ])

        // Drop dangling members that still reference missing groups.
        let existing = Set(groups.compactMap { $0["name"] as? String }).union(["DIRECT", "REJECT"])
        for i in groups.indices {
            guard var members = groups[i]["proxies"] as? [String] else { continue }
            let before = members
            members = members.filter { existing.contains($0) || allLeaves.contains($0) }
            if members.isEmpty { members = ["DIRECT"] }
            if members != before { groups[i]["proxies"] = members }
        }

        root["proxy-groups"] = groups

        // Prepend service-specific routing so imported broad rule sets (notably
        // SR-PROXY) cannot steal long-lived app/API traffic and pick an
        // incompatible region.
        var rules = stringList(root["rules"]) ?? []
        var inject = [
            "PROCESS-NAME,Telegram,TELEGRAM",
            "PROCESS-NAME,org.telegram.desktop,TELEGRAM",
            "PROCESS-PATH,*Telegram.app/Contents/MacOS/Telegram,TELEGRAM",
            "PROCESS-PATH,*Telegra2.app/Contents/MacOS/Telegram,TELEGRAM",
            "PROCESS-PATH,Telegra2,TELEGRAM",
            "IP-CIDR,149.154.160.0/20,TELEGRAM,no-resolve",
            "IP-CIDR,91.108.0.0/16,TELEGRAM,no-resolve",
            "IP-CIDR,91.105.192.0/23,TELEGRAM,no-resolve",
            "IP-CIDR,185.76.151.0/24,TELEGRAM,no-resolve",
            "IP-CIDR,95.161.64.0/20,TELEGRAM,no-resolve",
            "IP-CIDR6,2001:67c:4e8::/48,TELEGRAM,no-resolve",
            "IP-CIDR6,2001:b28:f23c::/48,TELEGRAM,no-resolve",
            "IP-CIDR6,2001:b28:f23d::/48,TELEGRAM,no-resolve",
            "IP-CIDR6,2001:b28:f23f::/48,TELEGRAM,no-resolve",
            "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
            "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
            "DOMAIN-SUFFIX,cdn-telegram.org,TELEGRAM",
            "DOMAIN-SUFFIX,telesco.pe,TELEGRAM",
            "DOMAIN-SUFFIX,t.me,TELEGRAM",
            "DOMAIN-SUFFIX,tx.me,TELEGRAM",
            "DOMAIN-KEYWORD,telegram,TELEGRAM",
            "DOMAIN-SUFFIX,cursor.sh,CURSOR",
            "DOMAIN-SUFFIX,cursor.com,CURSOR",
            "DOMAIN-SUFFIX,cursorapi.com,CURSOR",
            "DOMAIN-SUFFIX,cursor-cdn.com,CURSOR",
            "DOMAIN-SUFFIX,cursorvm.com,CURSOR",
            "DOMAIN-SUFFIX,anysphere.co,CURSOR",
            "DOMAIN-SUFFIX,anysphere.com,CURSOR",
            "DOMAIN,api2.cursor.sh,CURSOR",
            "DOMAIN,api3.cursor.sh,CURSOR",
            "DOMAIN,api4.cursor.sh,CURSOR",
            "DOMAIN-KEYWORD,gcpp.cursor,CURSOR",
            "DOMAIN-SUFFIX,anthropic.com,ANTHROPIC",
            "DOMAIN-SUFFIX,claude.ai,ANTHROPIC",
            "DOMAIN-SUFFIX,claude.com,ANTHROPIC",
            "DOMAIN-SUFFIX,claudeusercontent.com,ANTHROPIC",
            "DOMAIN-SUFFIX,claudemcpclient.com,ANTHROPIC",
            "DOMAIN-KEYWORD,claude,ANTHROPIC",
            "DOMAIN-KEYWORD,anthropic,ANTHROPIC",
        ]
        #if os(macOS)
        inject = AppRoutingRules.macAppBypassRules + inject
        #endif
        // Existing configs commonly already contain these domains, but much
        // farther down the list after imported RULE-SET,SR-PROXY.  Deduplicate
        // by matcher then force this complete set to the front.
        let injectMatchers = Set(inject.map {
            $0.split(separator: ",").prefix(2).joined(separator: ",").uppercased()
        })
        rules.removeAll { rule in
            let matcher = rule.split(separator: ",").prefix(2).joined(separator: ",").uppercased()
            return injectMatchers.contains(matcher)
        }
        rules.insert(contentsOf: inject, at: 0)
        root["rules"] = rules
    }

    /// Mac: keep PROXY as select; put the hub chip (AUTO/BALANCE/FALLBACK) first.
    /// Never rewrite PROXY into url-test of leaves — dead nodes would blackhole MATCH,PROXY.
    private static func applyPassthroughHubMode(
        _ root: inout [String: Any],
        mode: ProxyHubMode,
        turboMode: Bool
    ) {
        _ = turboMode
        guard mode != .manual else { return }
        var groups = (root["proxy-groups"] as? [[String: Any]]) ?? []
        guard !groups.isEmpty else { return }

        let primary = resolvePrimaryProxyGroupName(in: groups) ?? "PROXY"
        guard let idx = groups.firstIndex(where: { ($0["name"] as? String) == primary }) else { return }

        let hub: String = {
            switch mode {
            case .smart: return "AUTO"
            case .loadBalance: return "BALANCE"
            case .failover: return "FALLBACK"
            case .manual: return "AUTO"
            }
        }()

        var members = (groups[idx]["proxies"] as? [String]) ?? []
        members.removeAll { $0 == hub }
        members.insert(hub, at: 0)
        if !members.contains("DIRECT") { members.append("DIRECT") }
        groups[idx]["type"] = "select"
        groups[idx]["proxies"] = members
        groups[idx].removeValue(forKey: "url")
        groups[idx].removeValue(forKey: "interval")
        groups[idx].removeValue(forKey: "tolerance")
        groups[idx].removeValue(forKey: "lazy")
        groups[idx].removeValue(forKey: "strategy")
        groups[idx].removeValue(forKey: "expected-status")

        if primary != "PROXY" {
            if let proxyIdx = groups.firstIndex(where: { ($0["name"] as? String) == "PROXY" }) {
                var alias = groups[idx]
                alias["name"] = "PROXY"
                groups[proxyIdx] = alias
            }
        }

        root["proxy-groups"] = groups
    }

    /// Route Cursor / OpenAI / Anthropic / other AI (Shadowrocket AI.list).
    private static func normalizeAIRules(_ rules: [String], forIOS: Bool = false) -> [String] {
        // Drop whole-process Cursor hijack — forces npm/CN CDN through US sticky and breaks the IDE.
        var out = rules.filter { rule in
            let u = rule.uppercased()
            if u.hasPrefix("PROCESS-NAME,CURSOR") { return false }
            if u.hasPrefix("PROCESS-PATH,") && u.contains("CURSOR") { return false }
            return true
        }
        var inject: [String] = [
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
        if !forIOS {
            // Domain-only for Cursor cloud — do NOT PROCESS-NAME the whole Electron tree
            // (forces npm/CN CDN/local tooling through US sticky → IDE "busy"/broken).
            inject.insert(contentsOf: [
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
                "DOMAIN-KEYWORD,gcpp.cursor,CURSOR",
            ], at: 0)
        }

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
    private static func normalizeServiceRules(_ rules: [String], forIOS: Bool = false) -> [String] {
        var out = rules
        // Never inject GEOSITE on iOS — geo DB is scrubbed; Parse would hang or fail.
        var inject: [String] = [
            "DOMAIN-SUFFIX,steampowered.com,STEAM",
            "DOMAIN-SUFFIX,steamcommunity.com,STEAM",
            "DOMAIN-SUFFIX,microsoft.com,MICROSOFT",
            "DOMAIN-SUFFIX,apple.com,APPLE",
            "DOMAIN-SUFFIX,bilibili.com,DIRECT",
            "DOMAIN-SUFFIX,hdslb.com,DIRECT",
            "DOMAIN-SUFFIX,douyin.com,DIRECT",
            "DOMAIN-SUFFIX,bytedance.com,DIRECT",
            "DOMAIN-SUFFIX,netflix.com,NETFLIX",
            "DOMAIN-SUFFIX,tiktok.com,TIKTOK",
            "DOMAIN-SUFFIX,twitter.com,TWITTER",
            "DOMAIN-SUFFIX,x.com,TWITTER",
            "DOMAIN-SUFFIX,whatsapp.com,WHATSAPP",
        ]
        if !forIOS {
            inject.insert(contentsOf: [
                "GEOSITE,netflix,NETFLIX",
                "GEOSITE,tiktok,TIKTOK",
                "GEOSITE,twitter,TWITTER",
                "GEOSITE,whatsapp,WHATSAPP",
            ], at: 0)
        }
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

    /// Prefer low-latency Asia hubs for url-test / auto-pick (never Middle East first).
    static func preferredRegionNodes(from names: [String]) -> [String] {
        let core = coreAsiaPreferredNodes(from: names)
        if core.count >= 2 { return core }
        let asia = asiaPreferredNodes(from: names)
        if asia.count >= 2 { return asia }
        return names
    }

    /// Tier-1: HK / TW / SG / JP / KR — default auto-connect prefers these.
    static func isCoreAsiaPreferredNodeName(_ name: String) -> Bool {
        let keys = [
            "香港", "HK", "Hong Kong", "澳门", "MO", "Macao", "Macau",
            "台湾", "台灣", "TW", "Taiwan",
            "新加坡", "SG", "Singapore",
            "日本", "JP", "Japan", "东京", "大阪", "名古屋",
            "韩国", "韓國", "KR", "Korea", "首尔", "首爾",
        ]
        return keys.contains { name.localizedCaseInsensitiveContains($0) }
    }

    /// Tier-2 SEA — used only when no Tier-1 Asia node is healthy.
    static func isAsiaPreferredNodeName(_ name: String) -> Bool {
        if isCoreAsiaPreferredNodeName(name) { return true }
        let keys = [
            "马来", "馬來", "MY", "Malaysia",
            "泰国", "TH", "越南", "VN", "菲律宾", "PH", "印尼", "ID",
        ]
        return keys.contains { name.localizedCaseInsensitiveContains($0) }
    }

    /// Bahrain / UAE / etc. — fine as manual pick, never auto-preferred over Asia.
    static func isDeprioritizedRegionNodeName(_ name: String) -> Bool {
        let keys = [
            "巴林", "BH", "Bahrain",
            "迪拜", "阿联酋", "阿聯酋", "AE", "Dubai", "UAE",
            "沙特", "SA", "Saudi",
            "卡塔尔", "卡達", "QA", "Qatar",
            "科威特", "KW", "Kuwait",
            "以色列", "IL", "Israel",
            "土耳其", "TR", "Turkey", "Türkiye",
            "印度", "IN", "India",
            "巴西", "BR", "Brazil",
            "阿根廷", "AR", "Argentina",
            "南非", "ZA", "Africa",
            "尼日利亚", "NG", "Nigeria",
        ]
        return keys.contains { name.localizedCaseInsensitiveContains($0) }
    }

    static func coreAsiaPreferredNodes(from names: [String]) -> [String] {
        names.filter { isCoreAsiaPreferredNodeName($0) && !isDeprioritizedRegionNodeName($0) }
    }

    static func asiaPreferredNodes(from names: [String]) -> [String] {
        names.filter { isAsiaPreferredNodeName($0) && !isDeprioritizedRegionNodeName($0) }
    }

    /// Traffic / expiry / remark rows that are not real proxies.
    static func isPlaceholderNodeName(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("expire") || n.contains("到期") || n.contains("剩余") { return true }
        if n.contains("流量") || n.contains("traffic") || n.contains("重置") { return true }
        if n.contains("官网") || n.contains("套餐") || n.contains("通知") { return true }
        if n.contains("仅作展示") || n.contains("测速备用") || n.contains("公告") { return true }
        if n.contains("gb/") || n.contains("gb /") || n.contains("days") { return true }
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
        // Selected may sit outside the Asia-preferred subset (e.g. "懒人 01A").
        // Still force-include it from the FULL name list — otherwise iOS export drops it,
        // select API returns 400, and PROXY stays broken → connected but no network.
        if let selected, names.contains(selected) {
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
        // Always keep Telegra2 path — masqueraded installs don't match *Telegram.app/*.
        if !out.contains(where: { $0.contains("Telegra2") && $0.uppercased().contains("TELEGRAM") }) {
            let telegra2 = [
                "PROCESS-PATH,*Telegra2.app/Contents/MacOS/Telegram,TELEGRAM",
                "PROCESS-PATH,Telegra2,TELEGRAM",
            ]
            if let idx = out.firstIndex(where: {
                $0.uppercased().hasPrefix("PROCESS-NAME,TELEGRAM") || $0.uppercased().hasPrefix("PROCESS-PATH,*TELEGRAM.APP")
            }) {
                out.insert(contentsOf: telegra2, at: idx + 1)
            } else if let idx = out.firstIndex(where: { $0.contains("149.154.160.0/20") && $0.contains("TELEGRAM") }) {
                out.insert(contentsOf: telegra2, at: idx)
            } else {
                out.insert(contentsOf: telegra2, at: min(20, out.count))
            }
        }
        if !hasDC {
            let inject = [
                "PROCESS-NAME,Telegram,TELEGRAM",
                "PROCESS-NAME,org.telegram.desktop,TELEGRAM",
                "PROCESS-PATH,*Telegra2.app/Contents/MacOS/Telegram,TELEGRAM",
                "PROCESS-PATH,Telegra2,TELEGRAM",
                "PROCESS-PATH,*Telegram.app/Contents/MacOS/Telegram,TELEGRAM",
            ] + TelegramReliability.dcIPv4CIDRs.map { "IP-CIDR,\($0),TELEGRAM,no-resolve" }
                + TelegramReliability.dcIPv6CIDRs.map { "IP-CIDR6,\($0),TELEGRAM,no-resolve" }
                + [
                "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
                "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
                "DOMAIN-SUFFIX,cdn-telegram.org,TELEGRAM",
                "DOMAIN-SUFFIX,telesco.pe,TELEGRAM",
                "DOMAIN-SUFFIX,t.me,TELEGRAM",
                "DOMAIN-SUFFIX,tx.me,TELEGRAM",
                "DOMAIN-SUFFIX,graph.org,TELEGRAM",
                "DOMAIN-SUFFIX,tdesktop.com,TELEGRAM",
                "DOMAIN-SUFFIX,telegra.ph,TELEGRAM",
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
                return payload.contains("telegram") || payload.contains("telegra")
            }
            if type == "PROCESS-PATH" {
                return payload.contains("telegram") || payload.contains("telegra")
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
                    || payload.hasPrefix("95.161.")
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
        if isPlaceholderNodeName(node.name) { return false }
        let infoNeedles = [
            "剩余流量", "套餐到期", "距离下次", "Traffic:", "Expire:", "GB /", "GB/", "流量：", "流量:",
            "重置剩余", "套餐剩余", "已用流量", "到期时间", "用不完", "无限流量", "点击星辰",
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
        let prefixes = ["ss://", "ssr://", "vmess://", "vless://", "trojan://", "hysteria2://", "hy2://", "tuic://", "socks5://", "socks5h://", "socks://"]
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
        let udpCapable = ["vmess", "vless", "trojan", "ss", "ssr", "hysteria", "hysteria2", "tuic", "socks5"]
        guard udpCapable.contains(type) else { return }
        if dict["udp"] == nil {
            dict["udp"] = true
        }
    }

    /// IPFoxy etc. block CN — socks5 leaves dial through AUTO (airport), not DIRECT.
    private static func normalizeResidentialDialer(_ dict: inout [String: Any]) {
        let type = (dict["type"] as? String)?.lowercased() ?? ""
        guard type == "socks5" || type == "http" else { return }
        let server = ((dict["server"] as? String) ?? "").lowercased()
        guard server.contains("ipfoxy") else { return }
        if dict["dialer-proxy"] == nil {
            dict["dialer-proxy"] = "AUTO"
        }
    }

    /// Local SR-REJECT / SR-PROXY classical files (no runtime HTTP fetch in mihomo).
    private static func mergeShadowrocketRuleProviders(into root: inout [String: Any]) {
        let incoming = ShadowrocketForeverRules.ruleProvidersBlock()
        guard !incoming.isEmpty else { return }
        var merged = (root["rule-providers"] as? [String: Any]) ?? [:]
        for (key, value) in incoming {
            merged[key] = value
        }
        root["rule-providers"] = merged
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
        if lower.hasPrefix("socks5://") || lower.hasPrefix("socks5h://") || lower.hasPrefix("socks://") {
            return parseSocks5(line)
        }
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

    /// Supports:
    /// - `socks5://user:pass@host:port#name`
    /// - IPFoxy style `socks5://host:port:user:pass`
    private static func parseSocks5(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let hashParts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let main = hashParts[0]
        let fragName = hashParts.count > 1 ? (hashParts[1].removingPercentEncoding ?? hashParts[1]) : nil

        // Standard URL: socks5://user:pass@host:port
        if let url = URLComponents(string: main), let host = url.host, let port = url.port {
            var dict: [String: Any] = [
                "name": fragName ?? "SOCKS5-\(host)",
                "type": "socks5",
                "server": host,
                "port": port,
                "udp": true
            ]
            if let user = url.user?.removingPercentEncoding, !user.isEmpty {
                dict["username"] = user
            }
            if let pass = url.password?.removingPercentEncoding {
                dict["password"] = pass
            }
            applyResidentialDialerIfNeeded(&dict)
            return dict
        }

        // IPFoxy / vendor style: socks5://host:port:user:pass
        var body = main
        for prefix in ["socks5h://", "socks5://", "socks://"] where body.lowercased().hasPrefix(prefix) {
            body = String(body.dropFirst(prefix.count))
            break
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        // host:port:user:pass  — user/pass may contain ':' so take first two as host/port, rest split once
        guard parts.count >= 4, let port = Int(parts[1]), port > 0, port <= 65535 else { return nil }
        let host = parts[0]
        guard !host.isEmpty, !host.contains("/") else { return nil }
        let rest = parts.dropFirst(2).joined(separator: ":")
        guard let cut = rest.firstIndex(of: ":") else { return nil }
        let user = String(rest[..<cut])
        let pass = String(rest[rest.index(after: cut)...])
        guard !user.isEmpty, !pass.isEmpty else { return nil }
        var dict: [String: Any] = [
            "name": fragName ?? "SOCKS5-\(host)",
            "type": "socks5",
            "server": host,
            "port": port,
            "username": user,
            "password": pass,
            "udp": true
        ]
        applyResidentialDialerIfNeeded(&dict)
        return dict
    }

    /// IPFoxy / similar residential gates refuse mainland China dials — chain via airport AUTO.
    private static func applyResidentialDialerIfNeeded(_ dict: inout [String: Any]) {
        let server = ((dict["server"] as? String) ?? "").lowercased()
        guard server.contains("ipfoxy") || server.contains("gate-sg") || server.contains("gate-us") else { return }
        if dict["dialer-proxy"] == nil {
            dict["dialer-proxy"] = "AUTO"
        }
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
