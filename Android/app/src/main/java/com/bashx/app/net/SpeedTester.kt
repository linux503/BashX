package com.bashx.app.net

import com.bashx.app.clash.ClashConfigParser
import com.bashx.app.data.ProxyNode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * Clash Verge / Stash style latency:
 * - Prefer mihomo `GET /proxies/{name}/delay` (URLTest through that node).
 * - TCP host:port only when controller is unavailable (reachability, not tunnel quality).
 */
object SpeedTester {
    data class Result(val name: String, val delayMs: Int)

    suspend fun testAll(
        nodes: List<ProxyNode>,
        timeoutMs: Int,
        concurrency: Int,
        controller: String? = null,
        secret: String = "",
        testURL: String,
        onProgress: suspend (String, Int) -> Unit,
    ): List<Result> = coroutineScope {
        val testables = nodes.filter { ClashConfigParser.isSpeedTestable(it) }
        if (testables.isEmpty()) return@coroutineScope emptyList()

        val apiTimeout = timeoutMs.coerceIn(2000, 8000)
        val limit = Semaphore(concurrency.coerceIn(1, 8))
        val catalog = if (controller != null) fetchProxyCatalog(controller, secret) else emptyMap()
        val urls = testURLCandidates(testURL)

        testables.map { node ->
            async(Dispatchers.IO) {
                limit.withPermit {
                    val delay = if (controller != null) {
                        apiDelay(node, controller, secret, apiTimeout, urls, catalog)
                    } else {
                        tcpDelay(node.server, node.port, apiTimeout)
                    }
                    onProgress(node.name, delay)
                    Result(node.name, delay)
                }
            }
        }.awaitAll()
    }

    private fun testURLCandidates(primary: String): List<String> {
        val out = linkedSetOf<String>()
        fun add(u: String) {
            val t = u.trim()
            if (t.isNotEmpty()) out += t
        }
        add(primary)
        add("http://www.gstatic.com/generate_204")
        add("http://cp.cloudflare.com/generate_204")
        add("http://www.msftconnecttest.com/connecttest.txt")
        return out.toList()
    }

    private fun fetchProxyCatalog(controller: String, secret: String): Map<String, String> {
        val client = apiClient(secret, 4000)
        val req = Request.Builder().url("http://$controller/proxies").build()
        val body = runCatching { client.newCall(req).execute().use { it.body?.string().orEmpty() } }
            .getOrDefault("")
        if (body.isBlank()) return emptyMap()
        val out = linkedMapOf<String, String>()
        runCatching {
            val proxies = JSONObject(body).optJSONObject("proxies") ?: return@runCatching
            for (key in proxies.keys()) {
                val obj = proxies.optJSONObject(key) ?: continue
                val type = obj.optString("type").lowercase()
                if (type in setOf("direct", "reject", "select", "url-test", "fallback", "load-balance", "relay", "pass", "compatible")) {
                    continue
                }
                out[key] = key
                val server = obj.optString("server")
                val port = obj.optInt("port", 0)
                if (server.isNotBlank() && port > 0) {
                    out["${server.lowercase()}:$port"] = key
                }
            }
        }
        return out
    }

    private fun resolveProxyName(node: ProxyNode, catalog: Map<String, String>): String {
        catalog[node.name]?.let { return it }
        return catalog["${node.server.lowercase()}:${node.port}"] ?: node.name
    }

    /** Fallback: TCP connect RTT. Prefer IPv4 to avoid Happy Eyeballs ~1s stall. */
    private fun tcpDelay(host: String, port: Int, timeoutMs: Int): Int {
        if (host.isBlank() || port <= 0) return -1
        val start = System.nanoTime()
        return try {
            val address = resolveIPv4(host) ?: InetAddress.getByName(host)
            Socket().use { socket ->
                socket.connect(InetSocketAddress(address, port), timeoutMs.coerceAtLeast(500))
            }
            ((System.nanoTime() - start) / 1_000_000L).toInt().coerceAtLeast(1)
        } catch (_: Exception) {
            -1
        }
    }

    private fun resolveIPv4(host: String): InetAddress? = runCatching {
        InetAddress.getAllByName(host).firstOrNull { it is Inet4Address }
    }.getOrNull()

    private fun apiDelay(
        node: ProxyNode,
        controller: String,
        secret: String,
        timeoutMs: Int,
        urls: List<String>,
        catalog: Map<String, String>,
    ): Int {
        val name = resolveProxyName(node, catalog)
        for (testURL in urls) {
            val ms = apiDelayOnce(name, controller, secret, timeoutMs, testURL)
            if (ms > 0) return ms
        }
        return -1
    }

    private fun apiDelayOnce(
        name: String,
        controller: String,
        secret: String,
        timeoutMs: Int,
        testURL: String,
    ): Int {
        val encoded = encodePath(name)
        val url = "http://$controller/proxies/$encoded/delay" +
            "?timeout=${timeoutMs.coerceAtLeast(2000)}&url=${URLEncoder.encode(testURL, Charsets.UTF_8.name())}"
        val client = apiClient(secret, timeoutMs + 3000)
        return runCatching {
            client.newCall(Request.Builder().url(url).get().build()).execute().use { resp ->
                if (!resp.isSuccessful) return@use -1
                val body = resp.body?.string().orEmpty()
                val json = runCatching { JSONObject(body) }.getOrNull() ?: return@use -1
                if (json.has("message") && !json.has("delay")) return@use -1
                val delay = json.optInt("delay", -1)
                if (delay <= 0 || delay >= 60_000) -1 else delay
            }
        }.getOrDefault(-1)
    }

    private fun encodePath(value: String): String {
        val allowed = (('a'..'z') + ('A'..'Z') + ('0'..'9') + "-._~").toSet()
        return buildString {
            for (ch in value) {
                if (ch in allowed) append(ch) else append(URLEncoder.encode(ch.toString(), Charsets.UTF_8.name()))
            }
        }
    }

    private fun apiClient(secret: String, timeoutMs: Int): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            .proxy(java.net.Proxy.NO_PROXY) // API call must not go through system / mixed-port proxy
        if (secret.isNotBlank()) {
            builder.addInterceptor { chain ->
                chain.proceed(
                    chain.request().newBuilder()
                        .header("Authorization", "Bearer $secret")
                        .build()
                )
            }
        }
        return builder.build()
    }
}
