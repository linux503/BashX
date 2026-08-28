import Foundation

/// mihomo DNS presets — domestic / foreign / smart split.
enum DnsPreference: String, Codable, CaseIterable, Identifiable {
    case smart
    case domestic
    case foreign

    var id: String { rawValue }

    var title: String { title(lang: .current) }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .smart: return L10n.t("dns.smart", lang)
        case .domestic: return L10n.t("dns.domestic", lang)
        case .foreign: return L10n.t("dns.foreign", lang)
        }
    }

    var subtitle: String { subtitle(lang: .current) }

    func subtitle(lang: AppLanguage) -> String {
        switch self {
        case .smart: return L10n.t("dns.smart.sub", lang)
        case .domestic: return L10n.t("dns.domestic.sub", lang)
        case .foreign: return L10n.t("dns.foreign.sub", lang)
        }
    }

    private static let telegramFakeIPFilters: [String] = [
        "+.telegram.org",
        "+.telegram-cdn.org",
        "+.cdn-telegram.org",
        "+.telesco.pe",
        "+.t.me",
        "+.graph.org",
        "+.tdesktop.com",
        "+.telegra.ph",
    ]

    private static let googleFakeIPFilters: [String] = [
        "geosite:google",
        "geosite:youtube",
        "+.google.com",
        "+.googleapis.com",
        "+.gstatic.com",
        "+.googleusercontent.com",
        "+.googlevideo.com",
        "+.ggpht.com",
        "+.gvt1.com",
        "+.gvt2.com",
        "+.translate.goog",
    ]

    /// +.google.com does NOT cover google.com.hk / google.cn — CN DNS poisons these unless listed explicitly.
    private static let googleDnsPolicy: [String: [String]] = [
        "+.google.com": [],
        "+.google.com.hk": [],
        "+.google.cn": [],
        "+.google.com.tw": [],
        "+.google.co.jp": [],
        "+.google.co.uk": [],
        "+.googleapis.com": [],
        "+.googleapis.cn": [],
        "+.gstatic.com": [],
        "+.gstatic.cn": [],
        "+.googleusercontent.com": [],
        "+.googlevideo.com": [],
        "+.youtube.com": [],
        "+.youtu.be": [],
        "+.ytimg.com": [],
        "+.ggpht.com": [],
        "+.gmail.com": [],
    ]

    /// Shared fake-ip shell; nameserver / fallback vary by preference.
    static func dnsBlock(for preference: DnsPreference) -> [String: Any] {
        let cnNS = [
            "https://doh.pub/dns-query",
            "https://dns.alidns.com/dns-query",
            "223.5.5.5",
            "119.29.29.29",
        ]
        let foreignNS = [
            "https://1.1.1.1/dns-query",
            "https://8.8.8.8/dns-query",
            "tls://1.1.1.1:853",
        ]
        let telegramNS = Array(foreignNS.prefix(2))
        let proxyNS = [
            "https://doh.pub/dns-query",
            "https://dns.alidns.com/dns-query",
            "223.5.5.5",
        ]

        let telegramPolicy: [String: Any] = [
            "+.telegram.org": telegramNS,
            "+.telegram-cdn.org": telegramNS,
            "+.cdn-telegram.org": telegramNS,
            "+.telesco.pe": telegramNS,
            "+.t.me": telegramNS,
            "+.graph.org": telegramNS,
            "+.tdesktop.com": telegramNS,
            "+.telegra.ph": telegramNS,
        ]

        let (nameserver, fallback, policy): ([String], [String], [String: Any]) = {
            switch preference {
            case .smart:
                return (
                    Array(cnNS.prefix(2)),
                    Array(foreignNS.prefix(2)),
                    telegramPolicy.merging([
                        "+.local": ["system"],
                        "+.lan": ["system"],
                        "geosite:gfw": Array(foreignNS.prefix(2)),
                        "geosite:cn,private,apple@cn,microsoft@cn": cnNS,
                    ]) { _, new in new }
                )
            case .domestic:
                return (
                    cnNS,
                    cnNS + foreignNS,
                    telegramPolicy.merging([
                        "+.local": ["system"],
                        "+.lan": ["system"],
                        "geosite:gfw,geolocation-!cn": foreignNS,
                        "geosite:cn,private,apple@cn,microsoft@cn": cnNS,
                    ]) { _, new in new }
                )
            case .foreign:
                return (
                    foreignNS,
                    foreignNS,
                    telegramPolicy.merging([
                        "+.local": ["system"],
                        "+.lan": ["system"],
                        "geosite:cn,private,apple@cn,microsoft@cn": cnNS,
                    ]) { _, new in new }
                )
            }
        }()

        return [
            "enable": true,
            "listen": "127.0.0.1:53553",
            "enhanced-mode": "fake-ip",
            "fake-ip-range": "198.18.0.1/16",
            "use-system-hosts": true,
            // Clash Verge / MetaCubeX: DNS follows routing rules — Google gets real IP via fake-ip-filter.
            "respect-rules": true,
            "fake-ip-filter": [
                "*.lan",
                "*.local",
                "+.local",
                "geosite:cn",
                "geosite:private",
            ] + googleFakeIPFilters + [
                "localhost.ptlogin2.qq.com",
                "+.stun.*.*",
                "lens.l.google.com",
                "+.sslip.io",
                "+.nip.io",
            ],
            "default-nameserver": ["223.5.5.5", "119.29.29.29"],
            "proxy-server-nameserver": proxyNS,
            "nameserver": nameserver,
            "fallback": fallback,
            "fallback-filter": [
                "geoip": true,
                "geoip-code": "CN",
                "ipcidr": ["240.0.0.0/4"],
            ],
            "direct-nameserver": ["system"],
            "direct-nameserver-follow-policy": true,
            "nameserver-policy": policy,
        ]
    }

    /// iOS Network Extension (~15MB RAM): no geosite/geoip in DNS — avoids loading multi-MB databases.
    static func iosDnsBlock(for preference: DnsPreference) -> [String: Any] {
        let cnNS = [
            "https://223.5.5.5/dns-query",
            "https://1.12.12.12/dns-query",
            "https://doh.pub/dns-query",
        ]
        // DoH first — bare UDP:53 often fails under NE bind ("network is unreachable").
        let foreignNS = [
            "https://8.8.8.8/dns-query",
            "https://1.1.1.1/dns-query",
            "8.8.8.8",
            "1.1.1.1",
        ]
        let (nameserver, fallback): ([String], [String]) = {
            switch preference {
            // Domestic-first: unmatched apps/domains stay on CN DNS + DIRECT routing.
            case .smart: return (cnNS, foreignNS)
            case .domestic: return (cnNS, cnNS + foreignNS)
            case .foreign: return (foreignNS, foreignNS)
            }
        }()
        // Never use "system" DNS in NE — /etc/resolv.conf does not exist; DIRECT dials fail with
        // "can't resolve ip … open /etc/resolv.conf: no such file or directory".
        let bootstrapNS = [
            "223.5.5.5",
            "119.29.29.29",
            "https://223.5.5.5/dns-query",
        ]
        // Build programmatically — duplicate keys in dictionary literals trap at runtime in Debug.
        var policy: [String: Any] = [:]
        for suffix in [
            "+.local", "+.lan",
        ] {
            policy[suffix] = bootstrapNS
        }
        for suffix in [
            "+.cn", "+.baidu.com", "+.bdstatic.com", "+.bdimg.com",
            "+.baidubce.com", "+.bcebos.com",
            "+.qq.com", "+.weixin.qq.com", "+.weixin.com",
            "+.taobao.com", "+.aliyun.com", "+.alicdn.com",
            "+.jd.com", "+.bilibili.com", "+.zhihu.com",
        ] {
            policy[suffix] = cnNS
        }
        for suffix in [
            "+.github.com",
            "+.twitter.com", "+.x.com", "+.twimg.com", "+.t.co",
            "+.facebook.com", "+.instagram.com",
            "+.telegram.org", "+.telegram-cdn.org", "+.cdn-telegram.org",
            "+.telesco.pe", "+.t.me", "+.graph.org", "+.tdesktop.com",
        ] {
            policy[suffix] = foreignNS
        }
        for suffix in googleDnsPolicy.keys {
            policy[suffix] = foreignNS
        }

        var block: [String: Any] = [:]
        block["enable"] = true
        // Bind localhost — 198.18.0.2:53 cannot bind; NE still points DNS at 198.18.0.2,
        // and TUN dns-hijack feeds queries into mihomo (BaoLianDeng pattern).
        block["listen"] = "127.0.0.1:1053"
        block["enhanced-mode"] = "fake-ip"
        block["fake-ip-range"] = "198.18.0.1/16"
        block["use-system-hosts"] = false
        block["respect-rules"] = false
        block["fake-ip-filter"] = [
            "*.lan", "*.local", "+.local", "+.lan",
            // Apple：Push/系统服务需要真实 IP；分流靠下方 IP-CIDR + DOMAIN 规则。
            "+.apple.com", "+.icloud.com", "+.cdn-apple.com", "+.mzstatic.com",
            "+.push.apple.com", "+.apple-cloudkit.com",
            // 国内站走真实 IP，避免 fake-ip→DIRECT 二次解析拖慢百度等。
            "+.baidu.com", "+.bdstatic.com", "+.bdimg.com",
            "+.baidubce.com", "+.bcebos.com",
            // Telegram 保持 fake-ip → DOMAIN/TELEGRAM 规则可命中。
            "localhost.ptlogin2.qq.com",
            "+.stun.*.*", "lens.l.google.com",
        ]
        // IP-literal DoH bootstrap — plain UDP:53 often returns "network is unreachable" under NE bind.
        block["default-nameserver"] = bootstrapNS
        block["proxy-server-nameserver"] = [
            "https://223.5.5.5/dns-query",
            "https://doh.pub/dns-query",
            "119.29.29.29",
        ]
        block["nameserver"] = nameserver
        block["fallback"] = fallback
        // Explicit geoip:false — mihomo Default() has geoip:true; YAML merge keeps it
        // unless overridden, which triggers MMDB download and hangs the NE.
        block["fallback-filter"] = [
            "geoip": false,
            "ipcidr": ["240.0.0.0/4"],
        ]
        // MATCH,DIRECT + fake-ip: re-resolve domain via DoH (not system).
        block["direct-nameserver"] = bootstrapNS
        block["direct-nameserver-follow-policy"] = true
        block["nameserver-policy"] = policy
        return block
    }
}
