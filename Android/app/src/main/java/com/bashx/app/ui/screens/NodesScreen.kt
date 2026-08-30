package com.bashx.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bashx.app.data.ProxyNode
import com.bashx.app.ui.AppState
import com.bashx.app.ui.components.PageBackground
import com.bashx.app.ui.fold.LocalFold
import com.bashx.app.ui.theme.BashXTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NodesScreen(state: AppState) {
    val ui by state.ui.collectAsState()
    val fold = LocalFold.current
    PageBackground(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = fold.pagePad, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("节点", fontSize = fold.titleSize, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                IconButton(onClick = { state.toggleSort() }) {
                    Icon(
                        Icons.Default.SwapVert,
                        contentDescription = if (ui.sortByDelay) "按延迟" else "按名称",
                        modifier = Modifier.size(fold.iconSize),
                    )
                }
                IconButton(
                    onClick = { state.runSpeedTest() },
                    enabled = ui.nodes.isNotEmpty() && !ui.isTesting,
                ) {
                    Icon(
                        Icons.Default.Speed,
                        contentDescription = "测速",
                        tint = BashXTheme.accent,
                        modifier = Modifier.size(fold.iconSize),
                    )
                }
            }
            if (ui.nodes.isEmpty()) {
                Column(Modifier.fillMaxSize().padding(fold.pagePad * 2), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("暂无节点", fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    Text("在「订阅」页添加链接并更新，节点会按地区显示在这里。", color = Color.Gray)
                }
                return@Column
            }
            OutlinedTextField(
                value = ui.searchText,
                onValueChange = { state.setSearch(it) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = fold.pagePad),
                placeholder = { Text("搜索节点") },
                leadingIcon = { Icon(Icons.Default.Search, null) },
                singleLine = true,
            )
            Row(
                Modifier.horizontalScroll(rememberScrollState()).padding(fold.pagePad, 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Chip("全部", ui.selectedCategoryKey == null) { state.setCategory(null) }
                state.categorySummaries.forEach { g ->
                    Chip("${g.flag} ${g.title} ${g.nodes.size}", ui.selectedCategoryKey == g.key) {
                        state.setCategory(g.key)
                    }
                }
            }
            PullToRefreshBox(isRefreshing = ui.isTesting, onRefresh = { state.runSpeedTest() }) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(fold.nodeColumns),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = fold.pagePad, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    state.categoryGroups.forEach { group ->
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Text(
                                "${group.flag} ${group.title} · ${group.nodes.size}",
                                modifier = Modifier.padding(vertical = 8.dp),
                                fontWeight = FontWeight.SemiBold,
                                color = Color.Gray,
                            )
                        }
                        items(group.nodes, key = { it.name }) { node ->
                            NodeRow(node, selected = ui.settings.selectedNodeName == node.name) {
                                state.selectNode(node.name)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NodeRow(node: ProxyNode, selected: Boolean, onClick: () -> Unit) {
    val fold = LocalFold.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(if (fold.nodeColumns > 1) fold.cardRadius else 10.dp))
            .background(if (selected) BashXTheme.accentSoft else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(
                horizontal = if (fold.nodeColumns > 1) fold.cardPad else 4.dp,
                vertical = if (fold.isCover) 10.dp else 12.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(node.name, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
            Text(node.endpointSubtitle, fontSize = 12.sp, color = Color.Gray, maxLines = 1)
        }
        Text(node.delayText, color = BashXTheme.delayColor(node.delayMs), fontSize = if (fold.isCover) 13.sp else 14.sp)
        if (selected) {
            Spacer(Modifier.size(8.dp))
            Icon(Icons.Default.CheckCircle, null, tint = BashXTheme.accent, modifier = Modifier.size(fold.iconSize))
        }
    }
}

@Composable
private fun Chip(text: String, selected: Boolean, onClick: () -> Unit) {
    val fold = LocalFold.current
    Text(
        text,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (selected) BashXTheme.accent else BashXTheme.mist)
            .clickable(onClick = onClick)
            .padding(
                horizontal = if (fold.isCover) 12.dp else 16.dp,
                vertical = if (fold.isCover) 7.dp else 9.dp,
            ),
        color = if (selected) Color.White else Color.Black,
        fontSize = if (fold.isCover) 12.sp else 13.sp,
        fontWeight = FontWeight.Medium,
    )
}
