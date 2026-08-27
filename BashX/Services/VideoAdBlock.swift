import Foundation

/// High-priority REJECT rules for video / streaming ad networks.
/// Covers global platforms + major CN video apps (B站 / 爱奇艺 / 优酷 / 腾讯视频 /
/// 芒果TV / 抖音 / 快手 / 西瓜 / 搜狐 / PPTV 等).
/// Domain-level only — cannot strip in-stream ads served from the same CDN as the video itself.
enum VideoAdBlock {
    static let rules: [String] = [
        // —— Global ——
        "DOMAIN-SUFFIX,doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,googleadservices.com,REJECT",
        "DOMAIN-SUFFIX,googlesyndication.com,REJECT",
        "DOMAIN-SUFFIX,google-analytics.com,REJECT",
        "DOMAIN-SUFFIX,googletagmanager.com,REJECT",
        "DOMAIN-SUFFIX,googletagservices.com,REJECT",
        "DOMAIN-SUFFIX,adservice.google.com,REJECT",
        "DOMAIN-SUFFIX,ade.googlesyndication.com,REJECT",

        // —— YouTube / Google video ads (orchestration hosts; googlevideo streams can't be
        //     domain-blocked without killing the video itself) ——
        "DOMAIN-SUFFIX,pagead2.googlesyndication.com,REJECT",
        "DOMAIN-SUFFIX,pagead.l.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,googleads.g.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,googleads4.g.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,ad.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,static.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,stats.g.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,partnerad.l.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,g.doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,2mdn.net,REJECT",
        "DOMAIN-SUFFIX,ad.youtube.com,REJECT",
        "DOMAIN-SUFFIX,ads.youtube.com,REJECT",
        "DOMAIN-SUFFIX,s.youtube.com,REJECT",
        "DOMAIN-SUFFIX,video-ads.googlevideo.com,REJECT",
        "DOMAIN,www.googleadservices.com,REJECT",
        "DOMAIN,adservice.google.com,REJECT",
        "DOMAIN,adservice.google.com.hk,REJECT",
        "DOMAIN,adservice.google.cn,REJECT",
        "DOMAIN-KEYWORD,pagead,REJECT",
        "DOMAIN-KEYWORD,doubleclick,REJECT",
        "DOMAIN-KEYWORD,googleads,REJECT",
        "DOMAIN-KEYWORD,googlesyndication,REJECT",
        "DOMAIN-SUFFIX,innovid.com,REJECT",
        "DOMAIN-SUFFIX,serving-sys.com,REJECT",
        "DOMAIN-SUFFIX,fwmrm.net,REJECT",
        "DOMAIN-SUFFIX,tidaltv.com,REJECT",

        "DOMAIN-SUFFIX,an.facebook.com,REJECT",
        "DOMAIN-SUFFIX,ads.facebook.com,REJECT",
        "DOMAIN-SUFFIX,pixel.facebook.com,REJECT",

        "DOMAIN-SUFFIX,ads-twitter.com,REJECT",
        "DOMAIN-SUFFIX,ads-api.twitter.com,REJECT",
        "DOMAIN-SUFFIX,static.ads-twitter.com,REJECT",

        "DOMAIN-SUFFIX,amazon-adsystem.com,REJECT",
        "DOMAIN-SUFFIX,advertising.amazon.com,REJECT",
        "DOMAIN-SUFFIX,twitchads.com,REJECT",
        "DOMAIN-SUFFIX,ads.twitch.tv,REJECT",

        // —— 抖音 / 头条 / TikTok / 西瓜 ——
        "DOMAIN-SUFFIX,ads.tiktok.com,REJECT",
        "DOMAIN-SUFFIX,ads-api.tiktok.com,REJECT",
        "DOMAIN-KEYWORD,pangolin-sdk-toutiao,REJECT",
        "DOMAIN-SUFFIX,pglstatp-toutiao.com,REJECT",
        "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
        "DOMAIN-SUFFIX,pangolin-sdk-toutiao1.com,REJECT",
        "DOMAIN-SUFFIX,is.snssdk.com,REJECT",
        "DOMAIN-SUFFIX,ad.toutiao.com,REJECT",
        "DOMAIN-SUFFIX,dm.toutiao.com,REJECT",
        "DOMAIN-SUFFIX,lf.snssdk.com,REJECT",
        "DOMAIN-SUFFIX,i.snssdk.com,REJECT",
        "DOMAIN-SUFFIX,bds.snssdk.com,REJECT",
        "DOMAIN-SUFFIX,dig.bdurl.net,REJECT",
        "DOMAIN-SUFFIX,ad.zijieapi.com,REJECT",
        "DOMAIN-SUFFIX,luckycat-dypay.ixigua.com,REJECT",

        // —— Bilibili ——
        "DOMAIN-SUFFIX,cm.bilibili.com,REJECT",
        "DOMAIN-SUFFIX,adx.adxvip.com,REJECT",
        "DOMAIN-SUFFIX,g.hdslb.com,REJECT",
        "DOMAIN-SUFFIX,data.bilibili.com,REJECT",
        "DOMAIN-SUFFIX,mm.bilibili.com,REJECT",
        "DOMAIN-KEYWORD,bilibili-ad,REJECT",

        // —— 爱奇艺 ——
        "DOMAIN-SUFFIX,cupid.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,msg.qy.net,REJECT",
        "DOMAIN-SUFFIX,t7z.cupid.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,ifacelog.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,policy.video.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,msga.cupid.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,adservice.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,tracker.sns.iqiyi.com,REJECT",

        // —— 优酷 / 土豆 ——
        "DOMAIN-SUFFIX,atm.youku.com,REJECT",
        "DOMAIN-SUFFIX,iyes.youku.com,REJECT",
        "DOMAIN-SUFFIX,ad.api.3g.youku.com,REJECT",
        "DOMAIN-SUFFIX,hudong.pl.youku.com,REJECT",
        "DOMAIN-SUFFIX,valf.atm.youku.com,REJECT",
        "DOMAIN-SUFFIX,lstat.youku.com,REJECT",
        "DOMAIN-SUFFIX,ykad-data.youku.com,REJECT",
        "DOMAIN-SUFFIX,pl-ali.youku.com,REJECT",
        "DOMAIN-SUFFIX,ad.tudou.com,REJECT",

        // —— 腾讯视频 / 微视 ——
        "DOMAIN-SUFFIX,l.qq.com,REJECT",
        "DOMAIN-SUFFIX,t.l.qq.com,REJECT",
        "DOMAIN-SUFFIX,livep.l.qq.com,REJECT",
        "DOMAIN-SUFFIX,dp3.qq.com,REJECT",
        "DOMAIN-SUFFIX,btrace.qq.com,REJECT",
        "DOMAIN-SUFFIX,news.l.qq.com,REJECT",
        "DOMAIN-SUFFIX,p.l.qq.com,REJECT",
        "DOMAIN-SUFFIX,sdk.e.qq.com,REJECT",
        "DOMAIN-SUFFIX,e.qq.com,REJECT",
        "DOMAIN-SUFFIX,adsmind.gdtimg.com,REJECT",
        "DOMAIN-SUFFIX,adsmind.ugdtimg.com,REJECT",
        "DOMAIN-SUFFIX,pgdt.gtimg.cn,REJECT",
        "DOMAIN-SUFFIX,wa.gtimg.com,REJECT",
        "DOMAIN-SUFFIX,adsense.html5.qq.com,REJECT",
        "DOMAIN-SUFFIX,otheve.beacon.qq.com,REJECT",
        "DOMAIN-SUFFIX,tpns.qq.com,REJECT",

        // —— 芒果 TV ——
        "DOMAIN-SUFFIX,da.mgtv.com,REJECT",
        "DOMAIN-SUFFIX,adx.mgtv.com,REJECT",
        "DOMAIN-SUFFIX,figment-adx.mgtv.com,REJECT",
        "DOMAIN-SUFFIX,mobilesummit.mgtv.com,REJECT",
        "DOMAIN-SUFFIX,credits.bz.mgtv.com,REJECT",

        // —— 快手 ——
        "DOMAIN-SUFFIX,ad.kuaishou.com,REJECT",
        "DOMAIN-SUFFIX,gdfp.kuaishou.com,REJECT",
        "DOMAIN-SUFFIX,adeng.kuaishou.com,REJECT",
        "DOMAIN-SUFFIX,ali-ad.a.yximgs.com,REJECT",
        "DOMAIN-SUFFIX,js-ad.a.yximgs.com,REJECT",

        // —— 搜狐视频 / 搜狗 ——
        "DOMAIN-SUFFIX,at.sohu.com,REJECT",
        "DOMAIN-SUFFIX,pv.sohu.com,REJECT",
        "DOMAIN-SUFFIX,athena.wan.sogou.com,REJECT",
        "DOMAIN-SUFFIX,imp.as.sohu.com,REJECT",
        "DOMAIN-SUFFIX,ads.sohu.com,REJECT",

        // —— PPTV / 聚力 ——
        "DOMAIN-SUFFIX,asimgs.pplive.cn,REJECT",
        "DOMAIN-SUFFIX,g1.pplive.cn,REJECT",

        // —— 乐视 / 风行 / 华数 等 ——
        "DOMAIN-SUFFIX,ark.letv.com,REJECT",
        "DOMAIN-SUFFIX,i2.le.com,REJECT",
        "DOMAIN-SUFFIX,ad.funshion.com,REJECT",
        "DOMAIN-SUFFIX,adm.wasu.cn,REJECT",
        "DOMAIN-SUFFIX,adx.yidianzixun.com,REJECT",

        // —— 咪咕 / CNTV ——
        "DOMAIN-SUFFIX,ggic.cmvideo.cn,REJECT",
        "DOMAIN-SUFFIX,ggic2.cmvideo.cn,REJECT",
        "DOMAIN-SUFFIX,admdg.cctv.com,REJECT",
        "DOMAIN-SUFFIX,a.cctv.com,REJECT",

        // —— 国内通用广告联盟 / SDK ——
        "DOMAIN-SUFFIX,tanx.com,REJECT",
        "DOMAIN-SUFFIX,mmstat.com,REJECT",
        "DOMAIN-SUFFIX,cnzz.com,REJECT",
        "DOMAIN-SUFFIX,umeng.com,REJECT",
        "DOMAIN-SUFFIX,umengcloud.com,REJECT",
        "DOMAIN-SUFFIX,uyunad.com,REJECT",
        "DOMAIN-SUFFIX,mediav.com,REJECT",
        "DOMAIN-SUFFIX,ipinyou.com,REJECT",
        "DOMAIN-SUFFIX,gridsumdissector.com,REJECT",
        "DOMAIN-SUFFIX,miaozhen.com,REJECT",
        "DOMAIN-SUFFIX,admaster.com.cn,REJECT",
        "DOMAIN-SUFFIX,admaster.net,REJECT",
        "DOMAIN-SUFFIX,reachmax.cn,REJECT",
        "DOMAIN-SUFFIX,kejet.net,REJECT",
        "DOMAIN-SUFFIX,gentags.net,REJECT",
        "DOMAIN-SUFFIX,mtty.com,REJECT",
        "DOMAIN-SUFFIX,beacon.qq.com,REJECT",
        "DOMAIN-SUFFIX,wxsnsdy.wxs.qq.com,REJECT",
        "DOMAIN-SUFFIX,wxsnsdythumb.wxs.qq.com,REJECT",
        "DOMAIN-SUFFIX,adpm.app.qq.com,REJECT",
        // Extra CN / tracking hosts that often slip past category-ads-all
        "DOMAIN-SUFFIX,pos.baidu.com,REJECT",
        "DOMAIN-SUFFIX,cpro.baidu.com,REJECT",
        "DOMAIN-SUFFIX,duomai.com,REJECT",
        "DOMAIN-SUFFIX,allyes.com,REJECT",
        "DOMAIN-SUFFIX,ad.qq.com,REJECT",
        "DOMAIN-SUFFIX,adping.qq.com,REJECT",
        "DOMAIN-SUFFIX,adsfile.bssdlbig.kugou.com,REJECT",
        "DOMAIN-SUFFIX,adserviceretry.kugou.com,REJECT",
        "DOMAIN-SUFFIX,adse.w.ifeng.com,REJECT",
        "DOMAIN-KEYWORD,adservice,REJECT",
        "DOMAIN-KEYWORD,adserver,REJECT",

        // —— Common global ad / tracking CDNs ——
        "DOMAIN-SUFFIX,adnxs.com,REJECT",
        "DOMAIN-SUFFIX,adsrvr.org,REJECT",
        "DOMAIN-SUFFIX,advertising.com,REJECT",
        "DOMAIN-SUFFIX,adsafeprotected.com,REJECT",
        "DOMAIN-SUFFIX,adform.net,REJECT",
        "DOMAIN-SUFFIX,adcolony.com,REJECT",
        "DOMAIN-SUFFIX,admob.com,REJECT",
        "DOMAIN-SUFFIX,applovin.com,REJECT",
        "DOMAIN-SUFFIX,criteo.com,REJECT",
        "DOMAIN-SUFFIX,criteo.net,REJECT",
        "DOMAIN-SUFFIX,exoclick.com,REJECT",
        "DOMAIN-SUFFIX,inmobi.com,REJECT",
        "DOMAIN-SUFFIX,media.net,REJECT",
        "DOMAIN-SUFFIX,moatads.com,REJECT",
        "DOMAIN-SUFFIX,outbrain.com,REJECT",
        "DOMAIN-SUFFIX,pubmatic.com,REJECT",
        "DOMAIN-SUFFIX,rubiconproject.com,REJECT",
        "DOMAIN-SUFFIX,scorecardresearch.com,REJECT",
        "DOMAIN-SUFFIX,sharethrough.com,REJECT",
        "DOMAIN-SUFFIX,taboola.com,REJECT",
        "DOMAIN-SUFFIX,tapad.com,REJECT",
        "DOMAIN-SUFFIX,tremorhub.com,REJECT",
        "DOMAIN-SUFFIX,unityads.unity3d.com,REJECT",
        "DOMAIN-SUFFIX,smartadserver.com,REJECT",
        "DOMAIN-SUFFIX,casalemedia.com,REJECT",
        "DOMAIN-SUFFIX,openx.net,REJECT",
        "DOMAIN-SUFFIX,bidswitch.net,REJECT",
        "DOMAIN-SUFFIX,spotxchange.com,REJECT",
        "DOMAIN-SUFFIX,spotx.tv,REJECT",
        "DOMAIN-SUFFIX,teads.tv,REJECT",
        "DOMAIN-SUFFIX,flashtalking.com,REJECT",
        "DOMAIN-SUFFIX,imrworldwide.com,REJECT",

        "DOMAIN-SUFFIX,bat.bing.com,REJECT",
        "DOMAIN-SUFFIX,ads.linkedin.com,REJECT",
        "DOMAIN-SUFFIX,ads.pinterest.com,REJECT",
        "DOMAIN-SUFFIX,ads.yahoo.com,REJECT",
        "DOMAIN-SUFFIX,advertising.yahoo.com,REJECT",
    ]

    /// Extra geosite categories lifted to the front (before CN DIRECT).
    /// Only use lists that exist in MetaCubeX GeoSite.dat (category-ads-cn does NOT).
    private static let geositePriority: [String] = [
        // Must stay ahead of GEOSITE,youtube/google PROXY so ad hosts are rejected first.
        "GEOSITE,category-ads-all,REJECT",
    ]

    /// Known-bad / renamed geosite rules that crash mihomo on startup.
    static let brokenGeositeRules: Set<String> = [
        "GEOSITE,category-ads-cn,REJECT",
        "GEOSITE,category-ads-cn,DIRECT",
        "GEOSITE,category-ads-cn,PROXY",
    ]

    /// Prepend video-ad REJECT rules (high priority). Removes previous copies to avoid dupes.
    static func merge(into base: [String], enabled: Bool) -> [String] {
        let adDomains = Set(rules)
        var cleaned = base.filter { rule in
            let trimmed = rule.trimmingCharacters(in: .whitespaces)
            if adDomains.contains(trimmed) { return false }
            if isBrokenGeosite(trimmed) { return false }
            // Strip duplicate geosite ad tags — re-inserted at front when enabled.
            let upper = trimmed.uppercased()
            if upper.hasPrefix("GEOSITE,CATEGORY-ADS") { return false }
            return true
        }
        guard enabled else { return cleaned }
        return geositePriority + rules + cleaned
    }

    static func isBrokenGeosite(_ rule: String) -> Bool {
        let upper = rule.trimmingCharacters(in: .whitespaces).uppercased()
        if brokenGeositeRules.contains(where: { $0.uppercased() == upper }) { return true }
        // Catch variants: GEOSITE,category-ads-cn,...
        return upper.hasPrefix("GEOSITE,CATEGORY-ADS-CN,")
    }

    static var ruleCount: Int { geositePriority.count + rules.count }
}
