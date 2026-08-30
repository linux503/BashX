import AppKit
import SwiftUI

/// Native menu-bar dropdown (ClashX-style).
/// Labels use a frozen snapshot to avoid submenu flash.
struct MenuBarView: View {
    @ObservedObject var state: AppState
    @State private var snap = MenuBarSnapshot.empty
    @State private var menuIsOpen = false
    @State private var pendingSnapRefresh = false
    @State private var trackingID: UUID?

    var body: some View {
        MenuBarFrozenContent(snap: snap, state: state, onRefresh: { refreshSnap(reason: .userAction) })
            .equatable()
            .onAppear {
                refreshSnap(reason: .appear)
                if trackingID == nil {
                    trackingID = MenuBarDropdownTracking.shared.subscribe(
                        onOpen: { handleMenuPresent() },
                        onClose: { handleMenuDismiss() }
                    )
                }
            }
            .onDisappear {
                if let trackingID {
                    MenuBarDropdownTracking.shared.unsubscribe(trackingID)
                    self.trackingID = nil
                }
            }
            .onReceive(state.$chromeRevision) { _ in
                if menuIsOpen {
                    applyLiveToggleFields()
                } else {
                    refreshSnap(reason: .chrome)
                }
            }
            .onReceive(state.$launchAtLoginOn) { on in
                // Keep menu checkmark in sync when panel/settings toggle login item.
                guard snap.launchAtLoginEnabled != on else { return }
                var next = snap
                next.launchAtLoginEnabled = on
                snap = next
            }
            .onReceive(state.$subscriptionsRevision) { _ in
                guard !menuIsOpen else { return }
                refreshSnap(reason: .chrome)
            }
    }

    private enum RefreshReason {
        case appear, chrome, userAction, present
    }

    private func handleMenuPresent() {
        menuIsOpen = true
        refreshSnap(reason: .present)
    }

    private func handleMenuDismiss() {
        menuIsOpen = false
        if pendingSnapRefresh {
            pendingSnapRefresh = false
            refreshSnap(reason: .chrome)
        }
    }

    private func refreshSnap(reason: RefreshReason) {
        state.refreshLaunchAtLogin()

        // While the menu is opening/open: never rebuild the full snap (NSMenu remount = flash).
        if reason == .present {
            applyLiveToggleFields()
            return
        }

        if menuIsOpen {
            applyLiveToggleFields()
            if reason != .userAction {
                pendingSnapRefresh = true
            }
            return
        }

        let next = MenuBarSnapshot.capture(from: state)
        if next != snap {
            snap = next
        }
    }

    /// While the menu is open, only refresh toggle rows from live state — no full snap rebuild.
    private func applyLiveToggleFields() {
        var next = snap
        next.launchAtLoginEnabled = state.launchAtLoginOn
        next.systemProxyOn = state.systemProxyOn
        next.closeConnectionsOnSwitch = state.settings.closeConnectionsOnSwitch
        next.showMenuBarTraffic = state.settings.showMenuBarTraffic
        next.tunEnabled = state.settings.tunEnabled
        next.videoAdBlockEnabled = state.settings.videoAdBlockEnabled
        next.autoSpeedTestEnabled = state.settings.autoSpeedTestEnabled
        next.autoSelectFastest = state.settings.autoSelectFastest
        if next != snap {
            snap = next
        }
    }
}

// MARK: - Frozen content (no @ObservedObject — avoids NSMenu submenu flash)

private struct MenuBarFrozenContent: View, Equatable {
    let snap: MenuBarSnapshot
    let state: AppState
    var onRefresh: () -> Void

    static func == (lhs: MenuBarFrozenContent, rhs: MenuBarFrozenContent) -> Bool {
        lhs.snap == rhs.snap
    }

    private func t(_ key: String) -> String { L10n.t(key, snap.lang) }

    var body: some View {
        Text(snap.status)
            .foregroundStyle(.secondary)

        Text(AppVersion.title)
            .foregroundStyle(.tertiary)

        Divider()

        Button(t("mac.menu.openPanel")) {
            PanelPresenter.shared.open(state: state)
        }
        .keyboardShortcut("o")

        Divider()

        Menu(t("mac.menu.proxyMode").replacingOccurrences(of: "%@", with: snap.proxyModeTitle)) {
            ForEach(ProxyMode.allCases) { mode in
                Button {
                    Task {
                        await state.setProxyMode(mode)
                        onRefresh()
                    }
                } label: {
                    menuCheckRow(mode.title(lang: snap.lang), on: snap.proxyMode == mode)
                }
            }
        }

        nodePickerSection

        Button(t("mac.menu.openGroups")) {
            PanelPresenter.shared.open(state: state, intent: .groups)
        }

        Divider()

        Toggle(isOn: Binding(
            get: { snap.systemProxyOn },
            set: { v in
                Task {
                    await state.setSystemProxy(v)
                    onRefresh()
                }
            }
        )) {
            Text(t("mac.menu.systemProxy"))
        }

        Toggle(isOn: Binding(
            get: { snap.closeConnectionsOnSwitch },
            set: { v in
                state.setCloseConnectionsOnSwitch(v)
                onRefresh()
            }
        )) {
            Text(t("mac.menu.closeOnSwitch"))
        }

        Toggle(isOn: Binding(
            get: { snap.launchAtLoginEnabled },
            set: { v in
                state.setLaunchAtLogin(v)
                onRefresh()
            }
        )) {
            Text(t("mac.menu.launchAtLogin"))
        }

        Toggle(isOn: Binding(
            get: { snap.showMenuBarTraffic },
            set: { v in
                state.setShowMenuBarTraffic(v)
                onRefresh()
            }
        )) {
            Text(t("mac.menu.showTraffic"))
        }

        Toggle(isOn: Binding(
            get: { snap.tunEnabled },
            set: { v in
                Task {
                    await state.setTUN(v)
                    onRefresh()
                }
            }
        )) {
            Text(t("mac.menu.tun"))
        }

        Toggle(isOn: Binding(
            get: { snap.videoAdBlockEnabled },
            set: { v in
                Task {
                    await state.setVideoAdBlock(v)
                    onRefresh()
                }
            }
        )) {
            Text(t("mac.menu.adblock"))
        }

        Divider()

        subscriptionSection

        Button(snap.isTesting ? t("mac.menu.speedTesting") : t("mac.menu.speedTest")) {
            Task { await state.runSpeedTest() }
        }
        .disabled(snap.isTesting || snap.menuNodes.isEmpty)

        Divider()

        settingsSection

        Divider()

        Button(t("mac.menu.copyEnv")) {
            state.copyExternalProxy(kind: .exportEnv)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])

        Divider()

        Button(t("mac.menu.quit")) {
            state.quitApp()
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var nodePickerSection: some View {
        if snap.menuNodes.isEmpty {
            Text(t("mac.menu.noNodes"))
                .foregroundStyle(.secondary)
        } else {
            Menu(
                t("mac.menu.nodes")
                    .replacingOccurrences(of: "%1", with: snap.selectedHint)
                    .replacingOccurrences(of: "%2", with: "\(snap.menuNodeLimit)")
            ) {
                ForEach(snap.menuNodes) { node in
                    Button {
                        Task { await state.selectNode(node.name) }
                    } label: {
                        menuCheckRow(
                            "\(snap.shortName(node.name, 18))  \(node.delayText(lang: snap.lang))",
                            on: node.name == snap.selectedNodeName
                        )
                    }
                }
                if snap.totalNodeCount > snap.menuNodes.count {
                    Divider()
                    Button(t("mac.menu.allNodes")) {
                        PanelPresenter.shared.open(state: state)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Menu(snap.subscriptionMenuTitle) {
            if snap.subscriptions.isEmpty {
                Text(t("mac.menu.subsNone"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snap.subscriptions) { sub in
                    Toggle(isOn: Binding(
                        get: { sub.enabled },
                        set: { v in Task { await state.setSubscriptionEnabled(sub.id, enabled: v) } }
                    )) {
                        Text(snap.shortName(sub.name, 16))
                    }
                }
                Divider()
            }

            Button(t("mac.menu.addSub")) {
                PanelPresenter.shared.open(state: state, intent: .addSubscription)
            }
            Button(t("mac.menu.pasteSub")) {
                addSubscriptionFromPasteboard()
            }
            Button(snap.isBusy ? t("mac.menu.updating") : t("mac.menu.updateAll")) {
                Task { await state.updateAllSubscriptions() }
            }
            .disabled(snap.isBusy || snap.subscriptions.isEmpty)

            if !snap.subscriptions.isEmpty {
                Button(t("mac.menu.manageSubs")) {
                    PanelPresenter.shared.open(state: state, intent: .subscriptions)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        Menu(t("mac.menu.settings")) {
            Toggle(isOn: Binding(
                get: { snap.autoSpeedTestEnabled },
                set: { v in
                    state.setAutoSpeedTestEnabled(v)
                    onRefresh()
                }
            )) {
                Text(t("mac.menu.autoSpeed"))
            }
            .disabled(snap.menuNodes.isEmpty)

            Toggle(isOn: Binding(
                get: { snap.autoSelectFastest },
                set: { v in
                    state.setAutoSelectFastest(v)
                    onRefresh()
                }
            )) {
                Text(t("mac.menu.autoFastest"))
            }
            .disabled(snap.menuNodes.isEmpty)

            Menu(t("mac.menu.logo").replacingOccurrences(of: "%@", with: snap.logoStyleTitle)) {
                ForEach(LogoStyle.allCases) { style in
                    Button {
                        state.setLogoStyle(style)
                        onRefresh()
                    } label: {
                        if style == snap.logoStyle {
                            Label("\(style.title) · \(style.subtitle)", systemImage: "checkmark")
                        } else {
                            Text("\(style.title) · \(style.subtitle)")
                        }
                    }
                }
            }

            Divider()

            Button(t("mac.menu.openConfig")) {
                state.openConfigFolder()
            }

            Button(t("mac.menu.moreSettings")) {
                SettingsOpener.open(state: state, fromMenuBar: true)
            }
            .keyboardShortcut(",")
        }
    }

    private func addSubscriptionFromPasteboard() {
        let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") else {
            state.statusText = t("mac.menu.pasteNoUrl")
            PanelPresenter.shared.open(state: state, intent: .addSubscription)
            return
        }
        Task { await state.addSubscriptionAndFetch(name: "", url: raw) }
    }

    private func menuCheckRow(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            if on {
                Image(systemName: "checkmark")
            }
        }
    }
}

private struct MenuBarSnapshot: Equatable {
    var lang: AppLanguage
    var status: String
    var coreRunning: Bool
    var isBusy: Bool
    var isTesting: Bool
    var proxyMode: ProxyMode
    var proxyModeTitle: String
    var systemProxyOn: Bool
    var tunEnabled: Bool
    var videoAdBlockEnabled: Bool
    var closeConnectionsOnSwitch: Bool
    var subscriptions: [Subscription]
    var menuNodes: [ProxyNode]
    var menuNodeLimit: Int
    var totalNodeCount: Int
    var selectedNodeName: String?
    var runtimeOutboundName: String?
    var launchAtLoginEnabled: Bool
    var showMenuBarTraffic: Bool
    var autoSpeedTestEnabled: Bool
    var autoSelectFastest: Bool
    var logoStyle: LogoStyle
    var logoStyleTitle: String
    var subscriptionMenuTitle: String
    var selectedHint: String

    static let empty = MenuBarSnapshot(
        lang: .system,
        status: "",
        coreRunning: false,
        isBusy: false,
        isTesting: false,
        proxyMode: .rule,
        proxyModeTitle: ProxyMode.rule.title,
        systemProxyOn: false,
        tunEnabled: false,
        videoAdBlockEnabled: false,
        closeConnectionsOnSwitch: true,
        subscriptions: [],
        menuNodes: [],
        menuNodeLimit: 10,
        totalNodeCount: 0,
        selectedNodeName: nil,
        runtimeOutboundName: nil,
        launchAtLoginEnabled: false,
        showMenuBarTraffic: false,
        autoSpeedTestEnabled: false,
        autoSelectFastest: false,
        logoStyle: .ring,
        logoStyleTitle: LogoStyle.ring.title,
        subscriptionMenuTitle: "Subscriptions",
        selectedHint: ""
    )

    @MainActor
    private static func menuCoreStatus(state: AppState, lang: AppLanguage) -> String {
        if state.coreRunning { return L10n.t("mac.menu.coreRunning", lang) }
        if state.coreConnecting
            || state.statusText.contains("准备")
            || state.statusText.contains("解压")
            || state.statusText.contains("地理")
            || state.statusText.contains("启动内核")
            || state.statusText.contains("重试") {
            return L10n.t("mac.menu.coreStarting", lang)
        }
        return L10n.t("mac.menu.coreStopped", lang)
    }

    @MainActor
    static func capture(from state: AppState) -> MenuBarSnapshot {
        let lang = state.settings.uiLanguage
        let subs = state.settings.subscriptions
        let enabledCount = subs.filter(\.enabled).count
        let subTitle: String = {
            if subs.isEmpty { return L10n.t("mac.menu.subs", lang) }
            if enabledCount == 0 { return L10n.t("mac.menu.subsDisabled", lang) }
            return L10n.t("mac.menu.subsEnabled", lang).replacingOccurrences(of: "%@", with: "\(enabledCount)")
        }()
        let hint: String = {
            if let runtime = state.runtimeOutboundName, !runtime.isEmpty {
                return " · \(shortName(runtime, 10))"
            }
            guard let name = state.settings.selectedNodeName else { return "" }
            return " · \(shortName(name, 10))"
        }()
        return MenuBarSnapshot(
            lang: lang,
            status: menuCoreStatus(state: state, lang: lang),
            coreRunning: state.coreRunning,
            isBusy: state.isBusy,
            isTesting: state.isTesting,
            proxyMode: state.settings.proxyMode,
            proxyModeTitle: state.settings.proxyMode.title(lang: lang),
            systemProxyOn: state.systemProxyOn,
            tunEnabled: state.settings.tunEnabled,
            videoAdBlockEnabled: state.settings.videoAdBlockEnabled,
            closeConnectionsOnSwitch: state.settings.closeConnectionsOnSwitch,
            subscriptions: subs,
            menuNodes: state.menuNodes,
            menuNodeLimit: min(500, max(5, state.settings.menuNodeLimit)),
            totalNodeCount: state.nodes.count,
            selectedNodeName: state.settings.selectedNodeName,
            runtimeOutboundName: state.runtimeOutboundName,
            launchAtLoginEnabled: state.launchAtLoginOn,
            showMenuBarTraffic: state.settings.showMenuBarTraffic,
            autoSpeedTestEnabled: state.settings.autoSpeedTestEnabled,
            autoSelectFastest: state.settings.autoSelectFastest,
            logoStyle: state.settings.logoStyle,
            logoStyleTitle: state.settings.logoStyle.title,
            subscriptionMenuTitle: subTitle,
            selectedHint: hint
        )
    }

    func shortName(_ name: String, _ max: Int) -> String {
        Self.shortName(name, max)
    }

    private static func shortName(_ name: String, _ max: Int) -> String {
        guard name.count > max else { return name }
        return String(name.prefix(max - 1)) + "…"
    }
}


// MARK: - Snapshot
