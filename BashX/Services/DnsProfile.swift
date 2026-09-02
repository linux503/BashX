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

    /// Compact label for tight home quick-control chips (avoids segmented squash).
    func shortTitle(lang: AppLanguage) -> String {
        switch self {
        case .smart: return L10n.t("dns.smart.short", lang)
        case .domestic: return L10n.t("dns.domestic.short", lang)
        case .foreign: return L10n.t("dns.foreign.short", lang)
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
        "+.tx.me",
        "+.graph.org",
        "+.tdesktop.com",
        "+.telegra.ph",
        // WhatsApp intentionally NOT listed: Mac Desktop + system HTTP proxy breaks
        // WebSocket QR (`/ws/chat`). fake-ip + TUN keeps domain mapping so PROCESS/DOMAIN
        // rules match; pair with SystemProxy bypass for *.whatsapp.* / *.fbcdn.net.
    ]

    /// Cursor / Anysphere — real IP (fake-ip breaks long-lived agent WebSockets).
    private static let cursorFakeIPFilters: [String] = [
        "+.cursor.sh",
        "+.cursor.com",
        "+.cursorapi.com",
        "+.cursor-cdn.com",
        "+.cursorvm.com",
        "+.anysphere.co",
        "+.anysphere.com",
        "+.anysphere.tech",
    ]

    /// Binance — real IP (fake-ip + WS/行情长连接易卡顿、闪断重连).
    private static let binanceFakeIPFilters: [String] = [
        "+.binance.com",
        "+.binance.me",
        "+.binance.us",
        "+.binance.cc",
        "+.binance.co",
        "+.binance.net",
        "+.binance.org",
        "+.binance.info",
        "+.binance.vision",
        "+.binance.cloud",
        "+.binance.charity",
        "+.binancezh.com",
        "+.binancezh.pro",
        "+.binancezh.net",
        "+.binanceapi.com",
        "+.binancefuture.com",
        "+.binancecnt.com",
        "+.binancecorp.com",
        "+.binancecnl.com",
        "+.binance-cdn.com",
        "+.binanceavg.com",
        "+.bnbstatic.com",
        "+.nftstatic.com",
        "+.bnappzh.com",
        "+.bnappzh.co",
        "+.bntrace.com",
        "+.appsbinance.com",
        "+.saasexch.com",
        "+.saasexch.cc",
        "+.ficus.cc",
    ]

    // TikTok intentionally NOT in fake-ip-filter: real-IP + sniffer-off → MATCH,DIRECT.

    /// Huobi / HTX — real IP (fake-ip + WS/行情长连接易卡顿，同币安).
    private static let huobiFakeIPFilters: [String] = [
        "+.htx.com",
        "+.huobi.com",
        "+.huobi.pro",
        "+.huobi.co",
        "+.huobi.me",
        "+.huobi.sc",
        "+.huobipro.com",
        "+.huobigroup.com",
        "+.huobiapi.com",
        "+.huobiasia.vip",
        "+.hbfile.net",
        "+.hbg.com",
        "+.huobicdn.com",
    ]

    private static let googleFakeIPFilters: [String] = [
        // Do NOT use geosite:google / geosite:youtube here — those tags include
        // googlevideo CDN hosts. Real CDN IPs + MATCH,DIRECT = TUN-only YouTube die
        // while Telegram still works (DC IP-CIDR). Keep Search on real IP only.
        "+.google.com",
        "+.googleapis.com",
        "+.gstatic.com",
        "+.googleusercontent.com",
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
        // `#PROXY` forces DoH through the tunnel — bare 1.1.1.1/8.8.8.8 otherwise hit
        // MATCH,DIRECT and time out in CN (breaks WhatsApp nameserver-policy).
        // Prefer domain DoH: some exits DPI 1.1.1.1 IP but allow cloudflare-dns.com SNI.
        let foreignNS = [
            "https://cloudflare-dns.com/dns-query#PROXY",
            "https://1.1.1.1/dns-query#PROXY",
            "https://8.8.8.8/dns-query#PROXY",
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
            // WhatsApp chat (g.whatsapp.net) is poisoned by CN DNS → Twitter IPs → TLS die.
            "+.whatsapp.com": telegramNS,
            "+.whatsapp.net": telegramNS,
            "+.whatsapp.biz": telegramNS,
            "+.facebook.com": telegramNS,
            "+.fbcdn.net": telegramNS,
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
                        "+.tv": Array(foreignNS.prefix(2)),
                        "+.twitch.tv": Array(foreignNS.prefix(2)),
                        "+.ttvnw.net": Array(foreignNS.prefix(2)),
                        "+.jtvnw.net": Array(foreignNS.prefix(2)),
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
                        "+.tv": foreignNS,
                        "+.twitch.tv": foreignNS,
                        "+.ttvnw.net": foreignNS,
                        "+.jtvnw.net": foreignNS,
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
                        "+.tv": foreignNS,
                        "+.twitch.tv": foreignNS,
                        "+.ttvnw.net": foreignNS,
                        "+.jtvnw.net": foreignNS,
                    ]) { _, new in new }
                )
            }
        }()

        // Mac: keep TikTok on fake-ip too (same bare-IP / MATCH,DIRECT trap as iOS).
        let fakeIPFilter: [String] =
            ["*.lan", "*.local", "+.local", "geosite:cn", "geosite:private"]
            + googleFakeIPFilters
            + telegramFakeIPFilters
            + cursorFakeIPFilters
            + binanceFakeIPFilters
            + huobiFakeIPFilters
            + [
                "localhost.ptlogin2.qq.com",
                "+.stun.*.*",
                "lens.l.google.com",
                "+.sslip.io",
                "+.nip.io",
            ]

        return [
            "enable": true,
            "ipv6": false, // WhatsApp Mac Happy-Eyeballs otherwise prefers Meta AAAA:5222 (often blackholed)
            "listen": "127.0.0.1:53553",
            "enhanced-mode": "fake-ip",
            "fake-ip-range": "198.18.0.1/16",
            "use-system-hosts": true,
            // Clash Verge / MetaCubeX: DNS follows routing rules — Google gets real IP via fake-ip-filter.
            "respect-rules": true,
            "fake-ip-filter": fakeIPFilter,
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
        // UDP only — DoH :443 through gVisor/TUN timed out → douyinvod/amemv "couldn't find ip".
        let cnNS = ["223.5.5.5", "119.29.29.29", "1.12.12.12"]
        let foreignNS = ["8.8.8.8", "1.1.1.1", "9.9.9.9"]
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
        let bootstrapNS = ["223.5.5.5", "119.29.29.29", "1.12.12.12"]
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
            "+.qq.com", "+.weixin.qq.com", "+.weixin.com", "+.wechat.com",
            "+.qpic.cn", "+.qlogo.cn", "+.gtimg.cn", "+.gtimg.com",
            "+.servicewechat.com", "+.tenpay.com",
            "+.taobao.com", "+.tmall.com", "+.aliyun.com", "+.alicdn.com",
            "+.goofish.com", "+.idlefish.com", "+.jd.com",
            "+.bilibili.com", "+.zhihu.com",
        ] {
            policy[suffix] = cnNS
        }
        for suffix in [
            "+.github.com",
            "+.twitter.com", "+.x.com", "+.twimg.com", "+.t.co",
            "+.facebook.com", "+.instagram.com", "+.fbcdn.net",
            "+.whatsapp.com", "+.whatsapp.net", "+.whatsapp.biz",
            "+.telegram.org", "+.telegram-cdn.org", "+.cdn-telegram.org",
            "+.telesco.pe", "+.t.me", "+.graph.org", "+.tdesktop.com",
            "+.binance.com", "+.binance.me", "+.binancezh.com", "+.bnbstatic.com",
            "+.saasexch.com", "+.saasexch.cc", "+.bnappzh.com",
            "+.binance.vision", "+.binanceapi.com", "+.binancecnt.com",
            "+.binancecnl.com", "+.binance-cdn.com", "+.ficus.cc", "+.nftstatic.com",
            "+.htx.com", "+.huobi.com", "+.huobi.pro", "+.huobipro.com",
            "+.hbfile.net", "+.huobicdn.com", "+.huobiasia.vip",
            "+.tiktok.com", "+.tiktok-row.net", "+.tiktokv.com", "+.tiktokv.us", "+.tiktokv.eu",
            "+.tiktokcdn.com", "+.tiktokcdn-us.com", "+.tiktokcdn-eu.com", "+.tiktokcdn-in.com",
            "+.byteoversea.com", "+.byteoversea.net", "+.musical.ly", "+.ttlivecdn.com",
            "+.isnssdk.com", "+.sgsnssdk.com", "+.ibyteimg.com", "+.ibytedtos.com",
            // snssdk.com = 抖音 → cnNS（下方）
            "+.muscdn.com", "+.ipstatp.com", "+.sgpstatp.com", "+.goofy.app", "+.bytegecko.com",
            "+.bytegecko-i18n.com", "+.byteintlapi.com", "+.byteintl.net",
            "+.tv", "+.twitch.tv", "+.ttvnw.net", "+.jtvnw.net", "+.twitchcdn.net",
        ] {
            policy[suffix] = foreignNS
        }
        for suffix in DomesticBypassRoutes.douyinDomainSuffixes.map({ "+.\($0)" }) {
            policy[suffix] = cnNS
        }
        for suffix in googleDnsPolicy.keys {
            policy[suffix] = foreignNS
        }

        var block: [String: Any] = [:]
        block["enable"] = true
        // Never answer AAAA on iOS — only Telegram DC IPv6 is routed into TUN;
        // other AAAA would bypass the tunnel and hang Happy-Eyeballs.
        block["ipv6"] = false
        // Bind localhost — mihomo internal DNS (proxy bootstrap only; NE uses system DNS).
        block["listen"] = "127.0.0.1:1053"
        // redir-host: 真实 IP，不产生 198.18.x fake-ip（抖音 CDN 因此可 excludedRoutes 绕过 TUN）。
        block["enhanced-mode"] = "redir-host"
        block["use-system-hosts"] = false
        block["respect-rules"] = true
        // IP-literal DoH bootstrap — plain UDP:53 often returns "network is unreachable" under NE bind.
        block["default-nameserver"] = bootstrapNS
        block["proxy-server-nameserver"] = ["223.5.5.5", "119.29.29.29", "1.12.12.12"]
        block["nameserver"] = nameserver
        block["fallback"] = fallback
        // Explicit geoip:false — mihomo Default() has geoip:true; YAML merge keeps it
        // unless overridden, which triggers MMDB download and hangs the NE.
        block["fallback-filter"] = [
            "geoip": false,
            "ipcidr": ["240.0.0.0/4"],
        ]
        // MATCH,PROXY + fake-ip: foreign DNS via proxy path; DIRECT re-resolve via DoH.
        block["direct-nameserver"] = bootstrapNS
        block["direct-nameserver-follow-policy"] = true
        block["nameserver-policy"] = policy
        return block
    }
}
