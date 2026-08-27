package com.bashx.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bashx.app.data.Subscription
import com.bashx.app.ui.AppState
import com.bashx.app.ui.components.BashCard
import com.bashx.app.ui.components.FoldButtonModifier
import com.bashx.app.ui.components.PageBackground
import com.bashx.app.ui.fold.LocalFold
import com.bashx.app.ui.theme.BashXTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionsScreen(state: AppState) {
    val ui by state.ui.collectAsState()
    val fold = LocalFold.current
    var showAdd by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }

    LaunchedEffect(ui.pendingAddSubscription) {
        if (ui.pendingAddSubscription) {
            showAdd = true
            state.consumePendingAdd()
        }
    }

    PageBackground(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(fold.pagePad),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("订阅", fontSize = fold.titleSize, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                IconButton(onClick = { showAdd = true }) {
                    Icon(Icons.Default.Add, contentDescription = "添加订阅", tint = BashXTheme.accent)
                }
            }
            if (ui.settings.subscriptions.isEmpty()) {
                Column(Modifier.fillMaxSize().padding(fold.pagePad * 2), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("添加订阅", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    Text("粘贴 Clash 或机场订阅链接，更新后即可获取节点。", color = Color.Gray)
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = { showAdd = true },
                        colors = ButtonDefaults.buttonColors(containerColor = BashXTheme.accent),
                        modifier = FoldButtonModifier(),
                    ) { Text("添加订阅") }
                }
            } else {
                PullToRefreshBox(isRefreshing = ui.isBusy, onRefresh = { state.refreshAll() }) {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(fold.subColumns),
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = fold.pagePad, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            BashCard(Modifier.padding(bottom = 12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Column {
                                        Text("${ui.settings.subscriptions.size}", fontWeight = FontWeight.SemiBold, fontSize = 22.sp)
                                        Text("订阅", fontSize = 12.sp, color = Color.Gray)
                                    }
                                    Spacer(Modifier.padding(12.dp))
                                    Column {
                                        Text("${ui.nodes.size}", fontWeight = FontWeight.SemiBold, fontSize = 22.sp)
                                        Text("节点", fontSize = 12.sp, color = Color.Gray)
                                    }
                                    Spacer(Modifier.weight(1f))
                                    OutlinedButton(
                                        onClick = { state.refreshAll() },
                                        enabled = !ui.isBusy,
                                        modifier = Modifier.height(fold.buttonHeight),
                                    ) {
                                        Text("全部更新")
                                    }
                                }
                            }
                        }
                        items(ui.settings.subscriptions, key = { it.id }) { sub ->
                            SubscriptionCard(state, sub, busy = ui.isBusy)
                        }
                    }
                }
            }
        }
    }

    if (showAdd) {
        AlertDialog(
            onDismissRequest = { showAdd = false },
            title = { Text("添加订阅") },
            text = {
                Column {
                    OutlinedTextField(name, { name = it }, label = { Text("名称") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(url, { url = it }, label = { Text("订阅链接") }, modifier = Modifier.fillMaxWidth())
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    state.addSubscription(name, url)
                    name = ""; url = ""; showAdd = false
                }) { Text("添加") }
            },
            dismissButton = { TextButton(onClick = { showAdd = false }) { Text("取消") } },
        )
    }
}

@Composable
private fun SubscriptionCard(state: AppState, sub: Subscription, busy: Boolean) {
    BashCard(Modifier.padding(bottom = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(sub.name.ifEmpty { "未命名订阅" }, fontWeight = FontWeight.Bold)
                Text(
                    sub.updatedAtEpoch?.let {
                        SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA).format(Date(it))
                    } ?: "尚未更新",
                    fontSize = 12.sp,
                    color = if (sub.updatedAtEpoch == null) BashXTheme.warn else Color.Gray,
                )
            }
            Switch(sub.enabled, onCheckedChange = { state.setSubscriptionEnabled(sub.id, it) })
        }
        Text(sub.url, fontSize = 12.sp, color = Color.Gray, maxLines = 2)
        sub.userInfo?.usedRatio?.let { ratio ->
            Spacer(Modifier.height(6.dp))
            LinearProgressIndicator(progress = { ratio.toFloat() }, modifier = Modifier.fillMaxWidth(), color = BashXTheme.accent)
            Text(sub.userInfo.trafficSummary, fontSize = 11.sp, color = Color.Gray)
        }
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = { state.refreshOne(sub.id) },
            enabled = !busy,
            modifier = FoldButtonModifier(),
            colors = ButtonDefaults.buttonColors(containerColor = BashXTheme.accent),
        ) { Text(if (busy) "更新中…" else "更新此订阅") }
        TextButton(onClick = { state.removeSubscription(sub.id) }) {
            Text("删除", color = BashXTheme.bad)
        }
    }
}
