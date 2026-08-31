package com.bashx.app.clash

import com.bashx.app.AppConstants
import com.bashx.app.data.Paths
import com.bashx.app.data.ProxyMode
import com.bashx.app.data.ProxyNode
import com.bashx.app.data.DnsPreference
import java.io.File

object ConfigWriter {
    fun write(
        nodes: List<ProxyNode>,
        selectedName: String?,
        mode: ProxyMode,
        rules: List<String>,
        dnsPreference: DnsPreference,
        tunnelCapture: Boolean,
        profileRoot: Map<String, Any>? = null,
    ): Boolean {
        val yaml = if (profileRoot != null && ClashConfigParser.isCompleteProfile(profileRoot)) {
            buildPassthrough(
                root = profileRoot,
                mode = mode,
                dnsPreference = dnsPreference,
                tunnelCapture = tunnelCapture,
            )
        } else {
            build(
                nodes = nodes,
                selectedName = selectedName,
                mode = mode,
                rules = rules,
                dnsPreference = dnsPreference,
                tunnelCapture = tunnelCapture,
            )
        }
        return runCatching {
            atomicWrite(Paths.configFile, yaml)
            atomicWrite(Paths.mihomoConfig, yaml)
            true
        }.getOrDefault(false)
    }

    /** Keep subscription proxy-groups + rules; inject ports / TUN / controller. */
    fun buildPassthrough(
        root: Map<String, Any>,
        mode: ProxyMode,
        dnsPreference: DnsPreference,
        tunnelCapture: Boolean,
    ): String {
        val mutable = linkedMapOf<String, Any>().also { out ->
            root.forEach { (k, v) -> out[k] = v }
        }
        listOf(
            "mixed-port", "port", "socks-port", "redir-port", "tproxy-port",
            "allow-lan", "bind-address", "mode", "log-level",
            "external-controller", "secret", "external-ui", "external-ui-name", "external-ui-url",
            "tun",
        ).forEach { mutable.remove(it) }

        val mixed = if (tunnelCapture) 0 else AppConstants.mixedPort
        mutable["mixed-port"] = mixed
        mutable["allow-lan"] = false
        mutable["bind-address"] = "127.0.0.1"
        mutable["mode"] = mode.name
        mutable["log-level"] = "warning"
        mutable["external-controller"] = AppConstants.externalController
        mutable["secret"] = ""
        if (!mutable.containsKey("ipv6")) mutable["ipv6"] = true
        mutable["geodata-mode"] = false
        mutable["geo-auto-update"] = false
        mutable["find-process-mode"] = "off"
        if (!mutable.containsKey("tcp-concurrent")) mutable["tcp-concurrent"] = true
        if (tunnelCapture) {
            mutable["tun"] = linkedMapOf(
                "enable" to true,
                "stack" to "gvisor",
                "auto-route" to false,
                "auto-detect-interface" to false,
                "strict-route" to false,
                "mtu" to AppConstants.defaultMTU,
                "dns-hijack" to listOf("${AppConstants.tunDNS}:53", "any:53"),
            )
        }
        val needsDns = !mutable.containsKey("dns")
        val dumped = org.yaml.snakeyaml.Yaml().dump(mutable).trimEnd()
        return if (needsDns) {
            dumped + "\n" + DnsProfile.yaml(dnsPreference, AppConstants.dnsListen).trimEnd() + "\n"
        } else {
            dumped + "\n"
        }
    }

    private fun atomicWrite(file: File, text: String) {
        val parent = file.parentFile ?: error("no parent")
        if (!parent.exists()) parent.mkdirs()
        val tmp = File(parent, "${file.name}.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) {
            file.writeText(text)
            tmp.delete()
        }
    }

    fun build(
        nodes: List<ProxyNode>,
        selectedName: String?,
        mode: ProxyMode,
        rules: List<String>,
        dnsPreference: DnsPreference,
        tunnelCapture: Boolean,
    ): String {
        val names = nodes.map { it.name }
        val selected = selectedName?.takeIf { it in names }
        val proxyGroup = buildList {
            if (names.isEmpty()) add("DIRECT")
            else {
                // No GOOGLE/AI here — those groups must not form a PROXY loop.
                add("AUTO")
                add("JP")
                add("HK")
                add("US")
                addAll(names)
                add("DIRECT")
            }
            if (selected != null) {
                removeAll { it == selected }
                add(0, selected)
            }
        }
        val preferred = preferredRegionNodes(names).ifEmpty { names }.ifEmpty { listOf("DIRECT") }
        val autoPool = preferred.take(36).ifEmpty { listOf("DIRECT") }
        val mixed = if (tunnelCapture) 0 else AppConstants.mixedPort
        val sb = StringBuilder()
        sb.appendLine("mixed-port: $mixed")
        sb.appendLine("allow-lan: false")
        sb.appendLine("bind-address: 127.0.0.1")
        sb.appendLine("mode: ${mode.name}")
        sb.appendLine("log-level: warning")
        sb.appendLine("external-controller: ${AppConstants.externalController}")
        sb.appendLine("secret: \"\"")
        sb.appendLine("ipv6: true")
        sb.appendLine("geodata-mode: false")
        sb.appendLine("geo-auto-update: false")
        sb.appendLine("find-process-mode: off")
        sb.appendLine("tcp-concurrent: true")
        sb.appendLine(DnsProfile.yaml(dnsPreference, AppConstants.dnsListen))
        sb.appendLine("sniffer:")
        sb.appendLine("  enable: true")
        sb.appendLine("  force-dns-mapping: true")
        sb.appendLine("  parse-pure-ip: true")
        sb.appendLine("  override-destination: false")
        sb.appendLine("  sniff:")
        sb.appendLine("    TLS:")
        sb.appendLine("      ports: [443, 8443]")
        sb.appendLine("    HTTP:")
        sb.appendLine("      ports: [80, 8080]")
        if (tunnelCapture) {
            sb.appendLine("tun:")
            sb.appendLine("  enable: true")
            sb.appendLine("  stack: gvisor")
            sb.appendLine("  auto-route: false")
            sb.appendLine("  auto-detect-interface: false")
            sb.appendLine("  strict-route: false")
            sb.appendLine("  mtu: ${AppConstants.defaultMTU}")
            sb.appendLine("  dns-hijack:")
            sb.appendLine("    - ${AppConstants.tunDNS}:53")
            sb.appendLine("    - any:53")
        }
        sb.appendLine("proxies:")
        if (nodes.isEmpty()) sb.appendLine("  []")
        else nodes.forEach { sb.append(dumpProxy(it)) }
        sb.appendLine("proxy-groups:")
        sb.appendLine("  - name: PROXY")
        sb.appendLine("    type: select")
        sb.appendLine("    proxies:")
        proxyGroup.forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("  - name: AUTO")
        sb.appendLine("    type: url-test")
        sb.appendLine("    url: https://www.gstatic.com/generate_204")
        sb.appendLine("    interval: 300")
        sb.appendLine("    tolerance: 50")
        sb.appendLine("    lazy: true")
        sb.appendLine("    proxies:")
        autoPool.forEach { sb.appendLine("      - ${quote(it)}") }
        val jpPool = regionPool(names, listOf("日本", "JP", "Japan", "东京", "大阪", "Tokyo"))
        val hkPool = regionPool(names, listOf("香港", "HK", "Hong Kong"))
        val usPool = regionPool(names, listOf("美国", "US", "USA", "America", "洛杉矶", "西雅图"))
        fun appendUrlTest(name: String, pool: List<String>, interval: Int = 600) {
            sb.appendLine("  - name: $name")
            sb.appendLine("    type: url-test")
            sb.appendLine("    url: https://www.gstatic.com/generate_204")
            sb.appendLine("    interval: $interval")
            sb.appendLine("    tolerance: 50")
            sb.appendLine("    lazy: true")
            sb.appendLine("    proxies:")
            pool.ifEmpty { listOf("DIRECT") }.forEach { sb.appendLine("      - ${quote(it)}") }
        }
        appendUrlTest("JP", jpPool)
        appendUrlTest("HK", hkPool)
        appendUrlTest("US", usPool)
        appendUrlTest("GOOGLE-AUTO", autoPool, 180)
        sb.appendLine("  - name: GOOGLE")
        sb.appendLine("    type: select")
        sb.appendLine("    proxies:")
        listOfNotNull(
            jpPool.takeIf { it.isNotEmpty() }?.let { "JP" },
            hkPool.takeIf { it.isNotEmpty() }?.let { "HK" },
            "GOOGLE-AUTO", "DIRECT"
        ).forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("  - name: TELEGRAM")
        sb.appendLine("    type: url-test")
        sb.appendLine("    url: https://api.telegram.org")
        sb.appendLine("    interval: 180")
        sb.appendLine("    tolerance: 50")
        sb.appendLine("    lazy: true")
        sb.appendLine("    expected-status: \"200/301/302/404\"")
        sb.appendLine("    proxies:")
        autoPool.forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("  - name: APNS")
        sb.appendLine("    type: select")
        sb.appendLine("    proxies:")
        (listOf("PROXY") + autoPool + listOf("DIRECT")).distinct()
            .forEach { sb.appendLine("      - ${quote(it)}") }
        listOf("CURSOR", "OPENAI", "ANTHROPIC").forEach { g ->
            sb.appendLine("  - name: $g")
            sb.appendLine("    type: select")
            sb.appendLine("    proxies:")
            autoPool.forEach { sb.appendLine("      - ${quote(it)}") }
        }
        sb.appendLine("  - name: AI")
        sb.appendLine("    type: select")
        sb.appendLine("    proxies:")
        (listOf("US") + usPool.ifEmpty { autoPool } + listOf("DIRECT")).distinct()
            .forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("rules:")
        val finalRules = rewriteGoogle(rules.ifEmpty { listOf("MATCH,PROXY") }).toMutableList().also { list ->
            val inject = listOf(
                "DOMAIN-SUFFIX,cursor.sh,CURSOR",
                "DOMAIN-SUFFIX,cursor.com,CURSOR",
                "DOMAIN-SUFFIX,openai.com,OPENAI",
                "DOMAIN-SUFFIX,chatgpt.com,OPENAI",
                "DOMAIN-SUFFIX,anthropic.com,ANTHROPIC",
                "DOMAIN-SUFFIX,claude.ai,ANTHROPIC",
                "DOMAIN-SUFFIX,grok.com,AI",
                "DOMAIN-SUFFIX,perplexity.ai,AI",
            )
            inject.reversed().forEach { rule ->
                if (list.none { it.contains(rule.substringBeforeLast(',').substringAfter(',')) }) {
                    list.add(0, rule)
                }
            }
        }
        finalRules.forEach { sb.appendLine("  - ${quote(it)}") }
        return sb.toString()
    }

    private fun regionPool(names: List<String>, keys: List<String>): List<String> {
        val matched = names.filter { name -> keys.any { name.contains(it, ignoreCase = true) } }
        return (if (matched.size >= 2) matched else names).take(36)
    }

    private fun dumpProxy(node: ProxyNode): String {
        val keys = (listOf("name", "type", "server", "port") + node.raw.keys)
            .distinct()
            .filter { it !in setOf("raw") }
        val sb = StringBuilder()
        sb.appendLine("  - name: ${quote(node.name)}")
        keys.filter { it != "name" }.forEach { key ->
            val value = when (key) {
                "type" -> node.type
                "server" -> node.server.ifEmpty { node.raw["server"].orEmpty() }
                "port" -> if (node.port > 0) node.port.toString() else node.raw["port"].orEmpty()
                else -> node.raw[key].orEmpty()
            }
            if (value.isBlank()) return@forEach
            if (value.contains('\n')) return@forEach
            sb.appendLine("    $key: ${quoteIfNeeded(value)}")
        }
        if (node.raw["udp"].isNullOrBlank() && node.type.lowercase() in listOf("vmess", "vless", "trojan", "ss", "ssr", "hysteria", "hysteria2", "tuic")) {
            sb.appendLine("    udp: true")
        }
        return sb.toString()
    }

    private fun preferredRegionNodes(names: List<String>): List<String> {
        val keys = listOf(
            "香港", "HK", "Hong Kong", "台湾", "TW", "Singapore", "新加坡", "SG",
            "日本", "JP", "韩国", "KR", "美国", "US", "英国", "UK", "德国", "DE", "荷兰", "NL"
        )
        val preferred = names.filter { name -> keys.any { name.contains(it, ignoreCase = true) } }
        return if (preferred.size >= 4) preferred else names
    }

    private fun rewriteGoogle(rules: List<String>): List<String> {
        return rules.map { rule ->
            val parts = rule.split(",")
            if (parts.size < 3) return@map rule
            val type = parts[0].uppercase()
            val payload = parts[1].lowercase()
            val policy = parts[2].uppercase()
            if (policy != "PROXY" && policy != "AUTO") return@map rule
            val isGoogle = when (type) {
                "GEOSITE" -> payload == "google" || payload == "youtube"
                "DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD" ->
                    payload.contains("google") || payload.contains("gstatic") ||
                        payload.contains("youtube") || payload.contains("googleapis")
                else -> false
            }
            if (!isGoogle) rule else parts.toMutableList().also { it[2] = "GOOGLE" }.joinToString(",")
        }
    }

    private fun quote(value: String): String =
        if (value.any { it in ":,[]{}#&*!|>'\"%@`" } || value.startsWith(" ") || value.isEmpty()) {
            "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
        } else value

    private fun quoteIfNeeded(value: String): String {
        if (value.equals("true", true) || value.equals("false", true)) return value.lowercase()
        if (value.toIntOrNull() != null) return value
        if (value.startsWith("{") || value.startsWith("[")) return value
        return quote(value)
    }
}
