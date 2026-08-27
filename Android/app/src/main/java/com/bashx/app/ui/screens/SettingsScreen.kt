package com.bashx.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bashx.app.AppConstants
import com.bashx.app.BuildConfig
import com.bashx.app.clash.ChinaSmartRules
import com.bashx.app.data.ByteFormat
import com.bashx.app.data.DnsPreference
import com.bashx.app.data.Paths
import com.bashx.app.ui.AppState
import com.bashx.app.ui.L10n
import com.bashx.app.ui.UiState
import com.bashx.app.ui.components.BashCard
import com.bashx.app.ui.components.FoldButtonModifier
import com.bashx.app.ui.components.PageBackground
import com.bashx.app.ui.fold.LocalFold
import com.bashx.app.ui.theme.BashXTheme
import com.bashx.app.vpn.MihomoBridge
import com.bashx.app.vpn.VpnController

@Composable
fun SettingsScreen(state: AppState) {
    val ui by state.ui.collectAsState()
    val vpnStatus by state.vpn.status.collectAsState()
    val fold = LocalFold.current

    PageBackground(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(fold.pagePad)
        ) {
            Text(L10n.t("settings", ui.settings.uiLanguage), fontSize = fold.titleSize, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(12.dp))
            LanguageSection(state, ui)
            if (fold.settingsColumns == 1) {
                ConnectionSection(state, ui, vpnStatus)
                SpeedSection(state, ui)
                ProxySection(state, ui)
                DnsSection(state, ui)
                RulesSection(state, ui)
                DiagSection()
                AboutSection(ui)
            } else {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Column(Modifier.weight(1f)) {
                        ConnectionSection(state, ui, vpnStatus)
                        SpeedSection(state, ui)
                        ProxySection(state, ui)
                    }
                    Column(Modifier.weight(1f)) {
                        DnsSection(state, ui)
                        RulesSection(state, ui)
                        DiagSection()
                        AboutSection(ui)
                    }
                }
            }
            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun ConnectionSection(state: AppState, ui: UiState, vpnStatus: VpnController.Status) {
    Section("连接") {
        Line("连接", state.vpn.statusText)
        if (vpnStatus == VpnController.Status.connected) {
            val dur = (System.currentTimeMillis() - state.vpn.connectedSince) / 1000
            Line("时长", formatDuration(dur))
            Line("下行累计", ByteFormat.size(state.vpn.downloadBytes))
            Line("上行累计", ByteFormat.size(state.vpn.uploadBytes))
        }
        Line("节点", ui.settings.selectedNodeName ?: "—")
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("出站 IP", modifier = Modifier.weight(1f))
            Text(if (ui.outboundIPLoading) "查询中…" else ui.outboundIP, color = Color.Gray, fontFamily = FontFamily.Monospace)
            TextButton(onClick = { state.runRefreshOutboundIP() }, enabled = vpnStatus == VpnController.Status.connected) {
                Text("刷新")
            }
        }
        OutlinedButton(
            onClick = { state.vpn.stop() },
            enabled = vpnStatus != VpnController.Status.idle,
            modifier = FoldButtonModifier(),
        ) {
            Text("断开 VPN", color = BashXTheme.bad)
        }
    }
}

@Composable
private fun SpeedSection(state: AppState, ui: UiState) {
    Section("测速") {
        Line("超时", "${ui.settings.testTimeoutMs} ms")
        Slider(
            value = ui.settings.testTimeoutMs.toFloat(),
            onValueChange = { v -> state.updateSettings { it.copy(testTimeoutMs = v.toInt().coerceIn(1000, 8000)) } },
            valueRange = 1000f..8000f,
            steps = 13,
        )
        Line("并发", "${ui.settings.concurrency}")
        Slider(
            value = ui.settings.concurrency.toFloat(),
            onValueChange = { v -> state.updateSettings { it.copy(concurrency = v.toInt().coerceIn(2, 16)) } },
            valueRange = 2f..16f,
            steps = 13,
        )
    }
}

@Composable
private fun ProxySection(state: AppState, ui: UiState) {
    Section("代理模式") {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(if (ui.settings.tunEnabled) "TUN 全量（推荐）" else "HTTP 代理（实验）")
                Text(
                    if (ui.settings.tunEnabled) "捕获全部 App 流量。"
                    else "仅支持 HTTP 代理的 App；微信等可能不走代理。",
                    fontSize = 12.sp,
                    color = Color.Gray,
                )
            }
            Switch(ui.settings.tunEnabled, onCheckedChange = { state.setTunnelCapture(it) })
        }
        Text("切换后请断开再连接 VPN。HTTP 代理模式走 127.0.0.1:${AppConstants.mixedPort}。", fontSize = 12.sp, color = Color.Gray)
    }
}

@Composable
private fun DnsSection(state: AppState, ui: UiState) {
    Section("DNS") {
        DnsPreference.entries.forEach { pref ->
            Row(
                Modifier.fillMaxWidth().padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(pref.title, fontWeight = if (ui.settings.dnsPreference == pref) FontWeight.SemiBold else FontWeight.Normal)
                    Text(pref.subtitle, fontSize = 11.sp, color = Color.Gray)
                }
                Switch(ui.settings.dnsPreference == pref, onCheckedChange = { if (it) state.setDns(pref) })
            }
        }
        Text("修改 DNS 后请重新连接 VPN。", fontSize = 12.sp, color = Color.Gray)
    }
}

@Composable
private fun LanguageSection(state: AppState, ui: UiState) {
    val lang = ui.settings.uiLanguage
    Section(L10n.t("lang", lang)) {
        com.bashx.app.data.UiLanguage.entries.forEach { item ->
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(item.pickerTitle(), modifier = Modifier.weight(1f))
                Switch(lang == item, onCheckedChange = { if (it) state.setUiLanguage(item) })
            }
        }
    }
}

@Composable
private fun RulesSection(state: AppState, ui: UiState) {
    val lang = ui.settings.uiLanguage
    Section(L10n.t("routing", lang)) {
        Line("规则版本", "v${if (ui.settings.rulesVersion > 0) ui.settings.rulesVersion else ChinaSmartRules.version}")
        Line("生效条数", "${state.effectiveRules().size}")
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L10n.t("adblock", lang), modifier = Modifier.weight(1f))
            Switch(ui.settings.videoAdBlockEnabled, onCheckedChange = { state.setVideoAdBlock(it) })
        }
        Button(onClick = { state.applySmartRules() }, modifier = FoldButtonModifier()) {
            Text("恢复智能规则 v${ChinaSmartRules.version}")
        }
        Text("去广告默认开启：视频广告、开屏 SDK、电商跳转广告域。", fontSize = 12.sp, color = Color.Gray)
    }
}

@Composable
private fun DiagSection() {
    Section("诊断") {
        Line("Mihomo 内核", when {
            MihomoBridge.isAvailable -> "已加载 ${MihomoBridge.version()}"
            else -> "未加载${MihomoBridge.loadError?.let { "：$it" } ?: ""}"
        })
        Line("配置文件", if (Paths.mihomoConfig.exists()) "正常" else "缺失")
        val log = runCatching { Paths.tunnelLog.readText() }.getOrDefault("（无日志）")
        Text(log.takeLast(2000).ifBlank { "（无日志）" }, fontSize = 11.sp, fontFamily = FontFamily.Monospace, color = Color.Gray)
    }
}

@Composable
private fun AboutSection(ui: UiState) {
    val lang = ui.settings.uiLanguage
    Section(L10n.t("about", lang)) {
        Line(L10n.t("version", lang), "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        Text("BashX for Android · VpnService + Mihomo", fontSize = 12.sp, color = Color.Gray)
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Text(title, color = Color.Gray, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
    BashCard { content() }
    Spacer(Modifier.height(10.dp))
}

@Composable
private fun Line(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Text(value, color = Color.Gray)
    }
}

private fun formatDuration(total: Long): String {
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}
