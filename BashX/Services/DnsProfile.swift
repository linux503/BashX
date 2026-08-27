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
        let proxyNS = [
            "https://doh.pub/dns-query",
            "https://dns.alidns.com/dns-query",
            "223.5.5.5",
        ]

        let (nameserver, fallback, policy): ([String], [String], [String: Any]) = {
            switch preference {
            case .smart:
                return (
                    Array(cnNS.prefix(2)),
                    Array(foreignNS.prefix(2)),
                    [
                        "+.local": ["system"],
                        "+.lan": ["system"],
                        "geosite:gfw": Array(foreignNS.prefix(2)),
                        "geosite:cn,private,apple@cn,microsoft@cn": cnNS,
                    ]
                )
            case .domestic:
                return (
                    cnNS,
                    cnNS + foreignNS,
                    [
                        "+.local": ["system"],
                        "+.lan": ["system"],
                        "geosite:gfw,geolocation-!cn": foreignNS,
                        "geosite:cn,private,apple@cn,microsoft@cn": cnNS,
                    ]
                )
            case .foreign:
                return (
                    foreignNS,
                    foreignNS,
                    [
                        "+.local": ["system"],
                        "+.lan": ["system"],
                        "geosite:cn,private,apple@cn,microsoft@cn": cnNS,
                    ]
                )
            }
        }()

        return [
            "enable": true,
            "listen": "127.0.0.1:53553",
            "enhanced-mode": "fake-ip",
            "fake-ip-range": "198.18.0.1/16",
            "use-system-hosts": true,
            "respect-rules": false,
            "fake-ip-filter": [
                "*.lan",
                "*.local",
                "+.local",
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
}
