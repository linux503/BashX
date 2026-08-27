package com.bashx.app.clash

import com.bashx.app.AppConstants
import com.bashx.app.data.Paths
import com.bashx.app.data.ProxyMode
import com.bashx.app.data.ProxyNode
import com.bashx.app.data.DnsPreference

object ConfigWriter {
    fun write(
        nodes: List<ProxyNode>,
        selectedName: String?,
        mode: ProxyMode,
        rules: List<String>,
        dnsPreference: DnsPreference,
        tunnelCapture: Boolean,
    ): Boolean {
        val yaml = build(
            nodes = nodes,
            selectedName = selectedName,
            mode = mode,
            rules = rules,
            dnsPreference = dnsPreference,
            tunnelCapture = tunnelCapture,
        )
        return runCatching {
            Paths.configFile.writeText(yaml)
            Paths.mihomoConfig.writeText(yaml)
            true
        }.getOrDefault(false)
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
                add("GOOGLE")
                add("AUTO")
                addAll(names)
                add("DIRECT")
            }
            if (selected != null) {
                removeAll { it == selected }
                add(0, selected)
            }
        }
        val preferred = preferredRegionNodes(names).ifEmpty { names }.ifEmpty { listOf("DIRECT") }
        val mixed = if (tunnelCapture) 0 else AppConstants.mixedPort
        val sb = StringBuilder()
        sb.appendLine("mixed-port: $mixed")
        sb.appendLine("allow-lan: false")
        sb.appendLine("bind-address: 127.0.0.1")
        sb.appendLine("mode: ${mode.name}")
        sb.appendLine("log-level: info")
        sb.appendLine("external-controller: ${AppConstants.externalController}")
        sb.appendLine("secret: \"\"")
        sb.appendLine("ipv6: false")
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
        (names.ifEmpty { listOf("DIRECT") }).forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("  - name: GOOGLE")
        sb.appendLine("    type: url-test")
        sb.appendLine("    url: https://www.gstatic.com/generate_204")
        sb.appendLine("    interval: 180")
        sb.appendLine("    tolerance: 50")
        sb.appendLine("    lazy: false")
        sb.appendLine("    expected-status: \"200/204\"")
        sb.appendLine("    proxies:")
        preferred.forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("  - name: TELEGRAM")
        sb.appendLine("    type: url-test")
        sb.appendLine("    url: https://api.telegram.org")
        sb.appendLine("    interval: 120")
        sb.appendLine("    tolerance: 50")
        sb.appendLine("    lazy: false")
        sb.appendLine("    expected-status: \"200/301/302/404\"")
        sb.appendLine("    proxies:")
        preferred.forEach { sb.appendLine("      - ${quote(it)}") }
        sb.appendLine("rules:")
        val finalRules = rewriteGoogle(rules.ifEmpty { listOf("MATCH,PROXY") })
        finalRules.forEach { sb.appendLine("  - ${quote(it)}") }
        return sb.toString()
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
            "\"${value.replace("\"", "\\\"")}\""
        } else value

    private fun quoteIfNeeded(value: String): String {
        if (value.equals("true", true) || value.equals("false", true)) return value.lowercase()
        if (value.toIntOrNull() != null) return value
        if (value.startsWith("{") || value.startsWith("[")) return value
        return quote(value)
    }
}
