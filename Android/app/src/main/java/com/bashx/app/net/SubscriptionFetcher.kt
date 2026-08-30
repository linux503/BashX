package com.bashx.app.net

import com.bashx.app.AppConstants
import com.bashx.app.data.SubscriptionUserInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit

class SubscriptionFetchError(message: String) : Exception(message)

object SubscriptionFetcher {
    private const val MAX_BODY_BYTES = 8L * 1024L * 1024L

    data class FetchResult(
        val data: ByteArray,
        val userInfo: SubscriptionUserInfo?,
        val suggestedName: String?,
    )

    private val userAgents = listOf(
        "clash.meta",
        "ClashMeta/1.19.0",
        "clash-verge/v2.0.0",
        "ClashX/1.118.0 (com.west2online.ClashX)",
        "ClashforWindows/0.20.39",
        "Stash/3.0.0 Clash/1.18.0",
        "Clash/1.18.0",
    )

    fun normalized(url: String): String? {
        val trimmed = url.trim()
        if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) return null
        return trimmed
    }

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .build()

    suspend fun fetch(urlString: String, viaProxyPort: Int? = null): FetchResult = withContext(Dispatchers.IO) {
        val url = normalized(urlString) ?: throw SubscriptionFetchError("链接无效")
        var last: Exception? = null
        for (ua in userAgents.take(4)) {
            try {
                return@withContext fetchOnce(url, ua, viaProxyPort)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                last = e
            }
        }
        throw last ?: SubscriptionFetchError("更新失败")
    }

    private fun fetchOnce(url: String, userAgent: String, proxyPort: Int?): FetchResult {
        val http = if (proxyPort != null && proxyPort > 0) {
            client.newBuilder()
                .proxy(Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", proxyPort)))
                .build()
        } else client
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent)
            .header("Accept", "*/*")
            .header("profile-update-interval", "true")
            .build()
        http.newCall(request).execute().use { resp ->
            if (!resp.isSuccessful) throw SubscriptionFetchError("HTTP ${resp.code}")
            val bodyBytes = resp.body ?: throw SubscriptionFetchError("订阅内容为空")
            val declared = bodyBytes.contentLength()
            if (declared > MAX_BODY_BYTES) {
                throw SubscriptionFetchError("订阅过大（>${MAX_BODY_BYTES / (1024 * 1024)}MB）")
            }
            val body = bodyBytes.bytes()
            if (body.isEmpty()) throw SubscriptionFetchError("订阅内容为空")
            if (body.size > MAX_BODY_BYTES) {
                throw SubscriptionFetchError("订阅过大（>${MAX_BODY_BYTES / (1024 * 1024)}MB）")
            }
            val preview = body.toString(Charsets.UTF_8).trimStart().take(240).lowercase()
            if (preview.startsWith("<!doctype") || preview.startsWith("<html") || preview.contains("<head")) {
                throw SubscriptionFetchError("服务器返回了网页，不是订阅内容")
            }
            val userInfo = SubscriptionUserInfo.parse(
                resp.header("subscription-userinfo") ?: resp.header("Subscription-Userinfo")
            )
            val suggested = resp.header("profile-title")?.removePrefix("base64:")
            return FetchResult(body, userInfo, suggested)
        }
    }

    suspend fun fetchOutboundIP(viaProxy: Boolean): String? = withContext(Dispatchers.IO) {
        val urls = listOf(
            "https://api.ipify.org",
            "https://ifconfig.me/ip",
            "https://icanhazip.com",
        )
        val clientBuilder = OkHttpClient.Builder()
            .connectTimeout(6, TimeUnit.SECONDS)
            .readTimeout(6, TimeUnit.SECONDS)
        if (viaProxy) {
            clientBuilder.proxy(Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", AppConstants.mixedPort)))
        }
        val client = clientBuilder.build()
        urls.firstNotNullOfOrNull { url ->
            runCatching {
                client.newCall(Request.Builder().url(url).build()).execute().use { resp ->
                    resp.body?.string()?.trim()?.takeIf { it.matches(Regex("""\d{1,3}(\.\d{1,3}){3}""")) }
                }
            }.getOrNull()
        }
    }
}
