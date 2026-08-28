import Foundation
import Combine
import UIKit

@MainActor
final class IOSAppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var nodes: [ProxyNode] = []
    @Published var statusText = L10n.t("status.ready")
    @Published var isBusy = false
    @Published var isTesting = false
    @Published var testedCount = 0
    @Published var searchText = ""
    @Published var sortByDelay = true
    @Published var selectedCategoryKey: String? = nil
    @Published var outboundIP: String = "—"
    @Published var outboundIPLoading = false
    @Published var isPreparingGeodata = false
    @Published var proxyGroups: [VPNManager.ProxyGroupSnapshot] = []
    /// Root tab index: 0 home / 1 nodes / 2 subscriptions / 3 settings
    @Published var selectedTab = 0
    /// When true, SubscriptionsView should present the add sheet once.
    @Published var pendingShowAddSubscription = false
    /// Session unlock for wallpaper disguise (re-locks on background).
    @Published var isAppUnlocked = false
    /// Prefill URL when opened via QR / deep link.
    @Published var pendingSubscriptionURL: String?

    let vpn = VPNManager()
    private let tester = SpeedTester()
    private var persistTask: Task<Void, Never>?
    private var configWriteTask: Task<Void, Never>?
    private var outboundIPTask: Task<Void, Never>?
    private var proxyGroupsTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var showsDisguise: Bool {
        settings.iosDisguiseEnabled && !isAppUnlocked
    }
    init() {
        settings = SettingsStore.load()
        L10n.apply(settings.uiLanguage)
        settings.externalController = AppConstants.externalController
        settings.mixedPort = AppConstants.mixedPort
        if ChinaSmartRules.needsUpgrade(settings.rules, storedVersion: settings.rulesVersion) {
            settings.rules = ChinaSmartRules.rules
            settings.rulesVersion = ChinaSmartRules.version
        }
        let sanitized = GeoSiteRules.sanitize(settings.rules)
        if sanitized != settings.rules {
            settings.rules = sanitized
            settings.rulesVersion = ChinaSmartRules.version
        }
        reloadNodesFromCache()
        applyDelayCache()
        writeConfig()
        // Re-apply with catalog name `AppIcon-*` so SpringBoard never keeps a blank tile
        // from older builds that used bare style rawValues.
        Task { await IOSIconManager.apply(style: settings.logoStyle) }
        vpn.$status
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self else { return }
                if status == .connected {
                    self.scheduleOutboundIPRefresh(delay: 1.2)
                    self.scheduleProxyGroupsRefresh(delay: 0.8)
                } else if status == .disconnected || status == .invalid {
                    self.outboundIP = "—"
                    self.outboundIPLoading = false
                    self.proxyGroups = []
                }
            }
            .store(in: &cancellables)
    }

    var selectedNode: ProxyNode? {
        nodes.first { $0.name == settings.selectedNodeName }
    }

    var categorySummaries: [(key: String, title: String, flag: String, count: Int)] {
        NodeCategory.groups(from: nodes, sortByDelay: false).map {
            (key: $0.key, title: $0.title, flag: $0.flag, count: $0.nodes.count)
        }
    }

    var filteredNodes: [ProxyNode] {
        var list = nodes
        if !searchText.isEmpty {
            let q = searchText
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || $0.type.localizedCaseInsensitiveContains(q)
                    || $0.server.localizedCaseInsensitiveContains(q)
            }
        }
        if let key = selectedCategoryKey {
            let map = NodeCategory.displayGroups(among: nodes)
            list = list.filter { map[$0.name]?.key == key }
        }
        if sortByDelay {
            list.sort {
                let a = $0.delayMs ?? Int.max
                let b = $1.delayMs ?? Int.max
                if a != b { return a < b }
                return $0.name < $1.name
            }
        } else {
            list.sort { $0.name < $1.name }
        }
        return list
    }

    var categoryGroups: [NodeCategory.Group] {
        NodeCategory.groups(from: filteredNodes, sortByDelay: sortByDelay)
    }

    var fastestNode: ProxyNode? {
        nodes
            .filter { ($0.delayMs ?? -1) >= 0 }
            .min { ($0.delayMs ?? Int.max) < ($1.delayMs ?? Int.max) }
    }

    func persist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            _ = SettingsStore.save(settings)
        }
    }

    /// Flush settings immediately — used for mode / critical toggles so relaunch doesn't lose them.
    func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        _ = SettingsStore.save(settings)
    }

    func setMode(_ mode: ProxyMode) {
        guard settings.proxyMode != mode else {
            // Re-assert live mode if UI already shows it but tunnel drifted.
            if vpn.isConnected {
                vpn.setProxyMode(mode.rawValue)
                if mode != .direct, let name = settings.selectedNodeName {
                    Task { await vpn.selectNode(name) }
                }
            }
            return
        }
        var note = ""
        if settings.videoAdBlockEnabled, mode != .rule {
            settings.videoAdBlockEnabled = false
            note = L10n.t("status.adOffNote")
        }
        settings.proxyMode = mode
        writeConfig()
        persistNow()
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(mode.rawValue, forKey: "proxyMode")
        if vpn.isConnected {
            vpn.setProxyMode(mode.rawValue)
            // rule/global 出口节点；direct 忽略 selector。
            if mode != .direct, let name = settings.selectedNodeName, !name.isEmpty {
                Task { await vpn.selectNode(name) }
            }
        }
        statusText = String(format: L10n.t("status.modeSwitched"), mode.title, note)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func setVideoAdBlock(_ enabled: Bool) {
        settings.videoAdBlockEnabled = enabled
        var forcedRule = false
        if enabled, settings.proxyMode != .rule {
            settings.proxyMode = .rule
            forcedRule = true
        }
        writeConfig()
        persistNow()
        if forcedRule, vpn.isConnected {
            vpn.setProxyMode("rule")
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(ProxyMode.rule.rawValue, forKey: "proxyMode")
        }
        statusText = enabled
            ? String(format: L10n.t("status.adOn"), "\(VideoAdBlock.ruleCount)")
            : L10n.t("status.adOff")
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func reloadNodesFromCache() {
        var merged: [ProxyNode] = []
        var seen = Set<String>()
        for sub in settings.subscriptions where sub.enabled {
            let url = Paths.subscriptionCacheURL(id: sub.id)
            guard let data = try? Data(contentsOf: url),
                  let parsed = try? ClashConfigParser.parse(data) else { continue }
            for node in parsed.nodes {
                if seen.insert(node.name).inserted {
                    merged.append(node)
                }
            }
        }
        nodes = merged
        applyDelayCache()
        if let selected = settings.selectedNodeName,
           !merged.contains(where: { $0.name == selected }) {
            settings.selectedNodeName = merged.first?.name
        } else if settings.selectedNodeName == nil {
            settings.selectedNodeName = merged.first?.name
        }
    }

    private func applyDelayCache() {
        let cache = settings.nodeDelayCache
        for i in nodes.indices {
            if let d = cache[nodes[i].delayCacheKey] {
                nodes[i].delayMs = d
            }
        }
    }

    func addSubscription(name: String, url: String) {
        guard let trimmed = SubscriptionURL.normalized(url, allowInsecureHTTP: true) else {
            statusText = L10n.t("status.badURL")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let sub = Subscription(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.t("status.subDefault") : name,
            url: trimmed
        )
        settings.subscriptions.append(sub)
        persist()
        Task { await updateSubscription(id: sub.id) }
    }

    func removeSubscription(id: UUID) {
        settings.subscriptions.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Paths.subscriptionCacheURL(id: id))
        reloadNodesFromCache()
        writeConfig()
        persist()
    }

    func updateAllSubscriptions() async {
        isBusy = true
        statusText = L10n.t("status.updatingSubs")
        defer { isBusy = false }
        var okCount = 0
        var failCount = 0
        for sub in settings.subscriptions where sub.enabled {
            if await updateSubscription(id: sub.id, showBusy: false) {
                okCount += 1
            } else {
                failCount += 1
            }
        }
        if failCount == 0 {
            statusText = String(format: L10n.t("status.subsUpdated"), "\(nodes.count)")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if okCount == 0 {
            statusText = String(format: L10n.t("status.subsAllFail"), "\(failCount)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else {
            statusText = String(format: L10n.t("status.subsPartial"), "\(okCount)", "\(failCount)", "\(nodes.count)")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    @discardableResult
    func updateSubscription(id: UUID, showBusy: Bool = true) async -> Bool {
        guard let idx = settings.subscriptions.firstIndex(where: { $0.id == id }) else { return false }
        let subName = settings.subscriptions[idx].name
        if showBusy {
            isBusy = true
            statusText = String(format: L10n.t("status.updatingOne"), subName)
        }
        defer { if showBusy { isBusy = false } }

        guard let urlString = SubscriptionURL.normalized(
            settings.subscriptions[idx].url,
            allowInsecureHTTP: true
        ) else {
            statusText = String(format: L10n.t("status.oneBadURL"), subName)
            if showBusy { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            return false
        }

        _ = Paths.subscriptionsCacheDir
        let cacheURL = Paths.subscriptionCacheURL(id: id)
        let proxyPort: Int? = vpn.isConnected ? AppConstants.mixedPort : nil

        do {
            let result = try await SubscriptionFetcher.fetch(
                urlString: urlString,
                viaProxyPort: proxyPort
            )
            let parsed = try ClashConfigParser.parse(result.data)
            try result.data.write(to: cacheURL, options: .atomic)
            settings.subscriptions[idx].updatedAt = Date()
            settings.subscriptions[idx].userInfo = result.userInfo
            if let suggested = result.suggestedName,
               settings.subscriptions[idx].name == L10n.t("status.subDefault", .zh)
                || settings.subscriptions[idx].name == L10n.t("status.subDefault", .en)
                || settings.subscriptions[idx].name.isEmpty {
                settings.subscriptions[idx].name = suggested
            }
            reloadNodesFromCache()
            writeConfig()
            persist()
            if showBusy {
                statusText = String(format: L10n.t("status.oneUpdated"), subName, "\(parsed.nodes.count)")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            return true
        } catch {
            var message = error.localizedDescription
            if vpn.isConnected {
                message += L10n.t("status.disconnectRetry")
            }
            statusText = String(format: L10n.t("status.oneFail"), subName, message)
            if showBusy { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            return false
        }
    }

    func setLogoStyle(_ style: LogoStyle) {
        guard settings.logoStyle != style else { return }
        settings.logoStyle = style
        persist()
        statusText = String(format: L10n.t("status.icon"), style.title)
        Task { @MainActor in
            await IOSIconManager.apply(style: style)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectNode(_ name: String) {
        settings.selectedNodeName = name
        writeConfig()
        persist()
        Task { await vpn.selectNode(name) }
        statusText = String(format: L10n.t("status.selected"), name)
        UISelectionFeedbackGenerator().selectionChanged()
        if vpn.isConnected {
            scheduleOutboundIPRefresh(delay: 0.8)
        }
    }

    func selectGroupProxy(group: String, name: String) {
        guard vpn.isConnected else {
            statusText = String(format: L10n.t("status.needVpnSwitch"), group)
            return
        }
        statusText = String(format: L10n.t("status.switching"), group, name)
        Task {
            await vpn.selectGroupProxy(group: group, name: name)
            await refreshProxyGroups()
            statusText = String(format: L10n.t("status.groupSelected"), group, name)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func scheduleProxyGroupsRefresh(delay: TimeInterval = 0) {
        proxyGroupsTask?.cancel()
        proxyGroupsTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.refreshProxyGroups()
        }
    }

    func refreshProxyGroups() async {
        guard vpn.isConnected else {
            proxyGroups = []
            return
        }
        let groups = await vpn.fetchProxyGroups()
        proxyGroups = groups
    }

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
        guard vpn.isConnected else {
            outboundIP = "—"
            outboundIPLoading = false
            return
        }
        outboundIPLoading = true
        defer { outboundIPLoading = false }
        if let ip = await vpn.fetchOutboundIPViaTunnel() {
            outboundIP = ip
            return
        }
        if let ip = await OutboundIPProbe.fetch(viaProxyPort: nil) {
            outboundIP = ip
        } else {
            outboundIP = L10n.t("status.ipFail")
        }
    }

    func selectFastestIfAvailable() {
        guard let fastest = fastestNode else { return }
        selectNode(fastest.name)
    }

    func effectiveRuntimeRules() -> [String] {
        RuntimeRules.effective(
            base: settings.rules,
            prepend: settings.rulesPrepend,
            videoAdBlockEnabled: settings.videoAdBlockEnabled
        )
    }

    func applySmartRules() {
        settings.rules = ChinaSmartRules.rules
        settings.rulesVersion = ChinaSmartRules.version
        settings.rules = GeoSiteRules.sanitize(settings.rules)
        writeConfig()
        persist()
        statusText = String(format: L10n.t("status.rulesApplied"), "\(ChinaSmartRules.version)", "\(effectiveRuntimeRules().count)")
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func setDnsPreference(_ preference: DnsPreference) {
        guard settings.dnsPreference != preference else { return }
        settings.dnsPreference = preference
        writeConfig()
        persist()
        if vpn.isConnected {
            statusText = String(format: L10n.t("status.dnsReconnect"), preference.title)
        } else {
            statusText = String(format: L10n.t("status.dnsSet"), preference.title)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func writeConfig() {
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(settings.secret, forKey: "apiSecret")
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(settings.proxyMode.rawValue, forKey: "proxyMode")
        let nodes = nodes
        let selectedName = settings.selectedNodeName
        let mode = settings.proxyMode
        let rules = effectiveRuntimeRules()
        let secret = settings.secret
        let dnsPreference = settings.dnsPreference
        let tunnelCapture = settings.iosTunnelCapture
        configWriteTask?.cancel()
        configWriteTask = Task.detached(priority: .utility) {
            _ = IOSConfigWriter.write(
                nodes: nodes,
                selectedName: selectedName,
                mode: mode,
                rules: rules,
                secret: secret,
                dnsPreference: dnsPreference,
                tunnelCapture: tunnelCapture
            )
        }
    }

    func writeConfigNow() async {
        configWriteTask?.cancel()
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(settings.secret, forKey: "apiSecret")
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .set(settings.proxyMode.rawValue, forKey: "proxyMode")
        let nodes = nodes
        let selectedName = settings.selectedNodeName
        let mode = settings.proxyMode
        let rules = effectiveRuntimeRules()
        let secret = settings.secret
        let dnsPreference = settings.dnsPreference
        let tunnelCapture = settings.iosTunnelCapture
        await Task.detached(priority: .utility) {
            _ = IOSConfigWriter.write(
                nodes: nodes,
                selectedName: selectedName,
                mode: mode,
                rules: rules,
                secret: secret,
                dnsPreference: dnsPreference,
                tunnelCapture: tunnelCapture
            )
        }.value
    }

    func setIosTunnelCapture(_ enabled: Bool) {
        guard settings.iosTunnelCapture != enabled else { return }
        settings.iosTunnelCapture = enabled
        persist()
        writeConfig()
        statusText = enabled ? L10n.t("status.tunOn") : L10n.t("status.tunOff")
    }

    func testSpeeds(selectFastest: Bool = false) async {
        guard !nodes.isEmpty else { return }
        isTesting = true
        testedCount = 0
        statusText = L10n.t("status.testing")
        defer {
            isTesting = false
            statusText = L10n.t("status.tested")
        }
        let snapshot = nodes
        let results = await tester.testAll(
            nodes: snapshot,
            timeoutMs: settings.testTimeoutMs,
            concurrency: settings.concurrency,
            controller: vpn.status == .connected ? AppConstants.externalController : nil,
            secret: settings.secret,
            testURL: settings.testURL
        ) { [weak self] name, delay in
            guard let self else { return }
            if let i = self.nodes.firstIndex(where: { $0.name == name }) {
                self.nodes[i].delayMs = delay
                self.nodes[i].testedAt = Date()
                self.settings.nodeDelayCache[self.nodes[i].delayCacheKey] = delay
            }
            self.testedCount += 1
        }
        for r in results {
            if let i = nodes.firstIndex(where: { $0.name == r.name }) {
                nodes[i].delayMs = r.delayMs
                settings.nodeDelayCache[nodes[i].delayCacheKey] = r.delayMs
            }
        }
        persist()
        if selectFastest { selectFastestIfAvailable() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func openAddSubscription() {
        pendingShowAddSubscription = true
        selectedTab = 2
    }

    func unlockApp() {
        isAppUnlocked = true
        if pendingSubscriptionURL != nil {
            openAddSubscription()
        }
    }

    func lockApp() {
        guard settings.iosDisguiseEnabled else { return }
        isAppUnlocked = false
    }

    func setDisguiseEnabled(_ enabled: Bool) {
        settings.iosDisguiseEnabled = enabled
        if !enabled {
            isAppUnlocked = true
        }
        persist()
    }

    func setUiLanguage(_ language: AppLanguage) {
        settings.uiLanguage = language
        L10n.apply(language)
        persist()
        switch language {
        case .zh: statusText = L10n.t("lang.changed.zh", language)
        case .en: statusText = L10n.t("lang.changed.en", language)
        case .system: statusText = L10n.t("lang.changed.system", language)
        }
    }

    func handleOpenURL(_ url: URL) {
        // bashx://add?url=https%3A%2F%2F...
        // bashx://add/<url>
        // https://... subscription link opened into BashX
        let subURL: String? = {
            if url.scheme?.lowercased() == "bashx" {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let q = comps.queryItems?.first(where: { $0.name == "url" })?.value,
                   !q.isEmpty {
                    return q
                }
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if path.lowercased().hasPrefix("http") {
                    return path.removingPercentEncoding ?? path
                }
                return nil
            }
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url.absoluteString
            }
            return nil
        }()

        guard let subURL, !subURL.isEmpty else { return }
        pendingSubscriptionURL = subURL
        if showsDisguise {
            // Wait until unlock, then add sheet opens.
            return
        }
        openAddSubscription()
    }

    func toggleVPN() async {
        if nodes.isEmpty, !vpn.isConnected {
            statusText = L10n.t("status.needSubs")
            openAddSubscription()
            return
        }
        if let name = settings.selectedNodeName, !name.isEmpty {
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(name, forKey: "selectedNode")
        }
        await writeConfigNow()
        // Drop stale geo DBs that make mihomo hang downloading GitHub inside the NE.
        Self.scrubStaleGeoDatabases()
        if !vpn.isConnected {
            if let issue = MihomoConfigCheck.preflight() {
                statusText = issue
                return
            }
        }
        await vpn.toggle()
        if let err = vpn.lastError {
            statusText = err
        } else {
            statusText = vpn.statusText
        }
        if vpn.isConnected {
            scheduleOutboundIPRefresh(delay: 1.5)
        } else {
            outboundIP = "—"
        }
    }

    private static func scrubStaleGeoDatabases() {
        let fm = FileManager.default
        let home = Paths.mihomoHomeDir
        for name in ["geoip.metadb", "geosite.dat", "country.mmdb", "GeoLite2-Country.mmdb"] {
            let url = home.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }
}
