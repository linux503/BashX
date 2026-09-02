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
    /// `nil` = full test; otherwise the region group key being tested.
    @Published private(set) var speedTestScopeKey: String?
    /// Invalidates in-flight speed-test callbacks after timeout / cancel.
    private var speedTestToken = UUID()
    /// Progress counter — not @Published (was redrawing the whole panel every probe).
    var testedCount = 0
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
        case groups
    }
    @Published var panelIntent: PanelIntent = .none

    /// Current outbound IP via local proxy (updated after node switch).
    @Published var outboundIP: String = "—"
    @Published var outboundIPLoading = false
    /// Resolved leaf proxy name from mihomo (e.g. actual node behind AUTO).
    @Published var runtimeOutboundName: String?
    /// Settings: show launch diagnostic panel when bootstrap failed.
    @Published private(set) var launchHasError = false
    @Published private(set) var launchDiagnosticReport = ""
    /// True while bootstrap / startCoreAsync is bringing mihomo up.
    @Published private(set) var coreConnecting = false
    /// Bumped when node list / filters change — isolated views subscribe instead of whole AppState.
    @Published private(set) var nodeListRevision = 0
    /// Bumped when PROXY hub mode chips change — nodes pane header subscribes.
    @Published private(set) var hubModeRevision = 0
    /// Bumped when chrome (core/proxy/TUN/outbound) changes — sidebar + top bar subscribe.
    @Published private(set) var chromeRevision = 0
    /// Rare layout switches (极简/完整、主题、语言) — MainView listens to this, not chrome.
    @Published private(set) var layoutRevision = 0
    /// Mirrors SMAppService login-item state — panel + menu bar read this (not stale JSON).
    @Published private(set) var launchAtLoginOn = false
    /// Bumped when subscription list / enable flags change — subscription UI subscribes.
    @Published private(set) var subscriptionsRevision = 0
    /// Bumped when per-app routing rules change — apps pane subscribes.
    @Published private(set) var appRoutingRevision = 0
    /// Last known mixed-port TCP state (updated off main / from health ticks).
    @Published private(set) var mixedPortCachedAlive = false

    private var coreProcess: Process?
    private var outboundIPTask: Task<Void, Never>?
    private var runtimeOutboundTask: Task<Void, Never>?
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
    private var lastTelegramTunAssist = Date.distantPast
    private var lastTelegramRoutePatch = Date.distantPast
    private var telegramTunAssistInFlight = false
    private var cursorGuardTask: Task<Void, Never>?
    private var lastCursorNodeProbe = Date.distantPast
    private var persistTask: Task<Void, Never>?
    private var chromeBumpTask: Task<Void, Never>?
    private var writeConfigTask: Task<Void, Never>?
    private var writeConfigBuildTask: Task<Void, Never>?
    private var coreHealthMissStreak = 0
    private var coreHealthAliveStreak = 0
    private var coreHealthDeadStreak = 0
    /// Prevent overlapping repair / install work (was freezing UI + ballooning memory).
    private var coreRepairInFlight = false
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
    /// Consecutive speed-test failures per `delayCacheKey` (circuit breaker).
    private var nodeFailStreak: [String: Int] = [:]

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

    func bumpHubModeRevision() {
        hubModeRevision &+= 1
    }

    /// Refresh panel chrome (sidebar / top bar) without rebuilding the whole node list.
    /// Coalesce rapid bumps (proxy toggle + health + rates) so SwiftUI isn't remounting
    /// sidebar/top-bar hosts several times in one runloop burst.
    func bumpChromeRevision() {
        chromeBumpTask?.cancel()
        chromeBumpTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self else { return }
            self.chromeRevision &+= 1
        }
    }

    func bumpLayoutRevision() {
        layoutRevision &+= 1
    }

    func bumpSubscriptionsRevision() {
        subscriptionsRevision &+= 1
    }

    func bumpAppRoutingRevision() {
        appRoutingRevision &+= 1
    }

    /// Reassign so nested app-routing edits reliably publish to SwiftUI.
    private func mutateAppRoutingRules(_ block: (inout [AppRoutingRule]) -> Void) {
        var rules = settings.appRoutingRules
        block(&rules)
        settings.appRoutingRules = rules
        bumpAppRoutingRevision()
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
        bumpChromeRevision()
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

    /// UI-facing online flag. Uses cached port probe only — never blocks SwiftUI bodies.
    var isCoreVisiblyAlive: Bool {
        coreRunning || mixedPortCachedAlive
    }

    private func applyCoreRunning(_ alive: Bool) {
        guard coreRunning != alive else { return }
        coreRunning = alive
        if alive {
            coreHealthDeadStreak = 0
            coreHealthMissStreak = 0
            mixedPortCachedAlive = true
        }
        bumpChromeRevision()
    }

    /// Soft probe for UI / recovery — promotes online, never demotes (avoids status flicker).
    private func probeCoreAlive() async -> Bool {
        let port = await CoreHealth.mixedPortAliveAsync(port: settings.mixedPort)
        mixedPortCachedAlive = port
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
        // Port migrate deferred to bootstrapRuntime (PortProbe must not block init).
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
        migrateCursorAppRouting()
        migrateCursorReliabilitySettings()
        migrateMacAppBypassRouting()
        migrateAdsPowerProxyChain()
        migrateAnyDeskProxyRouting()
        migrateMacPluginCatalog()
        migrateNodeDisplayModeToCard()
        migrateTunDefaultOn()
        systemProxyOn = settings.systemProxyEnabled
        // Defer huge rulesText join — only needed when Rules tab opens.
        rulesText = ""
        clampPerfDefaults()
        settings.nodeDelayCache = pruneNodeDelayCache(settings.nodeDelayCache)
        launchAtLoginOn = LaunchAtLogin.isEnabled
        if settings.launchAtLoginEnabled != launchAtLoginOn {
            settings.launchAtLoginEnabled = launchAtLoginOn
        }
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
        LaunchDiagnostics.beginSession()

        let quit = await CompetingProxyApps.quitAllOnLaunch()
        if !quit.isEmpty {
            let msg = "已退出其他代理：\(quit.joined(separator: "、"))"
            statusText = msg
            LaunchDiagnostics.info(msg)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        coreConnecting = true
        defer {
            coreConnecting = false
            bumpChromeRevision()
        }

        // Always rebuild from every enabled subscription cache before writing config / starting core.
        // (Avoids "only ~15 nodes" from lastSubscriptionURL overwriting the merged pool.)
        if !rebuildEnabledNodesFromCache() {
            reloadNodesFromDiskIfNeeded()
        }
        refreshLaunchAtLogin()
        sanitizeRulesForCore()
        migrateTelegramRoutingDefaults()
        migrateMacAppBypassRouting()
        migrateAdsPowerProxyChain()
        migrateAnyDeskProxyRouting()
        await migrateBusyPortsIfNeeded()

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

        // GEOSITE/GEOIP rules need geoip.metadb + geosite.dat — download before first core start on new Macs.
        await ensureGeoDataReady(progress: true)

        // GFWList / Shadowrocket are large — fetch after core is up (see background Task below).

        // Always start (or attach to) mihomo when the app opens.
        await ensureCoreAtLaunch()
        await refreshCoreStatus()

        if settings.tunEnabled || settings.systemProxyEnabled {
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
        startCursorGuard()

        // Heavy merge / reload off the critical launch path.
        Task { [weak self] in
            guard let self else { return }
            await self.ensureTelegramConnectivity(forceNodeProbe: true)
            await self.ensureCursorConnectivity(forceNodeProbe: true)
            await self.ensureGeoDataReady(progress: false)
            let hadSR = ShadowrocketForeverRules.isReady
            try? await GfwListRules.ensurePresent { [weak self] msg in
                Task { @MainActor in self?.statusText = msg }
            }
            try? await ShadowrocketForeverRules.ensurePresent { [weak self] msg in
                Task { @MainActor in self?.statusText = msg }
            }
            let srUpdated = !hadSR && ShadowrocketForeverRules.isReady
            if srUpdated {
                self.statusText = ShadowrocketForeverRules.statusLine.map { "已注入 \($0)" } ?? "Shadowrocket 规则已就绪"
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
            if self.settings.tunEnabled || self.settings.systemProxyEnabled {
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

        recordBootstrapOutcome()
    }

    func refreshLaunchDiagnostics() {
        launchHasError = LaunchDiagnostics.isStartupFailure(
            statusText: statusText,
            coreRunning: coreRunning,
            coreConnecting: coreConnecting
        )
        launchDiagnosticReport = LaunchDiagnostics.buildReport(
            statusText: statusText,
            coreRunning: coreRunning
        )
    }

    private func recordBootstrapOutcome() {
        refreshLaunchDiagnostics()
        if launchHasError {
            LaunchDiagnostics.error("bootstrap 结束: \(statusText)")
        } else {
            LaunchDiagnostics.info("bootstrap 完成 · coreRunning=\(coreRunning)")
        }
    }

    func copyLaunchDiagnosticReport() {
        refreshLaunchDiagnostics()
        LaunchDiagnostics.copyReport(launchDiagnosticReport)
        statusText = "已复制启动诊断日志"
    }

    func openLaunchDiagnosticLog() {
        LaunchDiagnostics.revealLogFile()
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
        // Prefer HTTP generate_204 (Clash / Stash style) — HTTPS adds TLS noise to latency.
        if settings.testURL == "https://www.gstatic.com/generate_204"
            || settings.testURL.hasPrefix("https://www.gstatic.com/generate_204") {
            settings.testURL = "http://www.gstatic.com/generate_204"
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
        guard !userStoppedCore, !coreStartInFlight, !coreRepairInFlight else { return }

        let port = await CoreHealth.mixedPortAliveAsync(port: settings.mixedPort)
        // Promote immediately; demote only after consecutive misses so the start button
        // does not flicker when a probe briefly fails mid-restart.
        if port {
            if !mixedPortCachedAlive { mixedPortCachedAlive = true }
        } else if coreHealthMissStreak >= 1 {
            if mixedPortCachedAlive { mixedPortCachedAlive = false }
        }
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
        if !port, coreHealthMissStreak >= 2 {
            if mixedPortCachedAlive { mixedPortCachedAlive = false }
        }

        // Critical: kernel dead + system proxy still on = machine has NO network.
        // Clear OS proxy immediately; keep preference so reconnect can re-enable.
        if !port, (systemProxyOn || settings.systemProxyEnabled), !settings.userDisabledSystemProxy {
            if coreHealthMissStreak >= 1 {
                SystemProxy.setEnabled(false, port: settings.mixedPort)
                systemProxyOn = false
                if coreHealthMissStreak == 1 {
                    statusText = "内核离线，已临时关闭系统代理保网"
                }
            }
        }

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

        // Core still dead — do NOT force systemProxyEnabled back on (blackholes the Mac).
        // Preference stays true so a later successful start re-applies proxy.
    }

    /// BashX open => keep system proxy preference unless user explicitly disabled it.
    /// Never rewrite proxyMode — 规则/全局/直连 must stick to user choice.
    private func migrateTelegramReliabilitySettings() {
        var changed = false
        // Only force preference when core is already healthy — otherwise OS proxy blackholes net.
        if !settings.tunEnabled,
           !settings.userDisabledSystemProxy, !settings.systemProxyEnabled,
           coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) {
            settings.systemProxyEnabled = true
            changed = true
        }
        if changed { _ = SettingsStore.save(settings) }
    }

    /// One-shot: turn TUN on for existing installs (Telegram MTProto needs it).
    private func migrateTunDefaultOn() {
        guard !settings.userDisabledTun, !settings.tunEnabled else { return }
        settings.tunEnabled = true
        _ = SettingsStore.save(settings)
    }

    /// Old presets sent Cursor → PROXY/AUTO; that thrash breaks long-lived agent streams.
    private func migrateCursorAppRouting() {
        var changed = false
        // Remove whole-process Cursor hijack — forces npm/CN CDN via sticky US and breaks the IDE.
        let before = settings.appRoutingRules.count
        settings.appRoutingRules.removeAll { rule in
            rule.processName.localizedCaseInsensitiveContains("cursor")
                || rule.bundleId.lowercased().contains("230313mzl4w4u92")
                || rule.label.localizedCaseInsensitiveContains("cursor")
        }
        if settings.appRoutingRules.count != before { changed = true }
        for i in settings.appRoutingRules.indices {
            let rule = settings.appRoutingRules[i]
            let isCursor = rule.processName.localizedCaseInsensitiveContains("cursor")
                || rule.bundleId.lowercased().contains("230313mzl4w4u92")
            guard isCursor else { continue }
            let target = rule.proxyTarget.uppercased()
            if target == "PROXY" || target == "AUTO" || target.isEmpty {
                settings.appRoutingRules[i].proxyTarget = "CURSOR"
                changed = true
            }
        }
        if changed {
            schedulePersist()
        }
    }

    /// Cursor uses kernel FAILOVER — never pin CURSOR select to a single Asia leaf.
    private func migrateCursorReliabilitySettings() {
        // No persisted flags yet; heal runs at bootstrap / when Cursor is open.
    }

    private func startCursorGuard() {
        cursorGuardTask?.cancel()
        cursorGuardTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: UInt64 = CursorReliability.isCursorRunning()
                    ? 5_000_000_000
                    : 15_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                await self?.cursorGuardTick()
            }
        }
    }

    private func cursorGuardTick() async {
        guard !userStoppedCore, !settings.userDisabledSystemProxy else { return }
        guard settings.proxyMode != .direct else { return }

        guard CursorReliability.isCursorRunning() else { return }
        guard await coreIsHealthy() else { return }

        let port = settings.mixedPort
        if await CoreHealth.cursorReachable(port: port) { return }

        let cooldown: TimeInterval = 20
        guard Date().timeIntervalSince(lastCursorNodeProbe) >= cooldown else { return }
        lastCursorNodeProbe = Date()
        await healCursorGroupOnly()
    }

    private func ensureCursorConnectivity(forceNodeProbe: Bool) async {
        guard !settings.userDisabledSystemProxy else { return }
        _ = await ensureCoreRunning()

        let port = settings.mixedPort
        let cursorOK = await CoreHealth.cursorReachable(port: port)
        if forceNodeProbe || !cursorOK {
            await healCursorGroupOnly()
        }
    }

    private func startTelegramGuard() {
        telegramGuardTask?.cancel()
        telegramGuardTask = Task { [weak self] in
            while !Task.isCancelled {
                // Faster when Telegram is open; slower otherwise to save CPU.
                let interval: UInt64 = TelegramReliability.isTelegramRunning()
                    ? 4_000_000_000
                    : 12_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                await self?.telegramGuardTick()
            }
        }
    }

    private func telegramGuardTick() async {
        // Respect explicit 直连 / user-disabled system proxy — do not hijack mode.
        guard !userStoppedCore, !settings.userDisabledSystemProxy else { return }
        guard settings.proxyMode != .direct else { return }

        if !settings.tunEnabled, !settings.systemProxyEnabled {
            settings.systemProxyEnabled = true
            schedulePersist()
        }

        if !(await coreIsHealthy()) {
            await ensureCoreRunning()
        }

        let clients = TelegramReliability.runningClients()
        guard clients.any else { return }
        guard await coreIsHealthy() else { return }

        // Any Telegram variant → attach to *this* BashX VPN (reclaim Stash etc. + TUN for bare-IP).
        await attachTelegramToBashXVpn(clients: clients, forceNodeProbe: false)
    }

    private func ensureTelegramConnectivity(forceNodeProbe: Bool) async {
        guard !settings.userDisabledSystemProxy else { return }
        migrateTelegramReliabilitySettings()
        _ = await ensureCoreRunning()
        let clients = TelegramReliability.runningClients()
        if clients.any {
            await attachTelegramToBashXVpn(clients: clients, forceNodeProbe: forceNodeProbe)
        } else {
            await applyDefaultSystemProxyIfEnabled()
            let port = settings.mixedPort
            let telegramOK = await CoreHealth.telegramReachable(port: port)
            if forceNodeProbe || !telegramOK {
                await healTelegramGroupOnly()
            }
        }
    }

    /// Make every Telegram build follow the currently running BashX VPN:
    /// Desktop via system proxy; Telegra2/keepcoder via TUN + DC routes.
    private func attachTelegramToBashXVpn(
        clients: TelegramReliability.RunningClients,
        forceNodeProbe: Bool
    ) async {
        guard clients.any, await coreIsHealthy() else { return }
        let port = settings.mixedPort

        // 1) System proxy must point at BashX — not Stash/ClashX leftover :7890.
        let foreign = await Task.detached(priority: .utility) {
            SystemProxy.isForeignProxyActive(ourPort: port) || !SystemProxy.isEnabled(port: port)
        }.value
        if foreign || !systemProxyOn {
            await applyDefaultSystemProxyIfEnabled()
        }

        // 2) Native Mac / Telegra2 dials DC IPs → need TUN (unless user turned it off).
        if clients.needsTunCapture, !settings.userDisabledTun, !settings.tunEnabled,
           !telegramTunAssistInFlight {
            let cool: TimeInterval = 90
            if Date().timeIntervalSince(lastTelegramTunAssist) >= cool {
                lastTelegramTunAssist = Date()
                telegramTunAssistInFlight = true
                statusText = "检测到 Telegra2/Mac Telegram，自动开启 TUN 以接入 BashX…"
                await setTUN(true)
                telegramTunAssistInFlight = false
            }
        }

        // 3) Keep TUN DC routes hot so bare-IP MTProto enters the stack.
        if settings.tunEnabled, effectiveTunInConfig() {
            let attachCool: TimeInterval = forceNodeProbe ? 0 : 45
            if forceNodeProbe || Date().timeIntervalSince(lastTelegramRoutePatch) >= attachCool {
                lastTelegramRoutePatch = Date()
                try? await ClashCore.patchConfig(
                    controller: settings.externalController,
                    secret: settings.secret,
                    body: [
                        "tun": ClashConfigParser.tunConfigBlock(
                            stack: settings.tunStack.isEmpty ? "mixed" : settings.tunStack
                        ),
                        "ipv6": true
                    ]
                )
            }
        }

        // 4) Heal TELEGRAM group when API path is dead.
        if await CoreHealth.telegramReachable(port: port) {
            if forceNodeProbe { await healTelegramGroupOnly() }
            return
        }
        let cooldown: TimeInterval = forceNodeProbe ? 0 : 18
        guard Date().timeIntervalSince(lastTelegramNodeProbe) >= cooldown else { return }
        lastTelegramNodeProbe = Date()
        await healTelegramGroupOnly()
    }

    private func startLaunchCoreGuard() {
        launchGuardTask?.cancel()
        launchGuardTask = Task { [weak self] in
            for tick in 0..<8 {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard !self.userStoppedCore, !self.coreRepairInFlight else { return }
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
    /// Clash Verge style: system proxy and TUN are **independent**. TUN captures at
    /// the IP layer; system proxy covers HTTP(S)-aware apps. Both may be on at once.
    private func applyDefaultSystemProxyIfEnabled() async {
        // TUN preferred but not live → keep/restore system proxy so apps still work.
        if settings.tunEnabled, !effectiveTunInConfig(),
           !settings.userDisabledSystemProxy, !settings.systemProxyEnabled {
            settings.systemProxyEnabled = true
            schedulePersist()
        }
        guard settings.systemProxyEnabled, !settings.userDisabledSystemProxy else {
            let port = settings.mixedPort
            let wasOn = await Task.detached(priority: .utility) {
                SystemProxy.isEnabled(port: port)
            }.value
            if wasOn {
                _ = await SystemProxy.setEnabledAsync(
                    false,
                    port: port,
                    allowPrivilegePrompt: false
                )
            }
            if systemProxyOn || wasOn {
                systemProxyOn = false
                bumpChromeRevision()
            }
            return
        }
        guard await coreIsHealthy() else {
            systemProxyOn = false
            bumpChromeRevision()
            return
        }
        let port = settings.mixedPort
        // Never pop admin password from background recover — that spam is what
        // other Macs saw on every launch. Privilege prompt only on manual toggle.
        let on = await SystemProxy.setEnabledAsync(
            true,
            port: port,
            allowPrivilegePrompt: false
        )
        systemProxyOn = on
        bumpChromeRevision()
        if on {
            await syncSelectedOutbound()
            _ = await ClashCore.applyMode(
                controller: settings.externalController,
                secret: settings.secret,
                mode: settings.proxyMode
            )
        } else if let err = SystemProxy.lastError, !err.contains("未授权") {
            // Keep quiet for expected "helper not installed yet".
            statusText = err
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
            LaunchDiagnostics.error(statusText)
            return
        }

        if !rebuildEnabledNodesFromCache() {
            reloadNodesFromDiskIfNeeded()
        }
        await writeConfigAndWait()

        let apiOK = await CoreHealth.apiAlive(controller: settings.externalController, secret: settings.secret)
        let portOK = await CoreHealth.mixedPortAliveAsync(port: settings.mixedPort)
        let healthy = apiOK && portOK
        if healthy {
            mixedPortCachedAlive = true
            applyCoreRunning(true)
        } else {
            statusText = "正在启动内核…"
            for attempt in 1...3 where !coreRunning {
                if attempt > 1 {
                    statusText = "正在重试启动内核（\(attempt)/3）…"
                    await migrateBusyPortsIfNeeded()
                    await writeConfigAndWait()
                }
                await startCoreAsync(forceRestart: attempt > 1)
                if !coreRunning {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }

        if !coreRunning {
            statusText = "内核启动失败，正在后台重试…"
            LaunchDiagnostics.error("内核启动失败：\(statusText)")
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
            // Don't leave TUN-pref + system-proxy-off → no network.
            await applyDefaultSystemProxyIfEnabled()
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
        // Smart/LB/failover must stay on AUTO/BALANCE/FALLBACK — selecting a leaf forces
        // `.manual` and was pinning Ads/IPFoxy onto dead mid-hops after every reconnect.
        if settings.proxyHubMode != .manual {
            await syncSelectedOutbound()
        } else if settings.selectedNodeName == nil || settings.selectedNodeName == "AUTO" {
            await ensureUsableProxy(forceProbe: false, verifyGoogle: true)
        } else if settings.autoSelectFastest {
            await selectFastestNodeIfAvailable()
        }
    }

    /// Avoid colliding with Stash/ClashX default 7890/9090; also bump if OUR ports are occupied by others.
    private func migrateBusyPortsIfNeeded() async {
        let mixed = settings.mixedPort
        let controller = settings.externalController
        let result = await Task.detached(priority: .utility) { () -> (mixed: Int, controller: String, changed: Bool)? in
            var mixedPort = mixed
            var externalController = controller
            var changed = false
            if mixedPort == 7890, PortProbe.isListening(port: 7890) {
                mixedPort = 17890
                changed = true
            }
            if externalController == "127.0.0.1:9090", PortProbe.isListening(port: 9090) {
                externalController = "127.0.0.1:19090"
                changed = true
            }
            if PortProbe.isListening(port: mixedPort), !ClashCore.isMihomoAlive() {
                if let free = PortProbe.firstFreePort(from: mixedPort, limit: 30) {
                    mixedPort = free
                    changed = true
                }
            }
            let controllerPort = Int(externalController.split(separator: ":").last.map(String.init) ?? "") ?? 19090
            let controllerHost = externalController.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
            if PortProbe.isListening(host: controllerHost, port: controllerPort), !ClashCore.isMihomoAlive() {
                if let free = PortProbe.firstFreePort(from: controllerPort, limit: 30) {
                    externalController = "\(controllerHost):\(free)"
                    changed = true
                }
            }
            guard changed else { return nil }
            return (mixedPort, externalController, true)
        }.value
        guard let result else { return }
        settings.mixedPort = result.mixed
        settings.externalController = result.controller
        CoreHealth.invalidatePortCache()
        persist()
    }

    /// Drop rules that crash mihomo (missing GeoSite lists, etc.).
    private func sanitizeRulesForCore() {
        var before = settings.rules
        // Keep DOMAIN-SUFFIX,local,DIRECT — never rewrite to REJECT (breaks mDNS / local).
        let cleaned = GeoSiteRules.sanitize(before)
        if cleaned != settings.rules {
            settings.rules = cleaned
            persist()
        }
    }

    /// Keep Telegram on TELEGRAM group; drop traffic/expiry placeholders as selected node.
    private func migrateTelegramRoutingDefaults() {
        var changed = false
        for i in settings.appRoutingRules.indices {
            let rule = settings.appRoutingRules[i]
            let isTG = rule.processName.localizedCaseInsensitiveContains("telegram")
                || rule.processName.localizedCaseInsensitiveContains("telegra")
                || rule.bundleId.localizedCaseInsensitiveContains("telegram")
                || rule.bundleId.localizedCaseInsensitiveContains("keepcoder")
                || rule.label.localizedCaseInsensitiveContains("telegram")
                || rule.label.localizedCaseInsensitiveContains("telegra")
            guard isTG else { continue }
            let target = rule.proxyTarget.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if target == "PROXY" || target == "AUTO" || target.isEmpty {
                settings.appRoutingRules[i].proxyTarget = "TELEGRAM"
                changed = true
            }
        }
        if let sel = settings.selectedNodeName, ClashConfigParser.isPlaceholderNodeName(sel) {
            settings.selectedNodeName = nil
            changed = true
        }
        if changed {
            schedulePersist()
            bumpChromeRevision()
        }
    }

    /// ClashFX-style: domestic apps default DIRECT under TUN (AdsPower excluded — needs S5 chain).
    private func migrateMacAppBypassRouting() {
        var changed = false
        for preset in AppRoutingRules.autoDirectPresets {
            if let idx = AppRoutingRules.existingIndex(of: preset, in: settings.appRoutingRules) {
                if settings.appRoutingRules[idx].proxyTarget.uppercased() != "DIRECT" {
                    settings.appRoutingRules[idx].proxyTarget = "DIRECT"
                    settings.appRoutingRules[idx].enabled = true
                    changed = true
                } else if !settings.appRoutingRules[idx].enabled {
                    settings.appRoutingRules[idx].enabled = true
                    changed = true
                }
            } else {
                settings.appRoutingRules.append(preset.asRule(enabled: true, lang: settings.uiLanguage))
                changed = true
            }
        }
        // Clash Verge / ACL4SSR: browsers follow domain rules. Whole-process GOOGLE/PROXY
        // hijacks taobao/weixin inside Chrome.
        let browserKeys: Set<String> = [
            "com.google.chrome", "com.apple.safari", "com.microsoft.edgemac",
            "org.mozilla.firefox", "company.thebrowser.browser",
        ]
        let browserProcs: Set<String> = [
            "google chrome", "safari", "microsoft edge", "firefox", "arc",
        ]
        for i in settings.appRoutingRules.indices {
            let bid = settings.appRoutingRules[i].bundleId.lowercased()
            let proc = settings.appRoutingRules[i].processName.lowercased()
            guard settings.appRoutingRules[i].enabled else { continue }
            if browserKeys.contains(bid) || browserProcs.contains(proc),
               settings.appRoutingRules[i].proxyTarget.uppercased() == "GOOGLE" {
                settings.appRoutingRules[i].enabled = false
                changed = true
            }
        }
        if changed {
            schedulePersist()
            bumpAppRoutingRevision()
            bumpChromeRevision()
            scheduleWriteConfig()
        }
    }

    /// Disable AdsPower/SunBrowser whole-process DIRECT so IPFoxy S5 can chain via TUN/PROXY.
    /// Control-plane CDN stays DOMAIN DIRECT in smart rules / MacAppBypassRules.
    private func migrateAdsPowerProxyChain() {
        var changed = false
        for i in settings.appRoutingRules.indices {
            let bid = settings.appRoutingRules[i].bundleId.lowercased()
            let proc = settings.appRoutingRules[i].processName.lowercased()
            let isAds = bid.contains("adspower")
                || proc.contains("adspower")
                || proc == "sunbrowser"
                || proc.hasPrefix("sunbrowser ")
            guard isAds else { continue }
            if settings.appRoutingRules[i].enabled {
                settings.appRoutingRules[i].enabled = false
                changed = true
            }
            if settings.appRoutingRules[i].proxyTarget.uppercased() == "DIRECT" {
                settings.appRoutingRules[i].proxyTarget = "PROXY"
                changed = true
            }
        }
        // Strip leftover Ads/SunBrowser process lines from user smart rules.
        let before = settings.rules.count
        settings.rules.removeAll { line in
            let u = line.uppercased()
            let isProc = u.hasPrefix("PROCESS-NAME,") || u.hasPrefix("PROCESS-PATH,")
                || u.hasPrefix("PROCESS-NAME-REGEX,") || u.hasPrefix("PROCESS-PATH-REGEX,")
            return isProc && (u.contains("ADSPOWER") || u.contains("SUNBROWSER"))
        }
        if settings.rules.count != before { changed = true }
        if !settings.rules.contains(where: { $0.contains("ipfoxy.com,PROXY") }) {
            settings.rules.insert(contentsOf: MacAppBypassRules.residentialProxyChainRules, at: 0)
            changed = true
        }
        if changed {
            schedulePersist()
            bumpAppRoutingRevision()
            bumpChromeRevision()
            scheduleWriteConfig()
        }
    }

    /// Drop phone-app plugin IDs from Mac enabled list (market is PC-first).
    private func migrateMacPluginCatalog() {
        #if os(macOS)
        let visible = Set(PluginEngine.catalogForCurrentPlatform.map(\.id))
        let before = settings.enabledPluginIds
        let after = before.filter { visible.contains($0) }
        guard after != before else { return }
        settings.enabledPluginIds = after
        schedulePersist()
        scheduleWriteConfig()
        #endif
    }

    /// AnyDesk default DIRECT — PROXY exits often black-hole it; user can flip to PROXY in 应用分流.
    private func migrateAnyDeskProxyRouting() {
        var changed = false
        let presets = AppRoutingRules.commonPresets.filter {
            $0.processName.caseInsensitiveCompare("AnyDesk") == .orderedSame
                || $0.bundleId.localizedCaseInsensitiveContains("anydesk")
        }
        for preset in presets {
            if let idx = AppRoutingRules.existingIndex(of: preset, in: settings.appRoutingRules) {
                // Keep user's choice if they already set PROXY/DIRECT explicitly after migrate;
                // only force-enable and ensure rule exists.
                if !settings.appRoutingRules[idx].enabled {
                    settings.appRoutingRules[idx].enabled = true
                    changed = true
                }
            } else {
                settings.appRoutingRules.append(preset.asRule(enabled: true, lang: settings.uiLanguage))
                changed = true
            }
        }
        let inject = [
            "DOMAIN-SUFFIX,anydesk.com,DIRECT",
            "DOMAIN-SUFFIX,anydesk.com.cn,DIRECT",
            "DOMAIN-KEYWORD,anydesk,DIRECT",
        ]
        // Replace PROXY anydesk domain lines with DIRECT; keep user PROXY process override via app routing.
        var rules = settings.rules
        rules.removeAll { $0.lowercased().contains("anydesk") }
        settings.rules = inject + rules
        changed = true
        if changed {
            schedulePersist()
            bumpAppRoutingRevision()
            bumpChromeRevision()
            scheduleWriteConfig()
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
            statusText = "链接格式无效；默认需 https://（HTTP 请先在设置中开启）"
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
            let addedCount = (try? Data(contentsOf: cacheURL))
                .flatMap { try? ClashConfigParser.parse($0) }?
                .nodes.count ?? 0
            return .success(nodeCount: addedCount)
        }
        if statusText.contains("失败") {
            return .fetchFailed(statusText)
        }
        return .fetchFailed("未能解析节点，请检查链接是否有效")
    }

    func removeSubscription(_ id: UUID) {
        let name = settings.subscriptions.first(where: { $0.id == id })?.name ?? "订阅"
        replaceSubscriptions(settings.subscriptions.filter { $0.id != id })
        try? FileManager.default.removeItem(at: Paths.subscriptionCacheURL(id: id))
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
        } else if fetch {
            statusText = "当前 \(onCount) 个订阅 · \(nodes.count) 个节点"
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
        await runSpeedTest(nodes: nil, label: nil, groupKey: nil)
    }

    /// Speed-test nodes in one region category (respects current search filter).
    func runSpeedTest(forCategoryKey key: String) async {
        ensureDisplayCache()
        let title = categorySummary.first(where: { $0.key == key })?.title ?? key
        var pool = nodes.filter { displayCache[$0.name]?.key == key }
        if !searchText.isEmpty {
            let q = searchText
            pool = pool.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || $0.type.localizedCaseInsensitiveContains(q)
                    || $0.server.localizedCaseInsensitiveContains(q)
                    || (displayCache[$0.name]?.title.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        await runSpeedTest(nodes: pool, label: title, groupKey: key)
    }

    /// Speed-test all nodes, or only the given subset (e.g. one region group).
    func runSpeedTest(nodes targetNodes: [ProxyNode]?, label: String?, groupKey: String? = nil) async {
        guard !isTesting else { return }
        let scoped = targetNodes != nil
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
        speedTestScopeKey = scoped ? groupKey : nil
        let token = UUID()
        speedTestToken = token
        testedCount = 0
        bumpNodeListRevision()
        var pendingDelays: [String: (Int, Date)] = [:]
        var lastNodesFlush = Date.distantPast
        defer {
            if speedTestToken == token {
                isTesting = false
                speedTestScopeKey = nil
            }
            groupCacheSort = nil
            groupCache = []
            bumpNodeListRevision()
        }

        statusText = "测速中\(scope)…"
        // Cap core start so「测速中」cannot hang forever if mihomo never comes up.
        if !isCoreVisiblyAlive {
            let ok = await withTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask { await self.ensureCoreRunning() }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if !ok, !isCoreVisiblyAlive {
                statusText = "内核未就绪，改用 TCP 测速\(scope)"
            }
        }
        // Real latency = mihomo URLTest via /proxies/{name}/delay (same as Clash Verge / Stash).
        // The HTTP call to local API bypasses system proxy inside SpeedTester — "测试不走代理" means that,
        // not "skip proxy tunnel measurement". TCP host:port is fallback when API is down.
        let apiOK = await CoreHealth.apiAlive(controller: settings.externalController, secret: settings.secret)
        let controller: String? = apiOK ? settings.externalController : nil
        if controller == nil, isCoreVisiblyAlive {
            statusText = "API 未就绪，改用 TCP 测速\(scope)"
        }
        let perNodeTimeout = max(settings.testTimeoutMs, 3000)
        let workers = settings.turboMode
            ? min(max(settings.concurrency, 1), 6)
            : min(max(settings.concurrency, 1), 4)
        // Hard ceiling so UI never stays on「测速中」if a probe stalls.
        let hardCapNs = UInt64(max(20, testables.count) * perNodeTimeout / max(workers, 1) + 15_000) * 1_000_000
        let results: [SpeedTester.Result] = await withTaskGroup(of: [SpeedTester.Result]?.self) { group in
            group.addTask {
                await self.tester.testAll(
                    nodes: testables,
                    timeoutMs: perNodeTimeout,
                    concurrency: workers,
                    controller: controller,
                    secret: self.settings.secret,
                    testURL: self.settings.testURL
                ) { [weak self] name, delay in
                    guard let self else { return }
                    guard self.speedTestToken == token else { return }
                    pendingDelays[name] = (delay, Date())
                    self.testedCount += 1
                    let now = Date()
                    let done = self.testedCount == testables.count
                    // Throttle list rebuilds — frequent bumps were a major stutter source.
                    if done || now.timeIntervalSince(lastNodesFlush) > 1.0 {
                        lastNodesFlush = now
                        var updated = self.nodes
                        var nodesDirty = false
                        for (nodeName, pair) in pendingDelays {
                            if let idx = updated.firstIndex(where: { $0.name == nodeName }) {
                                let ms = pair.0 > 0 ? pair.0 : nil
                                if updated[idx].delayMs != ms || updated[idx].testedAt != pair.1 {
                                    updated[idx].delayMs = ms
                                    updated[idx].testedAt = pair.1
                                    nodesDirty = true
                                }
                            }
                        }
                        if nodesDirty {
                            self.nodes = updated
                        }
                        pendingDelays.removeAll(keepingCapacity: true)
                        self.bumpNodeListRevision()
                    }
                    if done || now.timeIntervalSince(self.speedUITick) > 0.8 {
                        self.speedUITick = now
                        self.statusText = "测速\(scope) \(self.testedCount)/\(testables.count)"
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: hardCapNs)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
        if results.isEmpty, testedCount < testables.count {
            statusText = "测速超时\(scope)，已停止"
        }

        if scoped {
            // Regional test: only reorder within the tested pool.
            let testedNames = Set(testables.map(\.name))
            let testedDelays = nodes.filter { testedNames.contains($0.name) }.compactMap(\.delayMs).filter { $0 > 0 }
            if !testedDelays.isEmpty { sortByDelay = true }
        } else {
            sortByDelay = true
        }
        invalidateNodeCaches()

        let ok = results.filter { $0.delayMs > 0 }.count
        let isolatedNow = applyCircuitBreaker(results: results)
        persistDelayCache(from: nodes)
        persist()
        let isolatedHint = isolatedNow > 0 ? "，已隔离 \(isolatedNow) 个持续超时节点" : ""
        statusText = "测速完成\(scope)：\(ok)/\(results.count) 可用" + (controller == nil ? "（TCP）" : "（代理）") + isolatedHint

        if scoped {
            if settings.autoSelectFastest {
                await selectFastestNode(from: testables)
            }
        } else {
            // Full test: existing global follow-up.
            if let sel = settings.selectedNodeName,
               let node = nodes.first(where: { $0.name == sel }),
               settings.isolatedNodeKeys.contains(node.delayCacheKey) {
                await selectFastestNodeIfAvailable()
            } else if settings.autoSelectFastest {
                await selectFastestNodeIfAvailable()
            } else if settings.selectedNodeName == nil || settings.selectedNodeName == "AUTO" {
                await ensureUsableProxy(forceProbe: false, verifyGoogle: true)
            }
        }
        scheduleWriteConfig()
    }

    /// Isolate nodes that fail 2+ consecutive tests; recover on success. Returns newly isolated count.
    @discardableResult
    private func applyCircuitBreaker(results: [SpeedTester.Result]) -> Int {
        var isolated = Set(settings.isolatedNodeKeys)
        let before = isolated.count
        let byName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.name, $0) })
        for r in results {
            guard let node = byName[r.name] else { continue }
            let key = node.delayCacheKey
            if r.delayMs > 0 {
                nodeFailStreak[key] = 0
                isolated.remove(key)
            } else {
                let streak = (nodeFailStreak[key] ?? 0) + 1
                nodeFailStreak[key] = streak
                if streak >= 2 {
                    isolated.insert(key)
                }
            }
        }
        // Bound size
        if isolated.count > 400 {
            isolated = Set(isolated.prefix(400))
        }
        settings.isolatedNodeKeys = Array(isolated)
        return max(0, isolated.count - before)
    }

    private func excludedNodeNamesForConfig() -> Set<String> {
        let keys = Set(settings.isolatedNodeKeys)
        guard !keys.isEmpty else { return [] }
        return Set(nodes.filter { keys.contains($0.delayCacheKey) }.map(\.name))
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
        bumpChromeRevision()
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
            IconManager.applyBundledAppIcon()
        }
        objectWillChange.send()
        statusText = enabled ? "程序坞已显示图标" : "程序坞已隐藏图标"
    }

    func setMacMinimalHome(_ enabled: Bool) {
        guard settings.macMinimalHome != enabled else { return }
        settings.macMinimalHome = enabled
        persist()
        // Resize + remount first so 完整版立刻出现大面板；再 bump chrome。
        PanelPresenter.shared.resizeForMode(minimal: enabled)
        bumpLayoutRevision()
        bumpChromeRevision()
        statusText = enabled
            ? L10n.t("mac.minimal.toSimple", settings.uiLanguage)
            : L10n.t("mac.minimal.toFull", settings.uiLanguage)
    }

    /// Minimal home: one-tap start/stop (core + system proxy).
    /// At most one admin password (install helper); later toggles use the helper with no prompt.
    func toggleMinimalConnection() async {
        let up = isCoreVisiblyAlive || systemProxyOn || coreRunning
        if up {
            await softDisconnectMinimal()
            return
        }
        let hasSub = settings.subscriptions.contains(where: \.enabled)
        guard hasSub else {
            statusText = L10n.t("mac.minimal.needSub", settings.uiLanguage)
            panelIntent = .addSubscription
            return
        }

        // At most one password: install helper once up front (TUN + system proxy share it).
        if !TunPrivilege.isReady {
            do {
                try TunPrivilege.ensureReady()
            } catch {
                statusText = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }

        // Helper missing → skip TUN (avoids legacy per-start osascript password).
        let wantTun = settings.tunEnabled
        let skipTun = wantTun && !TunPrivilege.isReady
        if skipTun {
            settings.tunEnabled = false
        }
        _ = await ensureCoreRunning()
        if skipTun {
            settings.tunEnabled = wantTun
        }

        // Like iOS「测速并选最快」: always pick lowest-latency real leaf, never traffic banners.
        await ensureMinimalFastestNode()

        // Never prompt again here — ensureReady already asked once if needed.
        systemProxyTask?.cancel()
        let port = settings.mixedPort
        // Clash Verge: TUN + system proxy are independent. Prefer both on for connect
        // (browsers → system proxy; TG/UDP/stubborn apps → TUN). WhatsApp stays on
        // SystemProxy.bypassDomains so it uses TUN, not HTTP CONNECT.
        if !settings.userDisabledSystemProxy {
            systemProxyOn = true
            settings.systemProxyEnabled = true
            bumpChromeRevision()
            schedulePersist()
            let ok = await SystemProxy.setEnabledAsync(
                true,
                port: port,
                allowPrivilegePrompt: false
            )
            if !ok {
                systemProxyOn = false
                settings.systemProxyEnabled = false
                bumpChromeRevision()
                statusText = SystemProxy.lastError
                    ?? (TunPrivilege.isReady ? "系统代理开启失败" : "请先完成助手安装（设置 → 特权助手）")
                return
            }
            systemProxyOn = true
        } else {
            systemProxyOn = false
            settings.systemProxyEnabled = false
            bumpChromeRevision()
            schedulePersist()
            _ = await SystemProxy.setEnabledAsync(
                false,
                port: port,
                allowPrivilegePrompt: false
            )
        }

        let nodeNote: String = {
            if let name = settings.selectedNodeName,
               let ms = nodes.first(where: { $0.name == name })?.delayMs, ms > 0 {
                return " · \(name) \(ms)ms"
            }
            if let name = settings.selectedNodeName, !name.isEmpty {
                return " · \(name)"
            }
            return ""
        }()
        let tunNote = settings.tunEnabled ? " · TUN" : " → 127.0.0.1:\(port)"
        statusText = "已连接\(tunNote)\(nodeNote)"
        Task { await syncSelectedOutbound() }
        return
    }

    /// Disconnect without admin password (helper restore / soft stop).
    private func softDisconnectMinimal() async {
        systemProxyTask?.cancel()
        systemProxyOn = false
        settings.systemProxyEnabled = false
        settings.userDisabledSystemProxy = true
        bumpChromeRevision()
        schedulePersist()
        _ = await SystemProxy.setEnabledAsync(
            false,
            port: settings.mixedPort,
            allowPrivilegePrompt: false
        )
        stopCore(clearProxy: false, force: false, markUserStopped: true)
        statusText = "已断开"
    }

    func setNodeDisplayMode(_ mode: NodeDisplayMode) {
        guard settings.nodeDisplayMode != mode else { return }
        settings.nodeDisplayMode = mode
        persist()
        // PanelNodesHost only redraws on nodeListRevision — bump so list/card switch applies.
        nodeListRevision &+= 1
        statusText = "节点展示：\(mode.title)"
    }

    /// Default node panel to card grid (list remains available in the picker).
    private func migrateNodeDisplayModeToCard() {
        guard settings.nodeDisplayMode == .list else { return }
        settings.nodeDisplayMode = .card
        _ = SettingsStore.save(settings)
    }

    func setAppearance(_ appearance: AppAppearance) {
        settings.appearance = appearance
        persist()
        ThemeRefresh.apply(state: self)
        bumpLayoutRevision()
        statusText = "主题：\(appearance.title)（已生效）"
    }

    func setUiLanguage(_ language: AppLanguage) {
        settings.uiLanguage = language
        L10n.apply(language)
        persist()
        bumpLayoutRevision()
        ThemeRefresh.apply(state: self)
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

    /// Pick the current lowest-latency node (delayMs > 0). Does not retarget AI stable groups.
    func selectFastestNodeIfAvailable() async {
        // Hub modes already url-test / failover — pinning a leaf here defeats AUTO.
        if settings.proxyHubMode != .manual { return }
        await selectFastestNode(from: usableOutboundNodes())
    }

    /// Real outbound nodes only — skip traffic / expiry / banner placeholders (iOS-aligned).
    func usableOutboundNodes() -> [ProxyNode] {
        nodes.filter {
            ClashConfigParser.isSpeedTestable($0)
                && !ClashConfigParser.isPlaceholderNodeName($0.name)
        }
    }

    /// Pick the fastest node within a tested pool (regional speed test).
    /// Asia hubs win over Middle East / distant regions even if those look slightly faster.
    private func selectFastestNode(from pool: [ProxyNode]) async {
        let names = Set(pool.map(\.name))
        let excluded = Set(settings.isolatedNodeKeys)
        let candidates = nodes.filter {
            names.contains($0.name)
                && ClashConfigParser.isSpeedTestable($0)
                && !ClashConfigParser.isPlaceholderNodeName($0.name)
                && ($0.delayMs ?? -1) > 0
                && !excluded.contains($0.delayCacheKey)
        }
        guard !candidates.isEmpty else { return }

        let asiaCore = candidates.filter {
            ClashConfigParser.isCoreAsiaPreferredNodeName($0.name)
                && !ClashConfigParser.isDeprioritizedRegionNodeName($0.name)
        }
        let asia = candidates.filter {
            ClashConfigParser.isAsiaPreferredNodeName($0.name)
                && !ClashConfigParser.isDeprioritizedRegionNodeName($0.name)
        }
        let nonDeprioritized = candidates.filter {
            !ClashConfigParser.isDeprioritizedRegionNodeName($0.name)
        }
        let rankedPool: [ProxyNode]
        if !asiaCore.isEmpty {
            rankedPool = asiaCore
        } else if !asia.isEmpty {
            rankedPool = asia
        } else if !nonDeprioritized.isEmpty {
            rankedPool = nonDeprioritized
        } else {
            rankedPool = candidates
        }
        let ranked = rankedPool.sorted(by: delaySort)
        guard let best = ranked.first else { return }

        if settings.selectedNodeName != best.name {
            await selectNode(best.name, pinAIStable: false)
            let region: String
            if asiaCore.contains(where: { $0.name == best.name }) {
                region = "亚洲核心"
            } else if asia.contains(where: { $0.name == best.name }) {
                region = "亚洲优选"
            } else {
                region = "最快可用"
            }
            statusText = "已切换到\(region)：\(best.name)（\(best.delayMs ?? 0) ms）"
        }
    }

    /// Minimal home connect: always land on lowest-latency real node (never traffic banners).
    private func ensureMinimalFastestNode() async {
        if let sel = settings.selectedNodeName,
           ClashConfigParser.isPlaceholderNodeName(sel)
            || nodes.first(where: { $0.name == sel }).map({ !ClashConfigParser.isSpeedTestable($0) }) == true {
            settings.selectedNodeName = nil
            schedulePersist()
        }

        let usable = usableOutboundNodes()
        guard !usable.isEmpty else {
            statusText = "没有可用节点（已跳过流量/到期占位）"
            return
        }

        let withDelay = usable.filter { ($0.delayMs ?? -1) > 0 }
        if withDelay.isEmpty, !isTesting {
            statusText = "测速中，将自动选最快节点…"
            await runSpeedTest(nodes: usable, label: "精简连接", groupKey: "minimal-connect")
        }
        await selectFastestNode(from: usable)

        if settings.selectedNodeName == nil
            || ClashConfigParser.isPlaceholderNodeName(settings.selectedNodeName ?? "") {
            // No measured leaf yet — stay on AUTO url-test pool (still skips placeholders).
            if settings.proxyHubMode == .manual {
                await setProxyHubMode(.smart)
            }
            statusText = "暂无测速结果，已用智能选路"
        }
        await syncSelectedOutbound()
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
            if n.delayMs == nil, let cached = settings.nodeDelayCache[node.delayCacheKey], cached > 0 {
                n.delayMs = cached
            }
            return n
        }
    }

    private func persistDelayCache(from list: [ProxyNode]) {
        var cache = settings.nodeDelayCache
        for node in list {
            if let ms = node.delayMs, ms > 0 {
                cache[node.delayCacheKey] = ms
            }
        }
        settings.nodeDelayCache = pruneNodeDelayCache(cache, keepingKeys: Set(list.map(\.delayCacheKey)))
    }

    /// Cap delay-cache growth across subscription churn (settings.json + memory).
    private func pruneNodeDelayCache(
        _ cache: [String: Int],
        keepingKeys: Set<String>? = nil
    ) -> [String: Int] {
        var filtered = cache.filter { $0.value > 0 }
        if let keepingKeys, !keepingKeys.isEmpty {
            // Prefer keys still present; keep a small orphan budget for disabled subs.
            let active = filtered.filter { keepingKeys.contains($0.key) }
            let orphans = filtered.filter { !keepingKeys.contains($0.key) }
            filtered = active
            if orphans.count > 200 {
                let orphanKept = Array(orphans.sorted { $0.value < $1.value }.prefix(200))
                filtered.merge(Dictionary(uniqueKeysWithValues: orphanKept)) { _, n in n }
            } else {
                filtered.merge(orphans) { _, n in n }
            }
        }
        let maxEntries = 2000
        guard filtered.count > maxEntries else { return filtered }
        // Keep lowest latency entries (most useful for ranking).
        let kept = Array(filtered.sorted { $0.value < $1.value }.prefix(maxEntries))
        return Dictionary(uniqueKeysWithValues: kept)
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
            if let old = oldDelays[node.name], old.0 > 0 {
                n.delayMs = old.0
                n.testedAt = old.1
            } else if let cached = settings.nodeDelayCache[node.delayCacheKey], cached > 0 {
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

        // Keep url-test / LB / fallback hubs; selecting a leaf here forces `.manual` and sticks on dead nodes.
        if settings.proxyHubMode != .manual {
            await syncSelectedOutbound()
            return
        }

        if !forceProbe,
           let name = settings.selectedNodeName,
           name != "AUTO", name != "DIRECT",
           let node = nodes.first(where: { $0.name == name }),
           let delay = node.delayMs, delay > 0 {
            await syncSelectedOutbound()
            return
        }

        if let best = nodes
            .filter({
                ($0.delayMs ?? -1) > 0
                    && ClashConfigParser.isSpeedTestable($0)
                    && !ClashConfigParser.isPlaceholderNodeName($0.name)
            })
            .sorted(by: { a, b in
                let aAsia = ClashConfigParser.isAsiaPreferredNodeName(a.name)
                    && !ClashConfigParser.isDeprioritizedRegionNodeName(a.name)
                let bAsia = ClashConfigParser.isAsiaPreferredNodeName(b.name)
                    && !ClashConfigParser.isDeprioritizedRegionNodeName(b.name)
                if aAsia != bAsia { return aAsia }
                return delaySort(a, b)
            })
            .first {
            await selectNode(best.name)
            statusText = "已选用可用节点：\(best.name)"
            return
        }

        guard forceProbe else {
            await syncSelectedOutbound()
            return
        }

        statusText = "正在挑选可用节点…"
        let keywords = ["香港", "日本", "新加坡", "台湾", "台灣", "韩国", "韓國", "马来", "馬來"]
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

        let apiOK = await CoreHealth.apiAlive(controller: settings.externalController, secret: settings.secret)
        let results = await tester.testAll(
            nodes: Array(pool.prefix(16)),
            timeoutMs: max(settings.testTimeoutMs, 5000),
            concurrency: 4,
            controller: apiOK ? settings.externalController : nil,
            secret: settings.secret,
            testURL: settings.testURL
        ) { [weak self] name, delay in
            guard let self else { return }
            if let idx = self.nodes.firstIndex(where: { $0.name == name }) {
                self.nodes[idx].delayMs = delay > 0 ? delay : nil
                self.nodes[idx].testedAt = Date()
                if delay > 0 {
                    self.settings.nodeDelayCache[self.nodes[idx].delayCacheKey] = delay
                }
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
                group: "GOOGLE-AUTO",
                url: GoogleReliability.probeURL,
                timeoutMs: 6000
            )
            // Prefer JP hub (Shadowrocket default), then GOOGLE-AUTO.
            for pick in ["JP", "GOOGLE-AUTO", "HK"] {
                try? await ClashCore.selectProxy(
                    controller: settings.externalController,
                    secret: settings.secret,
                    group: "GOOGLE",
                    name: pick
                )
                if await CoreHealth.googleReachable(port: settings.mixedPort) {
                    statusText = "Google 线路已优化（\(pick)）"
                    return
                }
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

    func selectNode(_ name: String, pinAIStable: Bool = true) async {
        // Manual pick → leave auto hub modes so the choice sticks.
        var needHubReload = false
        let hubNames: Set<String> = ["AUTO", "DIRECT", "BALANCE", "FALLBACK"]
        if !hubNames.contains(name), settings.proxyHubMode != .manual {
            var next = settings
            next.proxyHubMode = .manual
            settings = next
            needHubReload = true
            bumpHubModeRevision()
            scheduleWriteConfig()
        }
        guard settings.selectedNodeName != name else {
            if pinAIStable, name != "AUTO", name != "DIRECT", settings.stableAINodeName != name {
                settings.stableAINodeName = name
                schedulePersist()
                await syncAIStableGroups()
            }
            return
        }
        settings.selectedNodeName = name
        if pinAIStable, name != "AUTO", name != "DIRECT" {
            settings.stableAINodeName = name
        }
        // Chrome only — remounting the full node list on every switch was a major hitch.
        bumpChromeRevision()
        statusText = "切换中：\(name)"
        await Task.yield()

        schedulePersist()

        if coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) {
            applyCoreRunning(true)
            if needHubReload {
                writeConfig()
                await applyConfig(reloadIfRunning: true)
            }
            await syncSelectedOutbound()
            if pinAIStable {
                await syncAIStableGroups()
            }
            // Do not pin TELEGRAM to PROXY — TELEGRAM-FAILOVER handles HA independently.
            if settings.closeConnectionsOnSwitch {
                await ClashCore.closeAllConnections(
                    controller: settings.externalController,
                    secret: settings.secret
                )
            }
            statusText = "已切换：\(name)"
            scheduleOutboundIPRefresh()
            scheduleRuntimeOutboundRefresh()
        } else {
            statusText = "已选择：\(name)"
            outboundIP = "—"
            runtimeOutboundName = nil
        }
    }

    /// Switch PROXY hub between smart / load-balance / failover / manual.
    func setProxyHubMode(_ mode: ProxyHubMode) async {
        let already = settings.proxyHubMode == mode
        if !already {
            var next = settings
            next.proxyHubMode = mode
            if mode != .manual {
                next.selectedNodeName = mode.selectorName
                // AUTO url-test picks the leaf — pinning after 测速 would flip this back to manual.
                next.autoSelectFastest = false
            }
            settings = next
            schedulePersist()
        }
        bumpHubModeRevision()
        statusText = "切换\(mode.title)…"

        let alive = coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort)
        if alive {
            applyCoreRunning(true)
            var ok = await applyHubSelectorToCore()
            if !ok {
                await writeConfigAndWait()
                await applyConfig(reloadIfRunning: true)
                ok = await applyHubSelectorToCore()
            }
            if settings.closeConnectionsOnSwitch {
                await ClashCore.closeAllConnections(
                    controller: settings.externalController,
                    secret: settings.secret
                )
            }
            let now = await ClashCore.fetchProxyGroup(
                controller: settings.externalController,
                secret: settings.secret,
                group: "PROXY"
            )?.now ?? "—"
            statusText = ok
                ? "已启用\(mode.title)（PROXY → \(now)）"
                : "\(mode.title)未生效（内核 PROXY=\(now)），请重试"
            scheduleOutboundIPRefresh()
            scheduleRuntimeOutboundRefresh()
            scheduleWriteConfig()
        } else {
            scheduleWriteConfig()
            statusText = "已选择\(mode.title)（连接后生效）"
        }
        bumpHubModeRevision()
        bumpChromeRevision()
    }

    /// PUT PROXY+GLOBAL onto AUTO / BALANCE / FALLBACK and confirm mihomo `now`.
    @discardableResult
    private func applyHubSelectorToCore() async -> Bool {
        let target = activeProxyTarget()
        await syncSelectedOutbound()
        let info = await ClashCore.fetchProxyGroup(
            controller: settings.externalController,
            secret: settings.secret,
            group: "PROXY"
        )
        return info?.now == target
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

    func scheduleRuntimeOutboundRefresh(delay: TimeInterval = 0.5) {
        runtimeOutboundTask?.cancel()
        runtimeOutboundTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.refreshRuntimeOutbound()
        }
    }

    func refreshRuntimeOutbound() async {
        guard coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) else {
            if runtimeOutboundName != nil { runtimeOutboundName = nil }
            return
        }
        if settings.proxyMode == .direct {
            if runtimeOutboundName != "DIRECT" {
                runtimeOutboundName = "DIRECT"
                bumpChromeRevision()
            }
            return
        }
        let group = settings.proxyMode == .global ? "GLOBAL" : "PROXY"
        if let leaf = await resolveProxyLeaf(groupOrProxy: group) {
            if runtimeOutboundName != leaf {
                runtimeOutboundName = leaf
                bumpChromeRevision()
            }
        }
    }

    private func resolveProxyLeaf(groupOrProxy: String, depth: Int = 0) async -> String? {
        guard depth < 5 else { return groupOrProxy }
        let name = groupOrProxy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if name == "DIRECT" || name == "REJECT" || name == "PASS" { return name }
        if nodes.contains(where: { $0.name == name }) { return name }
        guard let info = await ClashCore.fetchProxyGroup(
            controller: settings.externalController,
            secret: settings.secret,
            group: name
        ) else {
            return name
        }
        let now = info.now.trimmingCharacters(in: .whitespacesAndNewlines)
        if now.isEmpty || now == name { return name }
        switch info.type.lowercased() {
        case "select", "url-test", "fallback", "load-balance", "relay":
            return await resolveProxyLeaf(groupOrProxy: now, depth: depth + 1)
        default:
            return now
        }
    }

    func upsertAppRoutingRule(_ rule: AppRoutingRule) async {
        mutateAppRoutingRules { rules in
            if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[idx] = rule
            } else if let idx = rules.firstIndex(where: { existing in
                !rule.bundleId.isEmpty && !existing.bundleId.isEmpty && existing.bundleId == rule.bundleId
                    || existing.processName.caseInsensitiveCompare(rule.processName) == .orderedSame
            }) {
                var merged = rule
                merged.id = rules[idx].id
                rules[idx] = merged
            } else {
                rules.append(rule)
            }
        }
        persist()
        scheduleWriteConfig()
        await applyConfig(reloadIfRunning: true)
        bumpChromeRevision()
        statusText = "应用分组已更新"
    }

    func addAppRoutingPreset(_ preset: AppRoutingRules.CommonAppPreset) async {
        var rule = preset.asRule(lang: settings.uiLanguage)
        await upsertAppRoutingRule(rule)
    }

    @discardableResult
    func addAllCommonAppRoutingPresets() async -> Int {
        var added = 0
        mutateAppRoutingRules { rules in
            for preset in AppRoutingRules.bulkAddPresets {
                guard AppRoutingRules.existingIndex(of: preset, in: rules) == nil else { continue }
                var rule = preset.asRule(lang: settings.uiLanguage)
                rules.append(rule)
                added += 1
            }
        }
        guard added > 0 else {
            statusText = "常用应用分组已全部添加"
            return 0
        }
        persist()
        scheduleWriteConfig()
        await applyConfig(reloadIfRunning: true)
        bumpChromeRevision()
        statusText = "已添加 \(added) 个常用应用分组"
        return added
    }

    func removeAppRoutingRule(id: UUID) async {
        mutateAppRoutingRules { rules in
            rules.removeAll { $0.id == id }
        }
        persist()
        scheduleWriteConfig()
        await applyConfig(reloadIfRunning: true)
        bumpChromeRevision()
        statusText = "已删除应用分组"
    }

    func setAppRoutingRuleEnabled(id: UUID, enabled: Bool) async {
        mutateAppRoutingRules { rules in
            guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
            rules[idx].enabled = enabled
        }
        persist()
        scheduleWriteConfig()
        await applyConfig(reloadIfRunning: true)
        bumpChromeRevision()
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
        if !rulesText.isEmpty {
            rulesText = settings.rules.joined(separator: "\n")
        }
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
            let writeOK = await SystemProxy.setEnabledAsync(
                enabled,
                port: port,
                allowPrivilegePrompt: true
            )
            guard !Task.isCancelled else { return }

            if enabled, !writeOK {
                self.systemProxyOn = false
                self.settings.systemProxyEnabled = false
                self.bumpChromeRevision()
                self.schedulePersist()
                self.statusText = SystemProxy.lastError
                    ?? "系统代理写入失败，请输入管理员密码授权（与 TUN 同一助手）"
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
    /// WHATSAPP follows the user's PROXY leaf — WHATSAPP-AUTO url-test only checks HTTP 200,
    /// not `/ws/chat` WebSocket; it often picks a node that loads the page but never shows QR.
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
        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: "WHATSAPP",
            name: "PROXY"
        )
    }

    /// Pin OPENAI / ANTHROPIC / AI to the sticky AI node (manual select only).
    /// CURSOR uses CURSOR-FAILOVER — do not pin here (Asia leaf breaks agent streams).
    private func syncAIStableGroups() async {
        let target = settings.stableAINodeName
            ?? settings.selectedNodeName
            ?? activeProxyTarget()
        guard target != "AUTO", !target.isEmpty else { return }
        for group in ["OPENAI", "ANTHROPIC", "AI"] {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: group,
                name: target
            )
        }
    }

    /// Heal TELEGRAM path — restore FAILOVER first (kernel-side HA), then try concrete leaves.
    /// Never closeAllConnections here (kills MTProto / other apps).
    private func healTelegramGroupOnly() async {
        guard coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) else { return }
        let port = settings.mixedPort

        // Retest AUTO pool so FAILOVER has fresh health.
        _ = await ClashCore.retestProxyGroup(
            controller: settings.externalController,
            secret: settings.secret,
            group: "TELEGRAM-AUTO",
            url: TelegramReliability.probeURL,
            timeoutMs: 6000
        )

        // Prefer PROXY (user node) first — FAILOVER chain may be missing on broken passthrough configs.
        for pick in ["PROXY", "TELEGRAM-FAILOVER", "TELEGRAM-AUTO"] {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "TELEGRAM",
                name: pick
            )
            if await CoreHealth.telegramReachable(port: port) {
                statusText = "Telegram 已恢复（\(pick)）"
                return
            }
        }

        // Regional hubs (url-test groups already in config).
        for hub in ["HK", "JP", "TW"] {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "TELEGRAM",
                name: hub
            )
            if await CoreHealth.telegramReachable(port: port) {
                statusText = "Telegram 已切区域：\(hub)"
                return
            }
        }

        if let best = await bestTelegramLeafName() {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "TELEGRAM",
                name: best
            )
            if await CoreHealth.telegramReachable(port: port) {
                statusText = "Telegram 已切：\(best)"
                return
            }
        }

        // Last resort: any healthy Asia leaf from delay cache / node list.
        let keywords = ["香港", "HK", "新加坡", "SG", "日本", "JP", "台湾", "TW"]
        var candidates: [ProxyNode] = []
        var used = Set<String>()
        for key in keywords {
            for node in nodes where !used.contains(node.name)
                && !ClashConfigParser.isPlaceholderNodeName(node.name)
                && node.name.localizedCaseInsensitiveContains(key)
                && (node.delayMs ?? -1) > 0 {
                used.insert(node.name)
                candidates.append(node)
                if candidates.count >= 10 { break }
            }
            if candidates.count >= 10 { break }
        }
        if candidates.isEmpty {
            candidates = nodes
                .filter { !ClashConfigParser.isPlaceholderNodeName($0.name) && ($0.delayMs ?? -1) > 0 }
                .sorted(by: delaySort)
                .prefix(10)
                .map { $0 }
        } else {
            candidates.sort(by: delaySort)
        }
        for candidate in candidates.prefix(8) {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "TELEGRAM",
                name: candidate.name
            )
            if await CoreHealth.telegramReachable(port: port) {
                statusText = "Telegram 已切：\(candidate.name)（\(candidate.delayMs ?? 0) ms）"
                return
            }
        }

        // Stick on FAILOVER even if probe still fails — kernel keeps rotating.
        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: "TELEGRAM",
            name: "TELEGRAM-FAILOVER"
        )
        statusText = "Telegram 探测未通，已挂故障转移链"
    }

    /// Heal CURSOR path — kernel FAILOVER first, then US / AI hubs and concrete leaves.
    private func healCursorGroupOnly() async {
        guard coreRunning || CoreHealth.mixedPortAlive(port: settings.mixedPort) else { return }
        let port = settings.mixedPort

        _ = await ClashCore.retestProxyGroup(
            controller: settings.externalController,
            secret: settings.secret,
            group: "CURSOR-AUTO",
            url: CursorReliability.probeURL,
            timeoutMs: 6000
        )

        for pick in ["PROXY", "CURSOR-FAILOVER", "CURSOR-AUTO"] {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "CURSOR",
                name: pick
            )
            if await CoreHealth.cursorReachable(port: port) {
                statusText = "Cursor 已恢复（\(pick)）"
                return
            }
        }

        for hub in ["US", "AI"] {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "CURSOR",
                name: hub
            )
            if await CoreHealth.cursorReachable(port: port) {
                statusText = "Cursor 已切区域：\(hub)"
                return
            }
        }

        if let best = await bestCursorLeafName() {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "CURSOR",
                name: best
            )
            if await CoreHealth.cursorReachable(port: port) {
                statusText = "Cursor 已切：\(best)"
                return
            }
        }

        let keywords = ["美国", "US", "USA", "Los Angeles", "San Jose", "西雅图", "纽约"]
        var candidates: [ProxyNode] = []
        var used = Set<String>()
        for key in keywords {
            for node in nodes where !used.contains(node.name)
                && !ClashConfigParser.isPlaceholderNodeName(node.name)
                && node.name.localizedCaseInsensitiveContains(key)
                && (node.delayMs ?? -1) > 0 {
                used.insert(node.name)
                candidates.append(node)
                if candidates.count >= 10 { break }
            }
            if candidates.count >= 10 { break }
        }
        if candidates.isEmpty {
            candidates = nodes
                .filter { !ClashConfigParser.isPlaceholderNodeName($0.name) && ($0.delayMs ?? -1) > 0 }
                .sorted(by: delaySort)
                .prefix(10)
                .map { $0 }
        } else {
            candidates.sort(by: delaySort)
        }
        for candidate in candidates.prefix(8) {
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "CURSOR",
                name: candidate.name
            )
            if await CoreHealth.cursorReachable(port: port) {
                statusText = "Cursor 已切：\(candidate.name)（\(candidate.delayMs ?? 0) ms）"
                return
            }
        }

        try? await ClashCore.selectProxy(
            controller: settings.externalController,
            secret: settings.secret,
            group: "CURSOR",
            name: "CURSOR-FAILOVER"
        )
        statusText = "Cursor 探测未通，已挂故障转移链"
    }

    /// Lowest-delay US leaf from CURSOR-AUTO delay map.
    private func bestCursorLeafName() async -> String? {
        let delays = await ClashCore.proxyGroupDelays(
            controller: settings.externalController,
            secret: settings.secret,
            group: "CURSOR-AUTO",
            url: CursorReliability.probeURL,
            timeoutMs: 6000
        )
        let preferredKeys = ["美国", "US", "USA", "Los Angeles", "San Jose", "西雅图", "纽约", "凤凰城"]
        let ranked = delays
            .filter { $0.value > 0 && $0.value < 5000 && !ClashConfigParser.isPlaceholderNodeName($0.key) }
            .sorted { $0.value < $1.value }
        let us = ranked.filter { item in
            preferredKeys.contains { item.key.localizedCaseInsensitiveContains($0) }
        }
        return (us.first ?? ranked.first)?.key
    }

    private func currentProxyGroupNow(_ group: String) async -> String? {
        await ClashCore.fetchProxyGroup(
            controller: settings.externalController,
            secret: settings.secret,
            group: group
        )?.now
    }

    /// Lowest-delay Asia leaf from TELEGRAM-AUTO delay map.
    private func bestTelegramLeafName() async -> String? {
        let delays = await ClashCore.proxyGroupDelays(
            controller: settings.externalController,
            secret: settings.secret,
            group: "TELEGRAM-AUTO",
            url: TelegramReliability.probeURL,
            timeoutMs: 6000
        )
        let preferredKeys = ["香港", "HK", "新加坡", "SG", "日本", "JP", "台湾", "TW"]
        let ranked = delays
            .filter { $0.value > 0 && $0.value < 5000 && !ClashConfigParser.isPlaceholderNodeName($0.key) }
            .sorted { $0.value < $1.value }
        let asia = ranked.filter { item in
            preferredKeys.contains { item.key.localizedCaseInsensitiveContains($0) }
        }
        return (asia.first ?? ranked.first)?.key
    }

    func setTUN(_ enabled: Bool) async {
        userStoppedCore = false
        settings.tunEnabled = enabled
        settings.userDisabledTun = !enabled
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
                if !settings.userDisabledSystemProxy {
                    settings.systemProxyEnabled = true
                }
                schedulePersist()
                writeConfig()
                await startCoreAsync(forceRestart: true)
                await applyDefaultSystemProxyIfEnabled()
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

    /// Selected node, or strategy hub when smart/LB/failover is on.
    func activeProxyTarget() -> String {
        switch settings.proxyHubMode {
        case .smart, .loadBalance, .failover:
            return settings.proxyHubMode.selectorName
        case .manual:
            if let name = settings.selectedNodeName,
               name == "DIRECT" || name == "AUTO" || name == "BALANCE" || name == "FALLBACK"
                || nodes.contains(where: { $0.name == name }) {
                return name
            }
            return nodes.isEmpty ? "DIRECT" : "AUTO"
        }
    }

    func writeConfig() {
        writeConfigTask?.cancel()
        _ = writeConfigNow()
    }

    /// Block until config.yaml is regenerated (used when recovering from mihomo -t failures).
    func writeConfigAndWait() async {
        writeConfigTask?.cancel()
        let task = writeConfigNow()
        await task.value
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

    private func writeConfigNow() -> Task<Void, Never> {
        let mergedRules = effectiveRuntimeRules()
        let snapshotNodes = nodes
        let selectedName = settings.selectedNodeName
        let stableAI = settings.stableAINodeName
        let excluded = excludedNodeNamesForConfig()
        let mixedPort = settings.mixedPort
        let controller = settings.externalController
        let secret = settings.secret
        let tunEnabled = effectiveTunInConfig()
        let tunStack = settings.tunStack
        let mode = settings.proxyMode
        let hubMode = settings.proxyHubMode
        let allowLan = settings.allowLan
        let turboMode = settings.turboMode
        let domainSniffing = settings.domainSniffing
        let dnsPreference = settings.dnsPreference
        let configURL = Paths.configURL
        let profileRoot = Self.loadPassthroughProfileRoot(from: settings)

        writeConfigBuildTask?.cancel()
        let task = Task { [weak self] in
            let yaml = await Task.detached(priority: .userInitiated) {
                if let profileRoot {
                    return ClashConfigParser.buildPassthroughConfig(
                        from: profileRoot,
                        mixedPort: mixedPort,
                        controller: controller,
                        secret: secret,
                        tunEnabled: tunEnabled,
                        tunStack: tunStack,
                        mode: mode,
                        allowLan: allowLan,
                        dnsPreference: dnsPreference,
                        domainSniffing: domainSniffing,
                        selectedName: selectedName,
                        proxyHubMode: hubMode,
                        turboMode: turboMode
                    )
                }
                return ClashConfigParser.buildConfig(
                    nodes: snapshotNodes,
                    selectedName: selectedName,
                    mixedPort: mixedPort,
                    controller: controller,
                    secret: secret,
                    rules: mergedRules,
                    tunEnabled: tunEnabled,
                    tunStack: tunStack,
                    mode: mode,
                    allowLan: allowLan,
                    turboMode: turboMode,
                    domainSniffing: domainSniffing,
                    dnsPreference: dnsPreference,
                    stableAINodeName: stableAI,
                    excludedNodeNames: excluded,
                    proxyHubMode: hubMode
                )
            }.value
            guard !Task.isCancelled, let self else { return }
            guard !yaml.isEmpty else {
                self.statusText = "配置生成失败"
                return
            }
            do {
                try await Task.detached(priority: .utility) {
                    try yaml.data(using: .utf8)?.write(to: configURL, options: .atomic)
                    OpenClashDirectRules.publish(nodes: snapshotNodes)
                }.value
            } catch {
                self.statusText = "写入 config.yaml 失败：\(error.localizedDescription)"
            }
        }
        writeConfigBuildTask = task
        return task
    }

    /// Single enabled Clash YAML with native `proxy-groups` → keep as profile (Verge/Stash).
    static func loadPassthroughProfileRoot(from settings: AppSettings) -> [String: Any]? {
        let enabled = settings.subscriptions.filter(\.enabled)
        guard enabled.count == 1, let sub = enabled.first else { return nil }
        let url = Paths.subscriptionCacheURL(id: sub.id)
        guard let data = try? Data(contentsOf: url),
              let parsed = try? ClashConfigParser.parse(data),
              ClashConfigParser.isCompleteProfile(parsed.rawRoot) else { return nil }
        return parsed.rawRoot
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
            appRouting: settings.appRoutingRules,
            videoAdBlockEnabled: settings.videoAdBlockEnabled,
            enabledPluginIds: settings.enabledPluginIds
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
    /// Stash-style: picking AUTO/BALANCE/FALLBACK on PROXY also updates hub mode.
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
            switch name.uppercased() {
            case "AUTO":
                settings.proxyHubMode = .smart
            case "BALANCE":
                settings.proxyHubMode = .loadBalance
            case "FALLBACK":
                settings.proxyHubMode = .failover
            default:
                settings.proxyHubMode = .manual
            }
            schedulePersist()
            bumpHubModeRevision()
            bumpChromeRevision()
            scheduleOutboundIPRefresh()
        } else {
            bumpChromeRevision()
        }
        statusText = "\(group) 已选：\(name)"
        scheduleRuntimeOutboundRefresh()
    }

    func fetchMenuProxyGroups() async -> [ClashCore.ProxyGroupInfo] {
        guard coreRunning else { return [] }
        let all = await ClashCore.fetchAllProxyGroups(
            controller: settings.externalController,
            secret: settings.secret
        )
        if !all.isEmpty { return all }
        var out: [ClashCore.ProxyGroupInfo] = []
        for name in AppConstants.menuProxyGroups {
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

    func setPluginEnabled(_ id: String, enabled: Bool) async {
        var ids = settings.enabledPluginIds
        if enabled {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        settings.enabledPluginIds = ids
        if enabled, settings.proxyMode != .rule {
            settings.proxyMode = .rule
        }
        persist()
        await applyConfig(reloadIfRunning: true)
        let name = PluginEngine.plugin(id: id)?.name ?? id
        statusText = enabled ? "已启用插件：\(name)" : "已关闭插件：\(name)"
    }

    func setAllPluginsEnabled(_ enabled: Bool) async {
        if enabled {
            settings.enabledPluginIds = PluginEngine.catalogForCurrentPlatform.map(\.id)
            if settings.proxyMode != .rule {
                settings.proxyMode = .rule
            }
        } else {
            settings.enabledPluginIds = []
        }
        persist()
        await applyConfig(reloadIfRunning: true)
        statusText = enabled
            ? L10n.t("plugin.market.enableAll", settings.uiLanguage)
            : L10n.t("plugin.market.disableAll", settings.uiLanguage)
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
        let changed = launchAtLoginOn != on || settings.launchAtLoginEnabled != on
        guard changed else { return }
        launchAtLoginOn = on
        if settings.launchAtLoginEnabled != on {
            settings.launchAtLoginEnabled = on
            persist()
        }
        bumpChromeRevision()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        _ = LaunchAtLogin.setEnabled(enabled)
        refreshLaunchAtLogin()
        if enabled, !launchAtLoginOn {
            statusText = "开机启动开启失败：\(LaunchAtLogin.statusText)"
        } else {
            statusText = launchAtLoginOn ? "已开启开机自动启动" : "已关闭开机自动启动"
        }
    }

    func applyConfig(reloadIfRunning: Bool) async {
        await writeConfigAndWait()
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
            try? await ClashCore.selectProxy(
                controller: settings.externalController,
                secret: settings.secret,
                group: "WHATSAPP",
                name: "PROXY"
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
        guard !coreRepairInFlight else { return }
        coreRepairInFlight = true
        isBusy = true
        defer {
            isBusy = false
            coreRepairInFlight = false
        }

        statusText = "正在修复内核…"
        stopCore(clearProxy: false, markUserStopped: false)
        try? await Task.sleep(nanoseconds: 400_000_000)

        do {
            let path = try await Task.detached(priority: .userInitiated) { [weak self] () async throws -> String in
                try? FileManager.default.removeItem(at: CoreInstaller.bundledPath)
                try? FileManager.default.removeItem(at: Paths.coreHashURL)
                if let seeded = CoreInstaller.seedEmbeddedCoreIfNeeded() {
                    return seeded
                }
                return try await CoreInstaller.ensureInstalled { msg in
                    Task { @MainActor in self?.statusText = msg }
                }
            }.value
            settings.clashBinaryPath = path
            schedulePersist()
            statusText = "内核已就绪：\(CoreInstaller.pinnedVersion)"
            _ = await ensureCoreRunning()
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
        guard !coreRepairInFlight else { return false }
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
                await migrateBusyPortsIfNeeded()
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
        return false
    }

    func startCoreAsync(forceRestart: Bool = false) async {
        if userStoppedCore && !forceRestart { return }
        if coreRepairInFlight { return }

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
                scheduleRuntimeOutboundRefresh()
                return
            }
        }

        coreStartInFlight = true
        let wasConnecting = coreConnecting
        if !wasConnecting {
            coreConnecting = true
            // Do not bumpChromeRevision here — it remounts sidebar chrome and makes
            // the start button look like it is flashing during auto-retry.
        }
        defer {
            coreStartInFlight = false
            if coreConnecting {
                coreConnecting = false
            }
        }
        userStoppedCore = false
        lastCoreRestartAttempt = Date()

        sanitizeRulesForCore()
        await migrateBusyPortsIfNeeded()

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
        let mixedPort = settings.mixedPort

        // If something is still holding ports…
        var portBusy = await Task.detached(priority: .utility) {
            PortProbe.isListening(port: mixedPort)
                || PortProbe.isListening(host: controllerHost, port: controllerPort)
        }.value

        if portBusy {
            // Alive API on those ports → already our core (or compatible).
            await refreshCoreStatus()
            if coreRunning, !forceRestart, !settings.tunEnabled {
                statusText = "内核已在运行"
                return
            }
            // Prefer port migration — elevated kill is bundled into TUN start (single password).
            await ClashCore.stopAllAsync(binaryHint: binaryHint)
            await migrateBusyPortsIfNeeded()
            let mixAfter = settings.mixedPort
            let apiPortAfter = Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? controllerPort
            let hostAfter = settings.externalController.split(separator: ":").first.map(String.init) ?? controllerHost
            portBusy = await Task.detached(priority: .utility) {
                PortProbe.isListening(port: mixAfter)
                    || PortProbe.isListening(host: hostAfter, port: apiPortAfter)
            }.value
            let mihomoAlive = await ClashCore.isMihomoAliveAsync()
            if portBusy, !mihomoAlive {
                // Last resort: bump ports so start can proceed.
                let freePorts = await Task.detached(priority: .utility) { () -> (Int?, Int?) in
                    (
                        PortProbe.firstFreePort(from: mixAfter + 1, limit: 40),
                        PortProbe.firstFreePort(from: apiPortAfter + 1, limit: 40)
                    )
                }.value
                if let freeMix = freePorts.0 {
                    settings.mixedPort = freeMix
                }
                if let freeAPI = freePorts.1 {
                    settings.externalController = "\(hostAfter):\(freeAPI)"
                }
                persist()
            }
        }

        let finalControllerHost = settings.externalController.split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        let finalControllerPort = Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? 19090
        let finalMixed = settings.mixedPort
        let stillBusy = await Task.detached(priority: .utility) {
            PortProbe.isListening(port: finalMixed)
                || PortProbe.isListening(host: finalControllerHost, port: finalControllerPort)
        }.value
        if stillBusy {
            await refreshCoreStatus()
            if coreRunning, !forceRestart {
                statusText = "内核已在运行"
                return
            }
            await migrateBusyPortsIfNeeded()
            let mix2 = settings.mixedPort
            let host2 = settings.externalController.split(separator: ":").first.map(String.init) ?? finalControllerHost
            let port2 = Int(settings.externalController.split(separator: ":").last.map(String.init) ?? "") ?? finalControllerPort
            let busy2 = await Task.detached(priority: .utility) {
                PortProbe.isListening(port: mix2)
                    || PortProbe.isListening(host: host2, port: port2)
            }.value
            if busy2 {
                let freePorts = await Task.detached(priority: .utility) { () -> (Int?, Int?) in
                    (
                        PortProbe.firstFreePort(from: mix2 + 1, limit: 40),
                        PortProbe.firstFreePort(from: port2 + 1, limit: 40)
                    )
                }.value
                if let freeMix = freePorts.0 {
                    settings.mixedPort = freeMix
                }
                if let freeAPI = freePorts.1 {
                    settings.externalController = "\(host2):\(freeAPI)"
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

            await writeConfigAndWait()
            await ensureGeoDataReady(progress: true)

            // Quick syntax/loop check via mihomo -t before we elevate / spawn.
            if let testErr = await Self.mihomoConfigTestError() {
                statusText = "配置异常：\(testErr)，正在修复…"
                if Self.isGeoRelatedConfigError(testErr) {
                    await ensureGeoDataReady(progress: true, force: true)
                }
                await writeConfigAndWait()
                if let still = await Self.mihomoConfigTestError() {
                    let hint = Self.isGeoRelatedConfigError(still)
                        ? "（需联网下载 geoip/geosite，可先连可用网络后重启）"
                        : ""
                    statusText = "配置仍异常：\(still)\(hint)"
                    LaunchDiagnostics.error(statusText)
                    applyCoreRunning(false)
                    return
                }
            }

            var attempt = 0
            var lastFailDetail = ""
            // Clash Verge style: if user wants TUN, always try elevate (install helper once if needed).
            // Bug was: requestElevatedCoreStart only set on toggle → restart dropped TUN from yaml
            // while UI still showed TUN on → Telegram MTProto UDP bypassed SOCKS and spun forever.
            if settings.tunEnabled {
                requestElevatedCoreStart = true
                if TunPrivilege.isReady {
                    runtimeTunInConfig = true
                }
            }
            let wantTUN = settings.tunEnabled
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
                    do {
                        coreProcess = try ClashCore.start(
                            binary: binary,
                            configDir: Paths.supportDir,
                            asRoot: useRoot
                        )
                    } catch {
                        // TUN helper / elevate failed — still bring core up without TUN.
                        if useRoot {
                            let msg = error.localizedDescription
                            statusText = "TUN 启动失败，改用普通模式：\(msg)"
                            useRoot = false
                            runtimeTunInConfig = false
                            requestElevatedCoreStart = false
                            writeConfig()
                            coreProcess = try ClashCore.start(
                                binary: binary,
                                configDir: Paths.supportDir,
                                asRoot: false
                            )
                        } else {
                            throw error
                        }
                    }
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
                                "tun": ClashConfigParser.tunConfigBlock(
                                    stack: settings.tunStack.isEmpty ? "mixed" : settings.tunStack
                                )
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
                    // Prefer cached delay / AUTO — avoid auto full speed-test (stuck「测速中」+ stutter).
                    if settings.proxyHubMode == .smart || settings.autoSelectFastest {
                        // Hub mode: stay on AUTO/BALANCE/FALLBACK — don't pin a dead leaf.
                        if settings.proxyHubMode == .manual {
                            await selectFastestNodeIfAvailable()
                        }
                    }
                    // Verify egress; dead sticky leaf → fall back to AUTO so Mac keeps net.
                    let port = settings.mixedPort
                    let egressOK = await CoreHealth.googleReachable(port: port)
                    if !egressOK {
                        if settings.proxyHubMode == .manual {
                            settings.proxyHubMode = .smart
                            settings.selectedNodeName = ProxyHubMode.smart.selectorName
                            bumpHubModeRevision()
                            schedulePersist()
                        }
                        let fallback = activeProxyTarget()
                        try? await ClashCore.selectProxy(
                            controller: settings.externalController,
                            secret: settings.secret,
                            group: "PROXY",
                            name: fallback
                        )
                        statusText = "节点不通，已切 \(fallback)"
                    }
                    // Kick TELEGRAM / CURSOR onto FAILOVER so apps have kernel-side HA immediately.
                    Task { await self.healTelegramGroupOnly() }
                    Task { await self.healCursorGroupOnly() }
                    scheduleOutboundIPRefresh()
                    scheduleRuntimeOutboundRefresh()
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
                    // `system` stack often reports enable=true but never installs default routes
                    // on newer macOS → AdsPower/IPFoxy still egress via en0 (CN) and fail.
                    // Prefer `mixed` which reliably auto-routes.
                    if settings.tunStack == "system" || settings.tunStack.isEmpty {
                        settings.tunStack = "mixed"
                        persist()
                        mutated = true
                        statusText = "改用 mixed 协议栈重试 TUN…"
                    } else if settings.tunStack != "gvisor" {
                        settings.tunStack = "gvisor"
                        persist()
                        mutated = true
                        statusText = "改用 gvisor 协议栈重试 TUN…"
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

    /// Download geo DBs mihomo needs for GEOSITE/GEOIP rules (first launch / after upgrade).
    private func ensureGeoDataReady(progress: Bool, force: Bool = false) async {
        guard force || !GeoDataBootstrap.isReady() else { return }
        if progress {
            statusText = "正在下载地理规则库（首次需联网）…"
        }
        do {
            try await GeoDataBootstrap.ensurePresent { [weak self] msg in
                guard progress else { return }
                Task { @MainActor in self?.statusText = msg }
            }
        } catch {
            if progress {
                statusText = "地理库下载失败：\(error.localizedDescription)"
            }
            LaunchDiagnostics.error("地理库下载失败：\(error.localizedDescription)")
        }
    }

    private static func isGeoRelatedConfigError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("geosite")
            || lower.contains("geoip")
            || lower.contains("geo site")
            || lower.contains("geoip.dat")
            || lower.contains("geosite.dat")
            || lower.contains("geoip.metadb")
            || message.contains("地理")
    }

    /// Run `mihomo -t` so proxy-group loops / bad YAML fail before elevate.
    private static func mihomoConfigTestError() async -> String? {
        let binary = ClashCore.resolveBinary(customPath: SettingsStore.load().clashBinaryPath)
            ?? Paths.supportDir.appendingPathComponent("mihomo").path
        let dir = Paths.supportDir.path
        let cfg = Paths.configURL.path
        guard FileManager.default.isExecutableFile(atPath: binary),
              FileManager.default.fileExists(atPath: cfg) else { return nil }
        return await Task.detached(priority: .utility) { () -> String? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = ["-t", "-d", dir, "-f", cfg]
            let err = Pipe()
            let out = Pipe()
            p.standardError = err
            p.standardOutput = out
            do { try p.run() } catch { return error.localizedDescription }
            p.waitUntilExit()
            guard p.terminationStatus != 0 else { return nil }
            let raw = String(data: err.fileHandleForReading.readDataToEndOfFile() + out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let line = raw.split(separator: "\n").reversed().first(where: {
                $0.localizedCaseInsensitiveContains("err")
                    || $0.localizedCaseInsensitiveContains("loop")
                    || $0.localizedCaseInsensitiveContains("parse")
                    || $0.localizedCaseInsensitiveContains("fail")
            }).map(String.init) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clipped.isEmpty else { return "配置校验失败" }
            return String(clipped.suffix(180))
        }.value
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
        Task.detached(priority: .userInitiated) {
            ClashCore.stopAll(binaryHint: hint)
        }
        applyCoreRunning(false)
        mixedPortCachedAlive = false
        CoreHealth.invalidatePortCache(port: settings.mixedPort)

        if clearProxy, settings.systemProxyEnabled || systemProxyOn {
            SystemProxy.setEnabled(false, port: settings.mixedPort)
            systemProxyOn = false
            settings.systemProxyEnabled = false
            persist()
        }
        statusText = "已请求停止内核"
    }

    /// Cleanup before exit (proxy + core). Never blocks or asks for password.
    func prepareForQuit() {
        healthTask?.cancel()
        healthTask = nil
        launchGuardTask?.cancel()
        launchGuardTask = nil
        telegramGuardTask?.cancel()
        telegramGuardTask = nil
        cursorGuardTask?.cancel()
        cursorGuardTask = nil
        autoSpeedTask?.cancel()
        autoSpeedTask = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        persistTask?.cancel()
        writeConfigTask?.cancel()
        writeConfigBuildTask?.cancel()
        persist()
        if systemProxyOn || settings.systemProxyEnabled {
            SystemProxy.setEnabled(false, port: settings.mixedPort)
            systemProxyOn = false
        }
        userStoppedCore = true
        coreProcess?.terminate()
        coreProcess = nil
        applyCoreRunning(false)
        mixedPortCachedAlive = false
        let controller = settings.externalController
        let secret = settings.secret
        let hint = ClashCore.resolveBinary(customPath: settings.clashBinaryPath)
        ClashCore.disableTUNViaAPI(controller: controller, secret: secret)
        // Fire-and-forget — quit path must not block MainActor on pkill.
        Task.detached(priority: .userInitiated) {
            ClashCore.stopAll(binaryHint: hint)
        }
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
