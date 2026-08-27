package com.bashx.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.bashx.app.ui.AppState
import com.bashx.app.ui.fold.FoldMetrics
import com.bashx.app.ui.fold.LocalFold
import com.bashx.app.ui.screens.HomeScreen
import com.bashx.app.ui.screens.NodesScreen
import com.bashx.app.ui.screens.SettingsScreen
import com.bashx.app.ui.screens.SubscriptionsScreen
import com.bashx.app.ui.theme.BashXTheme

class MainActivity : ComponentActivity() {
    private val state: AppState by viewModels {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                AppState(application) as T
        }
    }

    private val vpnPermission = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        state.onVpnPermission(result.resultCode)
    }

    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val width = calculateWindowSizeClass(this).widthSizeClass
            val expanded = width != WindowWidthSizeClass.Compact
            CompositionLocalProvider(LocalFold provides if (expanded) FoldMetrics.inner else FoldMetrics.cover) {
                BashXRoot(
                    state = state,
                    expanded = expanded,
                    onNeedVpnPermission = {
                        state.vpnPrepareIntent()?.let { vpnPermission.launch(it) }
                    },
                )
            }
        }
    }
}

private data class Tab(val title: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("首页", Icons.Default.Home),
    Tab("节点", Icons.Default.AccountTree),
    Tab("订阅", Icons.Default.Inbox),
    Tab("设置", Icons.Default.Settings),
)

@Composable
private fun BashXRoot(
    state: AppState,
    expanded: Boolean,
    onNeedVpnPermission: () -> Unit,
) {
    val ui by state.ui.collectAsState()
    val colors = NavigationBarItemDefaults.colors(
        selectedIconColor = BashXTheme.accentDeep,
        selectedTextColor = BashXTheme.accentDeep,
        indicatorColor = BashXTheme.accentSoft,
    )
    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        containerColor = BashXTheme.grouped,
        bottomBar = {
            if (!expanded) {
                NavigationBar(containerColor = Color.White.copy(alpha = 0.94f), tonalElevation = 0.dp) {
                    tabs.forEachIndexed { i, tab ->
                        NavigationBarItem(
                            selected = ui.selectedTab == i,
                            onClick = { state.setTab(i) },
                            icon = { Icon(tab.icon, tab.title) },
                            label = { Text(tab.title) },
                            colors = colors,
                        )
                    }
                }
            }
        }
    ) { padding ->
        if (expanded) {
            Row(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(BashXTheme.grouped)
            ) {
                NavigationRail(
                    containerColor = Color.White.copy(alpha = 0.94f),
                    modifier = Modifier.width(80.dp),
                ) {
                    tabs.forEachIndexed { i, tab ->
                        NavigationRailItem(
                            selected = ui.selectedTab == i,
                            onClick = { state.setTab(i) },
                            icon = { Icon(tab.icon, tab.title) },
                            label = { Text(tab.title) },
                            colors = NavigationRailItemDefaults.colors(
                                selectedIconColor = BashXTheme.accentDeep,
                                selectedTextColor = BashXTheme.accentDeep,
                                indicatorColor = BashXTheme.accentSoft,
                            ),
                        )
                    }
                }
                Box(Modifier.weight(0.40f).fillMaxSize()) {
                    HomeScreen(state, onOpenNodes = { state.setTab(1) }, onNeedVpnPermission = onNeedVpnPermission)
                }
                Box(Modifier.weight(0.60f).fillMaxSize()) {
                    when (ui.selectedTab) {
                        0, 1 -> NodesScreen(state)
                        2 -> SubscriptionsScreen(state)
                        else -> SettingsScreen(state)
                    }
                }
            }
        } else {
            Box(Modifier.fillMaxSize().padding(padding)) {
                when (ui.selectedTab) {
                    0 -> HomeScreen(state, onOpenNodes = { state.setTab(1) }, onNeedVpnPermission = onNeedVpnPermission)
                    1 -> NodesScreen(state)
                    2 -> SubscriptionsScreen(state)
                    else -> SettingsScreen(state)
                }
            }
        }
    }
}
