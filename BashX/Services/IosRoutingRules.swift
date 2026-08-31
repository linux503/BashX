import Foundation

/// Shared Mac/iOS routing aligned with LingJingMaster/Shadowrocket-Rules priority.
/// https://github.com/LingJingMaster/Shadowrocket-Rules
///
/// Order (top → bottom):
/// 0. (Mac) PROCESS-NAME app routing from base — prepended first
/// 1. WeChat local + LAN
/// 2. Google / AI / Telegram / GitHub / YouTube  → strategy groups
/// 3. Apple (push optional PROXY; rest APPLE/DIRECT)
/// 4. 国内服务 blanket DIRECT（含 B 站/抖音 — 勿默认进策略组）
/// 5. GeoIP（Mac）/ 外国 TLD；漏网之鱼 → MATCH,PROXY（ACL4SSR）
enum IosRoutingRules {
    /// Highest-priority APNs rules — prepended on iOS so apple.com DIRECT/APPLE cannot steal push.
    static let apnsPriorityRules: [String] = [
        "DOMAIN-SUFFIX,push.apple.com,APNS",
        "DOMAIN,gateway.push.apple.com,APNS",
        "DOMAIN,api.push.apple.com,APNS",
        "DOMAIN,sandbox.push.apple.com,APNS",
        "DOMAIN-SUFFIX,push-apple.com.akadns.net,APNS",
        "DOMAIN-KEYWORD,push.apple,APNS",
        "IP-CIDR,17.249.0.0/16,APNS,no-resolve",
        "IP-CIDR,17.252.0.0/16,APNS,no-resolve",
        "IP-CIDR,17.57.144.0/22,APNS,no-resolve",
        "IP-CIDR,17.188.128.0/18,APNS,no-resolve",
        "IP-CIDR,17.188.20.0/23,APNS,no-resolve",
        // Apple APNs IPv6 — without TUN capture, Happy-Eyeballs stalls for seconds on blocked v6.
        "IP-CIDR6,2620:149:a44::/48,APNS,no-resolve",
        "IP-CIDR6,2403:300:a42::/48,APNS,no-resolve",
        "IP-CIDR6,2403:300:a51::/48,APNS,no-resolve",
        "IP-CIDR6,2a01:b740:a42::/48,APNS,no-resolve",
    ]

    /// Full rule list written into mihomo (Packet Tunnel on iOS / local core on Mac).
    static func build(fromBase base: [String]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(512)

        #if os(macOS)
        // App-level routing must beat domain rules.
        for raw in base {
            let t = raw.trimmingCharacters(in: .whitespaces)
            let u = t.uppercased()
            if u.hasPrefix("PROCESS-NAME,") { out.append(t) }
        }
        #endif

        // WeChat CDN/upload first — bare-IP dials must not fall through to MATCH,PROXY.
        out.append(contentsOf: IosDirectDomains.wechatPriorityRules)
        // TikTok 必须在抖音 DIRECT 之前（共用 byteoversea / bytedance 基础设施）.
        out.append(contentsOf: IosDirectDomains.tiktokPriorityRules)
        // 淘宝 / 闲鱼 / 国内电商 — goofish 等须在 MATCH,PROXY 之前；也盖过 adblock 误伤.
        out.append(contentsOf: IosDirectDomains.ecommercePriorityRules)
        out.append(contentsOf: IosDirectDomains.xiaohongshuPriorityRules)
        out.append(contentsOf: IosDirectDomains.bankPriorityRules)
        out.append(contentsOf: IosDirectDomains.douyinPriorityRules)
        out.append(contentsOf: bootstrap)
        out.append(contentsOf: proxyFirst)   // must precede China blanket
        out.append(contentsOf: apple)
        out.append(contentsOf: chinaDirect) // 国内一律直连
        out.append(contentsOf: chinaIP)

        // Keep useful non-MATCH lines from smart rules (adblock / extras),
        // but drop geo/MATCH duplicates — tail injects industry-standard GEOIP + 漏网之鱼.
        for raw in base {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { continue }
            if RoutingGeoRules.shouldSkipBaseRule(t) { continue }
            #if os(macOS)
            if t.uppercased().hasPrefix("PROCESS-NAME,") || t.uppercased().hasPrefix("PROCESS-PATH,") {
                continue // already prepended
            }
            #else
            if t.uppercased().hasPrefix("PROCESS-NAME,") || t.uppercased().hasPrefix("PROCESS-PATH,") {
                continue
            }
            if t.uppercased().hasPrefix("GEOSITE,") || t.uppercased().hasPrefix("GEOIP,") {
                continue
            }
            #endif
            // WeChat / 阿里 HTTPDNS / 抖音核心 API: never REJECT.
            let u = t.uppercased()
            if (u.contains("DNS.WEIXIN.QQ.COM") || u.contains("HTTPDNS.ALICDN.COM") || u.contains("HTTPDNS.BAIDU.COM")
                || u.contains("I.SNSSDK.COM") || u.contains("IS.SNSSDK.COM") || u.contains("LF.SNSSDK.COM")
                || u.contains("BDS.SNSSDK.COM"))
                && u.contains("REJECT") {
                let parts = t.split(separator: ",").map(String.init)
                if parts.count >= 2 {
                    out.append("\(parts[0]),\(parts[1]),DIRECT")
                }
                continue
            }
            out.append(t)
        }

        out.append(contentsOf: RoutingGeoRules.tail(useGeoDB: GeoDataBootstrap.isReady()))
        return GeoSiteRules.sanitize(out)
    }

    // MARK: - 1. Bootstrap (WeChat local + LAN)

    private static let bootstrap: [String] = [
        // Shadowrocket: localhost.weixin.qq.com → 127.0.0.1 + DIRECT
        "DOMAIN,localhost.weixin.qq.com,DIRECT",
        "DOMAIN-SUFFIX,local,DIRECT",
        "DOMAIN-SUFFIX,localhost,DIRECT",
        "DOMAIN-SUFFIX,lan,DIRECT",
        "DOMAIN-SUFFIX,home.arpa,DIRECT",
        "DOMAIN-SUFFIX,in-addr.arpa,DIRECT",
        "DOMAIN-SUFFIX,ip6.arpa,DIRECT",
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,169.254.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,224.0.0.0/4,DIRECT,no-resolve",
        "DOMAIN,captive.apple.com,DIRECT",
        "DOMAIN,connectivitycheck.gstatic.com,DIRECT",
        // 腾讯云 IM / 豆包 — Shadowrocket 前置国内
        "DOMAIN,shortconn.im.qcloud.com,DIRECT",
        "DOMAIN-SUFFIX,doubao.com,DIRECT",
    ]

    // MARK: - 2. Proxy-first (before China blanket)

    private static let proxyFirst: [String] = [
        // 🔍 谷歌 — Shadowrocket 默认日本；iOS 用 GOOGLE 组
        "DOMAIN-SUFFIX,google.com,GOOGLE",
        "DOMAIN-SUFFIX,google.com.hk,GOOGLE",
        "DOMAIN-SUFFIX,google.cn,GOOGLE",
        "DOMAIN-SUFFIX,googleapis.com,GOOGLE",
        "DOMAIN-SUFFIX,googleapis.cn,GOOGLE",
        "DOMAIN-SUFFIX,gstatic.com,GOOGLE",
        "DOMAIN-SUFFIX,gstatic.cn,GOOGLE",
        "DOMAIN-SUFFIX,googleusercontent.com,GOOGLE",
        "DOMAIN-SUFFIX,googlesyndication.com,GOOGLE",
        "DOMAIN-SUFFIX,googlevideo.com,GOOGLE",
        "DOMAIN-SUFFIX,gmail.com,GOOGLE",
        "DOMAIN-SUFFIX,android.com,GOOGLE",
        "DOMAIN-SUFFIX,gvt1.com,GOOGLE",
        "DOMAIN-SUFFIX,gvt2.com,GOOGLE",
        "DOMAIN-SUFFIX,withgoogle.com,GOOGLE",
        "DOMAIN-SUFFIX,translate.goog,GOOGLE",
        "DOMAIN-KEYWORD,google,GOOGLE",
        // 📹 YouTube
        "DOMAIN-SUFFIX,youtube.com,GOOGLE",
        "DOMAIN-SUFFIX,youtu.be,GOOGLE",
        "DOMAIN-SUFFIX,ytimg.com,GOOGLE",
        "DOMAIN-SUFFIX,ggpht.com,GOOGLE",
        "DOMAIN-KEYWORD,youtube,GOOGLE",
        // 🤖 AI
        "DOMAIN-SUFFIX,openai.com,OPENAI",
        "DOMAIN-SUFFIX,chatgpt.com,OPENAI",
        "DOMAIN-SUFFIX,ai.com,AI",
        "DOMAIN-SUFFIX,anthropic.com,ANTHROPIC",
        "DOMAIN-SUFFIX,claude.ai,ANTHROPIC",
        "DOMAIN,copilot.microsoft.com,COPILOT",
        "DOMAIN-SUFFIX,githubcopilot.com,COPILOT",
        "DOMAIN-SUFFIX,cursor.com,CURSOR",
        "DOMAIN-SUFFIX,cursor.sh,CURSOR",
        "DOMAIN-SUFFIX,cursorapi.com,CURSOR",
        "DOMAIN-SUFFIX,cursor-cdn.com,CURSOR",
        "DOMAIN-SUFFIX,cursorvm.com,CURSOR",
        "DOMAIN-SUFFIX,anysphere.co,CURSOR",
        "DOMAIN-SUFFIX,anysphere.com,CURSOR",
        "DOMAIN-SUFFIX,anysphere.tech,CURSOR",
        "DOMAIN-KEYWORD,cursor.sh,CURSOR",
        "DOMAIN-KEYWORD,gcpp.cursor,CURSOR",
        // 📲 电报
        "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
        "DOMAIN-SUFFIX,cdn-telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telesco.pe,TELEGRAM",
        "DOMAIN-SUFFIX,t.me,TELEGRAM",
        "DOMAIN-SUFFIX,graph.org,TELEGRAM",
        "DOMAIN-SUFFIX,tdesktop.com,TELEGRAM",
        "DOMAIN-SUFFIX,telegra.ph,TELEGRAM",
        "DOMAIN-KEYWORD,telegram,TELEGRAM",
        "IP-CIDR,149.154.160.0/20,TELEGRAM,no-resolve",
        "IP-CIDR,91.108.0.0/16,TELEGRAM,no-resolve",
        "IP-CIDR,91.105.192.0/23,TELEGRAM,no-resolve",
        "IP-CIDR,185.76.151.0/24,TELEGRAM,no-resolve",
        "IP-CIDR,95.161.64.0/20,TELEGRAM,no-resolve",
        "IP-CIDR6,2001:67c:4e8::/48,TELEGRAM,no-resolve",
        "IP-CIDR6,2001:b28:f23c::/48,TELEGRAM,no-resolve",
        "IP-CIDR6,2001:b28:f23d::/48,TELEGRAM,no-resolve",
        "IP-CIDR6,2001:b28:f23f::/48,TELEGRAM,no-resolve",
        // 🐱 代码托管 / Wiki（须在 .org 直连之前）
        "DOMAIN-SUFFIX,github.com,PROXY",
        "DOMAIN-SUFFIX,githubusercontent.com,PROXY",
        "DOMAIN-SUFFIX,githubassets.com,PROXY",
        "DOMAIN-SUFFIX,gitlab.com,PROXY",
        "DOMAIN-SUFFIX,wikipedia.org,PROXY",
        "DOMAIN-SUFFIX,wikimedia.org,PROXY",
        "DOMAIN-SUFFIX,wikidata.org,PROXY",
        // Social
        "DOMAIN-SUFFIX,twitter.com,TWITTER",
        "DOMAIN-SUFFIX,x.com,TWITTER",
        "DOMAIN-SUFFIX,twimg.com,TWITTER",
        "DOMAIN-SUFFIX,t.co,TWITTER",
        "DOMAIN-SUFFIX,facebook.com,PROXY",
        "DOMAIN-SUFFIX,fbcdn.net,PROXY",
        "DOMAIN-SUFFIX,instagram.com,PROXY",
        "DOMAIN-SUFFIX,cdninstagram.com,PROXY",
        "DOMAIN-SUFFIX,whatsapp.com,WHATSAPP",
        "DOMAIN-SUFFIX,whatsapp.net,WHATSAPP",
        "DOMAIN-SUFFIX,discord.com,PROXY",
        "DOMAIN-SUFFIX,discordapp.com,PROXY",
        "DOMAIN-SUFFIX,reddit.com,PROXY",
        "DOMAIN-SUFFIX,netflix.com,NETFLIX",
        "DOMAIN-SUFFIX,spotify.com,PROXY",
        "DOMAIN-SUFFIX,tiktok.com,TIKTOK",
        "DOMAIN-SUFFIX,tiktokv.com,TIKTOK",
        "DOMAIN-SUFFIX,tiktokcdn.com,TIKTOK",
        "DOMAIN-SUFFIX,tiktokcdn-us.com,TIKTOK",
        "DOMAIN-SUFFIX,ttlivecdn.com,TIKTOK",
        "DOMAIN-SUFFIX,musical.ly,TIKTOK",
        "DOMAIN-SUFFIX,byteoversea.com,TIKTOK",
        "DOMAIN-SUFFIX,ibyteimg.com,TIKTOK",
        "DOMAIN-SUFFIX,ibytedtos.com,TIKTOK",
        "DOMAIN-KEYWORD,tiktok,TIKTOK",
        "DOMAIN-KEYWORD,byteoversea,TIKTOK",
        "DOMAIN-SUFFIX,cloudflare.com,PROXY",
        // 📺 .tv TLD + 流媒体（必须在 QUIC REJECT 之前）
        "DOMAIN-SUFFIX,tv,PROXY",
        "DOMAIN-SUFFIX,twitch.tv,PROXY",
        "DOMAIN-SUFFIX,twitchcdn.net,PROXY",
        "DOMAIN-SUFFIX,ttvnw.net,PROXY",
        "DOMAIN-SUFFIX,jtvnw.net,PROXY",
        "DOMAIN-SUFFIX,pluto.tv,PROXY",
        // QUIC→TCP（仅 CDN 域名，勿用泛 .tv 以免误伤）
        "AND,((DOMAIN-SUFFIX,ttvnw.net),(NETWORK,UDP),(DST-PORT,443)),REJECT",
        "AND,((DOMAIN-SUFFIX,jtvnw.net),(NETWORK,UDP),(DST-PORT,443)),REJECT",
        // 🍎 苹果推送 — 专用 APNS 组（见 apnsPriorityRules；此处保留一份供 Mac/非 iOS 预置）
        "DOMAIN-SUFFIX,push.apple.com,APNS",
        "DOMAIN,gateway.push.apple.com,APNS",
        "DOMAIN,api.push.apple.com,APNS",
        "DOMAIN,sandbox.push.apple.com,APNS",
        "DOMAIN-SUFFIX,push-apple.com.akadns.net,APNS",
        "DOMAIN-KEYWORD,push.apple,APNS",
        // Apple APNs IPv4 (support.apple.com/102266) — must NOT fall to DIRECT
        "IP-CIDR,17.249.0.0/16,APNS,no-resolve",
        "IP-CIDR,17.252.0.0/16,APNS,no-resolve",
        "IP-CIDR,17.57.144.0/22,APNS,no-resolve",
        "IP-CIDR,17.188.128.0/18,APNS,no-resolve",
        "IP-CIDR,17.188.20.0/23,APNS,no-resolve",
        "IP-CIDR6,2620:149:a44::/48,APNS,no-resolve",
        "IP-CIDR6,2403:300:a42::/48,APNS,no-resolve",
        "IP-CIDR6,2403:300:a51::/48,APNS,no-resolve",
        "IP-CIDR6,2a01:b740:a42::/48,APNS,no-resolve",
    ]

    // MARK: - 3. Apple DIRECT (non-push)

    private static let apple: [String] = [
        "DOMAIN-SUFFIX,apple.com,APPLE",
        "DOMAIN-SUFFIX,icloud.com,APPLE",
        "DOMAIN-SUFFIX,icloud-content.com,APPLE",
        "DOMAIN-SUFFIX,cdn-apple.com,APPLE",
        "DOMAIN-SUFFIX,mzstatic.com,APPLE",
        "DOMAIN-SUFFIX,apple-cloudkit.com,APPLE",
        "DOMAIN-SUFFIX,apple-mapkit.com,APPLE",
        "DOMAIN-SUFFIX,me.com,APPLE",
        "DOMAIN-SUFFIX,ess.apple.com,APPLE",
        "DOMAIN-SUFFIX,gs.apple.com,APPLE",
        "DOMAIN,gateway.icloud.com,APPLE",
        "DOMAIN,gsa.apple.com,APPLE",
        // Non-APNs Apple media/CDN — keep physical path; do NOT include 17.249 (APNs).
        "IP-CIDR,17.248.0.0/16,DIRECT,no-resolve",
        // System DoH must not hit GOOGLE health-check
        "DOMAIN,dns.google.com,DIRECT",
        "DOMAIN-SUFFIX,dns.google,DIRECT",
    ]

    // MARK: - 4. 国内服务 DIRECT（核心：国内 App 不走节点）

    private static let chinaDirect: [String] = [
        // blackmatrix7 China.list 精简核心
        "DOMAIN-SUFFIX,cn,DIRECT",
        "DOMAIN-KEYWORD,alicdn,DIRECT",
        "DOMAIN-KEYWORD,alipay,DIRECT",
        "DOMAIN-KEYWORD,aliyun,DIRECT",
        "DOMAIN-KEYWORD,baidu,DIRECT",
        "DOMAIN-KEYWORD,taobao,DIRECT",
        "DOMAIN-KEYWORD,.tmall.com,DIRECT",

        // 微信 / QQ / 腾讯（发图 CDN）
        "DOMAIN-SUFFIX,qq.com,DIRECT",
        "DOMAIN-SUFFIX,weixin.qq.com,DIRECT",
        "DOMAIN-SUFFIX,weixin.com,DIRECT",
        "DOMAIN-SUFFIX,wechat.com,DIRECT",
        "DOMAIN-SUFFIX,servicewechat.com,DIRECT",
        "DOMAIN-SUFFIX,tenpay.com,DIRECT",
        "DOMAIN-SUFFIX,qpic.cn,DIRECT",
        "DOMAIN-SUFFIX,qlogo.cn,DIRECT",
        "DOMAIN-SUFFIX,gtimg.cn,DIRECT",
        "DOMAIN-SUFFIX,gtimg.com,DIRECT",
        "DOMAIN-SUFFIX,idqqimg.com,DIRECT",
        "DOMAIN-SUFFIX,myapp.com,DIRECT",
        "DOMAIN-SUFFIX,tencent.com,DIRECT",
        "DOMAIN-SUFFIX,tencent-cloud.net,DIRECT",
        "DOMAIN-SUFFIX,tencentcs.com,DIRECT",
        "DOMAIN-SUFFIX,qcloud.com,DIRECT",
        "DOMAIN-KEYWORD,weixin,DIRECT",
        "DOMAIN-KEYWORD,qpic,DIRECT",

        // 阿里系（含闲鱼 goofish / HTTPDNS）
        "DOMAIN,httpdns.alicdn.com,DIRECT",
        "DOMAIN-SUFFIX,httpdns.alicdn.com,DIRECT",
        "DOMAIN-SUFFIX,alibaba.com,DIRECT",
        "DOMAIN-SUFFIX,alibaba-inc.com,DIRECT",
        "DOMAIN-SUFFIX,alicdn.com,DIRECT",
        "DOMAIN-SUFFIX,aliyuncs.com,DIRECT",
        "DOMAIN-SUFFIX,aliyun.com,DIRECT",
        "DOMAIN-SUFFIX,taobao.com,DIRECT",
        "DOMAIN-SUFFIX,tmall.com,DIRECT",
        "DOMAIN-SUFFIX,tmall.hk,DIRECT",
        "DOMAIN-SUFFIX,goofish.com,DIRECT",
        "DOMAIN-SUFFIX,goofish.pro,DIRECT",
        "DOMAIN-SUFFIX,idlefish.com,DIRECT",
        "DOMAIN-SUFFIX,xianyu.com,DIRECT",
        "DOMAIN-SUFFIX,tb.cn,DIRECT",
        "DOMAIN-SUFFIX,alipay.com,DIRECT",
        "DOMAIN-SUFFIX,alipayobjects.com,DIRECT",
        "DOMAIN-SUFFIX,cainiao.com,DIRECT",
        "DOMAIN-SUFFIX,fliggy.com,DIRECT",
        "DOMAIN-SUFFIX,kaola.com,DIRECT",
        "DOMAIN-SUFFIX,ele.me,DIRECT",
        "DOMAIN-SUFFIX,elemecdn.com,DIRECT",
        "DOMAIN-SUFFIX,amap.com,DIRECT",
        "DOMAIN-SUFFIX,autonavi.com,DIRECT",
        "DOMAIN-SUFFIX,dingtalk.com,DIRECT",
        "DOMAIN-SUFFIX,laiwang.com,DIRECT",
        "DOMAIN-KEYWORD,goofish,DIRECT",
        "DOMAIN-KEYWORD,xianyu,DIRECT",

        // 百度 / 字节 / 网易 / 京东 / 美团 / 出行
        "DOMAIN-SUFFIX,baidu.com,DIRECT",
        "DOMAIN-SUFFIX,bdstatic.com,DIRECT",
        "DOMAIN-SUFFIX,bdimg.com,DIRECT",
        "DOMAIN-SUFFIX,baidubce.com,DIRECT",
        "DOMAIN-SUFFIX,bcebos.com,DIRECT",
        // 抖音 / 字节 — 默认直连（策略组易被选成节点导致打不开）
        "DOMAIN-SUFFIX,zijieapi.com,DIRECT",
        "DOMAIN-SUFFIX,ecombdapi.com,DIRECT",
        "DOMAIN-SUFFIX,bytedance.com,DIRECT",
        "DOMAIN-SUFFIX,bytedance.net,DIRECT",
        "DOMAIN-SUFFIX,byteimg.com,DIRECT",
        "DOMAIN-SUFFIX,bytescm.com,DIRECT",
        "DOMAIN-SUFFIX,byteacctimg.com,DIRECT",
        // byteoversea → TikTok（见 tiktokPriorityRules），勿 DIRECT
        "DOMAIN-SUFFIX,douyin.com,DIRECT",
        "DOMAIN-SUFFIX,douyincdn.com,DIRECT",
        "DOMAIN-SUFFIX,douyinpic.com,DIRECT",
        "DOMAIN-SUFFIX,douyinvod.com,DIRECT",
        "DOMAIN-SUFFIX,douyinliving.com,DIRECT",
        "DOMAIN-SUFFIX,snssdk.com,DIRECT",
        "DOMAIN-SUFFIX,amemv.com,DIRECT",
        "DOMAIN-SUFFIX,pstatp.com,DIRECT",
        "DOMAIN-SUFFIX,ixigua.com,DIRECT",
        "DOMAIN-SUFFIX,toutiao.com,DIRECT",
        "DOMAIN-SUFFIX,toutiaovod.com,DIRECT",
        "DOMAIN-SUFFIX,toutiaostatic.com,DIRECT",
        "DOMAIN-SUFFIX,huoshan.com,DIRECT",
        "DOMAIN-SUFFIX,huoshanstatic.com,DIRECT",
        "DOMAIN-KEYWORD,zijieapi,DIRECT",
        "DOMAIN-KEYWORD,douyin,DIRECT",
        "DOMAIN-KEYWORD,snssdk,DIRECT",
        // 小红书
        "DOMAIN-SUFFIX,xiaohongshu.com,DIRECT",
        "DOMAIN-SUFFIX,xhscdn.com,DIRECT",
        "DOMAIN-SUFFIX,xhscdn.net,DIRECT",
        "DOMAIN-SUFFIX,xhslink.com,DIRECT",
        "DOMAIN-KEYWORD,xiaohongshu,DIRECT",
        "DOMAIN-KEYWORD,xhscdn,DIRECT",
        "DOMAIN-SUFFIX,feishu.cn,DIRECT",
        "DOMAIN-SUFFIX,larksuite.com,DIRECT",
        "DOMAIN-SUFFIX,jd.com,DIRECT",
        "DOMAIN-SUFFIX,jdpay.com,DIRECT",
        "DOMAIN-SUFFIX,360buyimg.com,DIRECT",
        "DOMAIN-SUFFIX,meituan.com,DIRECT",
        "DOMAIN-SUFFIX,meituan.net,DIRECT",
        "DOMAIN-SUFFIX,dianping.com,DIRECT",
        "DOMAIN-SUFFIX,ctrip.com,DIRECT",
        "DOMAIN-SUFFIX,c-ctrip.com,DIRECT",
        "DOMAIN-SUFFIX,12306.cn,DIRECT",
        "DOMAIN-SUFFIX,didichuxing.com,DIRECT",
        "DOMAIN-SUFFIX,udache.com,DIRECT",
        "DOMAIN-SUFFIX,map.qq.com,DIRECT",
        "DOMAIN-SUFFIX,map.baidu.com,DIRECT",

        // 视频 / 社交 / 资讯 — B 站默认直连
        "DOMAIN-SUFFIX,bilibili.com,DIRECT",
        "DOMAIN-SUFFIX,bilibili.cn,DIRECT",
        "DOMAIN-SUFFIX,bilivideo.com,DIRECT",
        "DOMAIN-SUFFIX,bilivideo.cn,DIRECT",
        "DOMAIN-SUFFIX,hdslb.com,DIRECT",
        "DOMAIN-SUFFIX,biliapi.com,DIRECT",
        "DOMAIN-SUFFIX,biliapi.net,DIRECT",
        "DOMAIN-SUFFIX,iqiyi.com,DIRECT",
        "DOMAIN-SUFFIX,iqiyipic.com,DIRECT",
        "DOMAIN-SUFFIX,youku.com,DIRECT",
        "DOMAIN-SUFFIX,ykimg.com,DIRECT",
        "DOMAIN-SUFFIX,zhihu.com,DIRECT",
        "DOMAIN-SUFFIX,zhimg.com,DIRECT",
        "DOMAIN-SUFFIX,weibo.com,DIRECT",
        "DOMAIN-SUFFIX,sina.com.cn,DIRECT",
        "DOMAIN-SUFFIX,sinaimg.cn,DIRECT",
        "DOMAIN-SUFFIX,163.com,DIRECT",
        "DOMAIN-SUFFIX,126.com,DIRECT",
        "DOMAIN-SUFFIX,127.net,DIRECT",
        "DOMAIN-SUFFIX,netease.com,DIRECT",
        "DOMAIN-SUFFIX,youdao.com,DIRECT",
        "DOMAIN-SUFFIX,kugou.com,DIRECT",
        "DOMAIN-SUFFIX,kuwo.cn,DIRECT",
        "DOMAIN-SUFFIX,music.163.com,DIRECT",
        "DOMAIN-SUFFIX,ximalaya.com,DIRECT",
        "DOMAIN-SUFFIX,xmcdn.com,DIRECT",

        // 厂商 / 支付 / 运营商
        "DOMAIN-SUFFIX,mi.com,DIRECT",
        "DOMAIN-SUFFIX,xiaomi.com,DIRECT",
        "DOMAIN-SUFFIX,miui.com,DIRECT",
        "DOMAIN-SUFFIX,mi-img.com,DIRECT",
        "DOMAIN-SUFFIX,huawei.com,DIRECT",
        "DOMAIN-SUFFIX,hicloud.com,DIRECT",
        "DOMAIN-SUFFIX,honor.com,DIRECT",
        "DOMAIN-SUFFIX,oppo.com,DIRECT",
        "DOMAIN-SUFFIX,heytap.com,DIRECT",
        "DOMAIN-SUFFIX,vivo.com.cn,DIRECT",
        "DOMAIN-SUFFIX,unionpay.com,DIRECT",
        "DOMAIN-SUFFIX,95516.com,DIRECT",
        "DOMAIN-SUFFIX,10086.cn,DIRECT",
        "DOMAIN-SUFFIX,189.cn,DIRECT",
        "DOMAIN-SUFFIX,10010.com,DIRECT",
        "DOMAIN-SUFFIX,chinamobile.com,DIRECT",
        "DOMAIN-SUFFIX,chinaunicom.com,DIRECT",
        "DOMAIN-SUFFIX,chinatelecom.com.cn,DIRECT",

        // CDN 杂项（国内 App 常用 .com 边缘，勿落 MATCH/PROXY）
        "DOMAIN-SUFFIX,qiniucdn.com,DIRECT",
        "DOMAIN-SUFFIX,qiniudn.com,DIRECT",
        "DOMAIN-SUFFIX,qnssl.com,DIRECT",
        "DOMAIN-SUFFIX,clouddn.com,DIRECT",
        "DOMAIN-SUFFIX,upyun.com,DIRECT",
        "DOMAIN-SUFFIX,upaiyun.com,DIRECT",
        "DOMAIN-SUFFIX,ksyun.com,DIRECT",
        "DOMAIN-SUFFIX,ksyuncs.com,DIRECT",
        "DOMAIN-SUFFIX,ks-cdn.com,DIRECT",
        "DOMAIN-SUFFIX,volces.com,DIRECT",
        "DOMAIN-SUFFIX,volccdn.com,DIRECT",
        "DOMAIN-SUFFIX,hwcdn.net,DIRECT",
        "DOMAIN-SUFFIX,cdngslb.com,DIRECT",
        "DOMAIN-SUFFIX,tbcdn.cn,DIRECT",
        "DOMAIN-SUFFIX,tbcache.com,DIRECT",

        // 政务 / 银行 — 本地直连（勿泛匹配全部 .org，以免误伤 Wikipedia）
        "DOMAIN-SUFFIX,gov.cn,DIRECT",
        "DOMAIN-SUFFIX,gov,DIRECT",
        "DOMAIN-SUFFIX,org.cn,DIRECT",
        "DOMAIN-SUFFIX,edu.cn,DIRECT",
        "DOMAIN-SUFFIX,ac.cn,DIRECT",
        "DOMAIN-SUFFIX,mil.cn,DIRECT",
        "DOMAIN-SUFFIX,bank,DIRECT",
        "DOMAIN-KEYWORD,bank,DIRECT",
        "DOMAIN-KEYWORD,银行,DIRECT",
        "DOMAIN-KEYWORD,gov,DIRECT",
        "DOMAIN-SUFFIX,icbc.com.cn,DIRECT",
        "DOMAIN-SUFFIX,icbc.com,DIRECT",
        "DOMAIN-SUFFIX,ccb.com,DIRECT",
        "DOMAIN-SUFFIX,abchina.com,DIRECT",
        "DOMAIN-SUFFIX,bankcomm.com,DIRECT",
        "DOMAIN-SUFFIX,boc.cn,DIRECT",
        "DOMAIN-SUFFIX,bankofchina.com,DIRECT",
        "DOMAIN-SUFFIX,cmbchina.com,DIRECT",
        "DOMAIN-SUFFIX,cmb.com.cn,DIRECT",
        "DOMAIN-SUFFIX,cib.com.cn,DIRECT",
        "DOMAIN-SUFFIX,spdb.com.cn,DIRECT",
        "DOMAIN-SUFFIX,cebbank.com,DIRECT",
        "DOMAIN-SUFFIX,cmbc.com.cn,DIRECT",
        "DOMAIN-SUFFIX,psbc.com,DIRECT",
        "DOMAIN-SUFFIX,citicbank.com,DIRECT",
        "DOMAIN-SUFFIX,hxb.com.cn,DIRECT",
        "DOMAIN-SUFFIX,cgbchina.com.cn,DIRECT",
        "DOMAIN-SUFFIX,bankofbeijing.com.cn,DIRECT",
        "DOMAIN-SUFFIX,bosc.cn,DIRECT",
        "DOMAIN-SUFFIX,hzbank.com.cn,DIRECT",
        "DOMAIN-SUFFIX,njcb.com.cn,DIRECT",
        "DOMAIN-SUFFIX,nbcb.com.cn,DIRECT",
        "DOMAIN-SUFFIX,czbank.com,DIRECT",
        "DOMAIN-SUFFIX,hsbank.com.cn,DIRECT",
        "DOMAIN-SUFFIX,bankofshanghai.com,DIRECT",
        "DOMAIN-SUFFIX,pingan.com,DIRECT",
        "DOMAIN-SUFFIX,1qianbao.com,DIRECT",
        "DOMAIN-SUFFIX,webank.com,DIRECT",
        "DOMAIN-SUFFIX,mybank.cn,DIRECT",
        "DOMAIN-SUFFIX,chinapay.com,DIRECT",
        "DOMAIN-SUFFIX,yeepay.com,DIRECT",
        "DOMAIN-SUFFIX,unionpay.com,DIRECT",
        "DOMAIN-SUFFIX,95516.com,DIRECT",
        "DOMAIN-SUFFIX,tenpay.com,DIRECT",

        // 其它常用国产电商
        "DOMAIN-SUFFIX,pinduoduo.com,DIRECT",
        "DOMAIN-SUFFIX,yangkeduo.com,DIRECT",
        "DOMAIN-SUFFIX,suning.com,DIRECT",
        "DOMAIN-SUFFIX,vip.com,DIRECT",
        "DOMAIN-SUFFIX,vipstatic.com,DIRECT",
        "DOMAIN-SUFFIX,dewu.com,DIRECT",
        "DOMAIN-SUFFIX,poizon.com,DIRECT",
        "DOMAIN-SUFFIX,smzdm.com,DIRECT",
        "DOMAIN-SUFFIX,ximalaya.com,DIRECT",
        "DOMAIN-SUFFIX,zhihuishu.com,DIRECT",
        "DOMAIN-SUFFIX,tencentmusic.com,DIRECT",
        "DOMAIN-SUFFIX,cctv.com,DIRECT",
        "DOMAIN-SUFFIX,cctvpic.com,DIRECT",
    ]

    // MARK: - China / Tencent CDN IP (bare-IP dials, no SNI)

    private static let chinaIP: [String] = [
        // blackmatrix7 China.list IP extras
        "IP-CIDR,183.128.0.0/11,DIRECT,no-resolve",
        "IP-CIDR,129.226.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,101.32.96.0/20,DIRECT,no-resolve",
        "IP-CIDR,203.205.238.0/23,DIRECT,no-resolve",
        "IP-CIDR,203.205.254.0/23,DIRECT,no-resolve",
        // 微信 / 腾讯 CDN 边缘
        "IP-CIDR,1.12.0.0/14,DIRECT,no-resolve",
        "IP-CIDR,14.17.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,14.18.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,14.19.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,14.116.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,58.251.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,59.37.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,101.226.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,101.227.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,113.96.0.0/12,DIRECT,no-resolve",
        "IP-CIDR,119.147.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,121.51.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,140.207.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,157.255.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,180.163.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,182.254.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.3.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.36.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.47.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.57.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.60.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.192.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,183.232.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,203.205.128.0/19,DIRECT,no-resolve",
        "IP-CIDR,211.95.0.0/16,DIRECT,no-resolve",
    ]
}
