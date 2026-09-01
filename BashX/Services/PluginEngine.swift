import Foundation

/// Rule-pack plugin engine (hub.kelee.one–style catalog).
/// Loads bundled JSON packs, sanitizes Clash-compatible rules, merges by enable order.
/// Does **not** run Loon/Surge MITM or JS rewrites.
enum PluginEngine {
    struct Plugin: Identifiable, Hashable, Codable {
        let id: String
        let name: String
        let summary: String
        let tag: String
        let symbol: String
        let rules: [String]
        /// Full effect needs MITM/script; packs here are rule approximations.
        let scriptHeavy: Bool

        var ruleCount: Int { rules.count }
    }

    private static let allowedTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX",
        "IP-CIDR", "IP-CIDR6",
        "PROCESS-NAME", "PROCESS-PATH",
    ]

    private static let allowedPolicies: Set<String> = [
        "REJECT", "DIRECT", "PROXY",
        "GOOGLE", "TELEGRAM", "APNS", "CURSOR", "TIKTOK",
    ]

    /// Loaded once: bundle JSON packs, then built-in fallback for any missing ids.
    static let catalog: [Plugin] = loadCatalog()

    static func plugin(id: String) -> Plugin? {
        catalog.first { $0.id == id }
    }

    static func rules(forEnabledIds ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in ids {
            guard let p = plugin(id: id) else { continue }
            for raw in p.rules {
                guard let rule = sanitize(raw) else { continue }
                guard !seen.contains(rule) else { continue }
                seen.insert(rule)
                out.append(rule)
            }
        }
        return out
    }

    /// Prepend enabled plugin rules (stable order = `enabledIds`), dedupe against base.
    static func merge(into base: [String], enabledIds: [String]) -> [String] {
        let pluginRules = rules(forEnabledIds: enabledIds)
        guard !pluginRules.isEmpty else { return base }
        let drop = Set(pluginRules)
        let cleaned = base.filter { !drop.contains($0.trimmingCharacters(in: .whitespaces)) }
        return pluginRules + cleaned
    }

    /// Normalize one Clash rule line for BashX / mihomo; nil = drop.
    static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        let upper = trimmed.uppercased()
        // Surge / Loon / Quantumult exclusive — never emit.
        if upper.hasPrefix("URL-REGEX") || upper.hasPrefix("AND,") || upper.hasPrefix("OR,")
            || upper.hasPrefix("NOT,") || upper.hasPrefix("USER-AGENT")
            || upper.hasPrefix("RULE-SET") || upper.hasPrefix("SCRIPT")
            || upper.hasPrefix("MITM") || upper.contains("EXTENDED-MATCHING")
            || upper.contains("PRE-MATCHING") {
            return nil
        }

        var parts = trimmed.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 3 else { return nil }

        let typeRaw = parts[0].uppercased()
        // Surge HOST* → Clash DOMAIN*
        let type: String = {
            switch typeRaw {
            case "HOST": return "DOMAIN"
            case "HOST-SUFFIX": return "DOMAIN-SUFFIX"
            case "HOST-KEYWORD": return "DOMAIN-KEYWORD"
            default: return typeRaw
            }
        }()
        guard allowedTypes.contains(type) else { return nil }

        #if os(iOS)
        if type.hasPrefix("PROCESS") || type == "GEOSITE" || type == "GEOIP" {
            return nil
        }
        #endif

        var policy = parts[2].uppercased()
        // Surge reject variants → Clash REJECT
        if policy == "REJECT-DROP" || policy == "REJECT-NO-DROP" || policy == "REJECT-TINYGIF"
            || policy.hasPrefix("REJECT") {
            policy = "REJECT"
        }
        guard allowedPolicies.contains(policy) else { return nil }
        parts[0] = type
        parts[2] = policy

        // Keep optional no-resolve for IP rules only.
        if parts.count > 3 {
            let opt = parts[3].lowercased()
            if type.hasPrefix("IP-CIDR"), opt == "no-resolve" {
                return "\(type),\(parts[1]),\(policy),no-resolve"
            }
            parts = Array(parts.prefix(3))
        }
        return parts.joined(separator: ",")
    }

    // MARK: - Load

    private static func loadCatalog() -> [Plugin] {
        var byId: [String: Plugin] = [:]
        for p in loadBundledPacks() {
            let cleaned = Plugin(
                id: p.id,
                name: p.name,
                summary: p.summary,
                tag: p.tag,
                symbol: p.symbol,
                rules: p.rules.compactMap(sanitize),
                scriptHeavy: p.scriptHeavy
            )
            byId[cleaned.id] = cleaned
        }
        // Ensure built-in fallbacks fill gaps / order.
        var ordered: [Plugin] = []
        var seen = Set<String>()
        for fallback in builtinFallback {
            let pack = byId[fallback.id] ?? fallback
            let cleaned = Plugin(
                id: pack.id,
                name: pack.name,
                summary: pack.summary,
                tag: pack.tag,
                symbol: pack.symbol,
                rules: pack.rules.compactMap(sanitize),
                scriptHeavy: pack.scriptHeavy
            )
            ordered.append(cleaned)
            seen.insert(cleaned.id)
        }
        for (id, p) in byId where !seen.contains(id) {
            ordered.append(p)
        }
        return ordered
    }

    private static func loadBundledPacks() -> [Plugin] {
        var urls: [URL] = []
        let fm = FileManager.default
        // Never use a top-level bundle folder named "plugins" — on case-insensitive
        // macOS build volumes it collides with iOS "PlugIns" and corrupts the appex.
        for sub in ["plugin-packs", "rules/plugin-packs", "Resources/rules/plugin-packs"] {
            if let dir = Bundle.main.resourceURL?.appendingPathComponent(sub),
               let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                urls.append(contentsOf: items.filter { $0.pathExtension.lowercased() == "json" })
            }
            if let found = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: sub) {
                urls.append(contentsOf: found)
            }
        }
        // Flat resources (no subdirectory copy)
        if let flat = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            urls.append(contentsOf: flat.filter { $0.lastPathComponent.hasPrefix("plugin-") || $0.path.contains("plugins") })
        }

        var unique = [URL]()
        var seenPath = Set<String>()
        for u in urls {
            let p = u.path
            guard !seenPath.contains(p) else { continue }
            seenPath.insert(p)
            unique.append(u)
        }

        let dec = JSONDecoder()
        var out: [Plugin] = []
        for url in unique {
            guard let data = try? Data(contentsOf: url),
                  let plugin = try? dec.decode(Plugin.self, from: data),
                  !plugin.id.isEmpty else { continue }
            out.append(plugin)
        }
        return out
    }

    /// Hardcoded fallback when JSON packs are missing from the bundle.
    private static let builtinFallback: [Plugin] = [
        Plugin(id: "36kr-ads", name: "36氪去广告", summary: "规则拦截开屏、信息流与广告网关域名。", tag: "去广告", symbol: "newspaper.fill", rules: [
            "DOMAIN,gateway-ad.36kr.com,REJECT",
            "DOMAIN,adx.36kr.com,REJECT",
            "DOMAIN,adapi.36kr.com,REJECT",
            "DOMAIN-SUFFIX,partner.36kr.com,REJECT",
            "DOMAIN-SUFFIX,36krcnd.com,REJECT",
            "DOMAIN-KEYWORD,36kr-ad,REJECT",
            "DOMAIN-KEYWORD,adapi.36kr,REJECT",
            "DOMAIN-KEYWORD,36kr.ad,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "123pan-ads", name: "123云盘去广告", summary: "规则拦截开屏与横幅广告域名。", tag: "去广告", symbol: "externaldrive.fill", rules: [
            "DOMAIN,ad.123pan.com,REJECT",
            "DOMAIN,ads.123pan.com,REJECT",
            "DOMAIN,advert.123pan.com,REJECT",
            "DOMAIN,ad-api.123pan.com,REJECT",
            "DOMAIN,adapi.123pan.com,REJECT",
            "DOMAIN-KEYWORD,123-ad,REJECT",
            "DOMAIN-KEYWORD,123pan.ad,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "apple-weather", name: "Apple天气增强", summary: "WeatherKit / 天气数据走代理，便于完整天气内容。", tag: "增强", symbol: "cloud.sun.fill", rules: [
            "DOMAIN-SUFFIX,weatherkit.apple.com,PROXY",
            "DOMAIN-SUFFIX,weather-data.apple.com,PROXY",
            "DOMAIN,weather-data.apple.com,PROXY",
            "DOMAIN-SUFFIX,weather.apple.com,PROXY",
            "DOMAIN,weather-data.apple.com.akadns.net,PROXY",
        ], scriptHeavy: false),
        Plugin(id: "echarge-ads", name: "e充电去广告", summary: "规则拦截开屏与运营位广告域名。", tag: "去广告", symbol: "bolt.car.fill", rules: [
            "DOMAIN,ad.eichong.com,REJECT",
            "DOMAIN,ads.eichong.com,REJECT",
            "DOMAIN,adapi.eichong.com,REJECT",
            "DOMAIN,advert.eichong.com,REJECT",
            "DOMAIN-KEYWORD,eichong-ad,REJECT",
            "DOMAIN-KEYWORD,echarge-ad,REJECT",
            "DOMAIN-KEYWORD,eichong.ad,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "cainiao-ads", name: "菜鸟去广告", summary: "拦截菜鸟裹裹全屏/开屏广告与广告流接口域名（物流主接口尽量保留）。", tag: "去广告", symbol: "shippingbox.fill", rules: [
            "DOMAIN,netflow-mtop.cainiao.com,REJECT",
            "DOMAIN,nbcps-mtop.cainiao.com,REJECT",
            "DOMAIN,guoguo-corp.cainiao.com,REJECT",
            "DOMAIN,cn-acs.m.cainiao.com,REJECT",
            "DOMAIN,adashx.ut.taobao.com,REJECT",
            "DOMAIN,wgo.mmstat.com,REJECT",
            "DOMAIN,log.mmstat.com,REJECT",
            "DOMAIN,gm.mmstat.com,REJECT",
            "DOMAIN,ytx-offline.alicdn.com,REJECT",
            "DOMAIN-KEYWORD,nbnetflow,REJECT",
            "DOMAIN-KEYWORD,cainiao-ad,REJECT",
            "DOMAIN-KEYWORD,cainiao.ad,REJECT",
            "DOMAIN-KEYWORD,guoguo.ads,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "amap-ads", name: "高德地图去广告", summary: "拦截高德开屏素材与广告 CDN（不拦 m5/oss/sns 主业务，避免影响导航）。", tag: "去广告", symbol: "map.fill", rules: [
            "DOMAIN,amap-aos-info-nogw.amap.com,REJECT",
            "DOMAIN,free-aos-cdn-image.amap.com,REJECT",
            "DOMAIN,optimus-ads.amap.com,REJECT",
            "DOMAIN-SUFFIX,optimus-ads.amap.com,REJECT",
            "DOMAIN-KEYWORD,amap-ad,REJECT",
            "DOMAIN-KEYWORD,amap.ad,REJECT",
            "DOMAIN-KEYWORD,aos-ads,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "jd-ads", name: "京东去广告", summary: "规则拦截开屏跳转、联盟与广告投放域名（不拦主站 API）。", tag: "去广告", symbol: "cart.fill", rules: [
            "DOMAIN,u.jd.com,REJECT",
            "DOMAIN,union-click.jd.com,REJECT",
            "DOMAIN,ccc-x.jd.com,REJECT",
            "DOMAIN,dsp-x.jd.com,REJECT",
            "DOMAIN,ads.jd.com,REJECT",
            "DOMAIN,x.jd.com,REJECT",
            "DOMAIN,blackhole.m.jd.com,REJECT",
            "DOMAIN-SUFFIX,jddebug.com,REJECT",
            "DOMAIN-KEYWORD,jd.ad,REJECT",
            "DOMAIN-KEYWORD,jdads,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "pdd-ads", name: "拼多多去广告", summary: "规则拦截推广、埋点与广告素材域名。", tag: "去广告", symbol: "bag.fill", rules: [
            "DOMAIN,titan.pinduoduo.com,REJECT",
            "DOMAIN,xg.pinduoduo.com,REJECT",
            "DOMAIN,cdl-1.pddpic.com,REJECT",
            "DOMAIN,cdl-p2.pddpic.com,REJECT",
            "DOMAIN,cd-1.pddpic.com,REJECT",
            "DOMAIN,apm.pinduoduo.com,REJECT",
            "DOMAIN,apm-a.pinduoduo.com,REJECT",
            "DOMAIN,th-b.pinduoduo.com,REJECT",
            "DOMAIN,ta.pinduoduo.com,REJECT",
            "DOMAIN,th.pinduoduo.com,REJECT",
            "DOMAIN,th-a.pinduoduo.com,REJECT",
            "DOMAIN,ta-a.pinduoduo.com,REJECT",
            "DOMAIN,meta.pinduoduo.com,REJECT",
            "DOMAIN-KEYWORD,pdd-ad,REJECT",
            "DOMAIN-KEYWORD,pinduoduo.ad,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "soda-ads", name: "汽水音乐去广告", summary: "规则拦截开屏与穿山甲/广告 SDK 域名。", tag: "去广告", symbol: "music.note", rules: [
            "DOMAIN,adapi.qishui.com,REJECT",
            "DOMAIN,ad.qishui.com,REJECT",
            "DOMAIN,ads.qishui.com,REJECT",
            "DOMAIN,pangolin.snssdk.com,REJECT",
            "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
            "DOMAIN-SUFFIX,pangle.io,REJECT",
            "DOMAIN-KEYWORD,qishui-ad,REJECT",
            "DOMAIN-KEYWORD,qishui.ad,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "kugou-ads", name: "酷狗音乐去广告", summary: "规则拦截开屏、广告服、统计与优量汇域名（无 MITM，部分网关内嵌广告可能仍在）。", tag: "去广告", symbol: "music.note.list", rules: [
            "DOMAIN,ads.service.kugou.com,REJECT",
            "DOMAIN,adservice.kugou.com,REJECT",
            "DOMAIN,adserviceretry.kugou.com,REJECT",
            "DOMAIN,adserviceretry.kglink.cn,REJECT",
            "DOMAIN,adsfile.bssdlbig.kugou.com,REJECT",
            "DOMAIN,adsfilebssdlbig.tx.kugou.com,REJECT",
            "DOMAIN,splashimgretrybssdl.cloud.kugou.com,REJECT",
            "DOMAIN,splashimgbssdl.yun.kugou.com,REJECT",
            "DOMAIN,gad.kugou.com,REJECT",
            "DOMAIN,gg.kugou.com,REJECT",
            "DOMAIN,mvads.kugou.com,REJECT",
            "DOMAIN,log.stat.kugou.com,REJECT",
            "DOMAIN,log.web.kugou.com,REJECT",
            "DOMAIN,kgmobilestat.kugou.com,REJECT",
            "DOMAIN,kgmobilestatbak.kugou.com,REJECT",
            "DOMAIN,mobilelog.kugou.com,REJECT",
            "DOMAIN,ad.tencentmusic.com,REJECT",
            "DOMAIN,adstats.tencentmusic.com,REJECT",
            "DOMAIN,tmead.y.qq.com,REJECT",
            "DOMAIN,tmeadbak.y.qq.com,REJECT",
            "DOMAIN,tmeadcomm.y.qq.com,REJECT",
            "DOMAIN,adsmind.gdtimg.com,REJECT",
            "DOMAIN,adsmind.ugdtimg.com,REJECT",
            "DOMAIN,pgdt.gtimg.cn,REJECT",
            "DOMAIN,pgdt.ugdtimg.com,REJECT",
            "DOMAIN,sdk.e.qq.com,REJECT",
            "DOMAIN,us.l.qq.com,REJECT",
            "DOMAIN-SUFFIX,gdt.qq.com,REJECT",
            "DOMAIN-SUFFIX,ugdtimg.com,REJECT",
            "DOMAIN-KEYWORD,kugou.ad,REJECT",
            "DOMAIN-KEYWORD,kugou-ad,REJECT",
            "DOMAIN-KEYWORD,adservice.kugou,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "tencent-video-ads", name: "腾讯视频去广告", summary: "拦截腾讯视频开屏、广点通投放与广告追踪域名（不拦正片主域名）。", tag: "去广告", symbol: "play.rectangle.fill", rules: [
            "DOMAIN,adsmind.gdtimg.com,REJECT",
            "DOMAIN,adsmind.ugdtimg.com,REJECT",
            "DOMAIN,info4.video.qq.com,REJECT",
            "DOMAIN,info6.video.qq.com,REJECT",
            "DOMAIN,activity.video.qq.com,REJECT",
            "DOMAIN,ads.video.qq.com,REJECT",
            "DOMAIN,sdkconfig.video.qq.com,REJECT",
            "DOMAIN,ios.video.mpush.qq.com,REJECT",
            "DOMAIN,otheve.beacon.qq.com,REJECT",
            "DOMAIN,pgdt.gtimg.cn,REJECT",
            "DOMAIN,pgdt.ugdtimg.com,REJECT",
            "DOMAIN,vv6.video.qq.com,REJECT",
            "DOMAIN,tmead.y.qq.com,REJECT",
            "DOMAIN,tmeadbak.y.qq.com,REJECT",
            "DOMAIN,tmeadcomm.y.qq.com,REJECT",
            "DOMAIN,sdk.e.qq.com,REJECT",
            "DOMAIN,tpns.qq.com,REJECT",
            "DOMAIN-SUFFIX,gdt.qq.com,REJECT",
            "DOMAIN-SUFFIX,l.qq.com,REJECT",
            "DOMAIN-SUFFIX,ugdtimg.com,REJECT",
            "DOMAIN-KEYWORD,trace.qq.com,REJECT",
            "DOMAIN-KEYWORD,trace.video.qq.com,REJECT",
            "DOMAIN-KEYWORD,vmind.qqvideo,REJECT",
            "IP-CIDR,47.110.187.87/32,REJECT,no-resolve",
        ], scriptHeavy: false),
        Plugin(id: "volvo-ads", name: "沃尔沃汽车去开屏", summary: "拦截开屏广告 SDK 与活动投放；不拦 digitalvolvo 素材站，避免红屏一直转圈。", tag: "去广告", symbol: "car.fill", rules: [
            "DOMAIN,campaigns.volvocars.com.cn,REJECT",
            "DOMAIN-KEYWORD,volvocars.campaign,REJECT",
            "DOMAIN-KEYWORD,volvo-ad,REJECT",
            "DOMAIN-KEYWORD,volvocars.ad,REJECT",
            "DOMAIN-SUFFIX,gdt.qq.com,REJECT",
            "DOMAIN,adsmind.gdtimg.com,REJECT",
            "DOMAIN,adsmind.ugdtimg.com,REJECT",
            "DOMAIN,pgdt.gtimg.cn,REJECT",
            "DOMAIN,pgdt.ugdtimg.com,REJECT",
            "DOMAIN-SUFFIX,l.qq.com,REJECT",
            "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
            "DOMAIN-SUFFIX,pangle.io,REJECT",
            "DOMAIN-SUFFIX,pglstatp-toutiao.com,REJECT",
            "DOMAIN,pangolin.snssdk.com,REJECT",
            "DOMAIN-SUFFIX,doubleclick.net,REJECT",
            "DOMAIN-SUFFIX,googlesyndication.com,REJECT",
            "DOMAIN-SUFFIX,umeng.com,REJECT",
            "DOMAIN-SUFFIX,umengcloud.com,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "lixiang-ads", name: "理想汽车去广告", summary: "拦截理想汽车 App 开屏/营销投放与埋点域名，缩短启动等待（不拦车控主接口）。", tag: "去广告", symbol: "car.side.fill", rules: [
            "DOMAIN,marketing.lixiang.com,REJECT",
            "DOMAIN,track.lixiang.com,REJECT",
            "DOMAIN-KEYWORD,track.lixiang,REJECT",
            "DOMAIN-KEYWORD,marketing.lixiang,REJECT",
            "DOMAIN-KEYWORD,lixiang.ad,REJECT",
            "DOMAIN-KEYWORD,lixiang-ad,REJECT",
            "DOMAIN-KEYWORD,chehejia.ad,REJECT",
            "DOMAIN-SUFFIX,growingio.com,REJECT",
            "DOMAIN-SUFFIX,gio.ren,REJECT",
            "DOMAIN-SUFFIX,sensorsdata.cn,REJECT",
            "DOMAIN-SUFFIX,umeng.com,REJECT",
            "DOMAIN-SUFFIX,umengcloud.com,REJECT",
            "DOMAIN-SUFFIX,gdt.qq.com,REJECT",
            "DOMAIN,adsmind.gdtimg.com,REJECT",
            "DOMAIN,pgdt.gtimg.cn,REJECT",
            "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
            "DOMAIN-SUFFIX,pangle.io,REJECT",
            "DOMAIN-SUFFIX,tingyun.com,REJECT",
            "DOMAIN-SUFFIX,networkbench.com,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "aito-ads", name: "问界汽车去广告", summary: "拦截问界(AITO) App 开屏营销、赛力斯活动页与华为侧埋点，缩短启动等待（不拦车控接口）。", tag: "去广告", symbol: "car.rear.fill", rules: [
            "DOMAIN,activity.seres.cn,REJECT",
            "DOMAIN-SUFFIX,activity.seres.cn,REJECT",
            "DOMAIN-KEYWORD,aito.ad,REJECT",
            "DOMAIN-KEYWORD,aito-ad,REJECT",
            "DOMAIN-KEYWORD,wenjie.ad,REJECT",
            "DOMAIN-KEYWORD,seres.ad,REJECT",
            "DOMAIN,metrics1.data.hicloud.com,REJECT",
            "DOMAIN,metrics-drcn.data.hicloud.com,REJECT",
            "DOMAIN,logservice1.hicloud.com,REJECT",
            "DOMAIN,logbak.hicloud.com,REJECT",
            "DOMAIN-SUFFIX,growingio.com,REJECT",
            "DOMAIN-SUFFIX,gio.ren,REJECT",
            "DOMAIN-SUFFIX,sensorsdata.cn,REJECT",
            "DOMAIN-SUFFIX,umeng.com,REJECT",
            "DOMAIN-SUFFIX,umengcloud.com,REJECT",
            "DOMAIN-SUFFIX,gdt.qq.com,REJECT",
            "DOMAIN,adsmind.gdtimg.com,REJECT",
            "DOMAIN,pgdt.gtimg.cn,REJECT",
            "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
            "DOMAIN-SUFFIX,pangle.io,REJECT",
            "DOMAIN-SUFFIX,tingyun.com,REJECT",
            "DOMAIN-SUFFIX,networkbench.com,REJECT",
        ], scriptHeavy: false),
        Plugin(id: "wechat-extlink", name: "微信外部链接解锁", summary: "直连微信外链中转页（weixin110 / security.wechat），减少拦截跳转。", tag: "解锁", symbol: "link", rules: [
            "DOMAIN-SUFFIX,weixin110.qq.com,DIRECT",
            "DOMAIN,weixin110.qq.com,DIRECT",
            "DOMAIN-SUFFIX,security.wechat.com,DIRECT",
            "DOMAIN,security.wechat.com,DIRECT",
            "DOMAIN-KEYWORD,weixin110,DIRECT",
            "DOMAIN-KEYWORD,newredirectconfirmcgi,DIRECT",
        ], scriptHeavy: false),
        Plugin(id: "auto-join-tf", name: "自动加入TestFlight", summary: "TestFlight 相关域名走代理，便于访问与加入测试。", tag: "工具", symbol: "airplane.departure", rules: [
            "DOMAIN-SUFFIX,testflight.apple.com,PROXY",
            "DOMAIN,testflight.apple.com,PROXY",
            "DOMAIN-SUFFIX,beta.itunes.apple.com,PROXY",
        ], scriptHeavy: false),
    ]
}
