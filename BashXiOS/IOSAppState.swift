import Foundation
import Combine
import UIKit

@MainActor
final class IOSAppState: ObservableObject {
    @Published var settings: AppSettings
    @Published var nodes: [ProxyNode] = []
    @Published var statusText = "就绪"
    @Published var isBusy = false
    @Published var isTesting = false
    @Published var testedCount = 0
    @Published var searchText = ""
    @Published var sortByDelay = true
    @Published var selectedCategoryKey: String? = nil
    @Published var outboundIP: String = "—"
    @Published var outboundIPLoading = false
    @Published var isPreparingGeodata = false

    let vpn = VPNManager()
    private let tester = SpeedTester()
    private var persistTask: Task<Void, Never>?
    private var outboundIPTask: Task<Void, Never>?
    private var vpnWatchTask: Task<Void, Never>?

    init() {
        settings = SettingsStore.load()
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
        vpnWatchTask = Task { [weak self] in
            guard let self else { return }
            var lastConnected = false
            while !Task.isCancelled {
                let connected = self.vpn.isConnected
                if connected != lastConnected {
                    lastConnected = connected
                    if connected {
                        self.scheduleOutboundIPRefresh(delay: 1.2)
                    } else {
                        self.outboundIP = "—"
                        self.outboundIPLoading = false
                    }
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
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
            statusText = "链接无效，请使用 http:// 或 https:// 开头"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let sub = Subscription(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "订阅" : name,
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
        statusText = "更新订阅…"
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
            statusText = "订阅已更新 · \(nodes.count) 节点"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if okCount == 0 {
            statusText = "全部更新失败（\(failCount) 个）"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else {
            statusText = "部分成功：\(okCount) 成功，\(failCount) 失败 · \(nodes.count) 节点"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    @discardableResult
    func updateSubscription(id: UUID, showBusy: Bool = true) async -> Bool {
        guard let idx = settings.subscriptions.firstIndex(where: { $0.id == id }) else { return false }
        let subName = settings.subscriptions[idx].name
        if showBusy {
            isBusy = true
            statusText = "更新 \(subName)…"
        }
        defer { if showBusy { isBusy = false } }

        guard let urlString = SubscriptionURL.normalized(
            settings.subscriptions[idx].url,
            allowInsecureHTTP: true
        ) else {
            statusText = "「\(subName)」链接无效"
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
               settings.subscriptions[idx].name == "订阅" || settings.subscriptions[idx].name.isEmpty {
                settings.subscriptions[idx].name = suggested
            }
            reloadNodesFromCache()
            writeConfig()
            persist()
            if showBusy {
                statusText = "已更新「\(subName)」· \(parsed.nodes.count) 节点"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            return true
        } catch {
            var message = error.localizedDescription
            if vpn.isConnected {
                message += "（可先断开 VPN 再试）"
            }
            statusText = "「\(subName)」更新失败：\(message)"
            if showBusy { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            return false
        }
    }

    func setLogoStyle(_ style: LogoStyle) {
        guard settings.logoStyle != style else { return }
        settings.logoStyle = style
        persist()
        statusText = "图标：\(style.title)"
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
        statusText = "已选：\(name)"
        UISelectionFeedbackGenerator().selectionChanged()
        if vpn.isConnected {
            scheduleOutboundIPRefresh(delay: 0.8)
        }
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
            outboundIP = "查询失败"
        }
    }

    func selectFastestIfAvailable() {
        guard let fastest = fastestNode else { return }
        selectNode(fastest.name)
    }

    func setMode(_ mode: ProxyMode) {
        guard settings.proxyMode != mode else { return }
        var note = ""
        if settings.videoAdBlockEnabled, mode != .rule {
            settings.videoAdBlockEnabled = false
            note = "（视频广告过滤已关闭）"
        }
        settings.proxyMode = mode
        writeConfig()
        persist()
        if vpn.isConnected {
            vpn.setProxyMode(mode.rawValue)
        }
        statusText = "已切换为\(mode.title)模式\(note)"
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func effectiveRuntimeRules() -> [String] {
        RuntimeRules.effective(
            base: settings.rules,
            videoAdBlockEnabled: settings.videoAdBlockEnabled
        )
    }

    func applySmartRules() {
        settings.rules = ChinaSmartRules.rules
        settings.rulesVersion = ChinaSmartRules.version
        settings.rules = GeoSiteRules.sanitize(settings.rules)
        writeConfig()
        persist()
        statusText = "已应用 BashX 智能规则 v\(ChinaSmartRules.version)（\(effectiveRuntimeRules().count) 条）"
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func setVideoAdBlock(_ enabled: Bool) {
        settings.videoAdBlockEnabled = enabled
        if enabled, settings.proxyMode != .rule {
            settings.proxyMode = .rule
        }
        writeConfig()
        persist()
        statusText = enabled
            ? "视频广告过滤已开启（\(VideoAdBlock.ruleCount) 条）"
            : "视频广告过滤已关闭"
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func setDnsPreference(_ preference: DnsPreference) {
        guard settings.dnsPreference != preference else { return }
        settings.dnsPreference = preference
        writeConfig()
        persist()
        if vpn.isConnected {
            statusText = "DNS 已设为\(preference.title)，请重连 VPN 生效"
        } else {
            statusText = "DNS 已设为\(preference.title)"
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func writeConfig() {
        _ = IOSConfigWriter.write(
            nodes: nodes,
            selectedName: settings.selectedNodeName,
            mode: settings.proxyMode,
            rules: effectiveRuntimeRules(),
            secret: settings.secret,
            dnsPreference: settings.dnsPreference
        )
    }

    func testSpeeds(selectFastest: Bool = false) async {
        guard !nodes.isEmpty else { return }
        isTesting = true
        testedCount = 0
        statusText = "测速中…"
        defer {
            isTesting = false
            statusText = "测速完成"
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

    func toggleVPN() async {
        if let name = settings.selectedNodeName, !name.isEmpty {
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
                .set(name, forKey: "selectedNode")
        }
        writeConfig()
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
