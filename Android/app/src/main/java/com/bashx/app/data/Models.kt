package com.bashx.app.data

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class ProxyMode(val title: String, val subtitle: String) {
    rule("规则", "按规则分流"),
    global("全局", "全部走代理"),
    direct("直连", "全部直连");
}

@Serializable
enum class DnsPreference(val title: String, val shortTitle: String, val subtitle: String) {
    smart("智能分流", "智能", "国内站走阿里/腾讯 DoH，国外站自动回落 Cloudflare/Google（默认）"),
    domestic("国内优选", "国内", "默认使用国内 DNS，国外域名再回落海外解析，适合日常国内浏览"),
    foreign("国外优选", "国外", "默认使用 Cloudflare/Google，国内域名走专用国内 DNS，适合海外节点为主");
}

@Serializable
data class ProxyNode(
    val name: String,
    val type: String,
    val server: String,
    val port: Int,
    val raw: Map<String, String> = emptyMap(),
    val delayMs: Int? = null,
) {
    val id: String get() = name
    val delayCacheKey: String get() = "${server.lowercase()}:$port|${type.lowercase()}"
    val delayText: String
        get() {
            val d = delayMs ?: return "—"
            return if (d < 0) "超时" else "$d ms"
        }
    /** Many airports share one entry IP; include port so rows look distinct. */
    val endpointSubtitle: String
        get() {
            val t = type.uppercase()
            if (server.isEmpty()) return t
            if (port <= 0) return "$t · $server"
            return if (server.contains(":") && !server.startsWith("[")) {
                "$t · [$server]:$port"
            } else {
                "$t · $server:$port"
            }
        }
}

@Serializable
data class SubscriptionUserInfo(
    val upload: Long = 0,
    val download: Long = 0,
    val total: Long = 0,
    val expireAtEpoch: Long? = null,
) {
    val used: Long get() = maxOf(0, upload) + maxOf(0, download)
    val remaining: Long? get() = if (total > 0) maxOf(0, total - used) else null
    val usedRatio: Double? get() = if (total > 0) (used.toDouble() / total).coerceIn(0.0, 1.0) else null
    val remainingText: String
        get() = remaining?.let { ByteFormat.size(it) } ?: if (total > 0) "0 B" else "不限"
    val totalText: String get() = if (total > 0) ByteFormat.size(total) else "不限"
    val expireRelativeText: String
        get() {
            val exp = expireAtEpoch ?: return "未知"
            val days = ((exp * 1000L - System.currentTimeMillis()) / 86_400_000L).toInt()
            return when {
                days < 0 -> "已过期"
                days == 0 -> "今日到期"
                days < 30 -> "剩 $days 天"
                else -> "有效"
            }
        }
    val trafficSummary: String
        get() = "剩 $remainingText/$totalText · $expireRelativeText"

    companion object {
        fun parse(headerRaw: String?): SubscriptionUserInfo? {
            var raw = headerRaw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            raw = runCatching { java.net.URLDecoder.decode(raw, Charsets.UTF_8.name()) }.getOrDefault(raw)
            val map = mutableMapOf<String, Long>()
            raw.split(';', ',', '&').forEach { part ->
                val piece = part.trim()
                val eq = piece.indexOf('=')
                if (eq <= 0) return@forEach
                val key = piece.substring(0, eq).trim().lowercase()
                val value = piece.substring(eq + 1).trim().toLongOrNull() ?: return@forEach
                map[key] = value
            }
            if (map.isEmpty()) return null
            val expire = map["expire"]
            return SubscriptionUserInfo(
                upload = map["upload"] ?: 0,
                download = map["download"] ?: 0,
                total = map["total"] ?: 0,
                expireAtEpoch = expire?.takeIf { it > 0 },
            )
        }
    }
}

@Serializable
data class Subscription(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val url: String,
    val updatedAtEpoch: Long? = null,
    val enabled: Boolean = true,
    val userInfo: SubscriptionUserInfo? = null,
)

@Serializable
enum class UiLanguage {
    system, zh, en;

    fun pickerTitle(): String = when (this) {
        system -> "System · 跟随系统"
        zh -> "中文"
        en -> "English"
    }
}

@Serializable
data class AppSettings(
    val subscriptions: List<Subscription> = emptyList(),
    val selectedNodeName: String? = null,
    val testURL: String = "http://www.gstatic.com/generate_204",
    val testTimeoutMs: Int = 4000,
    val concurrency: Int = 6,
    val mixedPort: Int = 17890,
    val externalController: String = "127.0.0.1:19090",
    val secret: String = "",
    val tunEnabled: Boolean = true,
    val videoAdBlockEnabled: Boolean = true,
    val dnsPreference: DnsPreference = DnsPreference.smart,
    val proxyMode: ProxyMode = ProxyMode.rule,
    val rules: List<String> = emptyList(),
    val rulesPrepend: List<String> = emptyList(),
    val rulesVersion: Int = 0,
    val nodeDelayCache: Map<String, Int> = emptyMap(),
    val closeConnectionsOnSwitch: Boolean = true,
    val uiLanguage: UiLanguage = UiLanguage.system,
)
