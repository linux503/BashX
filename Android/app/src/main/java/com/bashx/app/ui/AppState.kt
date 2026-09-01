package com.bashx.app.ui

import android.app.Activity
import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.bashx.app.AppConstants
import com.bashx.app.clash.ChinaSmartRules
import com.bashx.app.clash.ClashConfigParser
import com.bashx.app.clash.ConfigWriter
import com.bashx.app.clash.NodeCategory
import com.bashx.app.clash.RuntimeRules
import com.bashx.app.clash.VideoAdBlock
import com.bashx.app.data.AppSettings
import com.bashx.app.data.DnsPreference
import com.bashx.app.data.Paths
import com.bashx.app.data.ProxyMode
import com.bashx.app.data.ProxyNode
import com.bashx.app.data.SettingsStore
import com.bashx.app.data.Subscription
import com.bashx.app.net.SpeedTester
import com.bashx.app.net.SubscriptionFetcher
import com.bashx.app.vpn.VpnController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class UiState(
    val settings: AppSettings = AppSettings(),
    val nodes: List<ProxyNode> = emptyList(),
    val statusText: String = "就绪",
    val isBusy: Boolean = false,
    val isTesting: Boolean = false,
    val testedCount: Int = 0,
    val searchText: String = "",
    val sortByDelay: Boolean = true,
    val selectedCategoryKey: String? = null,
    val outboundIP: String = "—",
    val outboundIPLoading: Boolean = false,
    val selectedTab: Int = 0,
    val pendingAddSubscription: Boolean = false,
    val proxyGroups: List<VpnController.GroupSnapshot> = emptyList(),
)

class AppState(app: Application) : AndroidViewModel(app) {
    val vpn = VpnController(app)
    private val _ui = MutableStateFlow(UiState())
    val ui = _ui.asStateFlow()

    private var persistJob: Job? = null

    init {
        VideoAdBlock.warmUp(app)
        var settings = SettingsStore.load()
        settings = settings.copy(
            externalController = AppConstants.externalController,
            mixedPort = AppConstants.mixedPort,
        )
        val bundled = ChinaSmartRules.load(app)
        if (ChinaSmartRules.needsUpgrade(settings.rules, settings.rulesVersion) || settings.rules.isEmpty()) {
            settings = settings.copy(rules = bundled, rulesVersion = ChinaSmartRules.version)
        }
        _ui.value = _ui.value.copy(settings = settings)
        reloadNodesFromCache()
        writeConfig()
        viewModelScope.launch {
            while (isActive) {
                if (vpn.isConnected || vpn.isBusy) {
                    vpn.pollTraffic()
                    delay(1_500)
                } else {
                    delay(3_000)
                }
            }
        }
    }

    val selectedNode: ProxyNode?
        get() = _ui.value.nodes.firstOrNull { it.name == _ui.value.settings.selectedNodeName }

    val categorySummaries: List<NodeCategory.Group>
        get() = NodeCategory.groups(_ui.value.nodes, sortByDelay = false)

    val filteredNodes: List<ProxyNode>
        get() {
            val s = _ui.value
            var list = s.nodes
            if (s.searchText.isNotBlank()) {
                val q = s.searchText
                list = list.filter {
                    it.name.contains(q, true) || it.type.contains(q, true) || it.server.contains(q, true)
                }
            }
            if (s.selectedCategoryKey != null) {
                val groups = NodeCategory.groups(s.nodes, false).associate { g ->
                    g.key to g.nodes.map { it.name }.toSet()
                }
                val names = groups[s.selectedCategoryKey].orEmpty()
                list = list.filter { it.name in names }
            }
            return if (s.sortByDelay) {
                list.sortedWith(compareBy<ProxyNode> { it.delayMs ?: Int.MAX_VALUE }.thenBy { it.name })
            } else list.sortedBy { it.name }
        }

    val categoryGroups: List<NodeCategory.Group>
        get() = NodeCategory.groups(filteredNodes, _ui.value.sortByDelay)

    val fastestNode: ProxyNode?
        get() = _ui.value.nodes.filter { (it.delayMs ?: -1) >= 0 }.minByOrNull { it.delayMs ?: Int.MAX_VALUE }

    fun persist() {
        persistJob?.cancel()
        persistJob = viewModelScope.launch {
            delay(250)
            SettingsStore.save(_ui.value.settings)
        }
    }

    fun updateSettings(block: (AppSettings) -> AppSettings) {
        _ui.update { it.copy(settings = block(it.settings)) }
        persist()
    }

    fun reloadNodesFromCache() {
        val settings = _ui.value.settings
        val merged = mutableListOf<ProxyNode>()
        val seen = mutableSetOf<String>()
        for (sub in settings.subscriptions.filter { it.enabled }) {
            val file = Paths.subscriptionCache(sub.id)
            if (!file.exists()) continue
            val parsed = runCatching { ClashConfigParser.parse(file.readBytes()) }.getOrNull() ?: continue
            parsed.nodes.forEach { node ->
                if (seen.add(node.name)) merged += node
            }
        }
        val cache = settings.nodeDelayCache
        val withDelay = merged.map { n ->
            cache[n.delayCacheKey]?.let { n.copy(delayMs = it) } ?: n
        }
        var selected = settings.selectedNodeName
        if (selected != null && withDelay.none { it.name == selected }) selected = withDelay.firstOrNull()?.name
        if (selected == null) selected = withDelay.firstOrNull()?.name
        _ui.update { it.copy(nodes = withDelay, settings = it.settings.copy(selectedNodeName = selected)) }
    }

    fun addSubscription(name: String, url: String) {
        val trimmed = SubscriptionFetcher.normalized(url)
        if (trimmed == null) {
            _ui.update { it.copy(statusText = "链接无效，请使用 http:// 或 https:// 开头") }
            return
        }
        val sub = Subscription(
            name = name.trim().ifEmpty { "订阅" },
            url = trimmed,
        )
        updateSettings { it.copy(subscriptions = it.subscriptions + sub) }
        viewModelScope.launch { updateSubscription(sub.id) }
    }

    fun removeSubscription(id: String) {
        updateSettings { it.copy(subscriptions = it.subscriptions.filterNot { s -> s.id == id }) }
        Paths.subscriptionCache(id).delete()
        reloadNodesFromCache()
        writeConfig()
    }

    fun setSubscriptionEnabled(id: String, enabled: Boolean) {
        updateSettings {
            it.copy(subscriptions = it.subscriptions.map { s -> if (s.id == id) s.copy(enabled = enabled) else s })
        }
        reloadNodesFromCache()
        writeConfig()
    }

    suspend fun updateAllSubscriptions() {
        _ui.update { it.copy(isBusy = true, statusText = "更新订阅…") }
        var ok = 0
        var fail = 0
        _ui.value.settings.subscriptions.filter { it.enabled }.forEach { sub ->
            if (updateSubscription(sub.id, showBusy = false)) ok++ else fail++
        }
        _ui.update {
            it.copy(
                isBusy = false,
                statusText = when {
                    fail == 0 -> "订阅已更新 · ${it.nodes.size} 节点"
                    ok == 0 -> "全部更新失败（$fail 个）"
                    else -> "部分成功：$ok 成功，$fail 失败 · ${it.nodes.size} 节点"
                }
            )
        }
    }

    suspend fun updateSubscription(id: String, showBusy: Boolean = true): Boolean {
        val sub = _ui.value.settings.subscriptions.firstOrNull { it.id == id } ?: return false
        if (showBusy) _ui.update { it.copy(isBusy = true, statusText = "更新 ${sub.name}…") }
        return try {
            val proxy = if (vpn.isConnected) AppConstants.mixedPort else null
            val result = SubscriptionFetcher.fetch(sub.url, viaProxyPort = proxy)
            ClashConfigParser.parse(result.data)
            Paths.subscriptionCache(id).writeBytes(result.data)
            updateSettings {
                it.copy(subscriptions = it.subscriptions.map { s ->
                    if (s.id != id) s else s.copy(
                        updatedAtEpoch = System.currentTimeMillis(),
                        userInfo = result.userInfo ?: s.userInfo,
                        name = if (s.name == "订阅" || s.name.isEmpty()) result.suggestedName ?: s.name else s.name,
                    )
                })
            }
            reloadNodesFromCache()
            writeConfig()
            if (showBusy) _ui.update { it.copy(isBusy = false, statusText = "已更新「${sub.name}」") }
            true
        } catch (e: CancellationException) {
            _ui.update { it.copy(isBusy = false) }
            throw e
        } catch (e: Exception) {
            var message = e.message ?: "失败"
            if (message.contains("coroutine scope left", ignoreCase = true) ||
                message.contains("StandaloneCoroutine was cancelled", ignoreCase = true)
            ) {
                message = "更新被中断，请再试一次"
            }
            if (vpn.isConnected) message += "（可先断开 VPN 再试）"
            _ui.update { it.copy(isBusy = false, statusText = "「${sub.name}」更新失败：$message") }
            false
        }
    }

    fun refreshAll() {
        if (_ui.value.isBusy) return
        viewModelScope.launch { updateAllSubscriptions() }
    }

    fun refreshOne(id: String) {
        if (_ui.value.isBusy) return
        viewModelScope.launch { updateSubscription(id) }
    }

    fun runSpeedTest(selectFastest: Boolean = false) {
        if (_ui.value.isTesting) return
        viewModelScope.launch { testSpeeds(selectFastest) }
    }

    fun runRefreshOutboundIP() {
        viewModelScope.launch { refreshOutboundIP() }
    }

    fun runRefreshGroups() {
        viewModelScope.launch { refreshGroups() }
    }

    fun runSelectGroup(group: String, name: String) {
        viewModelScope.launch {
            vpn.selectGroup(group, name)
            refreshGroups()
        }
    }

    fun runToggleVPN() {
        viewModelScope.launch { toggleVPN() }
    }

    fun selectNode(name: String) {
        updateSettings { it.copy(selectedNodeName = name) }
        writeConfig()
        viewModelScope.launch { vpn.selectNode(name) }
        _ui.update { it.copy(statusText = "已选：$name") }
        if (vpn.isConnected) viewModelScope.launch {
            delay(800)
            refreshOutboundIP()
        }
    }

    fun setMode(mode: ProxyMode) {
        var note = ""
        updateSettings {
            var next = it.copy(proxyMode = mode)
            if (next.videoAdBlockEnabled && mode != ProxyMode.rule) {
                next = next.copy(videoAdBlockEnabled = false)
                note = "（去广告已关闭）"
            }
            next
        }
        writeConfig()
        if (vpn.isConnected) viewModelScope.launch { vpn.setMode(mode.name) }
        _ui.update { it.copy(statusText = "已切换为${mode.title}模式$note") }
    }

    fun setDns(pref: DnsPreference) {
        updateSettings { it.copy(dnsPreference = pref) }
        writeConfig()
        _ui.update {
            it.copy(
                statusText = if (vpn.isConnected) "DNS 已设为${pref.title}，请重连 VPN 生效"
                else "DNS 已设为${pref.title}"
            )
        }
    }

    fun setTunnelCapture(enabled: Boolean) {
        updateSettings { it.copy(tunEnabled = enabled) }
        writeConfig()
        _ui.update {
            it.copy(statusText = if (enabled) "已切换为 TUN 模式，请重连 VPN" else "已切换为 HTTP 代理模式，请重连 VPN")
        }
    }

    fun setVideoAdBlock(enabled: Boolean) {
        updateSettings {
            var next = it.copy(videoAdBlockEnabled = enabled)
            if (enabled && next.proxyMode != ProxyMode.rule) next = next.copy(proxyMode = ProxyMode.rule)
            next
        }
        writeConfig()
        _ui.update {
            it.copy(statusText = if (enabled) "去广告已开启（${VideoAdBlock.ruleCount} 条）" else "去广告已关闭")
        }
    }

    fun setUiLanguage(language: com.bashx.app.data.UiLanguage) {
        updateSettings { it.copy(uiLanguage = language) }
        _ui.update { it.copy(statusText = "Language · ${language.pickerTitle()}") }
    }

    fun applySmartRules() {
        val bundled = ChinaSmartRules.load(getApplication())
        updateSettings { it.copy(rules = bundled, rulesVersion = ChinaSmartRules.version) }
        writeConfig()
        _ui.update {
            it.copy(statusText = "已应用 BashX 智能规则 v${ChinaSmartRules.version}（${effectiveRules().size} 条）")
        }
    }

    fun effectiveRules(): List<String> = RuntimeRules.effective(_ui.value.settings)

    fun writeConfig() {
        val s = _ui.value
        ConfigWriter.write(
            nodes = s.nodes,
            selectedName = s.settings.selectedNodeName,
            mode = s.settings.proxyMode,
            rules = effectiveRules(),
            dnsPreference = s.settings.dnsPreference,
            tunnelCapture = s.settings.tunEnabled,
            profileRoot = loadPassthroughProfileRoot(s.settings),
        )
    }

    /** Single enabled Clash YAML with native proxy-groups → keep as profile. */
    private fun loadPassthroughProfileRoot(settings: AppSettings): Map<String, Any>? {
        val enabled = settings.subscriptions.filter { it.enabled }
        if (enabled.size != 1) return null
        val file = Paths.subscriptionCache(enabled[0].id)
        if (!file.exists()) return null
        val parsed = runCatching { ClashConfigParser.parse(file.readBytes()) }.getOrNull() ?: return null
        return parsed.rawRoot?.takeIf { ClashConfigParser.isCompleteProfile(it) }
    }

    fun openAddSubscription() {
        _ui.update { it.copy(pendingAddSubscription = true, selectedTab = 2) }
    }

    fun consumePendingAdd() {
        _ui.update { it.copy(pendingAddSubscription = false) }
    }

    fun setTab(tab: Int) = _ui.update { it.copy(selectedTab = tab) }
    fun setSearch(text: String) = _ui.update { it.copy(searchText = text) }
    fun toggleSort() = _ui.update { it.copy(sortByDelay = !it.sortByDelay) }
    fun setCategory(key: String?) = _ui.update { it.copy(selectedCategoryKey = key) }

    suspend fun testSpeeds(selectFastest: Boolean = false) {
        val nodes = _ui.value.nodes
        if (nodes.isEmpty()) return
        _ui.update { it.copy(isTesting = true, testedCount = 0, statusText = "测速中…") }
        try {
            val controller = if (vpn.isConnected) AppConstants.externalController else null
            val results = SpeedTester.testAll(
                nodes = nodes,
                timeoutMs = _ui.value.settings.testTimeoutMs,
                concurrency = _ui.value.settings.concurrency,
                controller = controller,
                secret = _ui.value.settings.secret,
                testURL = _ui.value.settings.testURL.ifBlank { "http://www.gstatic.com/generate_204" },
            ) { name, delay ->
                _ui.update { st ->
                    val node = st.nodes.firstOrNull { it.name == name }
                    val cache = if (node != null) st.settings.nodeDelayCache + (node.delayCacheKey to delay)
                    else st.settings.nodeDelayCache
                    st.copy(
                        testedCount = st.testedCount + 1,
                        nodes = st.nodes.map { n -> if (n.name == name) n.copy(delayMs = delay) else n },
                        settings = st.settings.copy(nodeDelayCache = cache),
                    )
                }
            }
            val cache = _ui.value.settings.nodeDelayCache.toMutableMap()
            results.forEach { r ->
                _ui.value.nodes.firstOrNull { it.name == r.name }?.let { cache[it.delayCacheKey] = r.delayMs }
            }
            updateSettings { it.copy(nodeDelayCache = cache) }
            _ui.update { st ->
                st.copy(
                    isTesting = false,
                    statusText = "测速完成",
                    nodes = st.nodes.map { n ->
                        results.firstOrNull { it.name == n.name }?.let { n.copy(delayMs = it.delayMs) } ?: n
                    }
                )
            }
            if (selectFastest) fastestNode?.let { selectNode(it.name) }
        } catch (e: CancellationException) {
            _ui.update { it.copy(isTesting = false) }
            throw e
        }
    }

    suspend fun refreshOutboundIP() {
        if (!vpn.isConnected) {
            _ui.update { it.copy(outboundIP = "—", outboundIPLoading = false) }
            return
        }
        _ui.update { it.copy(outboundIPLoading = true) }
        val ip = SubscriptionFetcher.fetchOutboundIP(viaProxy = true)
            ?: SubscriptionFetcher.fetchOutboundIP(viaProxy = false)
        _ui.update { it.copy(outboundIP = ip ?: "查询失败", outboundIPLoading = false) }
    }

    suspend fun refreshGroups() {
        _ui.update { it.copy(proxyGroups = if (vpn.isConnected) vpn.fetchGroups() else emptyList()) }
    }

    suspend fun toggleVPN() {
        val s = _ui.value
        if (s.nodes.isEmpty() && !vpn.isConnected) {
            _ui.update { it.copy(statusText = "请先添加订阅并更新节点") }
            openAddSubscription()
            return
        }
        writeConfig()
        vpn.toggle(s.settings.tunEnabled)
        delay(400)
        _ui.update { it.copy(statusText = vpn.lastError ?: vpn.statusText) }
        if (vpn.isConnected) {
            delay(1200)
            refreshOutboundIP()
            refreshGroups()
        } else {
            _ui.update { it.copy(outboundIP = "—", proxyGroups = emptyList()) }
        }
    }

    fun onVpnPermission(resultCode: Int) {
        if (resultCode == Activity.RESULT_OK) {
            viewModelScope.launch { toggleVPN() }
        } else {
            _ui.update { it.copy(statusText = "未授予 VPN 权限") }
        }
    }

    fun vpnPrepareIntent(): Intent? = vpn.prepareIntent()
}
