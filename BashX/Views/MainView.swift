import Combine
import SwiftUI

struct MainView: View {
    let state: AppState
    let monitor: TrafficMonitor
    let rates: MenuBarRateStore
    @Environment(\.bashxAppearance) private var appearance
    @State private var showLogoPicker = false
    @State private var detailTab: DetailTab = .nodes
    @State private var monitorSegment: MonitorPane.MonitorSegment = .connections
    @State private var renameTarget: Subscription?
    @State private var renameDraft = ""
    @State private var switchingNodeName: String?
    @State private var sidebarSubsExpanded = false

    private enum DetailTab: String, CaseIterable, Identifiable {
        case nodes = "节点"
        case subscriptions = "订阅"
        case monitor = "监控"
        case rules = "规则"
        var id: String { rawValue }
    }

    var body: some View {
        BashXThemed(appearance: state.settings.appearance) {
            ZStack {
                PanelAtmosphere()
                VStack(spacing: 0) {
                    PanelTopBarHost(state: state) {
                        topBar
                    }
                    GlassDivider()
                    HStack(spacing: 0) {
                        PanelSidebarHost(state: state) {
                            sidebar
                        }
                        .frame(width: 268)
                        Rectangle()
                            .fill(BashXTheme.hairline(for: appearance))
                            .frame(width: 1)
                        detail
                    }
                }
            }
            .background(.clear)
        }
        .onAppear {
            consumePanelIntent()
        }
        .onValueChange(state.panelIntent) { _ in
            consumePanelIntent()
        }
        .alert("重命名订阅", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("名称", text: $renameDraft)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let id = renameTarget?.id {
                    state.renameSubscription(id, name: renameDraft)
                }
                renameTarget = nil
            }
        } message: {
            Text("修改显示名称，不影响订阅链接。")
        }
        .task {
            _ = await state.ensureCoreRunning()
        }
        .onAppear { syncMonitorExtras() }
        .onDisappear {
            monitor.chartSamplesEnabled = false
            monitor.stopConnectionsAndLogs()
        }
        .onReceive(state.$coreRunning.receive(on: RunLoop.main)) { _ in syncMonitorExtras() }
        .onReceive(state.$searchText.dropFirst().receive(on: RunLoop.main)) { _ in state.bumpNodeListRevision() }
        .onReceive(state.$sortByDelay.dropFirst().receive(on: RunLoop.main)) { _ in state.bumpNodeListRevision() }
        .onReceive(state.$selectedCategoryKey.dropFirst().receive(on: RunLoop.main)) { _ in state.bumpNodeListRevision() }
        .onValueChange(detailTab) { tab in
            monitor.chartSamplesEnabled = (tab == .monitor)
            if tab == .rules {
                state.ensureRulesTextLoaded()
            }
            if tab == .monitor, state.coreRunning {
                monitor.startConnectionsAndLogs()
            } else {
                monitor.stopConnectionsAndLogs()
            }
        }
    }

    /// Panel only toggles connections/logs; traffic SSE is owned by BashXApp.
    private func syncMonitorExtras() {
        monitor.configure(
            controller: state.settings.externalController,
            secret: state.settings.secret
        )
        monitor.chartSamplesEnabled = (detailTab == .monitor)
        if state.coreRunning, detailTab == .monitor {
            monitor.startConnectionsAndLogs()
        } else {
            monitor.stopConnectionsAndLogs()
        }
    }

    /// Ventura-safe: open add-subscription in a dedicated window (`.sheet` is unreliable for LSUIElement).
    private func openAddSubscription() {
        detailTab = .subscriptions
        AddSubscriptionOpener.open(state: state)
    }

    private func consumePanelIntent() {
        switch state.panelIntent {
        case .none:
            break
        case .subscriptions:
            detailTab = .subscriptions
            state.panelIntent = .none
        case .addSubscription:
            detailTab = .subscriptions
            state.panelIntent = .none
            AddSubscriptionOpener.open(state: state)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    showLogoPicker.toggle()
                } label: {
                    LogoIconView(style: state.settings.logoStyle, size: 30, colored: true, panel: true)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(BashXTheme.accent(for: appearance).opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: BashXTheme.accentGlow(for: appearance), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .accessibilityLabel("切换 Logo 风格")
                .popover(isPresented: $showLogoPicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Logo 风格")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                        LogoStylePicker(
                            selection: Binding(
                                get: { state.settings.logoStyle },
                                set: {
                                    state.setLogoStyle($0)
                                    showLogoPicker = false
                                }
                            ),
                            appearance: appearance
                        )
                    }
                    .padding(10)
                    .frame(width: 248)
                    .background(BashXTheme.card(for: appearance))
                }
                .help("切换 Logo 风格")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("BashX")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("v\(AppVersion.short)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .help("Build \(AppVersion.build)")
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(state.isCoreVisiblyAlive ? BashXTheme.good(for: appearance) : Color.secondary.opacity(0.4))
                            .frame(width: 5, height: 5)
        Text(state.isCoreVisiblyAlive
                            ? "代理已连接"
                            : (state.coreConnecting
                               ? "内核连接中…"
                               : (state.coreRunning ? "内核已就绪" : "内核未启动")))
                            .font(.caption)
                            .foregroundStyle(state.isCoreVisiblyAlive ? BashXTheme.good(for: appearance) : .secondary)
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    StatusPill(title: state.isCoreVisiblyAlive ? "内核" : "内核关", active: state.isCoreVisiblyAlive)
                    StatusPill(title: state.systemProxyOn ? "系统代理" : "代理关", active: state.systemProxyOn)
                    StatusPill(
                        title: state.settings.proxyMode.title,
                        active: state.settings.proxyMode != .direct,
                        activeColor: state.settings.proxyMode == .global ? BashXTheme.warn : BashXTheme.accent(for: appearance)
                    )
                    if state.settings.tunEnabled {
                        StatusPill(title: "TUN", active: true)
                    }
                }
            }
            .frame(maxWidth: 280)

            if state.isCoreVisiblyAlive || state.coreRunning {
                PanelTopBarRates(rates: rates) {
                    detailTab = .monitor
                }
            }

            PanelStatusLine(state: state)

            Button {
                SettingsOpener.open(state: state)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(BashXTheme.secondaryFill(for: appearance))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                            )
                    }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("设置 (⌘,)")
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [BashXTheme.accent(for: appearance).opacity(0.12), BashXTheme.hairline(for: appearance)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                }
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            proxyModeSection

            selectedNodeCard

            sidebarSubscriptionsSection

            SidebarSectionHeader(title: "快捷操作")
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ActionChip(
                        title: state.isBusy ? "更新中" : "更新订阅",
                        systemImage: "arrow.clockwise",
                        enabled: !state.isBusy && !state.settings.subscriptions.isEmpty,
                        emphasized: state.isBusy
                    ) {
                        Task { await state.updateAllSubscriptions() }
                    }
                    ActionChip(
                        title: state.isTesting ? "测速中" : "测速",
                        systemImage: "gauge.with.dots.needle.67percent",
                        enabled: !state.isTesting && !state.nodes.isEmpty,
                        emphasized: state.isTesting
                    ) {
                        Task { await state.runSpeedTest() }
                    }
                }
                HStack(spacing: 6) {
                    ActionChip(
                        title: state.settings.autoSpeedTestEnabled ? "自动测速" : "自动测速",
                        systemImage: "timer",
                        enabled: !state.nodes.isEmpty,
                        emphasized: state.settings.autoSpeedTestEnabled
                    ) {
                        state.setAutoSpeedTestEnabled(!state.settings.autoSpeedTestEnabled)
                    }
                    ActionChip(
                        title: state.settings.autoSelectFastest ? "跟最快" : "跟最快",
                        systemImage: "bolt",
                        enabled: !state.nodes.isEmpty,
                        emphasized: state.settings.autoSelectFastest
                    ) {
                        state.setAutoSelectFastest(!state.settings.autoSelectFastest)
                    }
                }
                HStack(spacing: 6) {
                    if !(state.isCoreVisiblyAlive || state.coreRunning) {
                        if state.coreConnecting {
                            ActionChip(
                                title: "内核连接中…",
                                systemImage: "arrow.triangle.2.circlepath",
                                enabled: false,
                                emphasized: false
                            ) {}
                        } else {
                            ActionChip(
                                title: "启动内核",
                                systemImage: "play.fill",
                                emphasized: true
                            ) {
                                Task { await state.ensureCoreRunning() }
                            }
                        }
                    }
                }
            }

            SidebarSectionHeader(title: "开关")
            VStack(spacing: 2) {
                toggleRow(
                    icon: "network",
                    title: "系统代理",
                    subtitle: "127.0.0.1:\(state.settings.mixedPort)",
                    isOn: Binding(
                        get: { state.systemProxyOn },
                        set: { v in Task { await state.setSystemProxy(v) } }
                    )
                )
                toggleRow(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "TUN",
                    subtitle: "可与系统代理同时开",
                    isOn: Binding(
                        get: { state.settings.tunEnabled },
                        set: { v in Task { await state.setTUN(v) } }
                    )
                )
                toggleRow(
                    icon: "play.slash",
                    title: "视频广告过滤",
                    subtitle: "规则模式生效",
                    isOn: Binding(
                        get: { state.settings.videoAdBlockEnabled },
                        set: { v in Task { await state.setVideoAdBlock(v) } }
                    )
                )
            }

            Spacer(minLength: 4)

            HStack {
                Button("配置目录") { state.openConfigFolder() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Spacer()
                Text("v\(AppVersion.display)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .help("BashX \(AppVersion.display)")
            }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(width: 268)
        .background(BashXTheme.sidebarTint(for: appearance))
    }

    private var proxyModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarSectionHeader(title: "代理模式")
            HStack(spacing: 5) {
                ForEach(ProxyMode.allCases) { mode in
                    proxyModeButton(mode)
                }
            }
            if state.settings.videoAdBlockEnabled, state.settings.proxyMode == .rule {
                Text("开启视频过滤时仅规则模式生效；切全局/直连会自动关闭过滤")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }

    private func proxyModeButton(_ mode: ProxyMode) -> some View {
        let selected = state.settings.proxyMode == mode
        let color = BashXTheme.proxyModeColor(mode, appearance: appearance)
        return Button {
            Task { await state.setProxyMode(mode) }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(selected ? color.opacity(0.2) : Color.primary.opacity(0.06))
                        .frame(width: 28, height: 28)
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? color : .secondary)
                }
                Text(mode.title)
                    .font(.system(size: 10, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(selected ? color : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? color.opacity(0.1) : Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected ? color.opacity(0.5) : BashXTheme.separator(for: appearance),
                                lineWidth: selected ? 1.5 : 0.5
                            )
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(mode.subtitle)
    }

    private func selectNodeFromPanel(_ name: String) {
        guard switchingNodeName != name else { return }
        switchingNodeName = name
        Task {
            await state.selectNode(name)
            if switchingNodeName == name { switchingNodeName = nil }
        }
    }

    private var selectedNodeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("当前节点", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Spacer()
                if let name = state.settings.selectedNodeName,
                   let node = state.nodes.first(where: { $0.name == name }),
                   let ms = node.delayMs {
                    Text(ms < 0 ? "超时" : "\(ms) ms")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(BashXTheme.delayColor(ms, appearance: appearance))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BashXTheme.delayColor(ms, appearance: appearance).opacity(0.12))
                        )
                }
            }
            Text(state.settings.selectedNodeName ?? "未选择（AUTO）")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            PanelOutboundIP(state: state)

            HStack(spacing: 10) {
                MetricTile(label: "节点", value: "\(state.nodes.count)")
                Button { detailTab = .subscriptions } label: {
                    MetricTile(label: "订阅", value: "\(state.settings.subscriptions.count)")
                }
                .buttonStyle(.plain)
                MetricTile(label: "端口", value: "\(state.settings.mixedPort)")
                    .onTapGesture { SettingsOpener.open(state: state) }
                    .help("打开设置 · 外置代理")
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            state.coreRunning
                                ? LinearGradient(
                                    colors: [
                                        BashXTheme.accent(for: appearance).opacity(0.5),
                                        BashXTheme.accentGlow(for: appearance).opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [BashXTheme.separator(for: appearance)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: state.coreRunning ? 1 : 0.5
                        )
                )
                .shadow(color: state.coreRunning ? BashXTheme.accent(for: appearance).opacity(0.08) : .clear, radius: 6, y: 2)
        }
        .task(id: state.settings.selectedNodeName) {
            guard state.coreRunning else { return }
            await state.refreshOutboundIP()
            while !Task.isCancelled, state.coreRunning {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await state.refreshOutboundIP()
            }
        }
        .onValueChange(state.coreRunning) { running in
            if running {
                state.scheduleOutboundIPRefresh()
            } else {
                state.outboundIP = "—"
            }
        }
    }

    private var sidebarSubscriptionsSection: some View {
        let subs = state.settings.subscriptions
        let enabledCount = subs.filter(\.enabled).count
        let totalCount = subs.count
        let visibleSubs = sidebarVisibleSubscriptions(subs)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("订阅", systemImage: "tray.full.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(enabledCount)/\(totalCount)")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(BashXTheme.accentSoft(for: appearance)))
                Spacer()
                Button("管理") { detailTab = .subscriptions }
                    .font(.caption2.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(BashXTheme.accent(for: appearance))
            }

            Button {
                openAddSubscription()
            } label: {
                Label("添加订阅", systemImage: "plus.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(BashXTheme.accent(for: appearance))
            .contentShape(Rectangle())

            if subs.isEmpty {
                Text("还没有订阅，添加后点击「更新订阅」拉取节点")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 4) {
                    ForEach(visibleSubs) { sub in
                        sidebarSubscriptionRow(subscriptionId: sub.id)
                    }
                }

                if totalCount > 1 {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            sidebarSubsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sidebarSubsExpanded ? "收起" : "还有 \(totalCount - 1) 个订阅")
                                .font(.caption2.weight(.medium))
                            Image(systemName: sidebarSubsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }

                if enabledCount > 0 {
                    Text("已选 \(enabledCount) 个 · 合并 \(state.nodes.count) 节点")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("点圆钮启用订阅（可多选）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [BashXTheme.accent(for: appearance).opacity(0.35), BashXTheme.accent(for: appearance).opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: BashXTheme.accent(for: appearance).opacity(0.06), radius: 4, y: 1)
        }
    }

    private func sidebarVisibleSubscriptions(_ subs: [Subscription]) -> [Subscription] {
        guard !sidebarSubsExpanded, subs.count > 1 else { return subs }
        if let primary = subs.first(where: \.enabled) {
            return [primary]
        }
        return Array(subs.prefix(1))
    }

    private func sidebarSubscriptionRow(subscriptionId: UUID) -> some View {
        let sub = state.settings.subscriptions.first(where: { $0.id == subscriptionId })
            ?? Subscription(name: "—", url: "")
        let solo = sub.enabled && state.settings.subscriptions.filter(\.enabled).count == 1
        return HStack(spacing: 6) {
            Button {
                Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
            } label: {
                SubscriptionEnableControl(
                    enabled: sub.enabled,
                    monogram: sidebarSubMonogram(sub.name),
                    size: 20,
                    emphasized: solo
                )
            }
            .buttonStyle(PanelPressButtonStyle())
            .help(sub.enabled ? "停用此订阅" : "启用并合并节点（可多选）")

            Button {
                detailTab = .subscriptions
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(sub.name)
                            .font(.system(size: 11, weight: solo ? .semibold : .medium, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(sub.enabled ? .primary : .secondary)
                        if sub.enabled {
                            Text(solo ? "当前" : "已启用")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(BashXTheme.accent(for: appearance))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule(style: .continuous).fill(BashXTheme.accentSoft(for: appearance)))
                        }
                    }
                    Text(sidebarSubDetail(sub))
                        .font(.caption2)
                        .foregroundStyle(sidebarDetailColor(sub))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(sub.enabled ? BashXTheme.accentSoft(for: appearance).opacity(solo ? 0.85 : 0.45) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            solo ? BashXTheme.accent(for: appearance).opacity(0.35) : BashXTheme.separator(for: appearance),
                            lineWidth: solo ? 1 : 0.5
                        )
                )
        }
        .contextMenu {
            if let sub = state.settings.subscriptions.first(where: { $0.id == subscriptionId }) {
                Button("重命名") {
                    renameDraft = sub.name
                    renameTarget = sub
                }
                Button("更新此订阅") {
                    Task { await state.updateSubscription(subscriptionId) }
                }
                .disabled(state.isBusy)
                Button(sub.enabled ? "停用" : "启用") {
                    Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
                }
                Button("仅用此订阅") {
                    Task { await state.switchToSubscription(subscriptionId) }
                }
                Button("删除", role: .destructive) {
                    state.removeSubscription(subscriptionId)
                }
            }
        }
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption)
                Text(subtitle).font(.caption2).foregroundStyle(BashXTheme.secondaryLabel(for: appearance)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .frame(minHeight: 32)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        // Whole row is tappable; disable implicit animation so chrome refresh doesn't fight the switch.
        .transaction { $0.animation = nil }
    }

    private func sidebarSubMonogram(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        return String(first).uppercased()
    }

    private func sidebarSubDetail(_ sub: Subscription) -> String {
        if !sub.enabled { return "已停用 · 点左侧启用" }
        if let info = sub.userInfo {
            return "剩 \(info.remainingText)/\(info.totalText) · \(info.expireRelativeText)"
        }
        return sub.updatedAt.map { "更新于 \($0.formatted(.relative(presentation: .named)))" } ?? "未更新"
    }

    private func sidebarDetailColor(_ sub: Subscription) -> Color {
        guard sub.enabled, let info = sub.userInfo else { return .secondary }
        if info.isExpired { return BashXTheme.bad }
        if let ratio = info.usedRatio, ratio >= 0.9 { return BashXTheme.bad }
        if let ratio = info.usedRatio, ratio >= 0.7 { return BashXTheme.warn }
        return .secondary
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            detailHeader
            GlassDivider()

            Group {
                switch detailTab {
                case .nodes:
                    nodesPane
                case .subscriptions:
                    subscriptionsPane
                case .monitor:
                    MonitorPane(
                        monitor: monitor,
                        segment: $monitorSegment,
                        coreRunning: state.coreRunning,
                        onCloseAll: {
                            Task { await monitor.closeAllConnections() }
                        }
                    )
                case .rules:
                    RulesEditorPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("", selection: $detailTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }

            if detailTab == .nodes {
                PanelNodesHost(state: state) {
                    HStack(spacing: 8) {
                        SoftField {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                                    .font(.system(size: 11, weight: .semibold))
                                TextField("搜索节点 / 类型 / 地区", text: searchTextBinding)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .rounded))
                            }
                        }
                        .frame(minWidth: 140, maxWidth: 220)

                        Picker("", selection: Binding(
                            get: { state.settings.nodeDisplayMode },
                            set: { state.setNodeDisplayMode($0) }
                        )) {
                            ForEach(NodeDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                        .help("卡片 / 列表展示")

                        Picker("", selection: sortByDelayBinding) {
                            Text("延迟").tag(true)
                            Text("名称").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                        .help("组内排序方式")

                        Text("\(state.filteredNodes.count)/\(state.nodes.count)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var nodesPane: some View {
        PanelNodesHost(state: state) {
            nodesPaneContent
        }
    }

    private var nodesPaneContent: some View {
        VStack(spacing: 0) {
            categoryBar
            Rectangle()
                .fill(BashXTheme.hairline(for: appearance))
                .frame(height: 1)

            if state.filteredNodes.isEmpty {
                nodesEmptyState
            } else {
                NodesCategoriesView(
                    state: state,
                    appearance: appearance,
                    displayMode: state.settings.nodeDisplayMode,
                    selectedNodeName: state.settings.selectedNodeName,
                    switchingNodeName: switchingNodeName,
                    onSelect: selectNodeFromPanel
                )
            }
        }
    }

    private var nodesEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BashXTheme.accentSoft(for: appearance))
                    .frame(width: 64, height: 64)
                Image(systemName: state.nodes.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "magnifyingglass")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
            }
            Text(state.nodes.isEmpty ? "还没有节点" : "无匹配节点")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(state.nodes.isEmpty ? "在左侧添加订阅并点击「更新订阅」" : "换个关键词或分类试试")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("地区分类", systemImage: "globe.asia.australia.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Spacer()
                if let key = state.selectedCategoryKey,
                   let item = state.categorySummary.first(where: { $0.key == key }) {
                    Text("已选 \(item.title)")
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                }
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(
                        key: nil,
                        title: "全部",
                        flag: "🌐",
                        count: state.nodes.count
                    )
                    ForEach(state.categorySummary, id: \.key) { item in
                        categoryChip(
                            key: item.key,
                            title: item.title,
                            flag: item.flag,
                            count: item.count
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [BashXTheme.accentSoft(for: appearance).opacity(0.35), Color.primary.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func categoryChip(key: String?, title: String, flag: String, count: Int) -> some View {
        let selected = state.selectedCategoryKey == key
        return Button {
            state.selectedCategoryKey = key
        } label: {
            HStack(spacing: 5) {
                Text(flag).font(.system(size: 13))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? BashXTheme.accent(for: appearance) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(selected ? 0.06 : 0.04)))
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? BashXTheme.accentSoft(for: appearance).opacity(0.9) : BashXTheme.card(for: appearance).opacity(0.8))
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? BashXTheme.accent(for: appearance).opacity(0.45) : BashXTheme.separator(for: appearance), lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(PanelPressButtonStyle())
        .help(key == nil ? "显示全部地区" : "按地区筛选")
        .animation(nil, value: selected)
    }

    private var subscriptionsPane: some View {
        PanelSubscriptionsHost(state: state) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    subscriptionsHeader

                    if state.settings.subscriptions.isEmpty {
                        subscriptionsEmptyState
                    } else {
                        ForEach(state.settings.subscriptions) { sub in
                            SubscriptionManageCard(
                                subscriptionId: sub.id,
                                index: state.settings.subscriptions.firstIndex(where: { $0.id == sub.id }) ?? 0
                            )
                            .environmentObject(state)
                        }
                    }
                }
                .padding(20)
            }
            .transaction { $0.animation = nil }
        }
    }

    private var subscriptionsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("订阅")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("\(state.settings.subscriptions.filter(\.enabled).count)/\(state.settings.subscriptions.count) 启用 · 点左侧圆钮可多选合并")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            Spacer()
            Button {
                Task { await state.updateAllSubscriptions() }
            } label: {
                Label(state.isBusy ? "更新中…" : "全部更新", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.isBusy || state.settings.subscriptions.isEmpty)
            Button {
                openAddSubscription()
            } label: {
                Label("添加订阅", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(BashXTheme.accent(for: appearance))
            .contentShape(Rectangle())
        }
        .padding(.bottom, 2)
    }

    private var subscriptionsEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BashXTheme.accentSoft(for: appearance))
                    .frame(width: 64, height: 64)
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
            }

            VStack(spacing: 6) {
                Text("还没有订阅")
                    .font(.subheadline.weight(.semibold))
                Text("粘贴机场链接，自动拉取节点与流量信息")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                emptyStepRow("1", "复制机场订阅链接")
                emptyStepRow("2", "点击添加，自动识别节点")
                emptyStepRow("3", "勾选启用，合并到节点列表")
            }
            .padding(14)
            .frame(maxWidth: 320)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BashXTheme.card(for: appearance))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                    )
            }

            Button {
                openAddSubscription()
            } label: {
                Label("添加第一个订阅", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(BashXTheme.accent(for: appearance))
            .controlSize(.regular)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func emptyStepRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .frame(width: 18, height: 18)
                .background(Circle().strokeBorder(BashXTheme.accent(for: appearance).opacity(0.35), lineWidth: 1))
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        }
    }

    private var rulesPane: some View {
        RulesEditorPane()
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { state.searchText },
            set: {
                state.searchText = $0
                state.bumpNodeListRevision()
            }
        )
    }

    private var sortByDelayBinding: Binding<Bool> {
        Binding(
            get: { state.sortByDelay },
            set: {
                state.sortByDelay = $0
                state.bumpNodeListRevision()
            }
        )
    }
}

/// Isolated rules editor — observes AppState so text appears immediately (MainView itself is not Observable).
private struct RulesEditorPane: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance

    @State private var draft = ""
    @State private var ready = false
    @State private var dirty = false
    @State private var issues: [String] = []
    @State private var statusLine = ""
    @State private var validateTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("分流规则").font(.subheadline.weight(.semibold))
                    Text(statusLine.isEmpty ? "准备中…" : statusLine)
                        .font(.caption)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                }
                Spacer(minLength: 8)
                if dirty {
                    Text("未保存")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BashXTheme.warn(for: appearance))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(BashXTheme.warn(for: appearance).opacity(0.15)))
                }
            }

            if state.settings.proxyMode != .rule {
                Text("当前是\(state.settings.proxyMode.title)模式，分流规则不会生效。请在侧栏切回「规则」。")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.warn(for: appearance))
            } else if state.settings.videoAdBlockEnabled {
                Text("已开启视频广告过滤：运行时会自动前置约 \(VideoAdBlock.ruleCount) 条 REJECT（编辑区不显示）。")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            ZStack {
                TextEditor(text: $draft)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .opacity(ready ? 1 : 0)
                    .disabled(!ready)

                if !ready {
                    ProgressView("加载规则…")
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BashXTheme.field(for: appearance))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        issues.isEmpty
                            ? BashXTheme.separator(for: appearance)
                            : BashXTheme.warn(for: appearance).opacity(0.55),
                        lineWidth: 0.8
                    )
            )
            .onChange(of: draft) { _ in
                state.rulesText = draft
                scheduleValidate()
            }

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(issues.prefix(4).enumerated()), id: \.offset) { _, issue in
                        Text("· \(issue)")
                            .font(.caption2)
                            .foregroundStyle(BashXTheme.warn(for: appearance))
                    }
                    if issues.count > 4 {
                        Text("…另有 \(issues.count - 4) 条提示")
                            .font(.caption2)
                            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    }
                }
            }

            HStack(spacing: 8) {
                Button("应用智能规则 v\(ChinaSmartRules.version)") {
                    Task {
                        await state.applyChinaSmartRules()
                        reloadFromState()
                    }
                }
                .controlSize(.small)
                .help("用内置 BashX 智能规则覆盖当前编辑内容并立即生效")

                Spacer()

                Button("保存并生效") {
                    Task {
                        state.rulesText = draft
                        await state.saveRulesFromEditor()
                        reloadFromState()
                    }
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(!dirty && issues.isEmpty)
            }
        }
        .padding(16)
        .onAppear { reloadFromState() }
        .onReceive(state.$rulesText.receive(on: RunLoop.main)) { text in
            if !dirty, text != draft, !text.isEmpty {
                draft = text
                refreshMeta(for: text)
            }
        }
    }

    private func reloadFromState() {
        state.ensureRulesTextLoaded()
        let text = state.rulesText.isEmpty
            ? state.settings.rules.joined(separator: "\n")
            : state.rulesText
        if state.rulesText.isEmpty, !text.isEmpty {
            state.rulesText = text
        }
        draft = text
        ready = true
        refreshMeta(for: text)
    }

    private func scheduleValidate() {
        validateTask?.cancel()
        validateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            refreshMeta(for: draft)
        }
    }

    private func refreshMeta(for text: String) {
        let parsed = ClashRuleSyntax.parseLines(text)
        dirty = parsed != state.settings.rules
        issues = ClashRuleSyntax.validate(text)
        let edited = parsed.count
        let extra = state.settings.videoAdBlockEnabled ? VideoAdBlock.ruleCount : 0
        let runtime = edited + extra
        var parts = ["编辑 \(edited) 条", "生效约 \(runtime) 条"]
        if state.settings.rulesVersion > 0 {
            parts.insert("智能规则基准 v\(state.settings.rulesVersion)", at: 0)
        }
        statusLine = parts.joined(separator: " · ")
    }
}

// MARK: - Panel flicker isolation

/// Polls `AppState.statusText` without subscribing the whole panel to AppState publishes.
private struct PanelStatusLine: View {
    let state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @State private var text = ""

    var body: some View {
        Group {
            if !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 60, maxWidth: 140, alignment: .trailing)
            }
        }
        .onAppear { text = state.statusText }
        .onReceive(Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()) { _ in
            let next = state.statusText
            if next != text { text = next }
        }
        .transaction { $0.animation = nil }
    }
}

/// Only the rate chips re-render when traffic ticks (~1Hz).
private struct PanelTopBarRates: View {
    @ObservedObject var rates: MenuBarRateStore
    var onOpenMonitor: () -> Void

    var body: some View {
        TopBarRateBadge(panel: rates.panel)
            .fixedSize(horizontal: true, vertical: false)
            .onTapGesture(perform: onOpenMonitor)
            .help("打开流量监控")
            .transaction { $0.animation = nil }
    }
}

/// Polls outbound IP fields so sidebar chrome doesn't rebuild on every probe tick.
private struct PanelOutboundIP: View {
    let state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @State private var ip = "—"
    @State private var loading = false
    @State private var coreUp = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.caption2)
                .foregroundStyle(BashXTheme.accent(for: appearance))
            Text("出口 IP")
                .font(.caption2)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            Spacer(minLength: 4)
            if loading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else {
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(coreUp ? .primary : BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Button {
                state.scheduleOutboundIPRefresh(delay: 0)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            .buttonStyle(.plain)
            .disabled(!coreUp || loading)
            .help("刷新出口 IP")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(BashXTheme.accentSoft(for: appearance).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(BashXTheme.accent(for: appearance).opacity(0.15), lineWidth: 0.5)
                )
        }
        .onAppear { syncFromState() }
        .onReceive(state.$outboundIP.receive(on: RunLoop.main)) { _ in syncFromState() }
        .onReceive(state.$outboundIPLoading.receive(on: RunLoop.main)) { _ in syncFromState() }
        .onReceive(state.$chromeRevision.receive(on: RunLoop.main)) { _ in syncFromState() }
        .transaction { $0.animation = nil }
    }

    private var statusLabel: String {
        if coreUp {
            return ip.isEmpty ? "—" : ip
        }
        if state.coreConnecting { return "连接中…" }
        return "内核未启动"
    }

    private func syncFromState() {
        let nextCore = state.isCoreVisiblyAlive
        let nextLoading = state.outboundIPLoading
        let nextIP = state.outboundIP
        if nextCore != coreUp { coreUp = nextCore }
        if nextLoading != loading { loading = nextLoading }
        if nextIP != ip { ip = nextIP }
    }
}

private struct PanelSubscriptionsHost<Content: View>: View {
    let state: AppState
    @ViewBuilder var content: () -> Content
    @State private var revision = 0

    var body: some View {
        let _ = revision
        return content()
            .onReceive(state.$subscriptionsRevision.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
    }
}

private struct PanelSidebarHost<Content: View>: View {
    let state: AppState
    @ViewBuilder var content: () -> Content
    @State private var revision = 0

    var body: some View {
        let _ = revision
        return content()
            .onReceive(state.$chromeRevision.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
    }
}

private struct PanelNodesHost<Content: View>: View {
    let state: AppState
    @ViewBuilder var content: () -> Content
    @State private var revision = 0

    var body: some View {
        let _ = revision
        return content()
            .onReceive(state.$nodeListRevision.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
            // Intentionally ignore chromeRevision — node switch / proxy toggles must not remount the list.
    }
}

/// Category expand/collapse stays local so toggling does not rebuild the whole node tree.
private struct NodesCategoriesView: View {
    let state: AppState
    let appearance: AppAppearance
    let displayMode: NodeDisplayMode
    let selectedNodeName: String?
    let switchingNodeName: String?
    let onSelect: (String) -> Void

    @State private var collapsed: Set<String> = []
    @State private var groups: [NodeCategory.Group] = []

    var body: some View {
        Group {
            if displayMode == .card {
                cardPane
            } else {
                listPane
            }
        }
        .transaction { $0.animation = nil }
        .onAppear(perform: reload)
        .onReceive(state.$nodeListRevision.receive(on: RunLoop.main)) { _ in
            reload()
        }
    }

    private func reload() {
        groups = state.categoryGroups
        // Drop stale keys; keep user's open/closed choices for still-visible groups.
        let keys = Set(groups.map(\.key))
        collapsed = collapsed.intersection(keys).union(state.collapsedCategories.intersection(keys))
    }

    private func toggle(_ key: String) {
        var next = collapsed
        if next.contains(key) {
            next.remove(key)
        } else {
            next.insert(key)
        }
        collapsed = next
        state.collapsedCategories = next
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("节点")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("类型")
                    .frame(width: 56, alignment: .center)
                Text("延迟")
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.75))
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            if !collapsed.contains(group.key) {
                                ForEach(Array(group.nodes.enumerated()), id: \.element.id) { idx, node in
                                    nodeRow(node, index: idx + 1)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 2)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelect(node.name) }
                                }
                            }
                        } header: {
                            categoryHeader(group)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                                .background(BashXTheme.card(for: appearance).opacity(0.92))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .contextMenu {
                Button("复制节点信息") { state.copySelectedProxyLine() }
                Button("打开配置目录") { state.openConfigFolder() }
            }
        }
    }

    private var cardPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        if !collapsed.contains(group.key) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 148, maximum: 200), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(group.nodes) { node in
                                    nodeCard(node, group: group)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)
                        }
                    } header: {
                        categoryHeaderCard(group)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func categoryHeader(_ group: NodeCategory.Group) -> some View {
        let isCollapsed = collapsed.contains(group.key)
        let best = group.nodes.lazy.compactMap(\.delayMs).filter { $0 > 0 }.min()
        return Button {
            toggle(group.key)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .frame(width: 10)
                Text(group.flag)
                    .font(.system(size: 12))
                Text(group.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text("\(group.nodes.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(BashXTheme.secondaryFill(for: appearance)))
                Spacer(minLength: 4)
                if let best {
                    Text("最快 \(best)ms")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(BashXTheme.delayColor(best, appearance: appearance))
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelPressButtonStyle())
    }

    private func categoryHeaderCard(_ group: NodeCategory.Group) -> some View {
        let isCollapsed = collapsed.contains(group.key)
        let best = group.nodes.lazy.compactMap(\.delayMs).filter { $0 > 0 }.min()
        return Button {
            toggle(group.key)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCollapsed ? "chevron.right.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                Text(group.flag)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Text("\(group.nodes.count) 个节点")
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                }
                Spacer(minLength: 4)
                if let best {
                    Text("最快 \(best) ms")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BashXTheme.delayColor(best, appearance: appearance))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(BashXTheme.delayColor(best, appearance: appearance).opacity(0.12)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelPressButtonStyle())
    }

    private func nodeCard(_ node: ProxyNode, group: NodeCategory.Group) -> some View {
        let selected = node.name == selectedNodeName
        let switching = switchingNodeName == node.name
        let highlighted = selected || switching
        let delay = node.delayMs
        return Button {
            onSelect(node.name)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    Text(group.flag)
                        .font(.system(size: 10))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(BashXTheme.accentSoft(for: appearance).opacity(highlighted ? 1 : 0.7)))
                    Text(node.name)
                        .font(.system(size: 11, weight: highlighted ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if switching {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    } else if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(BashXTheme.accent(for: appearance))
                    }
                }

                HStack(spacing: 5) {
                    Text(shortType(node.type))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(highlighted ? BashXTheme.accent(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(highlighted
                                      ? BashXTheme.accent(for: appearance).opacity(0.15)
                                      : BashXTheme.secondaryFill(for: appearance))
                        )
                    Spacer(minLength: 0)
                    Text(delay.map { "\($0) ms" } ?? "—")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(
                            delay.map { BashXTheme.delayColor($0, appearance: appearance) } ?? BashXTheme.secondaryLabel(for: appearance)
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(highlighted ? BashXTheme.accentSoft(for: appearance) : BashXTheme.card(for: appearance))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                highlighted
                                    ? BashXTheme.accent(for: appearance).opacity(0.5)
                                    : BashXTheme.separator(for: appearance),
                                lineWidth: highlighted ? 1 : 0.5
                            )
                    )
            }
        }
        .buttonStyle(PanelPressButtonStyle())
        .help(highlighted ? "当前节点" : "点击切换到此节点")
    }

    private func nodeRow(_ node: ProxyNode, index: Int) -> some View {
        let selected = node.name == selectedNodeName
        let switching = switchingNodeName == node.name
        let highlighted = selected || switching
        return HStack(spacing: 8) {
            ZStack {
                if switching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("\(index)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)

            Text(node.name)
                .font(.system(size: 12, weight: highlighted ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(shortType(node.type))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .frame(width: 56, alignment: .center)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            delayBadge(node)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? BashXTheme.accentSoft(for: appearance).opacity(0.65) : Color.clear)
        }
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(BashXTheme.accent(for: appearance))
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
    }

    private func shortType(_ type: String) -> String {
        let t = type.uppercased()
        if t.count <= 6 { return t }
        return String(t.prefix(5))
    }

    private func delayBadge(_ node: ProxyNode) -> some View {
        let color = BashXTheme.delayColor(node.delayMs, appearance: appearance)
        let text: String = {
            guard let ms = node.delayMs else { return "—" }
            if ms < 0 { return "超时" }
            return "\(ms) ms"
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(minWidth: 64, alignment: .trailing)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(node.delayMs == nil ? 0.04 : 0.10))
            )
    }
}

private struct PanelTopBarHost<Content: View>: View {
    let state: AppState
    @ViewBuilder var content: () -> Content
    @State private var revision = 0

    var body: some View {
        let _ = revision
        return content()
            .onReceive(state.$chromeRevision.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
    }
}
