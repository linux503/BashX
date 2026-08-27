import Foundation

/// mihomo DNS presets — domestic / foreign / smart split.
enum DnsPreference: String, Codable, CaseIterable, Identifiable {
    case smart
    case domestic
    case foreign

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "智能分流"
        case .domestic: return "国内优选"
        case .foreign: return "国外优选"
        }
    }

    var subtitle: String {
        switch self {
        case .smart:
            return "国内站走阿里/腾讯 DoH，国外站自动回落 Cloudflare/Google（默认）"
        case .domestic:
            return "默认使用国内 DNS，国外域名再回落海外解析，适合日常国内浏览"
        case .foreign:
            return "默认使用 Cloudflare/Google，国内域名走专用国内 DNS，适合海外节点为主"
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
            ] + telegramFakeIPFilters + googleFakeIPFilters + [
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
        let foreignNS = [
            "https://1.1.1.1/dns-query",
            "https://8.8.8.8/dns-query",
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
            "https://223.5.5.5/dns-query",
            "https://1.12.12.12/dns-query",
        ]
        var policy: [String: Any] = [
            "+.local": bootstrapNS,
            "+.lan": bootstrapNS,
            "+.cn": cnNS,
            "+.baidu.com": cnNS,
            "+.qq.com": cnNS,
            "+.taobao.com": cnNS,
            "+.aliyun.com": cnNS,
            "+.jd.com": cnNS,
            "+.bilibili.com": cnNS,
            "+.zhihu.com": cnNS,
            "+.weixin.com": cnNS,
            "+.google.com": foreignNS,
            "+.youtube.com": foreignNS,
            "+.googleapis.com": foreignNS,
            "+.gstatic.com": foreignNS,
            "+.github.com": foreignNS,
            "+.twitter.com": foreignNS,
            "+.facebook.com": foreignNS,
            "+.instagram.com": foreignNS,
            "+.telegram.org": foreignNS,
            "+.telegram-cdn.org": foreignNS,
            "+.cdn-telegram.org": foreignNS,
            "+.telesco.pe": foreignNS,
            "+.t.me": foreignNS,
            "+.graph.org": foreignNS,
            "+.tdesktop.com": foreignNS,
        ]
        return [
            "enable": true,
            // Bind localhost — 198.18.0.2:53 cannot bind; NE still points DNS at 198.18.0.2,
            // and TUN dns-hijack feeds queries into mihomo (BaoLianDeng pattern).
            "listen": "127.0.0.1:1053",
            "enhanced-mode": "fake-ip",
            "fake-ip-range": "198.18.0.1/16",
            "use-system-hosts": false,
            "respect-rules": false,
            "fake-ip-filter": [
                "*.lan", "*.local", "+.local", "+.lan",
                "+.cn",
                // Domestic apps hit DIRECT — real IPs avoid fake-ip re-resolve.
                "+.qq.com", "+.weixin.qq.com", "+.weixin.com", "+.tenpay.com",
                "+.baidu.com", "+.alicdn.com", "+.taobao.com", "+.aliyun.com",
                "+.jd.com", "+.bilibili.com", "+.zhihu.com", "+.netease.com",
                "+.apple.com", "+.icloud.com", "+.cdn-apple.com", "+.mzstatic.com",
                "+.push.apple.com", "+.apple-cloudkit.com",
                // Telegram MUST stay in fake-ip so DOMAIN/TELEGRAM rules can match.
                "localhost.ptlogin2.qq.com",
                "+.stun.*.*", "lens.l.google.com",
            ],
            // IP-literal DoH bootstrap — plain UDP:53 often returns "network is unreachable" under NE bind.
            "default-nameserver": bootstrapNS,
            "proxy-server-nameserver": [
                "https://223.5.5.5/dns-query",
                "https://1.1.1.1/dns-query",
            ],
            "nameserver": nameserver,
            "fallback": fallback,
            // Explicit geoip:false — mihomo Default() has geoip:true; YAML merge keeps it
            // unless overridden, which triggers MMDB download and hangs the NE.
            "fallback-filter": [
                "geoip": false,
                "ipcidr": ["240.0.0.0/4"],
            ],
            // MATCH,DIRECT + fake-ip: re-resolve domain via DoH (not system).
            "direct-nameserver": bootstrapNS,
            "direct-nameserver-follow-policy": true,
            "nameserver-policy": policy,
        ]
    }
}
