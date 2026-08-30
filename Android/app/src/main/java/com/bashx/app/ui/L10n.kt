package com.bashx.app.ui

import com.bashx.app.data.UiLanguage
import java.util.Locale

object L10n {
    fun t(key: String, language: UiLanguage): String {
        val code = language.code()
        val row = table[key] ?: return key
        return row[code] ?: row["zh"] ?: key
    }

    private val table: Map<String, Map<String, String>> = mapOf(
        "settings" to mapOf("zh" to "设置", "en" to "Settings"),
        "lang" to mapOf("zh" to "语言", "en" to "Language"),
        "lang.system" to mapOf("zh" to "跟随系统", "en" to "System"),
        "lang.zh" to mapOf("zh" to "中文", "en" to "Chinese"),
        "lang.en" to mapOf("zh" to "English", "en" to "English"),
        "adblock" to mapOf("zh" to "去广告", "en" to "Ad Block"),
        "routing" to mapOf("zh" to "分流", "en" to "Routing"),
        "about" to mapOf("zh" to "关于", "en" to "About"),
        "version" to mapOf("zh" to "版本", "en" to "Version"),
        "home" to mapOf("zh" to "首页", "en" to "Home"),
        "nodes" to mapOf("zh" to "节点", "en" to "Nodes"),
        "subs" to mapOf("zh" to "订阅", "en" to "Subscriptions"),
    )
}

fun UiLanguage.code(): String = when (this) {
    UiLanguage.zh -> "zh"
    UiLanguage.en -> "en"
    UiLanguage.system -> {
        val id = Locale.getDefault().language
        if (id.startsWith("zh")) "zh" else "en"
    }
}
