import Foundation
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var nodes: [ProxyNode] = []
    @Published var statusText: String = "就绪"
    @Published var isBusy = false
    @Published var isTesting = false
    @Published var testedCount = 0
    @Published var coreRunning = false
    @Published var systemProxyOn = false
    @Published var searchText = ""
    @Published var sortByDelay = true
    @Published var rulesText: String = ""
    /// nil = 全部地区
    @Published var selectedCategoryKey: String? = nil
    /// Seeded into the nodes pane; not @Published (collapse must stay snappy).
    var collapsedCategories: Set<String> = []

    /// Panel open hint: switch tab / present add sheet.
    enum PanelIntent: Equatable {
        case none
        case subscriptions
        case addSubscription
    }
    @Published var panelIntent: PanelIntent = .none

    /// Current outbound IP via local proxy (updated after node switch).
    @Published var outboundIP: String = "—"
    @Published var outboundIPLoading = false
    /// True while bootstrap / startCoreAsync is bringing mihomo up.
    @Published private(set) var coreConnecting = false
    /// Bumped when node list / filters change — isolated views subscribe instead of whole AppState.
    @Published private(set) var nodeListRevision = 0
    /// Bumped when chrome (core/proxy/TUN/outbound) changes — sidebar + top bar subscribe.
    @Published private(set) var chromeRevision = 0
    /// Bumped when subscription list / enable flags change — subscription UI subscribes.
    @Published private(set) var subscriptionsRevision = 0

    private var coreProcess: Process?
    private var outboundIPTask: Task<Void, Never>?
    private var coreStartInFlight = false
    private var userStoppedCore = false
    private var lastCoreRestartAttempt = Date.distantPast
    private var subscriptionTask: Task<Void, Never>?
    private let tester = SpeedTester()
    private var healthTask: Task<Void, Never>?
    private var launchGuardTask: Task<Void, Never>?
    private var autoSpeedTask: Task<Void, Never>?
    private var systemProxyTask: Task<Void, Never>?
    private var telegramGuardTask: Task<Void, Never>?
    private var lastTelegramNodeProbe = Date.distantPast
    private var persistTask: Task<Void, Never>?
    private var writeConfigTask: Task<Void, Never>?
    private var coreHealthMissStreak = 0
    private var coreHealthAliveStreak = 0
    private var coreHealthDeadStreak = 0
    /// Only true right after user toggles TUN on — avoids admin prompt on every launch.
    private var requestElevatedCoreStart = false
    /// Whether the live config.yaml should include TUN (requires elevation when turning on).
    private var runtimeTunInConfig = false

    // Cached region grouping — rebuilt only when node set / sort changes.
    private var displayCache: [String: (key: String, title: String, flag: String)] = [:]
    private var summaryCache: [(key: String, title: String, flag: String, count: Int)] = []
    private var groupCacheSort: Bool?
    private var groupCache: [NodeCategory.Group] = []
    private var categoryGroupsCache: [NodeCategory.Group] = []
    private var categoryGroupsFingerprint = ""
    private var speedUITick = Date.distantPast

    var filteredNodes: [ProxyNode] {
        ensureDisplayCache()
        var list = nodes
        if !searchText.isEmpty {
            let q = searchText
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || $0.type.localizedCaseInsensitiveContains(q)
                    || $0.server.localizedCaseInsensitiveContains(q)
                    || (displayCache[$0.name]?.title.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        if let key = selectedCategoryKey {
            list = list.filter { displayCache[$0.name]?.key == key }
        }
        if sortByDelay {
            list.sort(by: delaySort)
        } else {
            list.sort { $0.name < $1.name }
        }
        return list
    }

    var categoryGroups: [NodeCategory.Group] {
        ensureGroupCache()
        // Fingerprint skips collapse toggles — those must not rebuild groups.
        let fp = "\(nodeListRevision)|\(searchText)|\(selectedCategoryKey ?? "")|\(sortByDelay)|\(nodes.count)|\(groupCache.count)"
        if fp == categoryGroupsFingerprint { return categoryGroupsCache }

        let visible = Set(filteredNodes.map(\.name))
        let built: [NodeCategory.Group] = groupCache.compactMap { group in
            var kept = group.nodes.filter { visible.contains($0.name) }
            guard !kept.isEmpty else { return nil }
            if sortByDelay {
                kept.sort(by: delaySort)
            } else {
                kept.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            return NodeCategory.Group(key: group.key, title: group.title, flag: group.flag, nodes: kept)
        }
        categoryGroupsFingerprint = fp
        categoryGroupsCache = built
        return built
    }

    var categorySummary: [(key: String, title: String, flag: String, count: Int)] {
        ensureDisplayCache()
        return summaryCache
    }

    /// Menu-bar quick list: fastest N by delay (N = menuNodeLimit).
    var menuNodes: [ProxyNode] {
        let limit = min(500, max(5, settings.menuNodeLimit))
        let sorted = nodes.sorted(by: delaySort)
        return Array(sorted.prefix(limit))
    }

    private func invalidateNodeCaches() {
        displayCache = [:]
        summaryCache = []
        groupCache = []
        groupCacheSort = nil
        categoryGroupsCache = []
        categoryGroupsFingerprint = ""
        nodeListRevision &+= 1
    }

    func bumpNodeListRevision() {
        nodeListRevision &+= 1
    }

    /// Refresh panel chrome (sidebar / top bar) without rebuilding the whole node list.
    func bumpChromeRevision() {
        chromeRevision &+= 1
    }

    func bumpSubscriptionsRevision() {
        subscriptionsRevision &+= 1
    }

    /// Reassign so nested subscription edits reliably publish to SwiftUI.
    private func replaceSubscriptions(_ subs: [Subscription]) {
        settings.subscriptions = subs
        bumpSubscriptionsRevision()
        bumpChromeRevision()
    }

    /// Node list + chrome — use after selection / collapse / layout changes.
    func bumpPanelRefresh() {
        nodeListRevision &+= 1
        chromeRevision &+= 1
    }

    func toggleCategoryCollapsed(_ key: String) {
        // Collapse is handled locally in the nodes pane — do NOT bump nodeListRevision
        // (that remounted the whole list and made expand/collapse feel stuck).
        if collapsedCategories.contains(key) {
            collapsedCategories.remove(key)
        } else {
            collapsedCategories.insert(key)
        }
    }

    /// Disk write off the hot path (node switch, toggles) — coalesced ~350ms.
    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.settings
            await Task.detached(priority: .utility) {
                _ = SettingsStore.save(snapshot)
            }.value
        }
    }

    /// Flush settings to disk immediately (quit / critical paths).
    func persist() {
        persistTask?.cancel()
        if !SettingsStore.save(settings) {
            statusText = "设置保存失败，请检查磁盘权限"
        }
    }

    /// UI-facing: treat listening mixed-port as online so brief API lag doesn't flash offline.
    var isCoreVisiblyAlive: Bool {
        coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort)
    }

    private func applyCoreRunning(_ alive: Bool) {
        guard coreRunning != alive else { return }
        coreRunning = alive
        if alive {
            coreHealthDeadStreak = 0
            coreHealthMissStreak = 0
        }
        bumpChromeRevision()
    }

    /// Soft probe for UI / recovery — promotes online, never demotes (avoids status flicker).
    private func probeCoreAlive() async -> Bool {
        let port = CoreHealth.mixedPortAlive(port: settings.mixedPort)
        guard port else { return false }
        let status = await ClashCore.apiStatus(
            controller: settings.externalController,
            secret: settings.secret
        )
        switch status {
        case .online:
            applyCoreRunning(true)
            return true
        case .authFailed:
            // Core is up but secret wrong — show clearly, do not pretend API is healthy.
            applyCoreRunning(true)
            if !statusText.contains("鉴权失败") {
                statusText = "内核在线，但 API 鉴权失败（请检查 secret）"
            }
            return false
        case .unreachable:
            // Port up but API briefly busy — still treat as healthy for callers; don't flip UI off.
            return coreRunning
        }
    }

    private func ensureDisplayCache() {
        guard displayCache.isEmpty, !nodes.isEmpty else {
            if nodes.isEmpty { displayCache = [:]; summaryCache = [] }
            return
        }
        displayCache = NodeCategory.displayGroups(among: nodes)
        summaryCache = NodeCategory.groups(from: nodes, sortByDelay: false).map {
            ($0.key, $0.title, $0.flag, $0.nodes.count)
        }
    }

    /// Always keep a non-empty API secret so controller calls stay consistent.
    private func ensureAPISecret() {
        let trimmed = settings.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }
        settings.secret = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))
        _ = SettingsStore.save(settings)
    }

    private func ensureGroupCache() {
        ensureDisplayCache()
        if groupCacheSort == sortByDelay, !groupCache.isEmpty { return }
        groupCache = NodeCategory.groups(from: nodes, sortByDelay: sortByDelay)
        groupCacheSort = sortByDelay
    }

    init() {
        settings = SettingsStore.load()
        L10n.apply(settings.uiLanguage)
        ensureAPISecret()
        AppActivation.preferDockIcon = settings.showDockIcon
        migrateBusyPortsIfNeeded()
        if ChinaSmartRules.needsUpgrade(settings.rules, storedVersion: settings.rulesVersion) {
            settings.rules = ChinaSmartRules.rules
            settings.rulesVersion = ChinaSmartRules.version
            _ = SettingsStore.save(settings)
        }
        let sanitized = GeoSiteRules.sanitize(settings.rules)
        if sanitized != settings.rules {
            settings.rules = sanitized
            _ = SettingsStore.save(settings)
        }
        ChinaSmartRules.publishRulesToDisk()
        migrateTelegramReliabilitySettings()
        systemProxyOn = settings.systemProxyEnabled
        // Defer huge rulesText join — only needed when Rules tab opens.
        rulesText = ""
        clampPerfDefaults()
        if settings.clashBinaryPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: CoreInstaller.bundledPath.path) {
            settings.clashBinaryPath = CoreInstaller.bundledPath.path
            schedulePersist()
        }
        // Parse all enabled subscription caches (never seed from a single last-subscription file).
        Task {
            _ = rebuildEnabledNodesFromCache()
            if nodes.isEmpty {
                reloadNodesFromDiskIfNeeded()
            }
            await bootstrapRuntime()
            restartAutoSpeedLoop()
        }
    }

    /// Fill rules editor text when user opens the Rules tab (avoids join cost at launch).
    func ensureRulesTextLoaded() {
        if rulesText.isEmpty, !settings.rules.isEmpty {
            rulesText = settings.rules.joined(separator: "\n")
        }
    }

    /// Repair broken states; always bring core up on launch.
    private func bootstrapRuntime() async {
        // App launch always hosts mihomo — ignore prior manual stop from last session.
        userStoppedCore = false
        runtimeTunInConfig = false
        Paths.trimSupportLogs()

        // Always rebuild from every enabled subscription cache before writing config / starting core.
        // (Avoids "only ~15 nodes" from lastSubscriptionURL overwriting the merged pool.)
        if !rebuildEnabledNodesFromCache() {
            reloadNodesFromDiskIfNeeded()
        }
        refreshLaunchAtLogin()
        sanitizeRulesForCore()
        migrateBusyPortsIfNeeded()

        statusText = "正在准备内核…"

        if settings.clashBinaryPath.isEmpty {
            let path = await Task.detached(priority: .userInitiated) {
                CoreInstaller.seedEmbeddedCoreIfNeeded()
            }.value
            if let path {
                settings.clashBinaryPath = path
                schedulePersist()
            }
        }
        if settings.clashBinaryPath.isEmpty || !FileManager.default.isExecutableFile(atPath: settings.clashBinaryPath),
           let path = try? await CoreInstaller.ensureInstalled(progress: { [weak self] msg in
            self?.statusText = msg
        }) {
            settings.clashBinaryPath = path
            schedulePersist()
        }

        // Always start (or attach to) mihomo when the app opens.
        await ensureCoreAtLaunch()
        await refreshCoreStatus()

        if settings.systemProxyEnabled {
            await applyDefaultSystemProxyIfEnabled()
        } else {
            let port = settings.mixedPort
            systemProxyOn = await Task.detached(priority: .utility) {
                SystemProxy.isEnabled(port: port)
            }.value
            bumpChromeRevision()
        }

        if !coreRunning, !CoreHealth.mixedPortAlive(port: settings.mixedPort) {
            startLaunchCoreGuard()
        }

        startHealthWatch()
        startTelegramGuard()
        await ensureTelegramConnectivity(forceNodeProbe: true)

        // Heavy merge / reload off the critical launch path.
        Task { [weak self] in
            guard let self else { return }
            if !GeoDataBootstrap.isReady() {
                self.statusText = "正在下载地理规则库…"
                try? await GeoDataBootstrap.ensurePresent { [weak self] msg in
                    Task { @MainActor in self?.statusText = msg }
                }
            }
            if !self.settings.subscriptions.filter(\.enabled).isEmpty {
                await self.applyEnabledSubscriptions(fetch: false)
            }
            if self.settings.videoAdBlockEnabled, self.settings.proxyMode != .rule {
                self.settings.proxyMode = .rule
                self.schedulePersist()
            }
            self.scheduleWriteConfig()
            if self.coreRunning {
                await self.applyConfig(reloadIfRunning: true)
            }
            if !self.userStoppedCore, !(await self.coreIsHealthy()) {
                await self.startCoreAsync()
            }
            if self.settings.systemProxyEnabled {
                await self.applyDefaultSystemProxyIfEnabled()
            }

            let stale = self.settings.subscriptions.contains {
                guard let t = $0.updatedAt else { return true }
                return Date().timeIntervalSince(t) > 6 * 3600
            }
            if stale, !self.settings.subscriptions.isEmpty {
                await self.updateAllSubscriptions()
            }
        }
    }

    /// Keep defaults lean for a menu-bar utility.
    private func clampPerfDefaults() {
        var changed = false
        if settings.concurrency > 8 {
            settings.concurrency = 8
            changed = true
        }
        if settings.menuNodeLimit > 500 {
            settings.menuNodeLimit = 500
            changed = true
        } else if settings.menuNodeLimit > 0, settings.menuNodeLimit < 5 {
            settings.menuNodeLimit = 5
            changed = true
        }
        if settings.testTimeoutMs < 3000 {
            settings.testTimeoutMs = 5000
            changed = true
        } else if settings.testTimeoutMs > 8000 {
            settings.testTimeoutMs = 8000
            changed = true
        }
        if settings.testURL.hasPrefix("http://www.gstatic.com") {
            settings.testURL = "https://www.gstatic.com/generate_204"
            changed = true
        }
        if changed { persist() }
    }

    private func startHealthWatch() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                // Slow watchdog — frequent probes caused UI flicker (内核关/开).
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self?.healthTick()
            }
        }
    }

    private func healthTick() async {
        guard !userStoppedCore, !coreStartInFlight else { return }

        let port = CoreHealth.mixedPortAlive(port: settings.mixedPort)
        // Prefer cheap port check; only hit API when port is up (or we think we're online).
        let api: Bool
        if port {
            api = await CoreHealth.apiAlive(controller: settings.externalController, secret: settings.secret)
        } else {
            api = false
        }
        let alive = api && port
        if alive {
            coreHealthDeadStreak = 0
            coreHealthAliveStreak += 1
            coreHealthMissStreak = 0
            applyCoreRunning(true)
            if settings.systemProxyEnabled, !settings.userDisabledSystemProxy {
                let port = settings.mixedPort
                let proxyOK = await Task.detached(priority: .utility) {
                    SystemProxy.isEnabled(port: port)
                }.value
                if !proxyOK || !systemProxyOn {
                    await applyDefaultSystemProxyIfEnabled()
                }
            }
            return
        }

        coreHealthAliveStreak = 0
        coreHealthDeadStreak += 1
        coreHealthMissStreak += 1

        // Need several consecutive misses before flipping UI to offline (~45s).
        if coreRunning, coreHealthDeadStreak >= 3 {
            applyCoreRunning(false)
        }

        // When core never came up, retry sooner; otherwise wait for cooldown.
        let urgent = !coreRunning
        guard urgent || coreHealthMissStreak >= 3 else { return }

        guard ClashCore.resolveBinary(customPath: settings.clashBinaryPath) != nil else { return }
        let cooldown: TimeInterval = urgent ? 5 : (settings.tunEnabled ? 60 : 40)
        guard Date().timeIntervalSince(lastCoreRestartAttempt) >= cooldown else { return }
        lastCoreRestartAttempt = Date()
        statusText = urgent ? "正在启动内核…" : "内核未响应，正在自动恢复…"
        await startCoreAsync(forceRestart: urgent)

        if await probeCoreAlive() {
            coreHealthMissStreak = 0
            coreHealthDeadStreak = 0
            await applyDefaultSystemProxyIfEnabled()
            return
        }

        // Keep system proxy on — Telegram relies on it; core recovery continues in background.
        if !settings.userDisabledSystemProxy, !settings.systemProxyEnabled {
            settings.systemProxyEnabled = true
            schedulePersist()
        }
    }

    /// BashX open => keep system proxy preference unless user explicitly disabled it.
    /// Never rewrite proxyMode — 规则/全局/直连 must stick to user choice.
    private func migrateTelegramReliabilitySettings() {
        var changed = false
        if !settings.userDisabledSystemProxy, !settings.systemProxyEnabled {
            settings.systemProxyEnabled = true
            changed = true
        }
        if changed { _ = SettingsStore.save(settings) }
    }

    private func startTelegramGuard() {
        telegramGuardTask?.cancel()
        telegramGuardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await self?.telegramGuardTick()
            }
        }
    }

    private func telegramGuardTick() async {
        // Respect explicit 直连 / user-disabled system proxy — do not hijack mode.
        guard !userStoppedCore, !settings.userDisabledSystemProxy else { return }
        guard settings.proxyMode != .direct else { return }

        if !settings.systemProxyEnabled {
            settings.systemProxyEnabled = true
            schedulePersist()
        }

        if !(await coreIsHealthy()) {
            await ensureCoreRunning()
        }

        let port = settings.mixedPort
        let proxyWritten = await Task.detached(priority: .utility) {
            SystemProxy.isEnabled(port: port)
        }.value
        if !proxyWritten || !systemProxyOn {
            await applyDefaultSystemProxyIfEnabled()
        }

        guard TelegramReliability.isTelegramRunning() else { return }
        guard await coreIsHealthy() else { return }
        if await CoreHealth.telegramReachable(port: port) { return }

        let cooldown: TimeInterval = 60
        guard Date().timeIntervalSince(lastTelegramNodeProbe) >= cooldown else { return }
        lastTelegramNodeProbe = Date()
        // Only retune TELEGRAM url-test — never selectNode / closeAllConnections (that kills MTProto).
        await healTelegramGroupOnly()
    }

    private func ensureTelegramConnectivity(forceNodeProbe: Bool) async {
        guard !settings.userDisabledSystemProxy else { return }
        migrateTelegramReliabilitySettings()
        _ = await ensureCoreRunning()
        await applyDefaultSystemProxyIfEnabled()

        let port = settings.mixedPort
        let telegramOK = await CoreHealth.telegramReachable(port: port)
        if forceNodeProbe || !telegramOK {
            await healTelegramGroupOnly()
        }
    }

    private func startLaunchCoreGuard() {
        launchGuardTask?.cancel()
        launchGuardTask = Task { [weak self] in
            for tick in 0..<8 {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard !self.userStoppedCore else { return }
                if await self.coreIsHealthy() {
                    await self.applyDefaultSystemProxyIfEnabled()
                    return
                }
                // Skip heavy restart if port already listening (transient API lag).
                if CoreHealth.mixedPortAlive(port: self.settings.mixedPort) {
                    continue
                }
                self.statusText = tick == 0 ? "正在启动内核…" : "内核未就绪，自动重试 (\(tick + 1))…"
                _ = await self.ensureCoreRunning()
            }
        }
    }

    private func coreIsHealthy() async -> Bool {
        if await probeCoreAlive() { return true }
        if CoreHealth.mixedPortAlive(port: settings.mixedPort) {
            applyCoreRunning(true)
            return true
        }
        return false
    }

    /// Wait for mixed-port / API without hammering restarts (system-proxy toggle path).
    private func waitForCoreReady(timeoutSeconds: Double = 30) async -> Bool {
        if await coreIsHealthy() { return true }
        if !coreStartInFlight, !userStoppedCore {
            Task { await startCoreAsync() }
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await coreIsHealthy() { return true }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    /// Turn on macOS system proxy when settings ask for it and mihomo is listening.
    private func applyDefaultSystemProxyIfEnabled() async {
        guard settings.systemProxyEnabled, !settings.userDisabledSystemProxy else {
            let port = settings.mixedPort
            systemProxyOn = await Task.detached(priority: .utility) {
                SystemProxy.isEnabled(port: port)
            }.value
            return
        }
        guard await coreIsHealthy() else {
            systemProxyOn = false
            bumpChromeRevision()
            return
        }
        let port = settings.mixedPort
        let on = await SystemProxy.setEnabledAsync(true, port: port)
        systemProxyOn = on
        bumpChromeRevision()
        if on {
            await syncSelectedOutbound()
            _ = await ClashCore.applyMode(
                controller: settings.externalController,
                secret: settings.secret,
                mode: settings.proxyMode
            )
        }
    }

    /// Start or attach to mihomo as soon as the app opens.
    private func ensureCoreAtLaunch() async {
        if ClashCore.resolveBinary(customPath: settings.clashBinaryPath) == nil {
            statusText = "内置内核未就绪，正在解压…"
            let path = await Task.detached(priority: .userInitiated) {
                CoreInstaller.seedEmbeddedCoreIfNeeded()
            }.value
            if let path {
                settings.clashBinaryPath = path
                schedulePersist()
            } else {
                await installOrRepairCore()
            }
        }
        guard ClashCore.resolveBinary(customPath: settings.clashBinaryPath) != nil else {
            statusText = "内核安装失败，请重新打开 BashX"
            return
        }

        if !rebuildEnabledNodesFromCache() {
            reloadNodesFromDiskIfNeeded()
        }
        writeConfig()

        let healthy = await CoreHealth.apiAlive(controller: settings.externalController, secret: settings.secret)
            && CoreHealth.mixedPortAlive(port: settings.mixedPort)
        if !healthy {
            statusText = "正在启动内核…"
            for attempt in 1...3 where !coreRunning {
                if attempt > 1 {
                    statusText = "正在重试启动内核（\(attempt)/3）…"
                    migrateBusyPortsIfNeeded()
                    writeConfig()
                }
                await startCoreAsync(forceRestart: attempt > 1)
                if !coreRunning {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        } else {
            applyCoreRunning(true)
        }

        if !coreRunning {
            statusText = "内核启动失败，正在后台重试…"
            // healthTick will retry within a few seconds
            return
        }

        let tunOn = await CoreHealth.tunEnabled(
            controller: settings.externalController,
            secret: settings.secret
        )
        if settings.tunEnabled, tunOn == true {
            runtimeTunInConfig = true
            statusText = "内核运行中（TUN）"
        } else if settings.tunEnabled {
            runtimeTunInConfig = false
            writeConfig()
            statusText = "内核已启动 · TUN 需在设置中重新开启（需管理员密码）"
        }

        let target = activeProxyTarget()
        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: "PROXY",
            name: target
        )
        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: "GLOBAL",
            name: target
        )
        _ = await ClashCore.applyMode(
            controller: settings.externalController,
            secret: settings.secret,
            mode: settings.proxyMode
        )
        if settings.selectedNodeName == nil || settings.selectedNodeName == "AUTO" {
            await ensureUsableProxy(forceProbe: false, verifyGoogle: true)
        }
    }

    /// Avoid colliding with Stash/ClashX default 7890/9090; also bump if OUR ports are occupied by others.
    private func migrateBusyPortsIfNeeded() {
        var changed = false
        if settings.mixedPort == 7890, PortProbe.isListening(port: 7890) {
            settings.mixedPort = 17890
            changed = true
        }
        if settings.externalController == "127.0.0.1:9090", PortProbe.isListening(port: 9090) {
            settings.externalController = "127.0.0.1:19090"
            changed = true
        }
        // If configured mixed-port is taken by a foreign process, pick a free nearby port.
        if PortProbe.isListening(port: settings.mixedPort), !ClashCore.isMihomoAlive() {
            if let free = PortProbe.firstFreePort(from: settings.mixedPort, limit: 30) {
                settings.mixedPort = free
                changed = true
            }
        }
        let controllerPort = Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? 19090
        let controllerHost = settings.externalController.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        if PortProbe.isListening(host: controllerHost, port: controllerPort), !ClashCore.isMihomoAlive() {
            if let free = PortProbe.firstFreePort(from: controllerPort, limit: 30) {
                settings.externalController = "\(controllerHost):\(free)"
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Drop rules that crash mihomo (missing GeoSite lists, etc.).
    private func sanitizeRulesForCore() {
        var before = settings.rules
        before = before.map { rule in
            let t = rule.trimmingCharacters(in: .whitespaces)
            if t.uppercased() == "DOMAIN-SUFFIX,LOCAL,DIRECT" {
                return "DOMAIN-SUFFIX,local,REJECT"
            }
            return rule
        }
        let cleaned = GeoSiteRules.sanitize(before)
        if cleaned != settings.rules {
            settings.rules = cleaned
            persist()
        }
    }

    private func stripGeoSiteRule(named site: String) {
        let filtered = settings.rules.filter { !GeoSiteRules.rule($0, usesSite: site) }
        guard filtered.count != settings.rules.count else { return }
        settings.rules = filtered
        persist()
    }

    enum AddSubscriptionOutcome: Equatable {
        case success(nodeCount: Int)
        case invalidURL
        case duplicate
        case fetchFailed(String)
    }

    static func normalizedSubscriptionURL(_ raw: String, allowInsecureHTTP: Bool) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") { return trimmed }
        if lower.hasPrefix("http://") {
            return allowInsecureHTTP ? trimmed : nil
        }
        return nil
    }

    static func normalizedSubscriptionURL(_ raw: String) -> String? {
        normalizedSubscriptionURL(raw, allowInsecureHTTP: true)
    }

    func hasDuplicateSubscription(url: String) -> Bool {
        guard let normalized = Self.normalizedSubscriptionURL(url, allowInsecureHTTP: true) else { return false }
        let key = normalized.lowercased()
        return settings.subscriptions.contains { Self.normalizedSubscriptionURL($0.url, allowInsecureHTTP: true)?.lowercased() == key }
    }

    func addSubscription(name: String, url: String) {
        guard let trimmed = Self.normalizedSubscriptionURL(url, allowInsecureHTTP: settings.allowInsecureHTTPSubscriptions) else { return }
        let subName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "订阅 \(settings.subscriptions.count + 1)"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        var subs = settings.subscriptions
        subs.append(Subscription(name: subName, url: trimmed, enabled: true))
        replaceSubscriptions(subs)
        persist()
    }

    /// Add subscription then immediately fetch nodes + traffic/expiry (and auto name if empty).
    @discardableResult
    func addSubscriptionAndFetch(name: String, url: String) async -> AddSubscriptionOutcome {
        let trimmedRaw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRaw.lowercased().hasPrefix("http://"), !settings.allowInsecureHTTPSubscriptions {
            statusText = "已拒绝明文 HTTP 订阅；请在设置中开启「允许不安全 HTTP 订阅」或改用 HTTPS"
            return .invalidURL
        }
        guard let trimmed = Self.normalizedSubscriptionURL(
            url,
            allowInsecureHTTP: settings.allowInsecureHTTPSubscriptions
        ) else {
            return .invalidURL
        }
        if hasDuplicateSubscription(url: trimmed) {
            statusText = "该订阅链接已存在"
            return .duplicate
        }

        let manualName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholder = manualName.isEmpty
            ? "订阅 \(settings.subscriptions.count + 1)"
            : manualName
        let sub = Subscription(name: placeholder, url: trimmed, enabled: true)
        var subs = settings.subscriptions
        subs.append(sub)
        replaceSubscriptions(subs)
        persist()

        let subId = sub.id
        statusText = "正在拉取订阅…"
        await applyEnabledSubscriptions(fetch: true, onlyIDs: [subId])

        guard let idx = settings.subscriptions.firstIndex(where: { $0.id == subId }) else {
            return .fetchFailed("添加失败，请重试")
        }
        let added = settings.subscriptions[idx]
        let cacheURL = Paths.subscriptionCacheURL(id: subId)
        let hasCache = ((try? Data(contentsOf: cacheURL))?.isEmpty == false)

        if added.updatedAt != nil || hasCache {
            return .success(nodeCount: nodes.count)
        }
        if statusText.contains("失败") {
            return .fetchFailed(statusText)
        }
        return .fetchFailed("未能解析节点，请检查链接是否有效")
    }

    func removeSubscription(_ id: UUID) {
        let name = settings.subscriptions.first(where: { $0.id == id })?.name ?? "订阅"
        replaceSubscriptions(settings.subscriptions.filter { $0.id != id })
        statusText = "已删除：\(name)"
        schedulePersist()
        Task {
            _ = rebuildEnabledNodesFromCache()
            await applyEnabledSubscriptions(fetch: false)
            bumpPanelRefresh()
        }
    }

    func renameSubscription(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = settings.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        guard settings.subscriptions[idx].name != trimmed else { return }
        var subs = settings.subscriptions
        subs[idx].name = trimmed
        replaceSubscriptions(subs)
        schedulePersist()
        statusText = "已重命名：\(trimmed)"
    }

    /// Toggle whether a subscription participates in the node pool.
    func setSubscriptionEnabled(_ id: UUID, enabled: Bool) async {
        guard let idx = settings.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        // Keep at least one enabled when possible.
        if !enabled {
            let othersOn = settings.subscriptions.filter { $0.id != id && $0.enabled }
            if othersOn.isEmpty {
                statusText = "至少保留一个启用的订阅"
                return
            }
        }
        var subs = settings.subscriptions
        subs[idx].enabled = enabled
        replaceSubscriptions(subs)
        let name = subs[idx].name
        statusText = enabled ? "启用中：\(name)" : "停用中：\(name)"
        bumpPanelRefresh()
        let hadNodes = rebuildEnabledNodesFromCache()
        if enabled, !hadNodes {
            statusText = "正在加载：\(name)…"
        }
        schedulePersist()
        await applyEnabledSubscriptions(fetch: false)
        bumpPanelRefresh()
        let onCount = settings.subscriptions.filter(\.enabled).count
        statusText = enabled
            ? "已启用 \(onCount) 个订阅 · \(nodes.count) 个节点"
            : "已停用：\(name) · \(nodes.count) 个节点"
    }

    /// Enable every subscription and merge all caches into the node pool.
    func enableAllSubscriptions() async {
        guard !settings.subscriptions.isEmpty else { return }
        var changed = false
        let subs = settings.subscriptions.map { sub -> Subscription in
            guard !sub.enabled else { return sub }
            changed = true
            var copy = sub
            copy.enabled = true
            return copy
        }
        if changed {
            replaceSubscriptions(subs)
            schedulePersist()
        }
        statusText = "正在合并全部订阅…"
        bumpPanelRefresh()
        _ = rebuildEnabledNodesFromCache()
        await applyEnabledSubscriptions(fetch: false)
        bumpPanelRefresh()
        let onCount = settings.subscriptions.filter(\.enabled).count
        statusText = "已启用 \(onCount) 个订阅 · \(nodes.count) 个节点"
    }

    /// Switch to a single subscription (disable others).
    func switchToSubscription(_ id: UUID) async {
        guard settings.subscriptions.contains(where: { $0.id == id }) else { return }
        let subs = settings.subscriptions.map { sub in
            var copy = sub
            copy.enabled = (sub.id == id)
            return copy
        }
        replaceSubscriptions(subs)
        let name = subs.first(where: { $0.id == id })?.name ?? ""
        statusText = "切换订阅：\(name)"
        bumpPanelRefresh()
        _ = rebuildEnabledNodesFromCache()
        schedulePersist()
        await applyEnabledSubscriptions(fetch: false)
        bumpPanelRefresh()
        statusText = "已切换到：\(name) · \(nodes.count) 个节点"
    }

    func updateAllSubscriptions() async {
        await applyEnabledSubscriptions(fetch: true)
    }

    /// Fetch only one subscription, then rebuild nodes from caches.
    func updateSubscription(_ id: UUID) async {
        guard let sub = settings.subscriptions.first(where: { $0.id == id }) else { return }
        isBusy = true
        defer { isBusy = false }
        _ = Paths.subscriptionsCacheDir
        statusText = "更新：\(sub.name)…"

        let cacheURL = Paths.subscriptionCacheURL(id: sub.id)
        let proxyPort: Int? = {
            guard coreRunning, CoreHealth.mixedPortAlive(port: settings.mixedPort) else { return nil }
            return settings.mixedPort
        }()

        do {
            let result = try await SubscriptionFetcher.fetch(
                urlString: sub.url,
                viaProxyPort: proxyPort
            )
            try result.data.write(to: cacheURL, options: .atomic)
            if sub.enabled {
                try result.data.write(to: Paths.lastSubscriptionURL, options: .atomic)
            }
            if let idx = settings.subscriptions.firstIndex(where: { $0.id == id }) {
                settings.subscriptions[idx].updatedAt = Date()
                if let info = result.userInfo {
                    settings.subscriptions[idx].userInfo = info
                }
                if let suggested = result.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !suggested.isEmpty {
                    let current = settings.subscriptions[idx].name
                    if current.hasPrefix("订阅 ") || current == "订阅" {
                        settings.subscriptions[idx].name = suggested
                    }
                }
            }
            persist()
            let trafficNote = result.userInfo == nil ? "（无流量头）" : "（已识别流量）"
            statusText = "已更新「\(sub.name)」\(trafficNote)"
        } catch {
            statusText = "「\(sub.name)」更新失败：\(error.localizedDescription)"
        }

        // Rebuild node pool from enabled caches (only this one was re-fetched).
        await applyEnabledSubscriptions(fetch: false)
    }

    /// Rebuild node list from enabled subscriptions (optionally re-fetch).
    /// - Parameters:
    ///   - fetch: when true, re-download all subscriptions
    ///   - onlyIDs: if non-nil with fetch=true, only download these IDs (others use cache)
    func applyEnabledSubscriptions(fetch: Bool, onlyIDs: Set<UUID>? = nil) async {
        let previous = subscriptionTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.applyEnabledSubscriptionsBody(fetch: fetch, onlyIDs: onlyIDs)
        }
        subscriptionTask = task
        await task.value
    }

    private func applyEnabledSubscriptionsBody(fetch: Bool, onlyIDs: Set<UUID>? = nil) async {
        let enabled = settings.subscriptions.filter(\.enabled)
        if !fetch, enabled.isEmpty {
            statusText = "请先启用至少一个订阅"
            return
        }
        if fetch { isBusy = true }
        defer { if fetch { isBusy = false } }
        _ = Paths.subscriptionsCacheDir

        var merged: [ProxyNode] = []
        var seen = Set<String>()
        var lastError: Error?
        var okCount = 0
        var cacheCount = 0
        var trafficCount = 0

        // Fetch targets: all / selected IDs / none (cache-only rebuild).
        let targets: [Subscription] = {
            if fetch {
                if let onlyIDs {
                    return settings.subscriptions.filter { onlyIDs.contains($0.id) }
                }
                return settings.subscriptions
            }
            return enabled
        }()
        guard !targets.isEmpty || !enabled.isEmpty else {
            statusText = "暂无订阅"
            return
        }

        // When only fetching some IDs, still need all enabled subs for the node merge.
        let mergeSubs: [Subscription] = fetch && onlyIDs != nil ? enabled : targets
        let loopSubs = fetch && onlyIDs == nil ? targets : mergeSubs

        let proxyPort: Int? = {
            guard coreRunning, CoreHealth.mixedPortAlive(port: settings.mixedPort) else { return nil }
            return settings.mixedPort
        }()

        // Parallel fetch when updating multiple subscriptions.
        if fetch, onlyIDs == nil, targets.count > 1 {
            let fetchTargets = targets
            await withTaskGroup(of: (UUID, Result<SubscriptionFetcher.FetchResult, Error>).self) { group in
                for sub in fetchTargets {
                    group.addTask {
                        do {
                            let result = try await SubscriptionFetcher.fetch(
                                urlString: sub.url,
                                viaProxyPort: proxyPort
                            )
                            return (sub.id, .success(result))
                        } catch {
                            return (sub.id, .failure(error))
                        }
                    }
                }
                for await (id, outcome) in group {
                    guard let idx = settings.subscriptions.firstIndex(where: { $0.id == id }) else { continue }
                    let sub = settings.subscriptions[idx]
                    let cacheURL = Paths.subscriptionCacheURL(id: id)
                    switch outcome {
                    case .success(let result):
                        try? result.data.write(to: cacheURL, options: .atomic)
                        if sub.enabled {
                            try? result.data.write(to: Paths.lastSubscriptionURL, options: .atomic)
                        }
                        settings.subscriptions[idx].updatedAt = Date()
                        if let info = result.userInfo {
                            settings.subscriptions[idx].userInfo = info
                            trafficCount += 1
                        }
                        if let suggested = result.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !suggested.isEmpty {
                            let current = settings.subscriptions[idx].name
                            if current.hasPrefix("订阅 ") || current == "订阅" {
                                settings.subscriptions[idx].name = suggested
                            }
                        }
                        okCount += 1
                    case .failure(let error):
                        lastError = error
                        if sub.enabled, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
                            cacheCount += 1
                        }
                    }
                }
            }
            bumpSubscriptionsRevision()
        }

        for sub in loopSubs {
            let shouldFetch = fetch && (onlyIDs == nil || onlyIDs!.contains(sub.id))
            if shouldFetch, onlyIDs == nil, targets.count > 1 {
                // Already fetched in parallel above.
            } else if shouldFetch {
                statusText = "更新：\(sub.name)…"
            }
            let cacheURL = Paths.subscriptionCacheURL(id: sub.id)
            let includeNodes = sub.enabled

            var data: Data?
            var fromCache = false

            if shouldFetch, onlyIDs == nil, targets.count > 1 {
                data = try? Data(contentsOf: cacheURL)
                fromCache = data != nil
            } else if shouldFetch {
                do {
                    let result = try await SubscriptionFetcher.fetch(
                        urlString: sub.url,
                        viaProxyPort: proxyPort
                    )
                    data = result.data
                    try data?.write(to: cacheURL, options: .atomic)
                    if includeNodes {
                        try data?.write(to: Paths.lastSubscriptionURL, options: .atomic)
                    }
                    if let idx = settings.subscriptions.firstIndex(where: { $0.id == sub.id }) {
                        settings.subscriptions[idx].updatedAt = Date()
                        if let info = result.userInfo {
                            settings.subscriptions[idx].userInfo = info
                            trafficCount += 1
                        }
                        if let suggested = result.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !suggested.isEmpty {
                            let current = settings.subscriptions[idx].name
                            if current.hasPrefix("订阅 ") || current == "订阅" {
                                settings.subscriptions[idx].name = suggested
                            }
                        }
                    }
                    okCount += 1
                } catch {
                    lastError = error
                    if includeNodes, let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
                        data = cached
                        fromCache = true
                        cacheCount += 1
                    }
                }
            } else if let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
                data = cached
                fromCache = true
                cacheCount += 1
            } else if fetch == false || (onlyIDs != nil && !shouldFetch) {
                // Cache miss while rebuilding / skipping this ID — try live once for enabled nodes.
                if includeNodes {
                    do {
                        let result = try await SubscriptionFetcher.fetch(
                            urlString: sub.url,
                            viaProxyPort: proxyPort
                        )
                        data = result.data
                        try data?.write(to: cacheURL, options: .atomic)
                        if let idx = settings.subscriptions.firstIndex(where: { $0.id == sub.id }) {
                            settings.subscriptions[idx].updatedAt = Date()
                            if let info = result.userInfo {
                                settings.subscriptions[idx].userInfo = info
                                trafficCount += 1
                            }
                        }
                        okCount += 1
                    } catch {
                        lastError = error
                    }
                }
            }

            guard includeNodes, let payload = data else { continue }
            do {
                let parsed = try ClashConfigParser.parse(payload)
                mergeSubscriptionNodes(parsed.nodes, subscriptionName: sub.name, into: &merged, seen: &seen)
                if shouldFetch, fromCache {
                    statusText = "\(sub.name) 拉取失败，已用本地缓存"
                }
            } catch {
                lastError = error
            }
        }

        // If we only fetched a subset, still merge the rest of enabled from cache.
        if fetch, let onlyIDs {
            for sub in enabled where !onlyIDs.contains(sub.id) {
                let cacheURL = Paths.subscriptionCacheURL(id: sub.id)
                guard let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty else { continue }
                if let parsed = try? ClashConfigParser.parse(cached) {
                    mergeSubscriptionNodes(parsed.nodes, subscriptionName: sub.name, into: &merged, seen: &seen)
                }
            }
        }

        persist()
        if enabled.isEmpty {
            statusText = "流量信息已刷新；请启用至少一个订阅以加载节点"
            return
        }
        if merged.isEmpty {
            statusText = "订阅加载失败：\(lastError?.localizedDescription ?? "无节点")"
            return
        }

        applyMergedNodes(merged)
        await applyConfig(reloadIfRunning: true)
        let onCount = enabled.count
        if fetch, onlyIDs == nil {
            let trafficNote = trafficCount > 0 ? "，流量 \(trafficCount)" : "，无流量头"
            if cacheCount > 0 {
                statusText = "已更新 \(nodes.count) 个节点（启用 \(onCount)，在线 \(okCount)，缓存 \(cacheCount)\(trafficNote)）"
            } else {
                statusText = "已更新 \(nodes.count) 个节点（启用 \(onCount)\(trafficNote)）"
            }
        } else if !fetch {
            // Keep single-update status if already set; otherwise show summary.
            if statusText.hasPrefix("已更新「") || statusText.contains("更新失败") {
                // preserve
            } else {
                statusText = "当前 \(onCount) 个订阅 · \(nodes.count) 个节点"
            }
        }
    }

    func runSpeedTest() async {
        await runSpeedTest(nodes: nil, label: nil)
    }

    /// Speed-test all nodes, or only the given subset (e.g. one region group).
    func runSpeedTest(nodes targetNodes: [ProxyNode]?, label: String?) async {
        guard !isTesting else { return }
        let snapshot = targetNodes ?? nodes
        guard !snapshot.isEmpty else {
            statusText = "没有可测速的节点"
            return
        }
        let scope = label.map { "（\($0)）" } ?? ""
        let testables = snapshot.filter { ClashConfigParser.isSpeedTestable($0) }
        guard !testables.isEmpty else {
            statusText = "没有可测速的节点（已跳过流量/到期占位节点）"
            return
        }
        isTesting = true
        testedCount = 0
        bumpNodeListRevision()
        var pendingDelays: [String: (Int, Date)] = [:]
        var lastNodesFlush = Date.distantPast
        defer {
            isTesting = false
            groupCacheSort = nil
            groupCache = []
            bumpNodeListRevision()
        }

        statusText = "测速中\(scope)…"
        if !isCoreVisiblyAlive {
            _ = await ensureCoreRunning()
        }
        let useAPI = isCoreVisiblyAlive || CoreHealth.mixedPortAlive(port: settings.mixedPort)
        let controller = useAPI ? settings.externalController : nil
        let perNodeTimeout = useAPI ? max(settings.testTimeoutMs, 5000) : max(settings.testTimeoutMs, 3000)
        let workers = settings.turboMode
            ? min(max(settings.concurrency, 1), 6)
            : min(max(settings.concurrency, 1), 4)
        let results = await tester.testAll(
            nodes: testables,
            timeoutMs: perNodeTimeout,
            concurrency: workers,
            controller: controller,
            secret: settings.secret,
            testURL: settings.testURL
        ) { [weak self] name, delay in
            guard let self else { return }
            pendingDelays[name] = (delay, Date())
            self.testedCount += 1
            let now = Date()
            let done = self.testedCount == testables.count
            if done || now.timeIntervalSince(lastNodesFlush) > 0.5 {
                lastNodesFlush = now
                for (nodeName, pair) in pendingDelays {
                    if let idx = self.nodes.firstIndex(where: { $0.name == nodeName }) {
                        self.nodes[idx].delayMs = pair.0
                        self.nodes[idx].testedAt = pair.1
                        self.settings.nodeDelayCache[self.nodes[idx].delayCacheKey] = pair.0
                    }
                }
                pendingDelays.removeAll(keepingCapacity: true)
                self.bumpNodeListRevision()
            }
            if done || now.timeIntervalSince(self.speedUITick) > 0.35 {
                self.speedUITick = now
                self.statusText = "测速\(scope) \(self.testedCount)/\(testables.count)"
            }
        }

        // Keep latency ranking so fastest nodes stay at the top.
        sortByDelay = true
        invalidateNodeCaches()

        let ok = results.filter { $0.delayMs > 0 }.count
        persistDelayCache(from: nodes)
        persist()
        statusText = "测速完成\(scope)：\(ok)/\(results.count) 可用" + (controller == nil ? "（TCP）" : "（代理）")

        if settings.autoSelectFastest {
            await selectFastestNodeIfAvailable()
        } else if settings.selectedNodeName == nil || settings.selectedNodeName == "AUTO" {
            await ensureUsableProxy(forceProbe: false, verifyGoogle: true)
        }
    }

    func setAutoSpeedTestEnabled(_ enabled: Bool) {
        settings.autoSpeedTestEnabled = enabled
        if enabled {
            sortByDelay = true
        }
        bumpChromeRevision()
        schedulePersist()
        restartAutoSpeedLoop()
        statusText = enabled
            ? "自动测速已开启（约每 \(max(3, settings.autoSpeedTestIntervalMinutes)) 分钟）"
            : "自动测速已关闭"
        if enabled, !isTesting, !nodes.isEmpty {
            Task { await runSpeedTest() }
        }
    }

    func setAutoSelectFastest(_ enabled: Bool) {
        settings.autoSelectFastest = enabled
        bumpChromeRevision()
        schedulePersist()
        if enabled {
            Task { await selectFastestNodeIfAvailable() }
        }
        statusText = enabled ? "已开启：自动选用最快节点" : "已关闭：自动选用最快节点"
    }

    func setTurboMode(_ enabled: Bool) async {
        settings.turboMode = enabled
        schedulePersist()
        writeConfig()
        if coreRunning {
            await applyConfig(reloadIfRunning: true)
        }
        statusText = enabled ? "已开启极速模式（多连接并发 + 懒测速）" : "已关闭极速模式"
    }

    func setDomainSniffing(_ enabled: Bool) async {
        settings.domainSniffing = enabled
        schedulePersist()
        writeConfig()
        if coreRunning, settings.turboMode {
            await applyConfig(reloadIfRunning: true)
        }
        statusText = enabled ? "已开启域名嗅探" : "已关闭域名嗅探"
    }

    func setDnsPreference(_ preference: DnsPreference) async {
        guard settings.dnsPreference != preference else { return }
        settings.dnsPreference = preference
        schedulePersist()
        writeConfig()
        await applyConfig(reloadIfRunning: true)
        statusText = "DNS：\(preference.title)"
    }

    func setLogoStyle(_ style: LogoStyle) {
        guard settings.logoStyle != style else { return }
        settings.logoStyle = style
        schedulePersist()
        statusText = "Logo：\(style.title)"
        // Dock icon render is heavy — keep UI instant, apply icon off the hot path.
        IconManager.applyAppIconAsync(style: style)
    }

    func setShowMenuBarTraffic(_ enabled: Bool) {
        settings.showMenuBarTraffic = enabled
        persist()
        bumpChromeRevision()
        statusText = enabled ? "菜单栏显示网速" : "菜单栏隐藏网速"
    }

    func setShowDockIcon(_ enabled: Bool) {
        settings.showDockIcon = enabled
        persist()
        AppActivation.preferDockIcon = enabled
        AppActivation.applyPolicy()
        if enabled {
            IconManager.applyAppIcon(style: settings.logoStyle)
        }
        objectWillChange.send()
        statusText = enabled ? "程序坞已显示图标" : "程序坞已隐藏图标"
    }

    func setNodeDisplayMode(_ mode: NodeDisplayMode) {
        guard settings.nodeDisplayMode != mode else { return }
        settings.nodeDisplayMode = mode
        persist()
        // PanelNodesHost only redraws on nodeListRevision — bump so list/card switch applies.
        nodeListRevision &+= 1
        statusText = "节点展示：\(mode.title)"
    }

    func setAppearance(_ appearance: AppAppearance) {
        settings.appearance = appearance
        persist()
        ThemeRefresh.apply(state: self)
        statusText = "主题：\(appearance.title)（已生效）"
    }

    func setUiLanguage(_ language: AppLanguage) {
        settings.uiLanguage = language
        L10n.apply(language)
        persist()
        bumpChromeRevision()
        ThemeRefresh.apply(state: self)
        objectWillChange.send()
        switch language {
        case .zh: statusText = L10n.t("lang.changed.zh", language)
        case .en: statusText = L10n.t("lang.changed.en", language)
        case .system: statusText = L10n.t("lang.changed.system", language)
        }
    }

    func setAutoSpeedTestIntervalMinutes(_ minutes: Int) {
        settings.autoSpeedTestIntervalMinutes = max(3, min(minutes, 120))
        persist()
        if settings.autoSpeedTestEnabled {
            restartAutoSpeedLoop()
        }
    }

    /// Pick the current lowest-latency node (delayMs > 0).
    func selectFastestNodeIfAvailable() async {
        guard let best = nodes.filter({ ($0.delayMs ?? -1) > 0 }).sorted(by: delaySort).first else {
            return
        }
        if settings.selectedNodeName != best.name {
            await selectNode(best.name)
            statusText = "已切换到最快节点：\(best.name)（\(best.delayMs ?? 0) ms）"
        }
    }

    func restartAutoSpeedLoop() {
        autoSpeedTask?.cancel()
        autoSpeedTask = nil
        guard settings.autoSpeedTestEnabled else { return }
        autoSpeedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isTesting, !self.nodes.isEmpty {
                    await self.runSpeedTest()
                }
                let mins = max(3, self.settings.autoSpeedTestIntervalMinutes)
                try? await Task.sleep(nanoseconds: UInt64(mins) * 60 * 1_000_000_000)
            }
        }
    }

    private func applyDelayCache(to list: [ProxyNode]) -> [ProxyNode] {
        list.map { node in
            var n = node
            if n.delayMs == nil, let cached = settings.nodeDelayCache[node.delayCacheKey] {
                n.delayMs = cached
            }
            return n
        }
    }

    private func persistDelayCache(from list: [ProxyNode]) {
        for node in list {
            if let ms = node.delayMs {
                settings.nodeDelayCache[node.delayCacheKey] = ms
            }
        }
    }

    /// Merge nodes from one subscription; prefix with subscription tag when names collide.
    private func mergeSubscriptionNodes(
        _ parsed: [ProxyNode],
        subscriptionName: String,
        into merged: inout [ProxyNode],
        seen: inout Set<String>
    ) {
        let tag = Self.subscriptionNodeTag(subscriptionName)
        for var node in parsed {
            var name = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if seen.contains(name) {
                name = uniqueNodeName(base: "\(tag)·\(node.name)", seen: &seen)
                node.name = name
                node.raw["name"] = AnyCodable(name)
            } else {
                seen.insert(name)
            }
            merged.append(node)
        }
    }

    /// Instant node list refresh from local caches (no network / core reload).
    @discardableResult
    private func rebuildEnabledNodesFromCache() -> Bool {
        let enabled = settings.subscriptions.filter(\.enabled)
        guard !enabled.isEmpty else {
            nodes = []
            invalidateNodeCaches()
            bumpNodeListRevision()
            return false
        }

        var merged: [ProxyNode] = []
        var seen = Set<String>()
        for sub in enabled {
            let cacheURL = Paths.subscriptionCacheURL(id: sub.id)
            guard let data = try? Data(contentsOf: cacheURL), !data.isEmpty,
                  let parsed = try? ClashConfigParser.parse(data) else { continue }
            mergeSubscriptionNodes(parsed.nodes, subscriptionName: sub.name, into: &merged, seen: &seen)
        }

        guard !merged.isEmpty else { return false }
        applyMergedNodes(merged)
        return true
    }

    private func applyMergedNodes(_ merged: [ProxyNode]) {
        let oldDelays = Dictionary(uniqueKeysWithValues: nodes.compactMap { n in
            n.delayMs.map { (n.name, ($0, n.testedAt)) }
        })
        let selected = settings.selectedNodeName
        nodes = merged.map { node in
            var n = node
            if let old = oldDelays[node.name] {
                n.delayMs = old.0
                n.testedAt = old.1
            } else if let cached = settings.nodeDelayCache[node.delayCacheKey] {
                n.delayMs = cached
            }
            return n
        }
        persistDelayCache(from: nodes)
        if let selected, !nodes.contains(where: { $0.name == selected }) {
            settings.selectedNodeName = nil
        }
        invalidateNodeCaches()
        bumpNodeListRevision()
    }

    private static func subscriptionNodeTag(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "订阅" }
        if trimmed.count <= 10 { return trimmed }
        return String(trimmed.prefix(9)) + "…"
    }

    private func uniqueNodeName(base: String, seen: inout Set<String>) -> String {
        if !seen.contains(base) {
            seen.insert(base)
            return base
        }
        var n = 2
        while seen.contains("\(base)(\(n))") { n += 1 }
        let final = "\(base)(\(n))"
        seen.insert(final)
        return final
    }

    /// Prefer subscription caches / last file / running config when memory list is empty.
    private func reloadNodesFromDiskIfNeeded() {
        guard nodes.isEmpty else { return }
        var merged: [ProxyNode] = []
        var seen = Set<String>()

        for sub in settings.subscriptions where sub.enabled {
            let url = Paths.subscriptionCacheURL(id: sub.id)
            if let data = try? Data(contentsOf: url),
               let parsed = try? ClashConfigParser.parse(data) {
                mergeSubscriptionNodes(parsed.nodes, subscriptionName: sub.name, into: &merged, seen: &seen)
            }
        }
        if merged.isEmpty,
           let data = try? Data(contentsOf: Paths.lastSubscriptionURL),
           let parsed = try? ClashConfigParser.parse(data) {
            mergeSubscriptionNodes(parsed.nodes, subscriptionName: "缓存", into: &merged, seen: &seen)
        }
        if merged.isEmpty,
           let data = try? Data(contentsOf: Paths.configURL),
           let parsed = try? ClashConfigParser.parse(data) {
            mergeSubscriptionNodes(parsed.nodes, subscriptionName: "配置", into: &merged, seen: &seen)
        }
        if !merged.isEmpty {
            nodes = applyDelayCache(to: merged)
            persistDelayCache(from: nodes)
            invalidateNodeCaches()
        }
    }

    /// Pick a live outbound so foreign traffic doesn't silently go DIRECT/dead AUTO.
    func ensureUsableProxy(forceProbe: Bool = true, verifyGoogle: Bool = false, verifyTelegram: Bool = false) async {
        reloadNodesFromDiskIfNeeded()
        guard coreRunning, !nodes.isEmpty else { return }

        if !forceProbe,
           let name = settings.selectedNodeName,
           name != "AUTO", name != "DIRECT",
           let node = nodes.first(where: { $0.name == name }),
           let delay = node.delayMs, delay > 0 {
            await syncSelectedOutbound()
            return
        }

        if let best = nodes.filter({ ($0.delayMs ?? -1) > 0 }).sorted(by: delaySort).first {
            await selectNode(best.name)
            statusText = "已选用可用节点：\(best.name)"
            return
        }

        guard forceProbe else {
            await syncSelectedOutbound()
            return
        }

        statusText = "正在挑选可用节点…"
        let keywords = ["香港", "日本", "新加坡", "台湾", "台灣", "美国", "美國", "韩国", "韓國"]
        var pool: [ProxyNode] = []
        var used = Set<String>()
        for key in keywords {
            for node in nodes where node.name.contains(key) && !used.contains(node.name) {
                used.insert(node.name)
                pool.append(node)
                if pool.filter({ $0.name.contains(key) }).count >= 2 { break }
            }
        }
        if pool.count < 6 {
            for node in nodes.prefix(16) where !used.contains(node.name) {
                pool.append(node)
            }
        }

        let results = await tester.testAll(
            nodes: Array(pool.prefix(16)),
            timeoutMs: max(settings.testTimeoutMs, 5000),
            concurrency: 4,
            controller: settings.externalController,
            secret: settings.secret,
            testURL: settings.testURL
        ) { [weak self] name, delay in
            guard let self else { return }
            if let idx = self.nodes.firstIndex(where: { $0.name == name }) {
                self.nodes[idx].delayMs = delay
                self.nodes[idx].testedAt = Date()
                self.settings.nodeDelayCache[self.nodes[idx].delayCacheKey] = delay
            }
            self.groupCache = []
            self.groupCacheSort = nil
        }

        persistDelayCache(from: nodes)
        persist()
        let ranked = results.filter { $0.delayMs > 0 }.sorted { $0.delayMs < $1.delayMs }
        if verifyTelegram {
            // Retest TELEGRAM url-test only — never fall through to selectNode (closes MTProto).
            await healTelegramGroupOnly()
            if !verifyGoogle { return }
        }
        if verifyGoogle {
            _ = await ClashCore.retestProxyGroup(
                controller: settings.externalController,
                secret: settings.secret,
                group: "GOOGLE",
                url: GoogleReliability.probeURL,
                timeoutMs: 6000
            )
            if await CoreHealth.googleReachable(port: settings.mixedPort) {
                statusText = "Google 线路已优化"
                return
            }
            for candidate in ranked.prefix(6) {
                try? await ClashCore.selectProxy(
                    controller: settings.externalController,
                    secret: settings.secret,
                    group: "GOOGLE",
                    name: candidate.name
                )
                if await CoreHealth.googleReachable(port: settings.mixedPort) {
                    statusText = "已自动选择（Google 可用）：\(candidate.name)（\(candidate.delayMs) ms）"
                    return
                }
            }
        }
        if let best = ranked.first {
            await selectNode(best.name)
            statusText = "已自动选择：\(best.name)（\(best.delayMs) ms）"
            return
        }

        settings.selectedNodeName = "AUTO"
        persist()
        await syncSelectedOutbound()
        statusText = "暂无快速可用节点，已切 AUTO — 请测速后手动选择"
    }

    func selectNode(_ name: String) async {
        guard settings.selectedNodeName != name else { return }
        settings.selectedNodeName = name
        // Chrome only — remounting the full node list on every switch was a major hitch.
        bumpChromeRevision()
        statusText = "切换中：\(name)"
        await Task.yield()

        schedulePersist()

        if coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) {
            applyCoreRunning(true)
            await syncSelectedOutbound()
            if settings.closeConnectionsOnSwitch {
                await ClashCore.closeAllConnections(
                    controller: settings.externalController,
                    secret: settings.secret
                )
            }
            statusText = "已切换：\(name)"
            scheduleOutboundIPRefresh()
        } else {
            statusText = "已选择：\(name)"
            outboundIP = "—"
        }
    }

    /// Query egress IP through mixed-port (debounced after node switch).
    func scheduleOutboundIPRefresh(delay: TimeInterval = 0.6) {
        outboundIPTask?.cancel()
        outboundIPTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.refreshOutboundIP()
        }
    }

    func refreshOutboundIP() async {
        guard coreRunning else {
            outboundIP = "—"
            outboundIPLoading = false
            return
        }
        guard CoreHealth.mixedPortAlive(port: settings.mixedPort) else {
            outboundIP = "端口未就绪"
            return
        }

        outboundIPLoading = true
        defer { outboundIPLoading = false }

        if Task.isCancelled { return }
        if let ip = await OutboundIPProbe.fetch(port: settings.mixedPort) {
            outboundIP = ip
        } else {
            outboundIP = "查询失败"
        }
    }

    func saveRulesFromEditor() async {
        let parsed = ClashRuleSyntax.parseLines(rulesText)
        let before = parsed.isEmpty ? AppSettings.defaultRules : parsed
        let sanitized = GeoSiteRules.sanitize(before)
        let removed = before.count - sanitized.count
        settings.rules = sanitized.isEmpty ? AppSettings.defaultRules : sanitized
        // Keep comments out of stored rules; editor shows active lines after save.
        rulesText = settings.rules.joined(separator: "\n")
        persist()
        await applyConfig(reloadIfRunning: true)
        if removed > 0 {
            statusText = "规则已保存（\(settings.rules.count) 条，已清理 \(removed) 条无效）"
        } else {
            statusText = "规则已保存并生效（\(settings.rules.count) 条"
                + (settings.videoAdBlockEnabled ? " · 含去广告 \(VideoAdBlock.ruleCount)" : "")
                + "）"
        }
    }

    func resetRules() {
        Task { await applyChinaSmartRules() }
    }

    func applyChinaSmartRules() async {
        settings.rules = ChinaSmartRules.rules
        settings.rulesVersion = ChinaSmartRules.version
        rulesText = settings.rules.joined(separator: "\n")
        ChinaSmartRules.publishRulesToDisk()
        persist()
        await applyConfig(reloadIfRunning: true)
        statusText = "已应用 BashX 智能规则 v\(ChinaSmartRules.version)（\(settings.rules.count) 条）"
    }

    func setSystemProxy(_ enabled: Bool) async {
        systemProxyTask?.cancel()
        systemProxyOn = enabled
        settings.systemProxyEnabled = enabled
        settings.userDisabledSystemProxy = !enabled
        bumpChromeRevision()
        statusText = enabled ? "正在开启系统代理…" : "正在关闭系统代理…"
        schedulePersist()
        await Task.yield()

        let port = settings.mixedPort
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if enabled {
                if !CoreHealth.mixedPortAlive(port: port) {
                    let ok = await self.waitForCoreReady(timeoutSeconds: 35)
                    guard !Task.isCancelled else { return }
                    guard ok else {
                        self.systemProxyOn = false
                        self.settings.systemProxyEnabled = false
                        self.bumpChromeRevision()
                        self.schedulePersist()
                        self.statusText = "内核未就绪，无法开启系统代理（请稍后重试或点「修复内核」）"
                        return
                    }
                } else {
                    self.applyCoreRunning(true)
                }
            }

            guard !Task.isCancelled else { return }
            let writeOK = await SystemProxy.setEnabledAsync(enabled, port: port)
            guard !Task.isCancelled else { return }

            if enabled, !writeOK {
                self.systemProxyOn = false
                self.settings.systemProxyEnabled = false
                self.bumpChromeRevision()
                self.schedulePersist()
                self.statusText = "系统代理写入失败，请检查网络权限 / 是否被其他代理占用"
                return
            }

            self.systemProxyOn = enabled
            self.bumpChromeRevision()
            let tunNote = self.settings.tunEnabled ? " · TUN 同步开着" : ""
            self.statusText = enabled
                ? "系统代理已开启 → 127.0.0.1:\(port)\(tunNote)"
                : "系统代理已关闭"

            if enabled {
                Task { await self.syncSelectedOutbound() }
            }
        }
        systemProxyTask = task
        await task.value
    }

    /// Rule → Global → Direct (ClashX-style hotkey target).
    func cycleProxyMode() async {
        let order: [ProxyMode] = [.rule, .global, .direct]
        guard let idx = order.firstIndex(of: settings.proxyMode) else {
            await setProxyMode(.rule)
            return
        }
        await setProxyMode(order[(idx + 1) % order.count])
    }

    func setMenuNodeLimit(_ limit: Int) {
        settings.menuNodeLimit = min(500, max(5, limit))
        schedulePersist()
        bumpChromeRevision()
    }

    /// Open mihomo web dashboard (local /ui or metacubexd).
    func openDashboard() {
        guard let url = dashboardURL else {
            statusText = "无法打开 Dashboard：external-controller 无效"
            return
        }
        NSWorkspace.shared.open(url)
        statusText = "已打开 Dashboard"
    }

    var dashboardURL: URL? {
        let host = settings.externalController.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        let port = settings.externalController.split(separator: ":").last.flatMap { Int($0) } ?? 19090
        let loopback = (host == "*" || host.isEmpty) ? "127.0.0.1" : host
        if coreRunning, loopback == "127.0.0.1" || loopback == "localhost" {
            var local = URLComponents()
            local.scheme = "http"
            local.host = loopback
            local.port = port
            local.path = "/ui"
            if !settings.secret.isEmpty {
                local.queryItems = [URLQueryItem(name: "secret", value: settings.secret)]
            }
            if let url = local.url { return url }
        }
        var remote = URLComponents(string: "https://metacubex.github.io/metacubexd/")!
        var query = [
            URLQueryItem(name: "hostname", value: loopback),
            URLQueryItem(name: "port", value: "\(port)"),
        ]
        let secret = settings.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            query.append(URLQueryItem(name: "secret", value: secret))
        }
        remote.queryItems = query
        return remote.url
    }

    func setProxyMode(_ mode: ProxyMode) async {
        guard settings.proxyMode != mode else {
            // Re-assert mode on core if UI already shows it but kernel drifted.
            if coreRunning {
                _ = await ClashCore.applyMode(
                    controller: settings.externalController,
                    secret: settings.secret,
                    mode: mode
                )
            }
            return
        }

        var adBlockNote = ""
        if settings.videoAdBlockEnabled, mode != .rule {
            settings.videoAdBlockEnabled = false
            adBlockNote = "（去广告已关闭）"
        }

        // Optimistic UI first — persist/yaml must not block the chip highlight.
        settings.proxyMode = mode
        bumpChromeRevision()
        statusText = "切换为\(mode.title)模式…"
        await Task.yield()

        schedulePersist()
        scheduleWriteConfig()

        if coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) {
            applyCoreRunning(true)
            var ok = await ClashCore.applyMode(
                controller: settings.externalController,
                secret: settings.secret,
                mode: mode
            )
            if !ok {
                // Hot-patch failed — full reload with yaml that already has the new mode.
                writeConfig()
                await applyConfig(reloadIfRunning: true)
                ok = await ClashCore.applyMode(
                    controller: settings.externalController,
                    secret: settings.secret,
                    mode: mode
                )
            }

            // rule/global need PROXY+GLOBAL selectors; direct ignores selectors.
            if mode != .direct {
                await syncSelectedOutbound()
            }
            if settings.closeConnectionsOnSwitch {
                await ClashCore.closeAllConnections(
                    controller: settings.externalController,
                    secret: settings.secret
                )
            }

            let verified = await ClashCore.fetchMode(
                controller: settings.externalController,
                secret: settings.secret
            )
            if let verified, verified != mode.rawValue {
                statusText = "模式切换未生效（内核=\(verified)），请重试或重启内核"
                bumpChromeRevision()
                return
            }
            statusText = ok
                ? "已切换为\(mode.title)模式\(adBlockNote)"
                : "已写入\(mode.title)模式，请确认流量是否符合预期\(adBlockNote)"
        } else {
            statusText = "已设为\(mode.title)模式（内核未运行，启动后生效）\(adBlockNote)"
        }
        bumpChromeRevision()
    }

    /// Keep PROXY + GLOBAL selectors on the selected leaf.
    /// Never pin TELEGRAM / GOOGLE — they are url-test groups and must pick healthy
    /// nodes independently (pinning them to PROXY is why Telegram spins while browsers work).
    func syncSelectedOutbound() async {
        let target = activeProxyTarget()
        for group in ["PROXY", "GLOBAL"] {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: group,
                name: target
            )
        }
    }

    /// Heal TELEGRAM path only — no PROXY switch, no closeAllConnections.
    private func healTelegramGroupOnly() async {
        guard coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) else { return }
        // Prefer Verge-style nested AUTO; fall back to TELEGRAM itself.
        let autoGroup = "TELEGRAM-AUTO"
        _ = await ClashCore.retestProxyGroup(
            controller: settings.externalController,
            secret: settings.secret,
            group: autoGroup,
            url: TelegramReliability.probeURL,
            timeoutMs: 8000
        )
        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: "TELEGRAM",
            name: autoGroup
        )
        if await CoreHealth.telegramReachable(port: settings.mixedPort) {
            statusText = "Telegram 线路已优化"
            return
        }
        let keywords = ["香港", "HK", "日本", "JP", "新加坡", "SG", "台湾", "TW", "美国", "US"]
        var candidates: [ProxyNode] = []
        var used = Set<String>()
        for key in keywords {
            for node in nodes where !used.contains(node.name)
                && node.name.localizedCaseInsensitiveContains(key)
                && (node.delayMs ?? -1) > 0 {
                used.insert(node.name)
                candidates.append(node)
                if candidates.count >= 8 { break }
            }
            if candidates.count >= 8 { break }
        }
        if candidates.isEmpty {
            candidates = nodes.filter { ($0.delayMs ?? -1) > 0 }.sorted(by: delaySort).prefix(8).map { $0 }
        } else {
            candidates.sort(by: delaySort)
        }
        for candidate in candidates.prefix(6) {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "TELEGRAM",
                name: candidate.name
            )
            if await CoreHealth.telegramReachable(port: settings.mixedPort) {
                statusText = "Telegram 已切：\(candidate.name)（\(candidate.delayMs ?? 0) ms）"
                return
            }
        }
    }

    func setTUN(_ enabled: Bool) async {
        userStoppedCore = false
        settings.tunEnabled = enabled
        if enabled {
            requestElevatedCoreStart = true
            runtimeTunInConfig = true
        } else {
            runtimeTunInConfig = false
        }
        bumpChromeRevision()
        statusText = enabled ? "正在开启 TUN（首次需授权，之后免密）…" : "正在关闭 TUN…"
        await Task.yield()
        schedulePersist()
        writeConfig()
        stopCore(clearProxy: false, force: true, markUserStopped: false)
        try? await Task.sleep(nanoseconds: 500_000_000)
        await startCoreAsync(forceRestart: true)
        if enabled {
            let tunOn = await CoreHealth.waitUntilTunEnabled(
                controller: settings.externalController,
                secret: settings.secret,
                attempts: 12,
                intervalNanoseconds: 250_000_000
            )
            if !coreRunning || !tunOn {
                let detail = statusText
                requestElevatedCoreStart = false
                runtimeTunInConfig = false
                settings.tunEnabled = false
                schedulePersist()
                writeConfig()
                await startCoreAsync(forceRestart: true)
                bumpChromeRevision()
                if detail.contains("取消") || detail.contains("管理员") || detail.contains("提权") || detail.contains("完整性") {
                    statusText = detail.contains("已回退") ? detail : "\(detail)（已回退普通模式）"
                } else if !ClashCore.isMihomoAlive() && detail.hasPrefix("启动失败") {
                    statusText = "\(detail)（已回退普通模式）"
                } else {
                    statusText = "TUN 未生效，已回退普通模式（需在弹出的密码框授权；勿取消）"
                }
                return
            }
            runtimeTunInConfig = true
            requestElevatedCoreStart = false
        } else {
            requestElevatedCoreStart = false
        }
        bumpChromeRevision()
        let proxyNote = systemProxyOn ? " · 系统代理同步开着" : ""
        statusText = enabled ? "TUN 已开启\(proxyNote)" : "TUN 已关闭"
    }

    /// Selected node, or AUTO when nodes exist, else DIRECT.
    func activeProxyTarget() -> String {
        if let name = settings.selectedNodeName,
           name == "DIRECT" || name == "AUTO" || nodes.contains(where: { $0.name == name }) {
            return name
        }
        return nodes.isEmpty ? "DIRECT" : "AUTO"
    }

    func writeConfig() {
        writeConfigTask?.cancel()
        writeConfigNow()
    }

    /// Coalesce rapid config rebuilds during bootstrap / bulk edits.
    func scheduleWriteConfig() {
        writeConfigTask?.cancel()
        writeConfigTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writeConfigNow()
        }
    }

    private func writeConfigNow() {
        let mergedRules = effectiveRuntimeRules()
        let yaml = ClashConfigParser.buildConfig(
            nodes: nodes,
            selectedName: settings.selectedNodeName,
            mixedPort: settings.mixedPort,
            controller: settings.externalController,
            secret: settings.secret,
            rules: mergedRules,
            tunEnabled: effectiveTunInConfig(),
            tunStack: settings.tunStack,
            mode: settings.proxyMode,
            allowLan: settings.allowLan,
            turboMode: settings.turboMode,
            domainSniffing: settings.domainSniffing,
            dnsPreference: settings.dnsPreference
        )
        guard !yaml.isEmpty else {
            statusText = "配置生成失败"
            return
        }
        do {
            try yaml.data(using: .utf8)?.write(to: Paths.configURL, options: .atomic)
        } catch {
            statusText = "写入 config.yaml 失败：\(error.localizedDescription)"
        }
    }

    /// TUN in yaml only when elevated start succeeded — avoids boot crash without admin rights.
    private func effectiveTunInConfig() -> Bool {
        settings.tunEnabled && runtimeTunInConfig
    }

    /// Rules written to mihomo — prepend (Merge) + base + optional video-ad REJECT.
    func effectiveRuntimeRules() -> [String] {
        RuntimeRules.effective(
            base: settings.rules,
            prepend: settings.rulesPrepend,
            videoAdBlockEnabled: settings.videoAdBlockEnabled
        )
    }

    func saveRulesPrependFromEditor(_ text: String) async {
        let parsed = ClashRuleSyntax.parseLines(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("MATCH,") }
        let sanitized = GeoSiteRules.sanitize(parsed)
        settings.rulesPrepend = sanitized
        persist()
        await applyConfig(reloadIfRunning: true)
        statusText = sanitized.isEmpty
            ? "自定义前置规则已清空"
            : "自定义前置规则已保存（\(sanitized.count) 条，更新订阅/智能规则不会覆盖）"
    }

    func setCloseConnectionsOnSwitch(_ enabled: Bool) {
        settings.closeConnectionsOnSwitch = enabled
        schedulePersist()
        bumpChromeRevision()
        statusText = enabled ? "切节点时关闭旧连接" : "切节点时保留旧连接"
    }

    /// Select a member inside a named proxy-group (GOOGLE / TELEGRAM / AUTO / PROXY).
    func selectGroupProxy(group: String, name: String) async {
        guard coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) else {
            statusText = "内核未运行，无法切换 \(group)"
            return
        }
        applyCoreRunning(true)
        statusText = "切换 \(group) → \(name)"
        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: group,
            name: name
        )
        if settings.closeConnectionsOnSwitch {
            await ClashCore.closeAllConnections(
                controller: settings.externalController,
                secret: settings.secret
            )
        }
        if group == "PROXY" || group == "GLOBAL" {
            settings.selectedNodeName = name
            schedulePersist()
            bumpChromeRevision()
            scheduleOutboundIPRefresh()
        } else {
            bumpChromeRevision()
        }
        statusText = "\(group) 已选：\(name)"
    }

    func fetchMenuProxyGroups() async -> [ClashCore.ProxyGroupInfo] {
        guard coreRunning else { return [] }
        var out: [ClashCore.ProxyGroupInfo] = []
        for name in ["GOOGLE", "TELEGRAM", "AUTO"] {
            if let info = await ClashCore.fetchProxyGroup(
                controller: settings.externalController,
                secret: settings.secret,
                group: name
            ), !info.all.isEmpty {
                out.append(info)
            }
        }
        return out
    }

    func setVideoAdBlock(_ enabled: Bool) async {
        settings.videoAdBlockEnabled = enabled
        // mihomo only evaluates REJECT rules in `rule` mode — global/direct skip all rules.
        if enabled, settings.proxyMode != .rule {
            settings.proxyMode = .rule
        }
        bumpChromeRevision()
        statusText = enabled ? "正在开启去广告…" : "正在关闭去广告…"
        await Task.yield()
        schedulePersist()
        scheduleWriteConfig()
        await applyConfig(reloadIfRunning: true)
        bumpChromeRevision()
        if enabled {
            statusText = "去广告已开启（\(VideoAdBlock.ruleCount) 条）· 规则模式"
        } else {
            statusText = "去广告已关闭"
        }
    }

    /// Local mixed-port for other apps (HTTP + SOCKS same port).
    var externalProxyHost: String {
        settings.allowLan ? (LocalNetwork.primaryIPv4() ?? "0.0.0.0") : "127.0.0.1"
    }

    var externalProxyAddress: String {
        "\(externalProxyHost):\(settings.mixedPort)"
    }

    var externalProxyHTTPURL: String {
        "http://\(externalProxyAddress)"
    }

    var externalProxySOCKSURL: String {
        "socks5://\(externalProxyAddress)"
    }

    func copyExternalProxy(kind: ExternalProxyCopyKind = .hostPort) {
        let text: String = {
            switch kind {
            case .hostPort: return externalProxyAddress
            case .http: return externalProxyHTTPURL
            case .socks: return externalProxySOCKSURL
            case .exportEnv:
                return """
                export https_proxy=\(externalProxyHTTPURL)
                export http_proxy=\(externalProxyHTTPURL)
                export all_proxy=\(externalProxySOCKSURL)
                """
            }
        }()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "已复制外置代理：\(kind.title)"
    }

    func setAllowLan(_ enabled: Bool) async {
        if enabled {
            if settings.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.secret = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))
            }
            // Keep API on loopback even when mixed-port is LAN-facing.
            if !settings.externalController.hasPrefix("127.0.0.1:")
                && !settings.externalController.hasPrefix("localhost:") {
                let port = settings.externalController.split(separator: ":").last.map(String.init) ?? "19090"
                settings.externalController = "127.0.0.1:\(port)"
            }
        }
        settings.allowLan = enabled
        persist()
        await applyConfig(reloadIfRunning: true)
        // allow-lan / bind-address often need core restart to take effect.
        if coreRunning {
            await startCoreAsync(forceRestart: true)
        }
        statusText = enabled
            ? "已允许局域网：其他设备可用 \(externalProxyAddress)（API 仍限本机，已确保 secret）"
            : "仅本机可用：127.0.0.1:\(settings.mixedPort)"
    }

    func setMixedPort(_ port: Int) async {
        let p = min(65535, max(1024, port))
        guard p != settings.mixedPort else { return }
        let wasProxy = systemProxyOn || settings.systemProxyEnabled
        if wasProxy {
            SystemProxy.setEnabled(false, port: settings.mixedPort)
        }
        settings.mixedPort = p
        persist()
        writeConfig()
        if coreRunning {
            await startCoreAsync(forceRestart: true)
        }
        if wasProxy, coreRunning {
            await setSystemProxy(true)
        }
        statusText = "外置代理端口已改为 \(p)"
    }

    enum ExternalProxyCopyKind {
        case hostPort, http, socks, exportEnv
        var title: String {
            switch self {
            case .hostPort: return "主机:端口"
            case .http: return "HTTP"
            case .socks: return "SOCKS5"
            case .exportEnv: return "环境变量"
            }
        }
    }

    func refreshLaunchAtLogin() {
        let on = LaunchAtLogin.isEnabled
        if settings.launchAtLoginEnabled != on {
            settings.launchAtLoginEnabled = on
            persist()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let ok = LaunchAtLogin.setEnabled(enabled)
        settings.launchAtLoginEnabled = LaunchAtLogin.isEnabled
        persist()
        if enabled, !ok {
            statusText = "开机启动开启失败：\(LaunchAtLogin.statusText)"
        } else {
            statusText = enabled ? "已开启开机自动启动" : "已关闭开机自动启动"
        }
    }

    func applyConfig(reloadIfRunning: Bool) async {
        writeConfig()
        guard reloadIfRunning, coreRunning else { return }
        do {
            try await ClashCore.reloadConfig(
                controller: settings.externalController,
                secret: settings.secret,
                path: Paths.configURL.path
            )
            let target = activeProxyTarget()
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "PROXY",
                name: target
            )
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "GLOBAL",
                name: target
            )
            _ = await ClashCore.applyMode(
                controller: settings.externalController,
                secret: settings.secret,
                mode: settings.proxyMode
            )
        } catch {
            statusText = "热重载失败，正在重启内核…"
            stopCore(clearProxy: false, markUserStopped: false)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await startCoreAsync(forceRestart: true)
        }
    }

    func installOrRepairCore() async {
        isBusy = true
        defer { isBusy = false }
        if let path = CoreInstaller.seedEmbeddedCoreIfNeeded() {
            settings.clashBinaryPath = path
            schedulePersist()
            statusText = "内置内核已就绪：\(CoreInstaller.pinnedVersion)"
            return
        }
        do {
            let path = try await CoreInstaller.ensureInstalled { [weak self] msg in
                self?.statusText = msg
            }
            settings.clashBinaryPath = path
            schedulePersist()
            statusText = "内核已就绪：\(path)"
        } catch {
            statusText = "安装内核失败：\(error.localizedDescription)"
        }
    }

    func startCore() {
        userStoppedCore = false
        Task { await startCoreAsync() }
    }

    @discardableResult
    func ensureCoreRunning() async -> Bool {
        userStoppedCore = false
        if await coreIsHealthy() {
            await applyDefaultSystemProxyIfEnabled()
            return true
        }
        for attempt in 1...5 {
            await startCoreAsync(forceRestart: attempt > 1)
            if await coreIsHealthy() {
                await applyDefaultSystemProxyIfEnabled()
                return true
            }
            if attempt < 5 {
                migrateBusyPortsIfNeeded()
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
        return false
    }

    func startCoreAsync(forceRestart: Bool = false) async {
        if userStoppedCore && !forceRestart { return }

        if coreStartInFlight {
            if !forceRestart {
                _ = await waitForCoreReady(timeoutSeconds: 40)
                return
            }
            for _ in 0..<60 {
                if !coreStartInFlight { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        if !forceRestart {
            let api = await CoreHealth.apiAlive(controller: settings.externalController, secret: settings.secret)
            let port = CoreHealth.mixedPortAlive(port: settings.mixedPort)
            if api && port {
                applyCoreRunning(true)
                if nodes.isEmpty { reloadNodesFromDiskIfNeeded() }
                scheduleOutboundIPRefresh()
                return
            }
        }

        coreStartInFlight = true
        let wasConnecting = coreConnecting
        if !wasConnecting {
            coreConnecting = true
            bumpChromeRevision()
        }
        defer {
            coreStartInFlight = false
            if coreConnecting {
                coreConnecting = false
                bumpChromeRevision()
            }
        }
        userStoppedCore = false
        lastCoreRestartAttempt = Date()

        sanitizeRulesForCore()
        migrateBusyPortsIfNeeded()

        if let existing = coreProcess, existing.isRunning {
            existing.terminate()
            coreProcess = nil
        }
        let binaryHint = ClashCore.resolveBinary(customPath: settings.clashBinaryPath)
            ?? CoreInstaller.bundledPath.path

        // Stop stale processes only when we actually need a fresh start.
        await ClashCore.stopAllAndWaitAsync(binaryHint: binaryHint, timeoutSeconds: 2.0)

        let controllerHost = settings.externalController.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        let controllerPort = Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? 19090

        // If something is still holding ports…
        var portBusy = PortProbe.isListening(port: settings.mixedPort)
            || PortProbe.isListening(host: controllerHost, port: controllerPort)

        if portBusy {
            // Alive API on those ports → already our core (or compatible).
            await refreshCoreStatus()
            if coreRunning, !forceRestart, !settings.tunEnabled {
                statusText = "内核已在运行"
                return
            }
            // Prefer port migration — elevated kill is bundled into TUN start (single password).
            ClashCore.stopAll(binaryHint: binaryHint)
            migrateBusyPortsIfNeeded()
            portBusy = PortProbe.isListening(port: settings.mixedPort)
                || PortProbe.isListening(host: controllerHost, port: Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? controllerPort)
            if portBusy, ClashCore.isMihomoAlive() == false {
                // Last resort: bump ports so start can proceed.
                if let freeMix = PortProbe.firstFreePort(from: settings.mixedPort + 1, limit: 40) {
                    settings.mixedPort = freeMix
                }
                if let freeAPI = PortProbe.firstFreePort(from: controllerPort + 1, limit: 40) {
                    settings.externalController = "\(controllerHost):\(freeAPI)"
                }
                persist()
            }
        }

        let finalControllerHost = settings.externalController.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        let finalControllerPort = Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? 19090
        if PortProbe.isListening(port: settings.mixedPort)
            || PortProbe.isListening(host: finalControllerHost, port: finalControllerPort) {
            await refreshCoreStatus()
            if coreRunning, !forceRestart {
                statusText = "内核已在运行"
                return
            }
            migrateBusyPortsIfNeeded()
            if PortProbe.isListening(port: settings.mixedPort)
                || PortProbe.isListening(host: finalControllerHost, port: finalControllerPort) {
                if let freeMix = PortProbe.firstFreePort(from: settings.mixedPort + 1, limit: 40) {
                    settings.mixedPort = freeMix
                }
                if let freeAPI = PortProbe.firstFreePort(from: finalControllerPort + 1, limit: 40) {
                    settings.externalController = "\(finalControllerHost):\(freeAPI)"
                }
                persist()
                writeConfig()
            }
        }

        do {
            let binary = try await CoreInstaller.ensureInstalled { [weak self] msg in
                self?.statusText = msg
            }
            settings.clashBinaryPath = binary
            persist()
            if nodes.isEmpty {
                _ = rebuildEnabledNodesFromCache()
                if nodes.isEmpty { reloadNodesFromDiskIfNeeded() }
            }

            var attempt = 0
            var lastFailDetail = ""
            // Clash Verge style: if user wants TUN and helper is ready, always elevate + write tun.
            // Bug was: requestElevatedCoreStart only set on toggle → restart dropped TUN from yaml
            // while UI still showed TUN on → Telegram MTProto UDP bypassed SOCKS and spun forever.
            if settings.tunEnabled, TunPrivilege.isReady {
                requestElevatedCoreStart = true
                runtimeTunInConfig = true
            }
            let wantTUN = settings.tunEnabled && (requestElevatedCoreStart || TunPrivilege.isReady)
            var useRoot = wantTUN
            if settings.tunEnabled, !useRoot {
                runtimeTunInConfig = false
            } else if wantTUN {
                runtimeTunInConfig = true
            }
            var didElevate = false
            while attempt < 3 {
                attempt += 1
                writeConfig()

                let aliveBefore = ClashCore.isMihomoAlive()
                // Avoid a second admin password prompt when the elevated process is already up
                // but TUN / API just needed more time.
                if useRoot, didElevate, aliveBefore {
                    statusText = "等待 TUN 就绪…"
                } else {
                    coreProcess = try ClashCore.start(
                        binary: binary,
                        configDir: Paths.supportDir,
                        asRoot: useRoot
                    )
                    if useRoot {
                        didElevate = true
                        requestElevatedCoreStart = false
                    }
                    statusText = attempt == 1 ? "正在启动内核…" : "正在以修复配置重启内核…"
                }

                var ready = false
                let maxWait = effectiveTunInConfig() ? 60 : 50
                for _ in 0..<maxWait {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if let proc = coreProcess, !proc.isRunning, !effectiveTunInConfig() {
                        break
                    }
                    let api = await CoreHealth.apiAlive(
                        controller: settings.externalController,
                        secret: settings.secret
                    )
                    let port = CoreHealth.mixedPortAlive(port: settings.mixedPort)
                    if api && port {
                        ready = true
                        break
                    }
                }
                applyCoreRunning(ready)

                if ready, effectiveTunInConfig() {
                    var tunOn = await CoreHealth.waitUntilTunEnabled(
                        controller: settings.externalController,
                        secret: settings.secret,
                        attempts: 16,
                        intervalNanoseconds: 250_000_000
                    )
                    if !tunOn {
                        // Hot-enable once — config may have been loaded before utun was ready.
                        try? await ClashCore.patchConfig(
                            controller: settings.externalController,
                            secret: settings.secret,
                            body: [
                                "tun": [
                                    "enable": true,
                                    "stack": settings.tunStack.isEmpty ? "mixed" : settings.tunStack,
                                    "auto-route": true,
                                    "auto-detect-interface": true,
                                    "dns-hijack": ["any:53"],
                                    "strict-route": false
                                ]
                            ]
                        )
                        tunOn = await CoreHealth.waitUntilTunEnabled(
                            controller: settings.externalController,
                            secret: settings.secret,
                            attempts: 12,
                            intervalNanoseconds: 250_000_000
                        )
                    }
                    if tunOn {
                        runtimeTunInConfig = true
                    } else {
                        ready = false
                        runtimeTunInConfig = false
                        applyCoreRunning(false)
                        statusText = "内核已起但 TUN 未生效"
                    }
                }

                if ready {
                    let target = activeProxyTarget()
                    try? await ClashCore.selectProxy(
                        controller: settings.externalController,
                        secret: settings.secret,
                        group: "PROXY",
                        name: target
                    )
                    try? await ClashCore.selectProxy(
                        controller: settings.externalController,
                        secret: settings.secret,
                        group: "GLOBAL",
                        name: target
                    )
                    _ = await ClashCore.applyMode(
                        controller: settings.externalController,
                        secret: settings.secret,
                        mode: settings.proxyMode
                    )
                    statusText = effectiveTunInConfig()
                        ? "内核运行中（TUN）· \(settings.proxyMode.title)"
                        : (settings.tunEnabled
                            ? "内核运行中 · \(settings.mixedPort)（TUN 待开启）"
                            : "内核运行中 · \(settings.mixedPort) · \(settings.proxyMode.title)")
                    if settings.selectedNodeName == nil || settings.selectedNodeName == "AUTO" {
                        await ensureUsableProxy(forceProbe: true, verifyGoogle: true)
                    }
                    // Kick TELEGRAM url-test so Desktop doesn't sit on a dead leaf after restart.
                    Task { await self.healTelegramGroupOnly() }
                    scheduleOutboundIPRefresh()
                    await applyDefaultSystemProxyIfEnabled()
                    return
                }

                lastFailDetail = Self.tailLog(
                    Paths.supportDir.appendingPathComponent("core.log"),
                    maxBytes: 8192
                )

                // Elevated core is alive but TUN flaky: rewrite stack / rules and reload — no 2nd password.
                if wantTUN, ClashCore.isMihomoAlive(), attempt < 3 {
                    var mutated = false
                    if settings.tunStack != "system" {
                        settings.tunStack = "system"
                        persist()
                        mutated = true
                        statusText = "改用 system 协议栈重试 TUN…"
                    }
                    if let missing = GeoSiteRules.parseMissingGeoSite(from: lastFailDetail) {
                        stripGeoSiteRule(named: missing)
                        mutated = true
                        statusText = "已移除无效规则 GEOSITE,\(missing)…"
                    } else if lastFailDetail.localizedCaseInsensitiveContains("geosite")
                                || lastFailDetail.localizedCaseInsensitiveContains("parse config") {
                        sanitizeRulesForCore()
                        mutated = true
                    }
                    if mutated {
                        writeConfig()
                        try? await ClashCore.reloadConfig(
                            controller: settings.externalController,
                            secret: settings.secret,
                            path: Paths.configURL.path
                        )
                        didElevate = true
                        useRoot = true
                        continue
                    }
                }

                await ClashCore.stopAllAndWaitAsync(binaryHint: binary, timeoutSeconds: 1.5)
                coreProcess = nil
                applyCoreRunning(false)
                didElevate = false
                useRoot = wantTUN

                if attempt < 3 {
                    if let missing = GeoSiteRules.parseMissingGeoSite(from: lastFailDetail) {
                        stripGeoSiteRule(named: missing)
                        statusText = "已移除无效规则 GEOSITE,\(missing)…"
                        continue
                    }
                    if lastFailDetail.localizedCaseInsensitiveContains("geosite")
                        || lastFailDetail.localizedCaseInsensitiveContains("parse config") {
                        sanitizeRulesForCore()
                        continue
                    }
                }
                break
            }

            if settings.systemProxyEnabled || systemProxyOn {
                SystemProxy.setEnabled(false, port: settings.mixedPort)
                systemProxyOn = false
            }
            statusText = "内核启动失败\(lastFailDetail.isEmpty ? "" : " · \(lastFailDetail)")"
        } catch {
            statusText = "启动失败：\(error.localizedDescription)"
            applyCoreRunning(false)
        }
    }

    func stopCore(clearProxy: Bool = true, force: Bool = false, markUserStopped: Bool = true) {
        if markUserStopped { userStoppedCore = true }
        if let process = coreProcess, process.isRunning {
            process.terminate()
            coreProcess = nil
        }
        // Disable TUN via API first so network effect stops immediately (no password).
        ClashCore.disableTUNViaAPI(
            controller: settings.externalController,
            secret: settings.secret
        )
        let hint = ClashCore.resolveBinary(customPath: settings.clashBinaryPath)
        // Fire stop signal; don't block MainActor — userStoppedCore prevents auto-restart.
        ClashCore.stopAll(binaryHint: hint)
        applyCoreRunning(false)

        if clearProxy, settings.systemProxyEnabled || systemProxyOn {
            SystemProxy.setEnabled(false, port: settings.mixedPort)
            systemProxyOn = false
            settings.systemProxyEnabled = false
            persist()
        }
        statusText = ClashCore.isMihomoAlive()
            ? "已请求停止（若仍残留，下次开 TUN 时清理）"
            : "已停止内核"
    }

    /// Cleanup before exit (proxy + core). Never blocks or asks for password.
    func prepareForQuit() {
        healthTask?.cancel()
        healthTask = nil
        launchGuardTask?.cancel()
        launchGuardTask = nil
        telegramGuardTask?.cancel()
        telegramGuardTask = nil
        autoSpeedTask?.cancel()
        autoSpeedTask = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        persistTask?.cancel()
        writeConfigTask?.cancel()
        persist()
        if systemProxyOn || settings.systemProxyEnabled {
            SystemProxy.setEnabled(false, port: settings.mixedPort)
            systemProxyOn = false
        }
        userStoppedCore = true
        coreProcess?.terminate()
        coreProcess = nil
        applyCoreRunning(false)
        let controller = settings.externalController
        let secret = settings.secret
        let hint = ClashCore.resolveBinary(customPath: settings.clashBinaryPath)
        ClashCore.disableTUNViaAPI(controller: controller, secret: secret)
        ClashCore.stopAll(binaryHint: hint)
    }

    func quitApp() {
        prepareForQuit()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    func refreshCoreStatus() async {
        // Soft: only promote online. Demotion is handled by healthTick streaks
        // so a single slow /configs probe can't flash「内核未启动」.
        _ = await probeCoreAlive()
    }

    func openConfigFolder() {
        NSWorkspace.shared.open(Paths.supportDir)
    }

    func subscriptionCacheURL(for id: UUID) -> URL {
        Paths.subscriptionCacheURL(id: id)
    }

    func subscriptionCachePathLabel(for id: UUID) -> String {
        Paths.shortPath(Paths.subscriptionCacheURL(id: id))
    }

    func subscriptionCacheExists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: Paths.subscriptionCacheURL(id: id).path)
    }

    /// Reveal cached subscription payload in Finder (or open subs folder if not downloaded yet).
    func revealSubscriptionFile(id: UUID) {
        let url = Paths.subscriptionCacheURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusText = "已在 Finder 中显示订阅文件"
        } else {
            NSWorkspace.shared.open(Paths.subscriptionsCacheDir)
            statusText = "订阅尚未缓存，已打开 subs 目录"
        }
    }

    func copySelectedProxyLine() {
        guard let name = settings.selectedNodeName,
              let node = nodes.first(where: { $0.name == name }) else { return }
        let line = "\(node.name) | \(node.type) | \(node.server):\(node.port) | \(node.delayText)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
        statusText = "已复制节点信息"
    }

    private static func tailLog(_ url: URL, maxBytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            try handle.seek(toOffset: start)
            let data = handle.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            // Prefer fatal/error lines for user-facing hints.
            let lines = text.split(separator: "\n").map(String.init)
            if let fatal = lines.last(where: { $0.localizedCaseInsensitiveContains("fatal") }) {
                return fatal
            }
            if let err = lines.last(where: { $0.localizedCaseInsensitiveContains("error") }) {
                return err
            }
            return lines.suffix(2).joined(separator: " | ")
        } catch {
            return ""
        }
    }

    private func delaySort(_ lhs: ProxyNode, _ rhs: ProxyNode) -> Bool {
        func rank(_ ms: Int?) -> Int {
            guard let ms else { return 1_000_000_000 }
            if ms < 0 { return 1_000_000_001 }
            return ms
        }
        let a = rank(lhs.delayMs)
        let b = rank(rhs.delayMs)
        if a != b { return a < b }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
