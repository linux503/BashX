import Foundation

/// Extra DIRECT rules for iOS light mode (no GeoSite). Keeps system & domestic apps working on VPN.
enum IosDirectDomains {
    static let privateIPRules: [String] = [
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,169.254.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,224.0.0.0/4,DIRECT,no-resolve",
    ]

    static let rules: [String] = privateIPRules + [
        // Apple (GEOSITE,apple@cn stripped on iOS)
        "DOMAIN-SUFFIX,apple.com,DIRECT",
        "DOMAIN-SUFFIX,icloud.com,DIRECT",
        "DOMAIN-SUFFIX,cdn-apple.com,DIRECT",
        "DOMAIN-SUFFIX,mzstatic.com,DIRECT",
        "DOMAIN-SUFFIX,apple-cloudkit.com,DIRECT",
        "DOMAIN-SUFFIX,apple-mapkit.com,DIRECT",
        "DOMAIN-SUFFIX,ess.apple.com,DIRECT",
        "DOMAIN-SUFFIX,gs.apple.com,DIRECT",
        "DOMAIN-SUFFIX,me.com,DIRECT",
        "DOMAIN-SUFFIX,icloud-content.com,DIRECT",
        "DOMAIN,gateway.icloud.com,DIRECT",
        "DOMAIN,gsa.apple.com,DIRECT",
        // WeChat / QQ — keep DIRECT so domestic chat stays fast under MATCH,PROXY
        "DOMAIN-SUFFIX,qq.com,DIRECT",
        "DOMAIN-SUFFIX,weixin.qq.com,DIRECT",
        "DOMAIN-SUFFIX,weixin.com,DIRECT",
        "DOMAIN-SUFFIX,wechat.com,DIRECT",
        "DOMAIN-SUFFIX,tenpay.com,DIRECT",
        "DOMAIN-KEYWORD,weixin,DIRECT",
        // iOS / carrier / local discovery
        "DOMAIN-SUFFIX,local,DIRECT",
        "DOMAIN-SUFFIX,home.arpa,DIRECT",
        "DOMAIN-SUFFIX,router,DIRECT",
        "DOMAIN-SUFFIX,localhost,DIRECT",
        // Common CN backends not always in smart list
        "DOMAIN-SUFFIX,163.com,DIRECT",
        "DOMAIN-SUFFIX,127.net,DIRECT",
        "DOMAIN-SUFFIX,youdao.com,DIRECT",
        "DOMAIN-SUFFIX,95516.com,DIRECT",
        "DOMAIN-SUFFIX,unionpay.com,DIRECT",
        "DOMAIN-SUFFIX,10086.cn,DIRECT",
        "DOMAIN-SUFFIX,189.cn,DIRECT",
        "DOMAIN-SUFFIX,chinamobile.com,DIRECT",
        "DOMAIN-SUFFIX,chinaunicom.com,DIRECT",
        "DOMAIN-SUFFIX,ctrip.com,DIRECT",
        "DOMAIN-SUFFIX,amap.com,DIRECT",
        "DOMAIN-SUFFIX,autonavi.com,DIRECT",
        "DOMAIN-SUFFIX,baidu.com,DIRECT",
        "DOMAIN-SUFFIX,bdstatic.com,DIRECT",
        "DOMAIN-SUFFIX,aliyun.com,DIRECT",
        "DOMAIN-SUFFIX,alicdn.com,DIRECT",
        "DOMAIN-SUFFIX,taobao.com,DIRECT",
        "DOMAIN-SUFFIX,alipay.com,DIRECT",
        "DOMAIN-SUFFIX,jd.com,DIRECT",
        "DOMAIN-SUFFIX,bilibili.com,DIRECT",
        "DOMAIN-SUFFIX,bilivideo.com,DIRECT",
        "DOMAIN-SUFFIX,zhihu.com,DIRECT",
        "DOMAIN-SUFFIX,netease.com,DIRECT",
    ]
}
