package com.bashx.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bashx.app.data.ProxyMode
import com.bashx.app.ui.AppState
import com.bashx.app.ui.components.BashCard
import com.bashx.app.ui.components.BrandMark
import com.bashx.app.ui.components.ConnectButton
import com.bashx.app.ui.components.FoldButtonModifier
import com.bashx.app.ui.components.PageBackground
import com.bashx.app.ui.components.StatusPill
import com.bashx.app.ui.fold.LocalFold
import com.bashx.app.ui.theme.BashXTheme
import com.bashx.app.vpn.MihomoBridge
import com.bashx.app.vpn.VpnController

@Composable
fun HomeScreen(state: AppState, onOpenNodes: () -> Unit, onNeedVpnPermission: () -> Unit = {}) {
    val ui by state.ui.collectAsState()
    val vpnStatus by state.vpn.status.collectAsState()
    val fold = LocalFold.current
    var showMode by remember { mutableStateOf(false) }
    var showTools by remember { mutableStateOf(false) }

    LaunchedEffect(vpnStatus) {
        if (vpnStatus == VpnController.Status.connected) {
            state.refreshGroups()
            state.refreshOutboundIP()
        }
    }

    val statusLabel = when {
        vpnStatus == VpnController.Status.connected || vpnStatus == VpnController.Status.connecting -> state.vpn.statusText
        ui.nodes.isEmpty() -> "请先添加订阅"
        ui.settings.selectedNodeName == null -> "请选择节点"
        else -> state.vpn.statusText
    }
    val subtitle = when {
        vpnStatus == VpnController.Status.connected -> "已加密连接 · 流量受保护"
        vpnStatus == VpnController.Status.connecting -> "正在建立安全隧道…"
        ui.nodes.isEmpty() -> "添加订阅后即可一键连接"
        else -> "一键连接 · 智能分流保护隐私"
    }

    PageBackground(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = fold.pagePad, vertical = if (fold.isCover) 10.dp else 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BrandMark()
            Spacer(Modifier.height(if (fold.isCover) 8.dp else 12.dp))
            Text("BashX", fontSize = fold.titleSize, fontWeight = FontWeight.Black, color = BashXTheme.ink)
            Text(subtitle, color = androidx.compose.ui.graphics.Color.Gray, fontSize = fold.subtitleSize)
            Spacer(Modifier.height(if (fold.isCover) 12.dp else 16.dp))
            StatusPill(statusLabel, vpnStatus)
            if (!MihomoBridge.isAvailable) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "当前安装包没有 VPN 内核，点连接不会真正翻墙。订阅、节点、测速可以先用。",
                    color = BashXTheme.warn,
                    fontSize = 12.sp,
                )
            }
            Spacer(Modifier.height(8.dp))
            Box {
                TextButton(onClick = { showMode = true }) {
                    val color = when (ui.settings.proxyMode) {
                        ProxyMode.rule -> BashXTheme.accent
                        ProxyMode.global -> BashXTheme.warn
                        ProxyMode.direct -> androidx.compose.ui.graphics.Color.Gray
                    }
                    Box(Modifier.size(if (fold.isCover) 7.dp else 8.dp).clip(CircleShape).background(color))
                    Spacer(Modifier.size(6.dp))
                    Text(ui.settings.proxyMode.title, fontWeight = FontWeight.SemiBold, color = BashXTheme.ink)
                    Icon(Icons.Default.ExpandMore, null, Modifier.size(fold.iconSize * 0.64f))
                }
                DropdownMenu(showMode, onDismissRequest = { showMode = false }) {
                    ProxyMode.entries.forEach { mode ->
                        DropdownMenuItem(
                            text = { Text("${mode.title} · ${mode.subtitle}") },
                            onClick = { state.setMode(mode); showMode = false },
                        )
                    }
                }
            }
            BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                val connect = fold.connectSize.coerceAtMost(maxWidth * 0.78f)
                ConnectButton(vpnStatus, enabled = true, size = connect) {
                    val prep = state.vpnPrepareIntent()
                    if (prep != null) onNeedVpnPermission()
                    else state.runToggleVPN()
                }
            }
            if (ui.nodes.isEmpty() && vpnStatus != VpnController.Status.connected) {
                Spacer(Modifier.height(8.dp))
                BashCard {
                    Text("首次使用", fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text("1. 添加订阅链接")
                    Text("2. 更新并选择节点")
                    Text("3. 点连接，允许 VPN 权限")
                    Spacer(Modifier.height(10.dp))
                    Button(
                        onClick = { state.openAddSubscription() },
                        colors = ButtonDefaults.buttonColors(containerColor = BashXTheme.accent),
                        modifier = FoldButtonModifier(),
                    ) { Text("去添加订阅") }
                }
            }
            state.vpn.lastError?.takeIf { it.isNotBlank() }?.let { err ->
                Spacer(Modifier.height(8.dp))
                Text(err, color = BashXTheme.bad, fontSize = 12.sp)
            }
            Spacer(Modifier.height(if (fold.isCover) 12.dp else 16.dp))
            BashCard(Modifier.clickable(enabled = ui.nodes.isNotEmpty()) { onOpenNodes() }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(fold.locationIcon)
                            .clip(CircleShape)
                            .background(BashXTheme.accentGradient),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Default.Place,
                            null,
                            tint = androidx.compose.ui.graphics.Color.White,
                            modifier = Modifier.size(fold.iconSize),
                        )
                    }
                    Spacer(Modifier.size(if (fold.isCover) 12.dp else 16.dp))
                    Column(Modifier.weight(1f)) {
                        Text("连接位置", fontSize = 12.sp, color = androidx.compose.ui.graphics.Color.Gray)
                        Text(ui.settings.selectedNodeName ?: "选择节点", fontWeight = FontWeight.SemiBold, maxLines = 1)
                        val node = state.selectedNode
                        Text(
                            when {
                                node != null -> "${node.type.uppercase()} · ${node.delayText}"
                                ui.nodes.isEmpty() -> "请先添加订阅"
                                else -> "${ui.nodes.size} 个节点可用"
                            },
                            fontSize = 12.sp,
                            color = BashXTheme.delayColor(node?.delayMs),
                        )
                    }
                    Icon(Icons.Default.ChevronRight, null, tint = BashXTheme.accent, modifier = Modifier.size(fold.iconSize))
                }
            }
            if (vpnStatus == VpnController.Status.connected) {
                Spacer(Modifier.height(12.dp))
                if (ui.proxyGroups.isEmpty()) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = BashXTheme.accent)
                        Spacer(Modifier.size(8.dp))
                        Text("加载策略组…", fontSize = 12.sp, color = androidx.compose.ui.graphics.Color.Gray)
                        Spacer(Modifier.weight(1f))
                        TextButton(onClick = { state.runRefreshGroups() }) { Text("刷新") }
                    }
                } else {
                    Column(Modifier.fillMaxWidth()) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text("策略组", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = androidx.compose.ui.graphics.Color.Gray)
                            Spacer(Modifier.weight(1f))
                            IconButton(onClick = { state.runRefreshGroups() }) {
                                Icon(Icons.Default.Refresh, null, tint = BashXTheme.accent)
                            }
                        }
                        ui.proxyGroups.forEach { group ->
                            var open by remember(group.name) { mutableStateOf(false) }
                            BashCard(Modifier.padding(bottom = 8.dp).clickable { open = true }) {
                                Row {
                                    Text(group.name, fontWeight = FontWeight.Bold, color = BashXTheme.accentDeep, modifier = Modifier.size(width = 88.dp, height = 20.dp))
                                    Text(group.now.ifEmpty { "—" }, maxLines = 1, modifier = Modifier.weight(1f))
                                }
                                DropdownMenu(open, onDismissRequest = { open = false }) {
                                    group.all.take(60).forEach { name ->
                                        DropdownMenuItem(
                                            text = { Text(if (name == group.now) "✓ $name" else name) },
                                            onClick = {
                                                state.runSelectGroup(group.name, name)
                                                open = false
                                            },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Metric("下行", com.bashx.app.data.ByteFormat.rate(0), Modifier.weight(1f))
                    Metric("上行", com.bashx.app.data.ByteFormat.rate(0), Modifier.weight(1f))
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(
                Modifier.fillMaxWidth().clickable { showTools = !showTools },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("快捷控制", color = androidx.compose.ui.graphics.Color.Gray, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                Icon(if (showTools) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null, tint = androidx.compose.ui.graphics.Color.Gray)
            }
            AnimatedVisibility(showTools) {
                Column {
                    Spacer(Modifier.height(8.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        com.bashx.app.data.DnsPreference.entries.forEach { pref ->
                            val selected = ui.settings.dnsPreference == pref
                            Box(
                                Modifier
                                    .weight(1f)
                                    .height(fold.buttonHeight)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(if (selected) BashXTheme.accent else BashXTheme.accentSoft)
                                    .clickable { state.setDns(pref) },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    pref.title,
                                    color = if (selected) androidx.compose.ui.graphics.Color.White else BashXTheme.accentDeep,
                                    fontSize = if (fold.isCover) 12.sp else 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        Mini("测速", ui.nodes.isEmpty() || ui.isTesting) { state.runSpeedTest() }
                        Mini("最快", ui.nodes.isEmpty() || ui.isTesting) { state.runSpeedTest(true) }
                        Mini("节点", false) { onOpenNodes() }
                    }
                }
            }
            if (ui.statusText.isNotBlank() && ui.statusText !in setOf("就绪", "未连接", "已连接", "连接中…")) {
                Spacer(Modifier.height(8.dp))
                Text(ui.statusText, fontSize = 12.sp, color = androidx.compose.ui.graphics.Color.Gray)
            }
            Spacer(Modifier.height(36.dp))
        }
    }
}

@Composable
private fun Metric(title: String, value: String, modifier: Modifier) {
    val fold = LocalFold.current
    Column(
        modifier
            .clip(RoundedCornerShape(fold.cardRadius))
            .background(BashXTheme.mist)
            .padding(fold.cardPad)
    ) {
        Text(title, fontSize = 12.sp, color = androidx.compose.ui.graphics.Color.Gray)
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun RowScope.Mini(title: String, disabled: Boolean, onClick: () -> Unit) {
    val fold = LocalFold.current
    Box(
        Modifier
            .weight(1f)
            .height(fold.buttonHeight)
            .clip(RoundedCornerShape(fold.cardRadius))
            .background(BashXTheme.accentSoft)
            .clickable(enabled = !disabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, color = BashXTheme.accentDeep, fontWeight = FontWeight.SemiBold)
    }
}
