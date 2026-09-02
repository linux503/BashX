import Foundation

/// Domestic CDN CIDRs bypassed at the NE layer (`excludedRoutes`) and in mihomo (`route-exclude-address`).
/// Video/image traffic never enters packetFlow → avoids jetsam on 抖音 / 淘宝 / WeChat.
enum DomesticBypassRoutes {
    static let ipv4CIDRs: [String] = [
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
        // 抖音 / 头条 / 火山引擎 mainland CDN (no byteoversea — TikTok intl stays in-tunnel)
        "49.51.0.0/16", "58.33.0.0/16", "59.80.0.0/15",
        "101.89.0.0/16", "106.38.0.0/16", "106.39.0.0/16", "106.75.0.0/16",
        "111.202.0.0/15", "111.206.0.0/16", "116.63.0.0/16",
        "117.50.0.0/16", "117.136.0.0/16", "118.195.0.0/16",
        "120.78.0.0/16", "121.199.0.0/16", "122.14.0.0/16",
        "123.57.0.0/16", "123.125.0.0/16",
        "124.70.0.0/16", "125.122.0.0/16",
        "139.9.0.0/16", "139.155.0.0/16",
        "150.109.0.0/16", "157.148.0.0/16",
        "180.97.0.0/16", "180.101.180.0/24", "180.149.0.0/16",
        "182.61.0.0/16",
        "203.107.0.0/16", "210.22.0.0/16", "218.75.0.0/16",
        "220.181.0.0/16", "220.243.0.0/16",
        "221.181.0.0/16", "221.194.0.0/16",
        "223.109.0.0/16", "223.111.0.0/16",
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
    ]

    /// mihomo IP-CIDR rules for bare-IP dials (video CDN often skips SNI).
    static var ipDirectRules: [String] {
        ipv4CIDRs.map { "IP-CIDR,\($0),DIRECT,no-resolve" }
    }

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
