import Foundation

/// Domain rules for iOS light mode (no GeoSite DB). Inserted before MATCH,PROXY.
enum IosProxyDomains {
    /// Telegram DC CIDRs — iOS strips GEOIP,telegram; real IPs otherwise need these CIDRs.
    static let telegramIPRules: [String] = [
        "IP-CIDR,149.154.160.0/20,TELEGRAM,no-resolve",
        "IP-CIDR,91.108.0.0/16,TELEGRAM,no-resolve",
        "IP-CIDR,91.105.192.0/23,TELEGRAM,no-resolve",
        "IP-CIDR,185.76.151.0/24,TELEGRAM,no-resolve",
    ]

    static let rules: [String] = telegramIPRules + [
        // Google / YouTube (incl. .hk / .cn — DOMAIN-SUFFIX,google.com misses these)
        "DOMAIN-SUFFIX,google.com,PROXY",
        "DOMAIN-SUFFIX,google.com.hk,PROXY",
        "DOMAIN-SUFFIX,google.cn,PROXY",
        "DOMAIN-SUFFIX,googleapis.com,PROXY",
        "DOMAIN-SUFFIX,googleapis.cn,PROXY",
        "DOMAIN-SUFFIX,gstatic.com,PROXY",
        "DOMAIN-SUFFIX,gstatic.cn,PROXY",
        "DOMAIN-SUFFIX,googleusercontent.com,PROXY",
        "DOMAIN-SUFFIX,googlesyndication.com,PROXY",
        "DOMAIN-SUFFIX,googlevideo.com,PROXY",
        "DOMAIN-SUFFIX,youtube.com,PROXY",
        "DOMAIN-SUFFIX,youtu.be,PROXY",
        "DOMAIN-SUFFIX,ytimg.com,PROXY",
        "DOMAIN-SUFFIX,ggpht.com,PROXY",
        "DOMAIN-SUFFIX,gmail.com,PROXY",
        "DOMAIN-SUFFIX,android.com,PROXY",
        "DOMAIN-SUFFIX,gvt1.com,PROXY",
        "DOMAIN-SUFFIX,gvt2.com,PROXY",
        "DOMAIN-KEYWORD,google,PROXY",
        "DOMAIN-KEYWORD,youtube,PROXY",
        // Social / chat
        "DOMAIN-SUFFIX,twitter.com,PROXY",
        "DOMAIN-SUFFIX,x.com,PROXY",
        "DOMAIN-SUFFIX,twimg.com,PROXY",
        "DOMAIN-SUFFIX,t.co,PROXY",
        "DOMAIN-KEYWORD,twitter,PROXY",
        "DOMAIN-SUFFIX,facebook.com,PROXY",
        "DOMAIN-SUFFIX,fbcdn.net,PROXY",
        "DOMAIN-SUFFIX,instagram.com,PROXY",
        "DOMAIN-SUFFIX,cdninstagram.com,PROXY",
        "DOMAIN-SUFFIX,whatsapp.com,PROXY",
        "DOMAIN-SUFFIX,whatsapp.net,PROXY",
        "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
        "DOMAIN-SUFFIX,cdn-telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telesco.pe,TELEGRAM",
        "DOMAIN-SUFFIX,t.me,TELEGRAM",
        "DOMAIN-SUFFIX,graph.org,TELEGRAM",
        "DOMAIN-SUFFIX,tdesktop.com,TELEGRAM",
        "DOMAIN-KEYWORD,telegram,TELEGRAM",
        "DOMAIN-SUFFIX,discord.com,PROXY",
        "DOMAIN-SUFFIX,discordapp.com,PROXY",
        // Dev / AI
        "DOMAIN-SUFFIX,github.com,PROXY",
        "DOMAIN-SUFFIX,githubusercontent.com,PROXY",
        "DOMAIN-SUFFIX,githubassets.com,PROXY",
        "DOMAIN-SUFFIX,openai.com,PROXY",
        "DOMAIN-SUFFIX,chatgpt.com,PROXY",
        "DOMAIN-SUFFIX,anthropic.com,PROXY",
        "DOMAIN-SUFFIX,claude.ai,PROXY",
        // Media
        "DOMAIN-SUFFIX,netflix.com,PROXY",
        "DOMAIN-SUFFIX,nflxvideo.net,PROXY",
        "DOMAIN-SUFFIX,spotify.com,PROXY",
        "DOMAIN-SUFFIX,tiktok.com,PROXY",
        "DOMAIN-SUFFIX,tiktokcdn.com,PROXY",
        "DOMAIN-SUFFIX,reddit.com,PROXY",
        "DOMAIN-SUFFIX,redd.it,PROXY",
        // Common blocked
        "DOMAIN-SUFFIX,wikipedia.org,PROXY",
        "DOMAIN-SUFFIX,medium.com,PROXY",
        "DOMAIN-SUFFIX,dropbox.com,PROXY",
        "DOMAIN-SUFFIX,cloudflare.com,PROXY",
        "DOMAIN-SUFFIX,cloudfront.net,PROXY",
    ]
}
