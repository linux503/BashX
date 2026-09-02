import AppKit
import SwiftUI

/// Native menu-bar dropdown (ClashX-style).
///
/// Critical: do **not** `@ObservedObject` AppState here. Any `@Published` churn
/// (statusText / health / chromeRevision) remounts NSMenu → endless flash.
/// Labels come from a frozen snapshot refreshed only when the menu is closed
/// or the user taps a control.
struct MenuBarView: View {
    let state: AppState
    @State private var snap = MenuBarSnapshot.empty
    @State private var menuIsOpen = false
    @State private var pendingSnapRefresh = false
    @State private var trackingID: UUID?

    var body: some View {
        MenuBarFrozenContent(snap: snap, state: state, onRefresh: { refreshSnap(reason: .userAction) })
            .equatable()
            .transaction { $0.animation = nil }
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
    }

    private enum RefreshReason {
        case appear, chrome, userAction, present
    }

    private func handleMenuPresent() {
        // Do not touch `snap` here — remounting NSMenu mid-open is the flash.
        menuIsOpen = true
    }

    private func handleMenuDismiss() {
        menuIsOpen = false
        pendingSnapRefresh = false
        refreshSnap(reason: .chrome)
    }

    private func refreshSnap(reason: RefreshReason) {
        // While open: never rebuild the menu. Queue a refresh for after dismiss.
        // Patch toggle rows for the control the user just tapped (checkmark sync).
        if menuIsOpen {
            if reason == .userAction {
                applyLiveToggleFields()
            } else {
                pendingSnapRefresh = true
            }
            return
        }

        if reason == .appear || reason == .chrome {
            let on = LaunchAtLogin.isEnabled
            if state.launchAtLoginOn != on {
                state.refreshLaunchAtLogin()
            }
        }

        let next = MenuBarSnapshot.capture(from: state)
        if next != snap {
            snap = next
        }
    }

    /// Patch toggle rows only — never replace menuNodes / subscriptions while open.
    private func applyLiveToggleFields() {
        var next = snap
        next.launchAtLoginEnabled = state.launchAtLoginOn
        next.systemProxyOn = state.systemProxyOn
        next.closeConnectionsOnSwitch = state.settings.closeConnectionsOnSwitch
        next.showMenuBarTraffic = state.settings.showMenuBarTraffic
        next.tunEnabled = state.settings.tunEnabled
        next.videoAdBlockEnabled = state.settings.videoAdBlockEnabled
        next.autoSelectFastest = state.settings.autoSelectFastest
        next.proxyMode = state.settings.proxyMode
        next.proxyModeTitle = state.settings.proxyMode.title(lang: next.lang)
        next.hubMode = state.settings.proxyHubMode
        next.selectedNodeName = state.settings.selectedNodeName
        next.runtimeOutboundName = state.runtimeOutboundName
        next.selectedHint = MenuBarSnapshot.lineHint(
            hubMode: next.hubMode,
            selected: next.selectedNodeName,
            runtime: next.runtimeOutboundName,
            lang: next.lang
        )
        next.isBusy = state.isBusy
        next.status = MenuBarSnapshot.menuCoreStatusPublic(state: state, lang: next.lang)
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
            Picker("", selection: Binding(
                get: { snap.proxyMode },
                set: { mode in
                    Task {
                        await state.setProxyMode(mode)
                        onRefresh()
                    }
                }
            )) {
                Text(t("mac.menu.modeRule")).tag(ProxyMode.rule)
                Text(t("mac.menu.modeGlobal")).tag(ProxyMode.global)
                Text(t("mac.menu.modeDirect")).tag(ProxyMode.direct)
            }
            .labelsHidden()
            .pickerStyle(.inline)
        }

        nodePickerSection

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
            Menu(t("mac.menu.line").replacingOccurrences(of: "%@", with: snap.selectedHint)) {
                if let runtime = snap.runtimeOutboundName, !runtime.isEmpty, snap.hubMode != .manual {
                    Text(t("mac.menu.currentExit").replacingOccurrences(of: "%@", with: snap.shortName(runtime, 22)))
                        .foregroundStyle(.secondary)
                    Divider()
                }

                Text(t("mac.menu.lineAuto"))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { snap.hubMode == .manual ? "" : snap.hubMode.rawValue },
                    set: { raw in
                        guard let mode = ProxyHubMode(rawValue: raw), mode != .manual else { return }
                        Task {
                            await state.setProxyHubMode(mode)
                            onRefresh()
                        }
                    }
                )) {
                    ForEach([ProxyHubMode.smart, .loadBalance, .failover], id: \.self) { mode in
                        Text("\(mode.title(lang: snap.lang))  \(mode.subtitle(lang: snap.lang))")
                            .tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)

                Divider()

                Text(t("mac.menu.lineManual"))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { snap.hubMode == .manual ? (snap.selectedNodeName ?? "") : "" },
                    set: { name in
                        guard !name.isEmpty else { return }
                        Task {
                            await state.selectNode(name)
                            onRefresh()
                        }
                    }
                )) {
                    ForEach(snap.menuNodes) { node in
                        Text("\(snap.shortName(node.name, 22))  \(node.delayText(lang: snap.lang))")
                            .tag(node.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)

                if snap.totalNodeCount > snap.menuNodes.count {
                    Divider()
                    Button(t("mac.menu.allNodes")) {
                        PanelPresenter.shared.open(state: state, intent: .groups)
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
}

// MARK: - Snapshot

private struct MenuBarSnapshot: Equatable {
    var lang: AppLanguage
    var status: String
    var coreRunning: Bool
    var isBusy: Bool
    var proxyMode: ProxyMode
    var proxyModeTitle: String
    var hubMode: ProxyHubMode
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
        proxyMode: .rule,
        proxyModeTitle: ProxyMode.rule.title,
        hubMode: .smart,
        systemProxyOn: false,
        tunEnabled: true,
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
        autoSelectFastest: false,
        logoStyle: .ring,
        logoStyleTitle: LogoStyle.ring.title,
        subscriptionMenuTitle: "Subscriptions",
        selectedHint: ""
    )

    @MainActor
    static func menuCoreStatusPublic(state: AppState, lang: AppLanguage) -> String {
        menuCoreStatus(state: state, lang: lang)
    }

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
            return L10n.t("mac.menu.subsEnabled", lang)
                .replacingOccurrences(of: "%@", with: "\(enabledCount)")
        }()
        let limit = min(500, max(5, state.settings.menuNodeLimit))
        let menuNodes = Array(state.menuNodes.prefix(limit))
        let hub = state.settings.proxyHubMode
        let selected = state.settings.selectedNodeName
        let runtime = state.runtimeOutboundName
        return MenuBarSnapshot(
            lang: lang,
            status: menuCoreStatus(state: state, lang: lang),
            coreRunning: state.coreRunning,
            isBusy: state.isBusy,
            proxyMode: state.settings.proxyMode,
            proxyModeTitle: state.settings.proxyMode.title(lang: lang),
            hubMode: hub,
            systemProxyOn: state.systemProxyOn,
            tunEnabled: state.settings.tunEnabled,
            videoAdBlockEnabled: state.settings.videoAdBlockEnabled,
            closeConnectionsOnSwitch: state.settings.closeConnectionsOnSwitch,
            subscriptions: subs,
            menuNodes: menuNodes,
            menuNodeLimit: limit,
            totalNodeCount: state.nodes.count,
            selectedNodeName: selected,
            runtimeOutboundName: runtime,
            launchAtLoginEnabled: state.launchAtLoginOn,
            showMenuBarTraffic: state.settings.showMenuBarTraffic,
            autoSelectFastest: state.settings.autoSelectFastest,
            logoStyle: state.settings.logoStyle,
            logoStyleTitle: state.settings.logoStyle.title,
            subscriptionMenuTitle: subTitle,
            selectedHint: lineHint(hubMode: hub, selected: selected, runtime: runtime, lang: lang)
        )
    }

    static func lineHint(
        hubMode: ProxyHubMode,
        selected: String?,
        runtime: String?,
        lang: AppLanguage
    ) -> String {
        if let runtime, !runtime.isEmpty {
            return " · \(shortNameStatic(runtime, 10))"
        }
        if hubMode != .manual {
            return " · \(hubMode.title(lang: lang))"
        }
        guard let selected, !selected.isEmpty else { return "" }
        return " · \(shortNameStatic(selected, 10))"
    }

    func shortName(_ name: String, _ max: Int) -> String {
        Self.shortNameStatic(name, max)
    }

    static func shortNameStatic(_ name: String, _ max: Int) -> String {
        guard name.count > max else { return name }
        let idx = name.index(name.startIndex, offsetBy: max - 1)
        return String(name[..<idx]) + "…"
    }
}
