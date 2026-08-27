import AppKit
import SwiftUI

/// Native menu-bar dropdown (ClashX-style).
/// Labels use a frozen snapshot; `.equatable()` blocks live @Published rebuilds that dismiss submenus.
struct MenuBarView: View {
    let state: AppState
    @State private var snap = MenuBarSnapshot.empty

    var body: some View {
        MenuBarFrozenContent(snap: $snap, state: state)
            .equatable()
            .background(MenuBarRefreshHook { refreshSnap() })
            .onAppear { refreshSnap() }
    }

    private func refreshSnap() {
        snap = MenuBarSnapshot.capture(from: state)
    }
}

// MARK: - Frozen content (no @ObservedObject — avoids NSMenu submenu flash)

private struct MenuBarFrozenContent: View, Equatable {
    @Binding var snap: MenuBarSnapshot
    let state: AppState

    static func == (lhs: MenuBarFrozenContent, rhs: MenuBarFrozenContent) -> Bool {
        lhs.snap == rhs.snap
    }

    var body: some View {
        Text(snap.status)
            .foregroundStyle(.secondary)

        Text(AppVersion.title)
            .foregroundStyle(.tertiary)

        Divider()

        Button("打开面板") {
            PanelPresenter.shared.open(state: state)
        }
        .keyboardShortcut("o")

        Divider()

        Menu("代理模式：\(snap.proxyModeTitle)") {
            ForEach(ProxyMode.allCases) { mode in
                Button {
                    Task {
                        await state.setProxyMode(mode)
                        snap = MenuBarSnapshot.capture(from: state)
                    }
                } label: {
                    menuCheckRow(mode.title, on: snap.proxyMode == mode)
                }
            }
        }

        nodePickerSection

        Divider()

        Toggle(isOn: Binding(
            get: { snap.systemProxyOn },
            set: { v in Task { await state.setSystemProxy(v) } }
        )) {
            Text("系统代理")
        }

        Toggle(isOn: Binding(
            get: { snap.launchAtLoginEnabled },
            set: { state.setLaunchAtLogin($0) }
        )) {
            Text("开机自动启动")
        }

        Toggle(isOn: Binding(
            get: { snap.showMenuBarTraffic },
            set: { v in
                state.setShowMenuBarTraffic(v)
                snap = MenuBarSnapshot.capture(from: state)
            }
        )) {
            Text("显示网速")
        }

        Toggle(isOn: Binding(
            get: { snap.tunEnabled },
            set: { v in Task { await state.setTUN(v) } }
        )) {
            Text("TUN 模式")
        }

        Toggle(isOn: Binding(
            get: { snap.videoAdBlockEnabled },
            set: { v in Task { await state.setVideoAdBlock(v) } }
        )) {
            Text("视频广告过滤")
        }

        Divider()

        subscriptionSection

        Button(snap.isTesting ? "测速中…" : "一键测速") {
            Task { await state.runSpeedTest() }
        }
        .disabled(snap.isTesting || snap.menuNodes.isEmpty)

        Divider()

        settingsSection

        Divider()

        Button("退出 BashX") {
            state.quitApp()
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var nodePickerSection: some View {
        if snap.menuNodes.isEmpty {
            Text("暂无节点")
                .foregroundStyle(.secondary)
        } else {
            Menu("节点\(snap.selectedHint) · 最快10") {
                ForEach(snap.menuNodes) { node in
                    Button {
                        Task { await state.selectNode(node.name) }
                    } label: {
                        menuCheckRow(
                            "\(snap.shortName(node.name, 18))  \(node.delayText)",
                            on: node.name == snap.selectedNodeName
                        )
                    }
                }
                if snap.totalNodeCount > snap.menuNodes.count {
                    Divider()
                    Button("全部节点…") {
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
                Text("暂无订阅")
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

            Button("添加订阅…") {
                PanelPresenter.shared.open(state: state, intent: .addSubscription)
            }
            Button("从剪贴板添加") {
                addSubscriptionFromPasteboard()
            }
            Button(snap.isBusy ? "更新中…" : "更新全部") {
                Task { await state.updateAllSubscriptions() }
            }
            .disabled(snap.isBusy || snap.subscriptions.isEmpty)

            if !snap.subscriptions.isEmpty {
                Button("管理订阅…") {
                    PanelPresenter.shared.open(state: state, intent: .subscriptions)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        Menu("设置") {
            Toggle(isOn: Binding(
                get: { snap.autoSpeedTestEnabled },
                set: { state.setAutoSpeedTestEnabled($0) }
            )) {
                Text("自动测速")
            }
            .disabled(snap.menuNodes.isEmpty)

            Toggle(isOn: Binding(
                get: { snap.autoSelectFastest },
                set: { state.setAutoSelectFastest($0) }
            )) {
                Text("跟最快节点")
            }
            .disabled(snap.menuNodes.isEmpty)

            Menu("Logo：\(snap.logoStyleTitle)") {
                ForEach(LogoStyle.allCases) { style in
                    Button {
                        state.setLogoStyle(style)
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

            Button("打开配置目录") {
                state.openConfigFolder()
            }

            Button("更多设置…") {
                SettingsOpener.open(state: state, fromMenuBar: true)
            }
            .keyboardShortcut(",")
        }
    }

    private func addSubscriptionFromPasteboard() {
        let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") else {
            state.statusText = "剪贴板没有订阅链接，已打开面板添加"
            PanelPresenter.shared.open(state: state, intent: .addSubscription)
            return
        }
        Task { await state.addSubscriptionAndFetch(name: "", url: raw) }
    }

    @ViewBuilder
    private func menuCheckRow(_ title: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: on ? "checkmark" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.accentColor : .clear)
                .frame(width: 14, alignment: .center)
            Text(title)
        }
    }
}

// MARK: - Snapshot

private struct MenuBarSnapshot: Equatable {
    var status: String
    var coreRunning: Bool
    var isBusy: Bool
    var isTesting: Bool
    var proxyMode: ProxyMode
    var proxyModeTitle: String
    var systemProxyOn: Bool
    var tunEnabled: Bool
    var videoAdBlockEnabled: Bool
    var subscriptions: [Subscription]
    var menuNodes: [ProxyNode]
    var totalNodeCount: Int
    var selectedNodeName: String?
    var launchAtLoginEnabled: Bool
    var showMenuBarTraffic: Bool
    var autoSpeedTestEnabled: Bool
    var autoSelectFastest: Bool
    var logoStyle: LogoStyle
    var logoStyleTitle: String
    var subscriptionMenuTitle: String
    var selectedHint: String

    static let empty = MenuBarSnapshot(
        status: "",
        coreRunning: false,
        isBusy: false,
        isTesting: false,
        proxyMode: .rule,
        proxyModeTitle: ProxyMode.rule.title,
        systemProxyOn: false,
        tunEnabled: false,
        videoAdBlockEnabled: false,
        subscriptions: [],
        menuNodes: [],
        totalNodeCount: 0,
        selectedNodeName: nil,
        launchAtLoginEnabled: false,
        showMenuBarTraffic: false,
        autoSpeedTestEnabled: false,
        autoSelectFastest: false,
        logoStyle: .ring,
        logoStyleTitle: LogoStyle.ring.title,
        subscriptionMenuTitle: "订阅",
        selectedHint: ""
    )

    @MainActor
    static func capture(from state: AppState) -> MenuBarSnapshot {
        let subs = state.settings.subscriptions
        let enabledCount = subs.filter(\.enabled).count
        let subTitle: String = {
            if subs.isEmpty { return "订阅" }
            if enabledCount == 0 { return "订阅 · 未启用" }
            return "订阅 · \(enabledCount) 个启用"
        }()
        let hint: String = {
            guard let name = state.settings.selectedNodeName else { return "" }
            return " · \(shortName(name, 10))"
        }()
        return MenuBarSnapshot(
            status: state.coreRunning ? "内核运行中" : "内核未启动",
            coreRunning: state.coreRunning,
            isBusy: state.isBusy,
            isTesting: state.isTesting,
            proxyMode: state.settings.proxyMode,
            proxyModeTitle: state.settings.proxyMode.title,
            systemProxyOn: state.systemProxyOn,
            tunEnabled: state.settings.tunEnabled,
            videoAdBlockEnabled: state.settings.videoAdBlockEnabled,
            subscriptions: subs,
            menuNodes: state.menuNodes,
            totalNodeCount: state.nodes.count,
            selectedNodeName: state.settings.selectedNodeName,
            launchAtLoginEnabled: state.settings.launchAtLoginEnabled,
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

// MARK: - Menu open refresh (onAppear only fires once in MenuBarExtra)

private struct MenuBarRefreshHook: NSViewRepresentable {
    var onPresent: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RefreshHookView()
        view.onPresent = onPresent
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RefreshHookView)?.onPresent = onPresent
    }

    private final class RefreshHookView: NSView {
        var onPresent: (() -> Void)?
        private var didPresent = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Refresh snapshot once when the menu appears — not on every layout pass.
            if window != nil {
                if !didPresent {
                    didPresent = true
                    onPresent?()
                }
            } else {
                didPresent = false
            }
        }
    }
}
