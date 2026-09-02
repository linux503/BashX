import Foundation

/// Domestic CDN CIDRs bypassed at the NE layer (`excludedRoutes`) and in mihomo (`route-exclude-address`).
/// Video/image traffic never enters packetFlow → avoids jetsam on 抖音 / 淘宝 / WeChat.
///
/// Keep the list ≤ ~48 routes — iOS NE silently truncates larger tables
/// (log: 69 routes → 112.x CDN still hit packetFlow → 抖音「无网络」).
enum DomesticBypassRoutes {
    /// Broad mainland ISP aggregates. Avoid 103.x (HK/SG), 45.x/47.x (intl cloud POPs).
    static let ipv4CIDRs: [String] = {
        var seen = Set<String>()
        return rawCIDRs.filter { seen.insert($0).inserted }
    }()

    /// 48 routes — fits iOS NE excludedRoutes budget after dedupe.
    private static let rawCIDRs: [String] = [
        // Tencent / WeChat (non-/8 blocks)
        "1.12.0.0/14",
        "14.16.0.0/12",
        "43.152.0.0/13",
        "58.240.0.0/12",
        // ByteDance / 火山 / 华东
        "27.16.0.0/12",
        // Mainland /8 aggregates (抖音 CDN 112/113/36/39/42/58-61 等)
        "36.0.0.0/8",
        "39.0.0.0/8",
        "42.0.0.0/8",
        "58.0.0.0/7",
        "60.0.0.0/7",
        "101.0.0.0/8",
        "106.0.0.0/8",
        "111.0.0.0/8",
        "112.0.0.0/8",
        "113.0.0.0/8",
        "114.0.0.0/8",
        "115.0.0.0/8",
        "116.0.0.0/8",
        "117.0.0.0/8",
        "118.0.0.0/8",
        "119.0.0.0/8",
        "120.0.0.0/8",
        "121.0.0.0/8",
        "122.0.0.0/8",
        "123.0.0.0/8",
        "124.0.0.0/8",
        "125.0.0.0/8",
        "139.0.0.0/8",
        "171.16.0.0/12",
        "175.0.0.0/11",
        "180.0.0.0/8",
        "182.0.0.0/8",
        "183.0.0.0/8",
        // Do not use 49/8, 109/8, 129/8, 140/8, 157/8, 202/8, 203/8 or 210/8
        // here. They contain large non-mainland allocations; excluding them from
        // the VPN silently blackholes foreign services that share those ranges.
        "218.0.0.0/8",
        "219.0.0.0/8",
        "220.0.0.0/8",
        "221.0.0.0/8",
        "222.0.0.0/8",
        "223.0.0.0/8",
    ]

    /// Domains that use **system DNS** (not tunnel). 抖音/淘宝/微信等国内 App 完全不进 VPN。
    /// Only `tunnelDNSMatchDomains` below use 198.18.0.2 (mihomo).
    static let domesticSystemDNSDomains: [String] = douyinDomainSuffixes + [
        "weixin.qq.com", "weixin.com", "wechat.com", "qq.com", "qpic.cn", "gtimg.cn",
        "taobao.com", "tmall.com", "alipay.com", "alicdn.com", "aliyun.com",
        "goofish.com", "idlefish.com", "xianyu.com",
        "meituan.com", "meituan.net", "dianping.com", "dpfile.com", "sankuai.com",
        "kuaishou.com", "yximgs.com", "gifshow.com",
        "bilibili.com", "hdslb.com", "163.com", "netease.com",
        "amap.com", "ctrip.com", "12306.cn", "zhihu.com", "weibo.com",
        "jd.com", "baidu.com", "bdstatic.com",
    ]

    /// Only foreign/proxy domains use tunnel DNS. Everything else (含抖音) → 系统 DNS → 国内 IP 走 excludedRoutes 绕过 TUN。
    static let tunnelDNSMatchDomains: [String] = [
        "google.com", "google.com.hk", "googleapis.com", "gstatic.com", "googleusercontent.com",
        "youtube.com", "youtu.be", "ytimg.com", "gmail.com", "gvt1.com", "gvt2.com",
        "twitter.com", "x.com", "twimg.com", "t.co",
        "facebook.com", "fbcdn.net", "instagram.com", "cdninstagram.com",
        "whatsapp.com", "whatsapp.net",
        "telegram.org", "telegram-cdn.org", "cdn-telegram.org", "telesco.pe", "t.me",
        "graph.org", "tdesktop.com",
        "discord.com", "discordapp.com",
        "github.com", "githubusercontent.com", "githubassets.com",
        "cursor.sh", "cursor.com", "cursorapi.com", "anysphere.co", "anysphere.com",
        "openai.com", "chatgpt.com", "anthropic.com", "claude.ai",
        "copilot.microsoft.com", "bing.com", "live.com", "microsoft.com", "office.com",
        "office365.com", "outlook.com", "azure.com",
        "netflix.com", "nflxvideo.net", "nflximg.net",
        "tiktok.com", "tiktokv.com", "tiktokcdn.com", "byteoversea.com", "byteoversea.net",
        "isnssdk.com", "sgsnssdk.com", "ibyteimg.com", "ibytedtos.com",
        "binance.com", "binance.me", "bnbstatic.com", "binanceapi.com",
        "htx.com", "huobi.com", "huobi.pro",
        "reddit.com", "redd.it", "spotify.com", "twitch.tv",
        "steamcommunity.com", "steampowered.com",
        "cloudfront.net", "amazonaws.com",
        "wikipedia.org", "dropbox.com",
    ]

    /// Douyin / ByteDance domain suffixes — real-IP DNS + DIRECT (not fake-ip).
    static let douyinDomainSuffixes: [String] = [
        "zjcdn.com", "bytecdn.com", "douyinstatic.com", "idouyinvod.com",
        "ixiguavideo.com", "bytednsdoc.com", "toutiaocloud.cn",
        "douyinvod.com", "douyinpic.com", "douyinliving.com",
        "douyin.com", "douyincdn.com", "bytedance.com", "bytedance.net",
        "zijieapi.com", "ecombdapi.com", "amemv.com", "byteimg.com",
        "bytescm.com", "byteacctimg.com", "pstatp.com", "snssdk.com",
        "ixigua.com", "toutiao.com", "toutiaovod.com", "toutiaostatic.com",
        "huoshan.com", "huoshanstatic.com", "volces.com", "volccdn.com",
        "ulikecam.com", "faceu.mobi", "bytedanceapi.com",
        "aweme.com", "aweme.cn", "iesdouyin.com", "douyinpay.com",
        "oceanengine.com", "csjplatform.com", "pglstatp-toutiao.com",
    ]

    /// mihomo IP-CIDR rules — Mac only; iOS relies on NE excludedRoutes (rule bloat costs NE RAM).
    static var ipDirectRules: [String] {
        #if os(iOS)
        return []
        #else
        return ipv4CIDRs.map { "IP-CIDR,\($0),DIRECT,no-resolve" }
        #endif
    }

    /// Mainland CDN IPv6 — Douyin Happy-Eyeballs prefers these; must stay off TUN
    /// (gVisor DIRECT to 2409:: times out → jetsam). Keep APNs 2403:300 out of this list.
    static let ipv6CIDRs: [(address: String, prefix: Int)] = [
        ("2408::", 13),
        ("2409::", 16),
        ("240a::", 16),
        ("240e::", 16),
        ("2400:3200::", 32),
        ("2400:da00::", 32),
    ]

    /// Host substrings for mihomo connection cleanup under memory pressure.
    static let domesticVideoHostMarkers: [String] = [
        "douyin", "amemv", "snssdk", "bytedance", "byteimg", "bytescm",
        "zjcdn", "bytecdn", "ixigua", "toutiao", "huoshan", "volces", "pstatp",
    ]

    /// Convert CIDR → NEIPv4Route network + mask (for PacketTunnel excludedRoutes).
    static func neIPv4Routes() -> [(address: String, mask: String)] {
        ipv4CIDRs.compactMap { cidr in
            let parts = cidr.split(separator: "/")
            guard parts.count == 2, let prefix = Int(parts[1]), prefix >= 0, prefix <= 32 else { return nil }
            let maskBits = prefix == 0 ? UInt32(0) : (UInt32(0xFFFFFFFF) << (32 - prefix))
            let mask = String(format: "%d.%d.%d.%d",
                              (maskBits >> 24) & 0xff, (maskBits >> 16) & 0xff,
                              (maskBits >> 8) & 0xff, maskBits & 0xff)
            return (String(parts[0]), mask)
        }
    }
}
