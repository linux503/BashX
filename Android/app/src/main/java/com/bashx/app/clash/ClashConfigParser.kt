package com.bashx.app.clash

import android.util.Base64
import com.bashx.app.data.ProxyNode
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import java.io.ByteArrayInputStream
import java.net.URLDecoder
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream

class ConfigError(message: String) : Exception(message)

object ClashConfigParser {
    private val nonProxy = setOf(
        "direct", "reject", "select", "url-test", "fallback",
        "load-balance", "relay", "pass", "dns", "block", "selector", "urltest",
    )
    private val uriPrefixes = listOf(
        "ss://", "ssr://", "vmess://", "vless://", "trojan://",
        "hysteria2://", "hy2://", "hysteria://", "tuic://",
    )
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    data class ParseResult(val nodes: List<ProxyNode>)

    fun parse(bytes: ByteArray): ParseResult {
        if (bytes.isEmpty()) throw ConfigError("订阅内容为空")
        val text = normalizeToText(unwrapBytes(bytes))
        if (text.isBlank()) throw ConfigError("订阅内容为空")
        if (looksLikeHtml(text)) throw ConfigError("服务器返回了网页，不是订阅内容")

        val fromLinks = ShareLinkParser.parseLines(text)
        if (fromLinks.isNotEmpty() && (looksLikeURIList(text) || !looksLikeYamlOrJson(text))) {
            return ParseResult(nodesFromProxies(fromLinks))
        }

        val root = loadDocument(text)
        val proxyList = when (root) {
            is Map<*, *> -> collectProxies(root)
            is List<*> -> collectFromList(root)
            else -> emptyList()
        }
        if (proxyList.isNotEmpty()) return ParseResult(nodesFromProxies(proxyList))
        if (fromLinks.isNotEmpty()) return ParseResult(nodesFromProxies(fromLinks))
        throw ConfigError("无法解析订阅内容")
    }

    private fun looksLikeYamlOrJson(text: String): Boolean {
        val t = text.trimStart()
        return t.startsWith("{") || t.startsWith("[") ||
            t.contains("proxies:") || t.contains("Proxy:") ||
            t.contains("proxy-providers:") || t.contains("\nproxy:")
    }

    private fun loadDocument(text: String): Any? {
        val trimmed = text.trim()
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            parseJson(trimmed)?.let { return it }
        }
        loadYaml(trimmed)?.let { return it }
        if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
            parseJson(trimmed)?.let { return it }
        }
        return null
    }

    private fun loadYaml(text: String): Any? {
        val opts = LoaderOptions().apply {
            isAllowDuplicateKeys = true
            codePointLimit = 32 * 1024 * 1024
            maxAliasesForCollections = 10_000
            nestingDepthLimit = 200
        }
        return runCatching { Yaml(opts).load<Any>(text) }.getOrNull()
    }

    private fun parseJson(text: String): Any? =
        runCatching { jsonToAny(json.parseToJsonElement(text)) }.getOrNull()

    private fun jsonToAny(el: JsonElement): Any? = when (el) {
        is JsonNull -> null
        is JsonPrimitive -> when {
            el.isString -> el.content
            el.booleanOrNull != null -> el.booleanOrNull
            el.longOrNull != null -> el.longOrNull
            el.doubleOrNull != null -> el.doubleOrNull
            else -> el.contentOrNull
        }
        is JsonObject -> el.mapValues { jsonToAny(it.value) }
        is JsonArray -> el.map { jsonToAny(it) }
    }

    private fun collectProxies(root: Map<*, *>): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        addProxies(list, root["proxies"] ?: root["Proxy"] ?: root["proxy"] ?: root["outbounds"])
        val providers = root["proxy-providers"] as? Map<*, *>
        providers?.values?.forEach { v ->
            val dict = v as? Map<*, *> ?: return@forEach
            addProxies(list, dict["proxies"])
        }
        return list
    }

    private fun collectFromList(items: List<*>): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        addProxies(list, items)
        return list
    }

    private fun addProxies(list: MutableList<Map<String, Any>>, value: Any?) {
        val items = value as? List<*> ?: return
        items.forEach { item ->
            when (item) {
                is String -> ShareLinkParser.parseURI(item.trim())?.let { list += it }
                else -> {
                    val map = asStringMap(item) ?: return@forEach
                    if (isProxy(map)) list += map
                }
            }
        }
    }

    private fun isProxy(item: Map<String, Any>): Boolean {
        val type = item["type"]?.toString()?.lowercase().orEmpty()
        if (type.isEmpty() || type in nonProxy) return false
        val name = item["name"]?.toString().orEmpty()
            .ifEmpty { item["tag"]?.toString().orEmpty() }
        if (name.isEmpty()) return false
        if (name.equals("DIRECT", true) || name.equals("REJECT", true)) return false
        return true
    }

    fun isSpeedTestable(node: ProxyNode): Boolean {
        val type = node.type.lowercase()
        if (type in nonProxy) return false
        if (node.server.isBlank()) return false
        if (node.port <= 0 || node.port > 65535) return false
        val upper = node.name.uppercase()
        if (upper == "DIRECT" || upper == "REJECT") return false
        val infoNeedles = listOf(
            "剩余流量", "套餐到期", "距离下次", "Traffic:", "Expire:", "GB /", "GB/", "流量：", "流量:",
            "重置剩余", "套餐剩余", "已用流量", "到期时间",
        )
        if (infoNeedles.any { node.name.contains(it) }) return false
        return true
    }

    private fun nodesFromProxies(proxyList: List<Map<String, Any>>): List<ProxyNode> {
        val used = mutableSetOf<String>()
        return proxyList.mapNotNull { item ->
            var name = item["name"]?.toString()?.ifEmpty { item["tag"]?.toString() } ?: return@mapNotNull null
            val type = item["type"]?.toString() ?: return@mapNotNull null
            if (name in used) {
                var i = 2
                while ("$name ($i)" in used) i++
                name = "$name ($i)"
            }
            used += name
            val server = item["server"]?.toString().orEmpty()
            val port = intValue(item["port"]) ?: 0
            val raw = item.entries.associate { it.key.toString() to stringify(it.value) }.toMutableMap()
            raw["name"] = name
            ProxyNode(name = name, type = type, server = server, port = port, raw = raw)
        }
    }

    private fun unwrapBytes(data: ByteArray): ByteArray {
        if (data.size >= 2 && data[0] == 0x1f.toByte() && data[1] == 0x8b.toByte()) {
            return runCatching { GZIPInputStream(ByteArrayInputStream(data)).readBytes() }.getOrDefault(data)
        }
        if (data.size >= 2 && data[0] == 0x78.toByte()) {
            return runCatching { InflaterInputStream(ByteArrayInputStream(data)).readBytes() }.getOrDefault(data)
        }
        return data
    }

    private fun decodeCharset(data: ByteArray): String {
        if (data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte()) {
            return String(data, 3, data.size - 3, StandardCharsets.UTF_8)
        }
        if (data.size >= 2 && data[0] == 0xFF.toByte() && data[1] == 0xFE.toByte()) {
            return String(data, Charset.forName("UTF-16LE"))
        }
        if (data.size >= 2 && data[0] == 0xFE.toByte() && data[1] == 0xFF.toByte()) {
            return String(data, Charset.forName("UTF-16BE"))
        }
        return data.toString(StandardCharsets.UTF_8)
    }

    private fun normalizeToText(data: ByteArray): String {
        val raw = decodeCharset(data).trim().removePrefix("\uFEFF").trim()
        if (raw.isEmpty()) throw ConfigError("订阅内容为空")
        if (looksLikeHtml(raw)) return raw
        if (raw.contains("proxies:") || raw.contains("Proxy:") ||
            raw.contains("proxy-providers:") || raw.contains("outbounds") ||
            looksLikeURIList(raw) || hasShareLinks(raw)
        ) return raw
        decodeFlexibleBase64(raw)?.let { decodedBytes ->
            val decoded = decodeCharset(decodedBytes).trim().removePrefix("\uFEFF").trim()
            if (decoded.isNotEmpty() && (
                    decoded.contains("proxies:") || decoded.contains("Proxy:") ||
                        decoded.contains("proxy-providers:") || looksLikeURIList(decoded) ||
                        hasShareLinks(decoded) || decoded.startsWith("{") || decoded.startsWith("[")
                    )
            ) return decoded
        }
        return raw
    }

    private fun looksLikeHtml(text: String): Boolean {
        val s = text.trimStart().take(240).lowercase()
        return s.startsWith("<!doctype") || s.startsWith("<html") ||
            s.startsWith("<head") || s.contains("<html")
    }

    private fun looksLikeURIList(text: String): Boolean {
        val sample = contentLines(text).take(20).toList()
        if (sample.isEmpty()) return false
        return sample.any { line -> uriPrefixes.any { line.lowercase().startsWith(it) } }
    }

    private fun hasShareLinks(text: String): Boolean =
        contentLines(text).any { line -> uriPrefixes.any { line.lowercase().startsWith(it) } }

    private fun contentLines(text: String): Sequence<String> =
        text.replace("\r\n", "\n").replace("\r", "\n")
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") && !it.startsWith("//") }

    fun decodeFlexibleBase64(raw: String): ByteArray? {
        val cleaned = raw.filter { !it.isWhitespace() }.replace('-', '+').replace('_', '/')
        if (cleaned.length < 16 || cleaned.any { it !in BASE64_CHARS }) return null
        val padded = cleaned + "=".repeat((4 - cleaned.length % 4) % 4)
        val decoded = runCatching { Base64.decode(padded, Base64.DEFAULT) }.getOrNull() ?: return null
        return decoded.takeIf { it.isNotEmpty() }
    }

    private val BASE64_CHARS = ('A'..'Z') + ('a'..'z') + ('0'..'9') + '+' + '/' + '='

    private fun asStringMap(value: Any?): Map<String, Any>? {
        val map = value as? Map<*, *> ?: return null
        return map.entries.associate { it.key.toString() to (it.value ?: "") }
    }

    private fun intValue(value: Any?): Int? = when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Double -> value.toInt()
        is Float -> value.toInt()
        is String -> value.toIntOrNull()
        else -> null
    }

    private fun stringify(value: Any?): String = when (value) {
        null -> ""
        is Boolean, is Number -> value.toString()
        is Map<*, *> -> {
            val inner = value.entries.joinToString(", ") { "${it.key}: ${stringify(it.value)}" }
            "{$inner}"
        }
        is List<*> -> "[${value.joinToString(", ") { stringify(it) }}]"
        else -> value.toString()
    }
}

object ShareLinkParser {
    fun parseLines(text: String): List<Map<String, Any>> =
        text.replace("\r\n", "\n").replace("\r", "\n")
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { parseURI(it) }
            .toList()

    fun parseURI(line: String): Map<String, Any>? {
        val trimmed = line.trim().removePrefix("clash://")
        val lower = trimmed.lowercase()
        return when {
            lower.startsWith("ss://") -> parseShadowsocks(trimmed)
            lower.startsWith("trojan://") -> parseTrojan(trimmed)
            lower.startsWith("vmess://") -> parseVmess(trimmed)
            lower.startsWith("vless://") -> parseVless(trimmed)
            lower.startsWith("hysteria2://") || lower.startsWith("hy2://") -> parseHysteria2(trimmed)
            lower.startsWith("tuic://") -> parseTuic(trimmed)
            else -> null
        }
    }

    private fun parseShadowsocks(line: String): Map<String, Any>? {
        val withoutScheme = line.drop(5)
        val hashParts = withoutScheme.split("#", limit = 2)
        val main = hashParts[0]
        val name = if (hashParts.size > 1) decode(hashParts[1]) else "SS"
        val at = main.indexOf('@')
        if (at >= 0) {
            val user = main.substring(0, at)
            var hostPart = main.substring(at + 1)
            if ('?' in hostPart) hostPart = hostPart.substringBefore('?')
            hostPart = hostPart.trimEnd('/')
            val colon = hostPart.lastIndexOf(':')
            if (colon < 0) return null
            val port = hostPart.substring(colon + 1).toIntOrNull() ?: return null
            val host = hostPart.substring(0, colon).trim('[', ']')
            val methodPass = decodeUserInfo(user) ?: return null
            val parts = methodPass.split(":", limit = 2)
            if (parts.size != 2) return null
            return mapOf(
                "name" to name,
                "type" to "ss",
                "server" to host,
                "port" to port,
                "cipher" to parts[0],
                "password" to parts[1],
                "udp" to true,
            )
        }
        val decoded = ClashConfigParser.decodeFlexibleBase64(main)?.toString(StandardCharsets.UTF_8) ?: return null
        val at2 = decoded.lastIndexOf('@')
        if (at2 < 0) return null
        val userInfo = decoded.substring(0, at2)
        val hostPort = decoded.substring(at2 + 1)
        val mp = userInfo.split(":", limit = 2)
        val hp = hostPort.split(":", limit = 2)
        if (mp.size != 2 || hp.size != 2) return null
        val port = hp[1].toIntOrNull() ?: return null
        return mapOf(
            "name" to name,
            "type" to "ss",
            "server" to hp[0],
            "port" to port,
            "cipher" to mp[0],
            "password" to mp[1],
            "udp" to true,
        )
    }

    private fun parseTrojan(line: String): Map<String, Any>? {
        val parsed = parseUserHost(line.removePrefix("trojan://")) ?: return null
        val map = mutableMapOf<String, Any>(
            "name" to parsed.name.ifEmpty { "Trojan" },
            "type" to "trojan",
            "server" to parsed.host,
            "port" to parsed.port,
            "password" to parsed.user,
            "udp" to true,
        )
        parsed.query["sni"]?.let { map["sni"] = it }
        parsed.query["peer"]?.let { map.putIfAbsent("sni", it) }
        if (parsed.query["allowInsecure"] == "1" || parsed.query["insecure"] == "1") {
            map["skip-cert-verify"] = true
        }
        return map
    }

    private fun parseVmess(line: String): Map<String, Any>? {
        val payload = line.drop(8).substringBefore("#").trim()
        val decoded = ClashConfigParser.decodeFlexibleBase64(payload)?.toString(StandardCharsets.UTF_8) ?: return null
        val obj = runCatching {
            Json.parseToJsonElement(decoded) as? JsonObject
        }.getOrNull() ?: return null
        fun str(key: String) = (obj[key] as? JsonPrimitive)?.content?.takeIf { it.isNotEmpty() }
        val host = str("add") ?: return null
        val port = str("port")?.toIntOrNull() ?: return null
        val uuid = str("id") ?: return null
        val name = str("ps") ?: "VMess"
        val network = str("net") ?: "tcp"
        val map = mutableMapOf<String, Any>(
            "name" to name,
            "type" to "vmess",
            "server" to host,
            "port" to port,
            "uuid" to uuid,
            "alterId" to (str("aid")?.toIntOrNull() ?: 0),
            "cipher" to (str("scy") ?: "auto"),
            "network" to network,
            "udp" to true,
        )
        if (str("tls") == "tls" || str("tls") == "true") map["tls"] = true
        str("sni")?.let { map["servername"] = it }
        val path = str("path")
        val wsHost = str("host")
        when (network) {
            "ws" -> {
                val opts = mutableMapOf<String, Any>()
                if (!path.isNullOrEmpty()) opts["path"] = path
                if (!wsHost.isNullOrEmpty()) opts["headers"] = mapOf("Host" to wsHost)
                if (opts.isNotEmpty()) map["ws-opts"] = opts
            }
            "grpc" -> {
                val opts = mutableMapOf<String, Any>()
                (str("path") ?: str("serviceName"))?.let { opts["grpc-service-name"] = it }
                if (opts.isNotEmpty()) map["grpc-opts"] = opts
            }
            "h2", "http" -> {
                val opts = mutableMapOf<String, Any>()
                if (!path.isNullOrEmpty()) opts["path"] = path
                if (!wsHost.isNullOrEmpty()) opts["host"] = listOf(wsHost)
                if (opts.isNotEmpty()) map["h2-opts"] = opts
            }
        }
        return map
    }

    private fun parseVless(line: String): Map<String, Any>? {
        val parsed = parseUserHost(line.removePrefix("vless://")) ?: return null
        val q = parsed.query
        val network = q["type"] ?: q["network"] ?: "tcp"
        val map = mutableMapOf<String, Any>(
            "name" to parsed.name.ifEmpty { "VLESS" },
            "type" to "vless",
            "server" to parsed.host,
            "port" to parsed.port,
            "uuid" to parsed.user,
            "network" to network,
            "udp" to true,
            "encryption" to (q["encryption"] ?: "none"),
        )
        val security = q["security"].orEmpty()
        if (security == "tls" || security == "reality") map["tls"] = true
        (q["sni"] ?: q["servername"])?.let { map["servername"] = it }
        q["flow"]?.let { map["flow"] = it }
        q["fp"]?.let { map["client-fingerprint"] = it }
        if (q["allowInsecure"] == "1" || q["insecure"] == "1") map["skip-cert-verify"] = true
        when (network) {
            "ws" -> {
                val opts = mutableMapOf<String, Any>()
                q["path"]?.let { opts["path"] = it }
                q["host"]?.let { opts["headers"] = mapOf("Host" to it) }
                if (opts.isNotEmpty()) map["ws-opts"] = opts
            }
            "grpc" -> {
                val service = q["serviceName"] ?: q["path"]
                if (service != null) map["grpc-opts"] = mapOf("grpc-service-name" to service)
            }
        }
        if (security == "reality") {
            val reality = mutableMapOf<String, Any>()
            q["pbk"]?.let { reality["public-key"] = it }
            q["sid"]?.let { reality["short-id"] = it }
            if (reality.isNotEmpty()) map["reality-opts"] = reality
        }
        return map
    }

    private fun parseHysteria2(line: String): Map<String, Any>? {
        val stripped = line.substringAfter("://")
        val parsed = parseUserHost(stripped) ?: return null
        val map = mutableMapOf<String, Any>(
            "name" to parsed.name.ifEmpty { "Hysteria2" },
            "type" to "hysteria2",
            "server" to parsed.host,
            "port" to parsed.port,
            "password" to parsed.user,
            "udp" to true,
        )
        parsed.query["sni"]?.let { map["sni"] = it }
        if (parsed.query["insecure"] == "1" || parsed.query["insecure"] == "true") {
            map["skip-cert-verify"] = true
        }
        parsed.query["obfs"]?.let { map["obfs"] = it }
        parsed.query["obfs-password"]?.let { map["obfs-password"] = it }
        return map
    }

    private fun parseTuic(line: String): Map<String, Any>? {
        val parsed = parseUserHost(line.removePrefix("tuic://")) ?: return null
        val uuidPass = parsed.user.split(":", limit = 2)
        val map = mutableMapOf<String, Any>(
            "name" to parsed.name.ifEmpty { "TUIC" },
            "type" to "tuic",
            "server" to parsed.host,
            "port" to parsed.port,
            "udp" to true,
        )
        if (uuidPass.size == 2) {
            map["uuid"] = uuidPass[0]
            map["password"] = uuidPass[1]
        } else {
            map["uuid"] = parsed.user
        }
        parsed.query["sni"]?.let { map["sni"] = it }
        parsed.query["congestion_control"]?.let { map["congestion-controller"] = it }
        parsed.query["alpn"]?.let { map["alpn"] = listOf(it) }
        return map
    }

    private data class UserHost(
        val user: String,
        val host: String,
        val port: Int,
        val query: Map<String, String>,
        val name: String,
    )

    private fun parseUserHost(rest: String): UserHost? {
        val hashParts = rest.split("#", limit = 2)
        val name = if (hashParts.size > 1) decode(hashParts[1]) else ""
        val main = hashParts[0]
        val qIndex = main.indexOf('?')
        val query = if (qIndex >= 0) parseQuery(main.substring(qIndex + 1)) else emptyMap()
        val body = if (qIndex >= 0) main.substring(0, qIndex) else main
        val at = body.lastIndexOf('@')
        if (at < 0) return null
        val user = decode(body.substring(0, at))
        var hostPort = body.substring(at + 1).trimEnd('/')
        val colon = hostPort.lastIndexOf(':')
        if (colon < 0) return null
        val port = hostPort.substring(colon + 1).toIntOrNull() ?: return null
        val host = hostPort.substring(0, colon).trim('[', ']')
        if (host.isEmpty() || user.isEmpty()) return null
        return UserHost(user, host, port, query, name)
    }

    private fun parseQuery(raw: String): Map<String, String> =
        raw.split("&").mapNotNull { part ->
            val eq = part.indexOf('=')
            if (eq <= 0) return@mapNotNull null
            decode(part.substring(0, eq)) to decode(part.substring(eq + 1))
        }.toMap()

    private fun decodeUserInfo(user: String): String? {
        if (':' in user) return decode(user)
        return ClashConfigParser.decodeFlexibleBase64(user)?.toString(StandardCharsets.UTF_8)
    }

    private fun decode(value: String): String =
        runCatching { URLDecoder.decode(value.replace("+", "%2B"), Charsets.UTF_8.name()) }.getOrDefault(value)
}
