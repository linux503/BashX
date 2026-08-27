package com.bashx.app.clash

import com.bashx.app.data.ProxyNode

object NodeCategory {
    data class Group(
        val key: String,
        val title: String,
        val flag: String,
        val nodes: List<ProxyNode>,
    )

    private val titles = mapOf(
        "GAT" to ("港澳台" to "🇭🇰"),
        "JK" to ("日韩" to "🇯🇵"),
        "SEA" to ("东南亚" to "🇸🇬"),
        "HK" to ("香港" to "🇭🇰"),
        "MO" to ("澳门" to "🇲🇴"),
        "TW" to ("台湾" to "🇹🇼"),
        "SG" to ("新加坡" to "🇸🇬"),
        "JP" to ("日本" to "🇯🇵"),
        "KR" to ("韩国" to "🇰🇷"),
        "US" to ("美国" to "🇺🇸"),
        "CA" to ("加拿大" to "🇨🇦"),
        "GB" to ("英国" to "🇬🇧"),
        "DE" to ("德国" to "🇩🇪"),
        "FR" to ("法国" to "🇫🇷"),
        "NL" to ("荷兰" to "🇳🇱"),
        "AU" to ("澳大利亚" to "🇦🇺"),
        "IN" to ("印度" to "🇮🇳"),
        "TR" to ("土耳其" to "🇹🇷"),
        "RU" to ("俄罗斯" to "🇷🇺"),
        "OTHER" to ("未识别" to "🏳️"),
        "SPARSE" to ("其他" to "🌐"),
    )

    private val keywords = listOf(
        "香港" to "HK", "HK" to "HK", "Hong Kong" to "HK",
        "澳门" to "MO", "澳門" to "MO", "MO" to "MO",
        "台湾" to "TW", "台灣" to "TW", "TW" to "TW", "Taiwan" to "TW",
        "新加坡" to "SG", "SG" to "SG", "Singapore" to "SG",
        "日本" to "JP", "JP" to "JP", "东京" to "JP", "大阪" to "JP", "Japan" to "JP",
        "韩国" to "KR", "韓國" to "KR", "KR" to "KR", "首尔" to "KR", "Korea" to "KR",
        "美国" to "US", "美國" to "US", "US" to "US", "USA" to "US", "Los Angeles" to "US",
        "英国" to "GB", "英國" to "GB", "UK" to "GB", "GB" to "GB", "London" to "GB",
        "德国" to "DE", "德國" to "DE", "DE" to "DE", "Frankfurt" to "DE",
        "法国" to "FR", "法國" to "FR", "FR" to "FR",
        "荷兰" to "NL", "荷蘭" to "NL", "NL" to "NL", "Amsterdam" to "NL",
        "加拿大" to "CA", "CA" to "CA",
        "澳洲" to "AU", "澳大利亚" to "AU", "AU" to "AU",
        "泰国" to "SG", "越南" to "SG", "菲律宾" to "SG", "马来" to "SG", "印尼" to "SG",
        "印度" to "IN", "土耳其" to "TR", "俄罗斯" to "RU",
    )

    private val gat = setOf("HK", "MO", "TW")
    private val jk = setOf("JP", "KR")
    private val sea = setOf("SG")
    private val order = listOf("GAT", "JK", "SEA", "US", "CA", "GB", "DE", "FR", "NL", "AU", "IN", "TR", "RU")

    fun classify(name: String): Triple<String, String, String> {
        val raw = rawCountry(name)
        val region = bucket(raw)
        val meta = titles[region] ?: titles.getValue("OTHER")
        return Triple(region, meta.first, meta.second)
    }

    fun groups(nodes: List<ProxyNode>, sortByDelay: Boolean): List<Group> {
        val assignment = nodes.associate { it.name to bucket(rawCountry(it.name)) }
        val counts = assignment.values.groupingBy { it }.eachCount()
        val finalKey = assignment.mapValues { (_, region) ->
            if ((counts[region] ?: 0) <= 1 && region !in setOf("GAT", "JK", "SEA", "HK", "TW", "JP", "KR", "US", "GB", "DE")) {
                "SPARSE"
            } else region
        }
        return nodes.groupBy { finalKey[it.name] ?: "OTHER" }
            .map { (key, list) ->
                val sorted = if (sortByDelay) list.sortedWith(delayComparator) else list.sortedBy { it.name }
                val meta = titles[key] ?: titles.getValue("OTHER")
                Group(key, meta.first, meta.second, sorted)
            }
            .sortedWith(compareBy({ order.indexOf(it.key).let { i -> if (i < 0) 999 else i } }, { it.title }))
    }

    private fun bucket(country: String): String = when {
        country in gat -> "GAT"
        country in jk -> "JK"
        country in sea -> "SEA"
        country == "UK" -> "GB"
        else -> country
    }

    private fun rawCountry(name: String): String {
        keywords.forEach { (kw, code) ->
            if (name.contains(kw, ignoreCase = true)) return code
        }
        return "OTHER"
    }

    private val delayComparator = Comparator<ProxyNode> { a, b ->
        val ra = rank(a.delayMs)
        val rb = rank(b.delayMs)
        if (ra != rb) ra.compareTo(rb) else a.name.compareTo(b.name)
    }

    private fun rank(ms: Int?): Int = when {
        ms == null -> 1_000_000_000
        ms < 0 -> 1_000_000_001
        else -> ms
    }
}
