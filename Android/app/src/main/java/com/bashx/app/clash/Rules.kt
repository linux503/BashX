package com.bashx.app.clash

import android.content.Context
import com.bashx.app.data.AppSettings

object ChinaSmartRules {
    const val version = 15

    fun load(context: Context): List<String> {
        val text = runCatching {
            context.assets.open("rules/bashx-smart-rules.txt").bufferedReader().use { it.readText() }
        }.getOrNull()
        val parsed = parseRulesText(text.orEmpty())
        return parsed.ifEmpty { embeddedFallback }
    }

    fun parseRulesText(text: String): List<String> =
        text.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .toList()

    fun needsUpgrade(rules: List<String>, storedVersion: Int): Boolean {
        if (storedVersion < version) return true
        if (rules.none { it.contains("telegram-cdn.org") }) return true
        if (rules.none { it.contains(",TELEGRAM") }) return true
        if (rules.none { it.contains("translate-pa.googleapis.com") }) return true
        return false
    }

    private val embeddedFallback = listOf(
        "DOMAIN-SUFFIX,local,REJECT",
        "DOMAIN-SUFFIX,localhost,DIRECT",
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "DOMAIN-SUFFIX,google.com,PROXY",
        "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
        "MATCH,PROXY",
    )
}

object RuntimeRules {
    fun effective(settings: AppSettings): List<String> {
        val prepend = settings.rulesPrepend
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") && !it.uppercase().startsWith("MATCH,") }
        val base = settings.rules.ifEmpty { emptyList() }
        val withPrepend = prepend + base
        val merged = if (settings.videoAdBlockEnabled) {
            VideoAdBlock.merge(into = withPrepend)
        } else {
            withPrepend.filter { !VideoAdBlock.isBrokenGeosite(it.trim()) }
        }
        val body = merged.filter { !it.trim().uppercase().startsWith("MATCH,") }
        return body + AndroidDirectDomains.rules + AndroidProxyDomains.rules + "MATCH,PROXY"
    }
}

object VideoAdBlock {
    private val geositePriority = listOf("GEOSITE,category-ads-all,REJECT")

    private val brokenGeositeRules = setOf(
        "GEOSITE,category-ads-cn,REJECT",
        "GEOSITE,category-ads-cn,DIRECT",
        "GEOSITE,category-ads-cn,PROXY",
    )

    @Volatile
    private var cachedRules: List<String>? = null

    val rules: List<String> get() = cachedRules ?: embeddedFallback

    val ruleCount: Int get() = geositePriority.size + rules.size

    fun warmUp(context: Context) {
        if (cachedRules != null) return
        cachedRules = loadFromAssets(context)
    }

    fun merge(into: List<String>): List<String> {
        val adDomains = rules.toSet()
        val cleaned = into.filter { rule ->
            val trimmed = rule.trim()
            trimmed !in adDomains
                && !isBrokenGeosite(trimmed)
                && !trimmed.uppercase().startsWith("GEOSITE,CATEGORY-ADS")
        }
        return geositePriority + rules + cleaned
    }

    fun isBrokenGeosite(rule: String): Boolean {
        val upper = rule.trim().uppercase()
        if (brokenGeositeRules.any { it.uppercase() == upper }) return true
        return upper.startsWith("GEOSITE,CATEGORY-ADS-CN,")
    }

    private fun loadFromAssets(context: Context): List<String> {
        val text = runCatching {
            context.assets.open("rules/bashx-adblock.txt").bufferedReader().use { it.readText() }
        }.getOrNull().orEmpty()
        val parsed = ChinaSmartRules.parseRulesText(text)
        return parsed.ifEmpty { embeddedFallback }
    }

    private val embeddedFallback = listOf(
        "DOMAIN-SUFFIX,doubleclick.net,REJECT",
        "DOMAIN-SUFFIX,googleadservices.com,REJECT",
        "DOMAIN-SUFFIX,googlesyndication.com,REJECT",
        "DOMAIN-SUFFIX,adservice.google.com,REJECT",
        "DOMAIN-KEYWORD,pagead,REJECT",
        "DOMAIN-SUFFIX,pangolin-sdk-toutiao.com,REJECT",
        "DOMAIN-SUFFIX,cupid.iqiyi.com,REJECT",
        "DOMAIN-SUFFIX,atm.youku.com,REJECT",
        "DOMAIN-SUFFIX,l.qq.com,REJECT",
        "DOMAIN-SUFFIX,e.qq.com,REJECT",
        "DOMAIN-SUFFIX,pgdt.gtimg.cn,REJECT",
        "DOMAIN-SUFFIX,umeng.com,REJECT",
        "DOMAIN-SUFFIX,tanx.com,REJECT",
        "DOMAIN-SUFFIX,sigmob.com,REJECT",
        "DOMAIN-SUFFIX,applovin.com,REJECT",
        "DOMAIN-SUFFIX,unityads.unity3d.com,REJECT",
        "DOMAIN-SUFFIX,alimama.com,REJECT",
        "DOMAIN,s.click.taobao.com,REJECT",
        "DOMAIN,u.jd.com,REJECT",
        "DOMAIN,union-click.jd.com,REJECT",
        "DOMAIN-SUFFIX,duomai.com,REJECT",
    )
}

object AndroidDirectDomains {
    val rules = listOf(
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,169.254.0.0/16,DIRECT,no-resolve",
        "DOMAIN-SUFFIX,local,DIRECT",
        "DOMAIN-SUFFIX,localhost,DIRECT",
        "DOMAIN-SUFFIX,qq.com,DIRECT",
        "DOMAIN-SUFFIX,weixin.qq.com,DIRECT",
        "DOMAIN-SUFFIX,wechat.com,DIRECT",
        "DOMAIN-KEYWORD,weixin,DIRECT",
        "DOMAIN-SUFFIX,baidu.com,DIRECT",
        "DOMAIN-SUFFIX,bdstatic.com,DIRECT",
        "DOMAIN-SUFFIX,taobao.com,DIRECT",
        "DOMAIN-SUFFIX,alipay.com,DIRECT",
        "DOMAIN-SUFFIX,aliyun.com,DIRECT",
        "DOMAIN-SUFFIX,alicdn.com,DIRECT",
        "DOMAIN-SUFFIX,jd.com,DIRECT",
        "DOMAIN-SUFFIX,bilibili.com,DIRECT",
        "DOMAIN-SUFFIX,zhihu.com,DIRECT",
        "DOMAIN-SUFFIX,amap.com,DIRECT",
        "DOMAIN-SUFFIX,163.com,DIRECT",
        "DOMAIN-SUFFIX,connectivitycheck.gstatic.com,DIRECT",
        "DOMAIN,connectivitycheck.android.com,DIRECT",
        "DOMAIN,www.msftconnecttest.com,DIRECT",
    )
}

object AndroidProxyDomains {
    val rules = listOf(
        "IP-CIDR,149.154.160.0/20,TELEGRAM,no-resolve",
        "IP-CIDR,91.108.0.0/16,TELEGRAM,no-resolve",
        "DOMAIN-SUFFIX,google.com,GOOGLE",
        "DOMAIN-SUFFIX,google.com.hk,GOOGLE",
        "DOMAIN-SUFFIX,googleapis.com,GOOGLE",
        "DOMAIN-SUFFIX,gstatic.com,GOOGLE",
        "DOMAIN-SUFFIX,googleusercontent.com,GOOGLE",
        "DOMAIN-SUFFIX,googlevideo.com,GOOGLE",
        "DOMAIN-SUFFIX,youtube.com,GOOGLE",
        "DOMAIN-SUFFIX,youtu.be,GOOGLE",
        "DOMAIN-SUFFIX,ytimg.com,GOOGLE",
        "DOMAIN-KEYWORD,google,GOOGLE",
        "DOMAIN-SUFFIX,twitter.com,PROXY",
        "DOMAIN-SUFFIX,x.com,PROXY",
        "DOMAIN-SUFFIX,twimg.com,PROXY",
        "DOMAIN-SUFFIX,facebook.com,PROXY",
        "DOMAIN-SUFFIX,instagram.com,PROXY",
        "DOMAIN-SUFFIX,telegram.org,TELEGRAM",
        "DOMAIN-SUFFIX,telegram-cdn.org,TELEGRAM",
        "DOMAIN-SUFFIX,t.me,TELEGRAM",
        "DOMAIN-SUFFIX,graph.org,TELEGRAM",
        "DOMAIN-KEYWORD,telegram,TELEGRAM",
        "DOMAIN-SUFFIX,github.com,PROXY",
        "DOMAIN-SUFFIX,openai.com,PROXY",
        "DOMAIN-SUFFIX,chatgpt.com,PROXY",
        "DOMAIN-SUFFIX,netflix.com,PROXY",
        "DOMAIN-SUFFIX,spotify.com,PROXY",
        "DOMAIN-SUFFIX,wikipedia.org,PROXY",
        "DOMAIN-SUFFIX,cloudflare.com,PROXY",
    )
}

object DnsProfile {
    fun yaml(preference: com.bashx.app.data.DnsPreference, listen: String): String {
        val cn = listOf(
            "https://223.5.5.5/dns-query",
            "https://1.12.12.12/dns-query",
            "https://doh.pub/dns-query",
        )
        val foreign = listOf(
            "https://8.8.8.8/dns-query",
            "https://1.1.1.1/dns-query",
            "8.8.8.8",
            "1.1.1.1",
        )
        val (nameserver, fallback) = when (preference) {
            com.bashx.app.data.DnsPreference.smart -> cn to foreign
            com.bashx.app.data.DnsPreference.domestic -> cn to (cn + foreign)
            com.bashx.app.data.DnsPreference.foreign -> foreign to foreign
        }
        fun list(items: List<String>) = items.joinToString("\n") { "    - $it" }
        return """
dns:
  enable: true
  listen: $listen
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-system-hosts: false
  respect-rules: false
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - +.local
    - +.lan
    - +.baidu.com
    - +.qq.com
    - +.weixin.qq.com
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
    - https://223.5.5.5/dns-query
  proxy-server-nameserver:
    - https://223.5.5.5/dns-query
    - https://doh.pub/dns-query
    - 119.29.29.29
  nameserver:
${list(nameserver)}
  fallback:
${list(fallback)}
  fallback-filter:
    geoip: false
    ipcidr:
      - 240.0.0.0/4
  direct-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  direct-nameserver-follow-policy: true
  nameserver-policy:
    "+.cn": ${cn.joinToString(",") { "\"$it\"" }}
    "+.baidu.com": ${cn.joinToString(",") { "\"$it\"" }}
    "+.qq.com": ${cn.joinToString(",") { "\"$it\"" }}
    "+.github.com": ${foreign.joinToString(",") { "\"$it\"" }}
    "+.google.com": ${foreign.joinToString(",") { "\"$it\"" }}
    "+.telegram.org": ${foreign.joinToString(",") { "\"$it\"" }}
    "+.x.com": ${foreign.joinToString(",") { "\"$it\"" }}
""".trimIndent()
    }
}
