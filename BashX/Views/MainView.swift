import Combine
import SwiftUI

struct MainView: View {
    @ObservedObject var state: AppState
    let monitor: TrafficMonitor
    let rates: MenuBarRateStore
    @Environment(\.bashxAppearance) private var appearance
    @State private var showLogoPicker = false
    @State private var detailTab: DetailTab = .nodes
    @State private var monitorSegment: MonitorPane.MonitorSegment = .connections
    @State private var renameTarget: Subscription?
    @State private var renameDraft = ""
    @State private var switchingNodeName: String?
    @State private var pendingHubMode: ProxyHubMode?
    /// Instant chip highlight before chromeRevision lands.
    @State private var pendingProxyMode: ProxyMode?
    @State private var minimalToggling = false
    @State private var showMinimalNodePicker = false
    @State private var minimalNodeQuery = ""
    @State private var minimalSwitchingNode = false
    @State private var showMinimalModePicker = false
    @State private var minimalBrandAppear = false
    @State private var minimalHeroBreath = false
    @State private var minimalRingSpin: Double = 0
    @State private var minimalShimmer: CGFloat = -0.4

    /// Single-row panel menus: 订阅 · 节点 · 应用分流 · 域名规则 · 监控
    private enum DetailTab: CaseIterable, Identifiable {
        case subscriptions, nodes, apps, rules, monitor
        var id: String { String(describing: self) }
        func title(lang: AppLanguage) -> String {
            switch self {
            case .subscriptions: return L10n.t("mac.panel.subscriptions", lang)
            case .nodes: return L10n.t("mac.panel.nodes", lang)
            case .apps: return L10n.t("mac.panel.apps", lang)
            case .rules: return L10n.t("mac.panel.rules", lang)
            case .monitor: return L10n.t("mac.panel.monitor", lang)
            }
        }
        var systemImage: String {
            switch self {
            case .subscriptions: return "link.circle.fill"
            case .nodes: return "server.rack"
            case .apps: return "app.badge.fill"
            case .rules: return "list.bullet.rectangle"
            case .monitor: return "waveform.path.ecg"
            }
        }
    }

    private var lang: AppLanguage { state.settings.uiLanguage }

    var body: some View {
        BashXThemed(appearance: state.settings.appearance) {
            panelContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BashXTheme.canvas(for: appearance))
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
            // 极简首页：用户点连接再启动；完整版才自动保活内核。
            guard !state.settings.macMinimalHome else { return }
            _ = await state.ensureCoreRunning()
        }
        .onAppear {
            monitor.chartSamplesEnabled = true
            syncMonitorExtras()
        }
        .onDisappear {
            monitor.chartSamplesEnabled = false
            monitor.stopConnectionsAndLogs()
        }
        .onReceive(state.$coreRunning.receive(on: RunLoop.main)) { _ in syncMonitorExtras() }
        .onReceive(state.$chromeRevision.receive(on: RunLoop.main)) { _ in syncMonitorExtras() }
        .onReceive(state.$searchText.dropFirst().receive(on: RunLoop.main)) { _ in state.bumpNodeListRevision() }
        .onReceive(state.$sortByDelay.dropFirst().receive(on: RunLoop.main)) { _ in state.bumpNodeListRevision() }
        .onReceive(state.$selectedCategoryKey.dropFirst().receive(on: RunLoop.main)) { _ in state.bumpNodeListRevision() }
        .onValueChange(detailTab) { tab in
            if tab == .rules {
                state.ensureRulesTextLoaded()
            }
            syncMonitorExtras()
        }
    }

    private var panelContent: some View {
        ZStack {
            if state.settings.macMinimalHome {
                MinimalHomeBackdrop()
            } else {
                PanelAtmosphere()
            }
            if state.settings.macMinimalHome {
                minimalHome
            } else {
                VStack(spacing: 0) {
                    PanelTopBarHost(state: state) {
                        topBar
                    }
                    GlassDivider()
                    HStack(spacing: 0) {
                        PanelSidebarHost(state: state) {
                            sidebar
                        }
                        .frame(width: PanelMetrics.sidebarWidth)
                        Rectangle()
                            .fill(BashXTheme.hairline(for: appearance))
                            .frame(width: 1)
                        detail
                    }
                }
            }
        }
    }

    // MARK: - Minimal home (iOS-like)

    private var minimalConnected: Bool {
        state.isCoreVisiblyAlive || state.systemProxyOn
    }

    private var minimalBusy: Bool {
        minimalToggling
    }

    private var minimalDisplayNodeName: String {
        if let runtime = state.runtimeOutboundName, !runtime.isEmpty { return runtime }
        if let selected = state.settings.selectedNodeName, !selected.isEmpty { return selected }
        return L10n.t("mac.minimal.pickNode", lang)
    }

    private var minimalHeroAccent: Color {
        if minimalConnected { return BashXTheme.good(for: appearance) }
        if minimalBusy { return BashXTheme.warn(for: appearance) }
        return BashXTheme.accent(for: appearance)
    }

    private var minimalHeroSubtitle: String {
        if minimalConnected { return L10n.t("home.hero.connected", lang) }
        if minimalBusy { return L10n.t("home.hero.connecting", lang) }
        if state.nodes.isEmpty { return L10n.t("home.hero.empty", lang) }
        return L10n.t("home.hero.ready", lang)
    }

    private var minimalStatusText: String {
        if minimalBusy { return L10n.t("mac.minimal.connecting", lang) }
        if minimalConnected { return L10n.t("mac.minimal.protected", lang) }
        if state.nodes.isEmpty { return L10n.t("mac.minimal.needSub", lang) }
        if state.settings.selectedNodeName == nil {
            return L10n.t("mac.minimal.pickNode", lang)
        }
        return L10n.t("mac.minimal.ready", lang)
    }

    private var minimalHome: some View {
        VStack(spacing: 0) {
            // Toolbar chrome only — brand lives in hero (iOS-like)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                PanelHomeModeToggle(
                    isMinimal: true,
                    lang: lang,
                    onSelectMinimal: { state.setMacMinimalHome($0) }
                )
                Button {
                    SettingsOpener.open(state: state)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(BashXTheme.card(for: appearance).opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("设置")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .zIndex(2)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    minimalHeroSection
                        .padding(.top, 4)

                    minimalNodePickerBar
                        .padding(.horizontal, 18)
                        .padding(.top, 2)
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                minimalBrandAppear = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                minimalHeroBreath = true
            }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                minimalRingSpin = 360
            }
            withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
                minimalShimmer = 1.2
            }
        }
    }

    private var minimalHeroSection: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                minimalHeroLogoMark
                    .scaleEffect(minimalBrandAppear ? 1 : 0.82)
                    .opacity(minimalBrandAppear ? 1 : 0)
                    .scaleEffect(minimalHeroBreath ? 1.03 : 1)

                minimalBrandTitle
                    .opacity(minimalBrandAppear ? 1 : 0)
                    .offset(y: minimalBrandAppear ? 0 : 10)

                Text(minimalHeroSubtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BashXTheme.card(for: appearance).opacity(0.72))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(minimalHeroAccent.opacity(0.18), lineWidth: 0.6)
                            )
                    )
                    .opacity(minimalBrandAppear ? 1 : 0)
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                minimalStatusPill
                minimalModePill
            }
            .scaleEffect(minimalBrandAppear ? 1 : 0.9)
            .opacity(minimalBrandAppear ? 1 : 0)

            MacConnectControl(
                isConnected: minimalConnected,
                isBusy: minimalBusy,
                appearance: appearance,
                language: lang
            ) {
                guard !minimalToggling else { return }
                minimalToggling = true
                Task {
                    await state.toggleMinimalConnection()
                    await MainActor.run { minimalToggling = false }
                }
            }
            .padding(.top, 2)

            if !state.settings.subscriptions.contains(where: \.enabled), !minimalConnected {
                Text(L10n.t("mac.minimal.needSub", lang))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
            }

            if !state.statusText.isEmpty,
               state.statusText != "就绪",
               !state.statusText.contains("代理已") {
                Text(state.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var minimalHeroLogoMark: some View {
        ZStack {
            Circle()
                .fill(minimalHeroAccent.opacity(minimalHeroBreath ? 0.22 : 0.10))
                .frame(width: 78, height: 78)
                .blur(radius: 10)
                .scaleEffect(minimalHeroBreath ? 1.12 : 0.92)

            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                minimalHeroAccent.opacity(0),
                                minimalHeroAccent.opacity(0.55),
                                BashXTheme.accent(for: appearance).opacity(0.35),
                                minimalHeroAccent.opacity(0),
                            ],
                            center: .center
                        ),
                        lineWidth: i == 0 ? 1.3 : 1
                    )
                    .frame(width: 64 + CGFloat(i) * 12, height: 64 + CGFloat(i) * 12)
                    .rotationEffect(.degrees(minimalRingSpin * (i == 0 ? 1 : -0.7)))
                    .opacity(0.7)
            }

            LogoIconView(style: state.settings.logoStyle, size: 46, colored: true, panel: true)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    minimalHeroAccent.opacity(0.35),
                                    Color.white.opacity(0.15),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )
                )
                .shadow(color: minimalHeroAccent.opacity(0.32), radius: minimalHeroBreath ? 14 : 8, y: 4)
        }
        .frame(width: 88, height: 88)
    }

    private var minimalBrandTitle: some View {
        Text("BashX")
            .font(.system(size: 32, weight: .heavy, design: .rounded))
            .tracking(-1.0)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        BashXTheme.primaryLabel(for: appearance),
                        BashXTheme.accent(for: appearance).opacity(0.92),
                        BashXTheme.primaryLabel(for: appearance),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(appearance == .dark ? 0.35 : 0.55),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 48)
                .offset(x: minimalShimmer * 130)
                .blendMode(.softLight)
                .mask(
                    Text("BashX")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .tracking(-1.0)
                )
            }
    }

    private var minimalStatusPill: some View {
        let tone = minimalConnected
            ? BashXTheme.good(for: appearance)
            : (minimalBusy ? BashXTheme.warn(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
        return HStack(spacing: 6) {
            Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
            Text(minimalStatusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(tone.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tone.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    private var minimalModePill: some View {
        let current = pendingProxyMode ?? state.settings.proxyMode
        let color = BashXTheme.proxyModeColor(current, appearance: appearance)
        return Button { showMinimalModePicker.toggle() } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(current.title(lang: lang))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(color.opacity(0.22), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMinimalModePicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ProxyMode.allCases) { mode in
                    let selected = mode == current
                    let color = BashXTheme.proxyModeColor(mode, appearance: appearance)
                    Button {
                        showMinimalModePicker = false
                        guard current != mode else { return }
                        pendingProxyMode = mode
                        Task {
                            await state.setProxyMode(mode)
                            if pendingProxyMode == mode {
                                pendingProxyMode = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(color)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.title(lang: lang))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(mode.subtitle(lang: lang))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                            }
                            Spacer(minLength: 4)
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(color)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? color.opacity(0.12) : Color.clear)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 260)
            .background(BashXTheme.card(for: appearance))
        }
        .help(current.subtitle(lang: lang))
    }

    private var minimalNodePickerBar: some View {
        let accent = BashXTheme.accent(for: appearance)
        let hasNode = !(state.settings.selectedNodeName ?? "").isEmpty
            || !(state.runtimeOutboundName ?? "").isEmpty
        let delayNode: ProxyNode? = {
            if let name = state.runtimeOutboundName,
               let n = state.nodes.first(where: { $0.name == name }) { return n }
            if let name = state.settings.selectedNodeName,
               let n = state.nodes.first(where: { $0.name == name }) { return n }
            return nil
        }()

        return Button {
            showMinimalNodePicker = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(L10n.t("mac.currentNode.title", lang))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    if let ms = delayNode?.delayMs {
                        Text(delayNode?.delayText(lang: lang) ?? "")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(BashXTheme.delayColor(ms, appearance: appearance))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(BashXTheme.delayColor(ms, appearance: appearance).opacity(0.14))
                            )
                    }
                }
                .foregroundStyle(accent)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                            .shadow(color: accent.opacity(0.35), radius: 8, y: 3)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(minimalDisplayNodeName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        if let node = delayNode {
                            Text("\(node.type.uppercased()) · \(L10n.t("home.location", lang))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        } else if state.nodes.isEmpty {
                            Text(L10n.t("mac.minimal.needSub", lang))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        } else {
                            Text(L10n.t("mac.minimal.pickNode", lang))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        }
                    }

                    Spacer(minLength: 4)

                    if minimalSwitchingNode {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(accent)
                                    .shadow(color: accent.opacity(0.35), radius: 4, y: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BashXTheme.card(for: appearance).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(hasNode ? 0.55 : 0.22),
                                        accent.opacity(hasNode ? 0.22 : 0.10),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: hasNode ? 1.4 : 0.8
                            )
                    )
                    .shadow(color: accent.opacity(hasNode ? 0.18 : 0.08), radius: hasNode ? 14 : 8, y: 3)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PanelPressButtonStyle())
        .popover(isPresented: $showMinimalNodePicker, arrowEdge: .bottom) {
            minimalNodePopover
        }
        .disabled(state.nodes.isEmpty)
        .opacity(state.nodes.isEmpty ? 0.72 : 1)
        .help(state.nodes.isEmpty ? L10n.t("mac.minimal.needSub", lang) : L10n.t("mac.minimal.pickNode", lang))
    }

    private var minimalNodePopover: some View {
        let q = minimalNodeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodes: [ProxyNode] = {
            var list = state.nodes.filter { !ClashConfigParser.isPlaceholderNodeName($0.name) }
            if !q.isEmpty {
                list = list.filter {
                    $0.name.localizedCaseInsensitiveContains(q)
                        || $0.type.localizedCaseInsensitiveContains(q)
                        || $0.server.localizedCaseInsensitiveContains(q)
                }
            }
            return Array(list.prefix(120))
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .font(.system(size: 11, weight: .semibold))
                TextField(L10n.t("mac.minimal.pickNode", lang), text: $minimalNodeQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BashXTheme.field(for: appearance))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                    )
            }

            if nodes.isEmpty {
                Text(state.nodes.isEmpty ? L10n.t("mac.minimal.needSub", lang) : "无匹配节点")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(nodes) { node in
                            let selected = node.name == state.settings.selectedNodeName
                                || node.name == state.runtimeOutboundName
                            Button {
                                guard !minimalSwitchingNode else { return }
                                minimalSwitchingNode = true
                                showMinimalNodePicker = false
                                Task {
                                    await state.selectNode(node.name)
                                    await MainActor.run { minimalSwitchingNode = false }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(node.name)
                                            .font(.system(size: 12, weight: selected ? .bold : .semibold, design: .rounded))
                                            .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                                            .lineLimit(1)
                                        Text(node.type.uppercased())
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                                    }
                                    Spacer(minLength: 4)
                                    Text(node.delayText(lang: lang))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(BashXTheme.delayColor(node.delayMs, appearance: appearance))
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(BashXTheme.accent(for: appearance))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected
                                              ? BashXTheme.accentSoft(for: appearance)
                                              : Color.clear)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(BashXTheme.card(for: appearance))
        .onDisappear { minimalNodeQuery = "" }
    }

    /// Panel toggles connections/logs; traffic SSE is owned by BashXApp.
    private func syncMonitorExtras() {
        let coreUp = state.isCoreVisiblyAlive || state.coreRunning
        monitor.chartSamplesEnabled = (detailTab == .monitor)
        if coreUp, detailTab == .monitor {
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
        case .groups:
            detailTab = .nodes
            state.panelIntent = .none
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 10) {
                topBarBrand
                Spacer(minLength: 8)
                PanelStatusLine(state: state)
                PanelHomeModeToggle(
                    isMinimal: false,
                    lang: lang,
                    onSelectMinimal: { state.setMacMinimalHome($0) }
                )
                topBarSettingsButton
            }

            HStack(spacing: 5) {
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
                if let nodePill = currentNodePillTitle {
                    StatusPill(title: nodePill, active: state.isCoreVisiblyAlive)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(BashXTheme.secondaryFill(for: appearance).opacity(0.55))
            }
            .allowsHitTesting(false)
        }
        .frame(height: PanelMetrics.topBarHeight)
        .padding(.horizontal, 12)
        .background {
            Rectangle()
                .fill(BashXTheme.card(for: appearance))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(BashXTheme.hairline(for: appearance))
                        .frame(height: 1)
                }
        }
        .transaction { $0.animation = nil }
    }

    private var topBarBrand: some View {
        HStack(spacing: 8) {
            Button {
                showLogoPicker.toggle()
            } label: {
                LogoIconView(style: state.settings.logoStyle, size: 22, colored: true, panel: true)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(BashXTheme.accent(for: appearance).opacity(0.28), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .accessibilityLabel("切换 Logo 风格")
            .popover(isPresented: $showLogoPicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Logo 风格")
                        .font(PanelMetrics.sectionTitle)
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

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("BashX")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("v\(AppVersion.short)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                        .help("Build \(AppVersion.build)")
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isCoreVisiblyAlive ? BashXTheme.good(for: appearance) : BashXTheme.tertiaryLabel(for: appearance).opacity(0.55))
                        .frame(width: 4.5, height: 4.5)
                    Text(state.isCoreVisiblyAlive
                          ? "代理已连接"
                          : (state.coreConnecting
                             ? "内核连接中…"
                             : (state.coreRunning ? "内核已就绪" : "内核未启动")))
                        .font(PanelMetrics.micro)
                        .foregroundStyle(state.isCoreVisiblyAlive ? BashXTheme.good(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var topBarSettingsButton: some View {
        Button {
            SettingsOpener.open(state: state)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BashXTheme.secondaryFill(for: appearance))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                        )
                }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
        .help("设置 (⌘,)")
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PanelMetrics.sidebarStack) {
                PanelSidebarTraffic(
                    panel: rates.panel,
                    coreRunning: state.isCoreVisiblyAlive || state.coreRunning
                ) {
                    detailTab = .monitor
                }

                selectedNodeCard
                proxyModeSection
                sidebarSubsSummary
                sidebarSettingsCard
            }
            .padding(.horizontal, PanelMetrics.sidebarInset)
            .padding(.vertical, PanelMetrics.sidebarInset)
        }
        .frame(width: PanelMetrics.sidebarWidth)
        .background(BashXTheme.sidebarTint(for: appearance))
    }

    private var sidebarSettingsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            SidebarSectionHeader(title: "连接", systemImage: "link.circle.fill")

            VStack(spacing: 4) {
                sidebarToggleTile(
                    icon: "network",
                    tint: BashXTheme.accent(for: appearance),
                    title: "系统代理",
                    subtitle: "127.0.0.1:\(state.settings.mixedPort)",
                    isOn: Binding(
                        get: { state.systemProxyOn },
                        set: { v in Task { await state.setSystemProxy(v) } }
                    )
                )
                sidebarToggleTile(
                    icon: "point.3.connected.trianglepath.dotted",
                    tint: Color(red: 0.36, green: 0.72, blue: 0.88),
                    title: "TUN",
                    subtitle: TunPrivilege.isReady ? "已授权 · Telegram 稳" : "首次需管理员密码",
                    isOn: Binding(
                        get: { state.settings.tunEnabled },
                        set: { v in Task { await state.setTUN(v) } }
                    )
                )
                sidebarToggleTile(
                    icon: "power.circle.fill",
                    tint: Color(red: 0.52, green: 0.78, blue: 0.42),
                    title: L10n.t("mac.launchAtLogin", lang),
                    subtitle: L10n.t("mac.launchAtLogin.sub", lang),
                    isOn: Binding(
                        get: { state.launchAtLoginOn },
                        set: { state.setLaunchAtLogin($0) }
                    )
                )
                sidebarToggleTile(
                    icon: "play.slash.fill",
                    tint: Color(red: 0.92, green: 0.42, blue: 0.48),
                    title: L10n.t("mac.nodes.adblock", lang),
                    subtitle: L10n.t("mac.nodes.adblock.sub", lang),
                    isOn: Binding(
                        get: { state.settings.videoAdBlockEnabled },
                        set: { v in Task { await state.setVideoAdBlock(v) } }
                    )
                )
            }
            .onAppear {
                state.refreshLaunchAtLogin()
            }
            .onReceive(state.$chromeRevision.receive(on: RunLoop.main)) { _ in
                state.refreshLaunchAtLogin()
            }

            // Keep the button mounted while auto-retry toggles `coreConnecting`
            // — inserting/removing the view is what made it look like it was flashing.
            if !(state.isCoreVisiblyAlive || state.coreRunning) {
                let starting = state.coreConnecting
                Button {
                    guard !starting else { return }
                    Task { await state.ensureCoreRunning() }
                } label: {
                    HStack(spacing: 6) {
                        if starting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(starting ? "正在启动…" : "启动内核")
                            .font(PanelMetrics.caption)
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Text(starting ? "请稍候" : "开始代理")
                            .font(PanelMetrics.micro)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: PanelMetrics.chipRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        BashXTheme.accent(for: appearance),
                                        BashXTheme.accent(for: appearance).opacity(starting ? 0.65 : 0.82),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(starting)
                .transaction { $0.animation = nil }
            }
        }
        .padding(PanelMetrics.cardPad)
        .transaction { $0.animation = nil }
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private func sidebarToggleTile(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(appearance == .dark ? 0.22 : 0.14))
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(PanelMetrics.body)
                    .foregroundStyle(disabled ? BashXTheme.tertiaryLabel(for: appearance) : BashXTheme.primaryLabel(for: appearance))
                Text(subtitle)
                    .font(PanelMetrics.micro)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(disabled)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.chipRadius, style: .continuous)
                .fill(isOn.wrappedValue
                      ? tint.opacity(appearance == .dark ? 0.10 : 0.06)
                      : BashXTheme.secondaryFill(for: appearance).opacity(0.55))
        }
        .opacity(disabled ? 0.55 : 1)
        .transaction { $0.animation = nil }
    }

    private func sidebarActionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        disabled: Bool = false,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(disabled ? BashXTheme.tertiaryLabel(for: appearance) : .primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        disabled
                            ? BashXTheme.tertiaryLabel(for: appearance)
                            : (emphasized ? BashXTheme.accent(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
                    )
                    .frame(width: 28, alignment: .trailing)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .transaction { $0.animation = nil }
    }

    private var proxyModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarSectionHeader(title: L10n.t("proxy.outbound", lang), systemImage: "arrow.triangle.branch")

            HStack(spacing: 4) {
                ForEach(ProxyMode.allCases) { mode in
                    proxyModeChip(mode)
                }
            }

            Text((pendingProxyMode ?? state.settings.proxyMode).subtitle(lang: lang))
                .font(PanelMetrics.micro)
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PanelMetrics.cardPad)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private func proxyModeChip(_ mode: ProxyMode) -> some View {
        let current = pendingProxyMode ?? state.settings.proxyMode
        let selected = current == mode
        let color = BashXTheme.proxyModeColor(mode, appearance: appearance)
        return Button {
            guard current != mode else { return }
            pendingProxyMode = mode
            Task {
                await state.setProxyMode(mode)
                if pendingProxyMode == mode {
                    pendingProxyMode = nil
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(mode.title)
                    .font(.system(size: 11, weight: selected ? .bold : .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? color : BashXTheme.secondaryLabel(for: appearance))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: PanelMetrics.chipRadius, style: .continuous)
                    .fill(selected ? color.opacity(appearance == .dark ? 0.16 : 0.10) : BashXTheme.secondaryFill(for: appearance).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: PanelMetrics.chipRadius, style: .continuous)
                            .strokeBorder(
                                selected ? color.opacity(0.50) : Color.clear,
                                lineWidth: selected ? 1 : 0
                            )
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.chipRadius, style: .continuous))
        }
        .buttonStyle(PanelPressButtonStyle())
        .help(mode.subtitle)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private func selectNodeFromPanel(_ name: String) {
        guard switchingNodeName != name else { return }
        switchingNodeName = name
        Task {
            await state.selectNode(name)
            if switchingNodeName == name { switchingNodeName = nil }
        }
    }

    private var currentNodePillTitle: String? {
        guard state.isCoreVisiblyAlive || state.coreRunning else { return nil }
        if let runtime = state.runtimeOutboundName, !runtime.isEmpty {
            let short = runtime.count > 14 ? String(runtime.prefix(13)) + "…" : runtime
            return short
        }
        if let selected = state.settings.selectedNodeName, !selected.isEmpty {
            let short = selected.count > 14 ? String(selected.prefix(13)) + "…" : selected
            return short
        }
        return "AUTO"
    }

    private var selectedNodeCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(L10n.t("mac.currentNode.title", lang), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(PanelMetrics.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Spacer(minLength: 0)
                if let name = effectiveNodeDelayName,
                   let node = state.nodes.first(where: { $0.name == name }),
                   let ms = node.delayMs {
                    Text(ms < 0 ? L10n.t("probe.timeout", lang) : "\(ms) ms")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BashXTheme.delayColor(ms, appearance: appearance))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BashXTheme.delayColor(ms, appearance: appearance).opacity(0.12))
                        )
                }
            }

            if let runtime = state.runtimeOutboundName, !runtime.isEmpty {
                Text(runtime)
                    .font(PanelMetrics.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                let selected = state.settings.selectedNodeName ?? "AUTO"
                if selected != runtime {
                    Text(L10n.t("mac.currentNode.selected", lang)
                        .replacingOccurrences(of: "%@", with: selected))
                        .font(PanelMetrics.micro)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                        .lineLimit(1)
                }
            } else {
                Text(state.settings.selectedNodeName ?? L10n.t("mac.currentNode.auto", lang))
                    .font(PanelMetrics.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(PanelMetrics.cardPad)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(
                            state.coreRunning
                                ? LinearGradient(
                                    colors: [
                                        BashXTheme.accent(for: appearance).opacity(0.45),
                                        BashXTheme.accentGlow(for: appearance).opacity(0.25)
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
                .shadow(color: state.coreRunning ? BashXTheme.accent(for: appearance).opacity(0.06) : .clear, radius: 4, y: 1)
        }
        .task(id: "\(state.settings.selectedNodeName ?? "")|\(state.coreRunning)") {
            guard state.coreRunning else { return }
            await state.refreshRuntimeOutbound()
            while !Task.isCancelled, state.coreRunning {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await state.refreshRuntimeOutbound()
            }
        }
        .onValueChange(state.coreRunning) { running in
            if running {
                state.scheduleRuntimeOutboundRefresh()
            } else {
                state.runtimeOutboundName = nil
            }
        }
    }

    private var effectiveNodeDelayName: String? {
        if let runtime = state.runtimeOutboundName,
           state.nodes.contains(where: { $0.name == runtime }) {
            return runtime
        }
        if let selected = state.settings.selectedNodeName,
           state.nodes.contains(where: { $0.name == selected }) {
            return selected
        }
        return nil
    }

    private var sidebarSubsSummary: some View {
        let subs = state.settings.subscriptions
        let enabledCount = subs.filter(\.enabled).count
        let totalCount = subs.count

        return VStack(alignment: .leading, spacing: 6) {
            SidebarSectionHeader(title: "订阅", systemImage: "tray.full")

            if totalCount == 0 {
                Text("还没有订阅")
                    .font(PanelMetrics.micro)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            } else {
                HStack(spacing: 6) {
                    subSummaryMetric(
                        value: "\(enabledCount)/\(totalCount)",
                        label: enabledCount == totalCount ? "已全部启用" : "已启用"
                    )
                    subSummaryMetric(
                        value: "\(state.nodes.count)",
                        label: "合并节点",
                        accent: true
                    )
                }
                if enabledCount < totalCount {
                    Text("还有 \(totalCount - enabledCount) 个未启用")
                        .font(PanelMetrics.micro)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
            }

            HStack(spacing: 5) {
                Button {
                    detailTab = .subscriptions
                } label: {
                    Text("管理")
                        .font(PanelMetrics.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    openAddSubscription()
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(PanelMetrics.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(BashXTheme.accent(for: appearance))

                Button {
                    Task { await state.updateAllSubscriptions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.isBusy || subs.isEmpty)
                .help("更新全部订阅")
            }

            if totalCount > 1, enabledCount < totalCount {
                Button {
                    Task { await state.enableAllSubscriptions() }
                } label: {
                    Text("启用全部并合并")
                        .font(PanelMetrics.micro)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .disabled(state.isBusy)
            } else if subs.isEmpty {
                Text("添加订阅后点 ↻ 拉取节点")
                    .font(PanelMetrics.micro)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }
        }
        .padding(PanelMetrics.cardPad)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private func subSummaryMetric(value: String, label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? BashXTheme.accent(for: appearance) : BashXTheme.primaryLabel(for: appearance))
            Text(label)
                .font(PanelMetrics.micro)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accent
                      ? BashXTheme.accentSoft(for: appearance)
                      : BashXTheme.secondaryFill(for: appearance))
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

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            detailHeader
            GlassDivider()

            Group {
                switch detailTab {
                case .nodes:
                    nodesPane
                case .apps:
                    AppRoutingPane()
                case .rules:
                    RulesEditorPane()
                        .padding(12)
                case .subscriptions:
                    subscriptionsPane
                case .monitor:
                    MonitorPane(
                        monitor: monitor,
                        panel: rates.panel,
                        segment: $monitorSegment,
                        coreAlive: state.isCoreVisiblyAlive || state.coreRunning,
                        lang: lang,
                        onCloseAll: {
                            Task { await monitor.closeAllConnections() }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BashXTheme.canvas(for: appearance))
    }

    private var detailHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                detailTabBar
                Spacer(minLength: 0)
            }

            if detailTab == .nodes {
                PanelNodesHost(state: state) {
                    HStack(spacing: 7) {
                        SoftField {
                            HStack(spacing: 5) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                                    .font(.system(size: 10, weight: .semibold))
                                TextField("搜索节点", text: searchTextBinding)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Picker("节点展示", selection: Binding(
                            get: { state.settings.nodeDisplayMode },
                            set: { state.setNodeDisplayMode($0) }
                        )) {
                            ForEach(NodeDisplayMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 90)
                        .help("卡片 / 列表")

                        Text("\(state.filteredNodes.count)/\(state.nodes.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(BashXTheme.accentSoft(for: appearance))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var detailTabBar: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                detailTabChip(tab)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(appearance == .dark ? 0.18 : 0.05), radius: 6, y: 1)
        }
    }

    private func detailTabChip(_ tab: DetailTab) -> some View {
        let selected = detailTab == tab
        let accent = BashXTheme.accent(for: appearance)
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                detailTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(tab.title(lang: lang))
                    .font(.system(size: 11.5, weight: selected ? .bold : .medium, design: .rounded))
            }
            .foregroundStyle(selected ? Color.white : BashXTheme.secondaryLabel(for: appearance))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Group {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private var nodesPane: some View {
        PanelNodesHost(state: state) {
            nodesPaneContent
        }
    }

    private var nodesPaneContent: some View {
        VStack(spacing: 0) {
            nodesSmartSection
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

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

    private var nodesSmartSection: some View {
        let hubMode = pendingHubMode ?? state.settings.proxyHubMode
        let activeTint = nodesHubModeTint(hubMode)
        let testingAll = state.isTesting && state.speedTestScopeKey == nil
        let canTest = !state.nodes.isEmpty && !state.isTesting
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(activeTint.opacity(appearance == .dark ? 0.22 : 0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(activeTint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("mac.nodes.smart", lang))
                        .font(PanelMetrics.body)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(activeTint)
                            .frame(width: 4, height: 4)
                        Text(hubMode.title(lang: lang))
                            .font(PanelMetrics.micro)
                            .foregroundStyle(activeTint)
                    }
                    Text(L10n.t("mac.groups.hubHint", lang))
                        .font(PanelMetrics.micro)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    guard canTest else {
                        if state.nodes.isEmpty {
                            state.statusText = "请先更新订阅加载节点"
                        }
                        return
                    }
                    Task {
                        await state.runSpeedTest()
                        if state.settings.proxyHubMode == .smart || state.settings.autoSelectFastest {
                            await state.selectFastestNodeIfAvailable()
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        if testingAll {
                            ProgressView()
                                .controlSize(.small)
                                .tint(BashXTheme.accent(for: appearance))
                        } else {
                            Image(systemName: "gauge.with.dots.needle.67percent")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(testingAll
                             ? L10n.t("mac.nodes.speedBigBusy", lang)
                             : L10n.t("mac.nodes.speedAll", lang))
                            .font(PanelMetrics.micro)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(BashXTheme.accentSoft(for: appearance))
                    }
                }
                .buttonStyle(PanelPressButtonStyle())
                .opacity(canTest || testingAll ? 1 : 0.55)
                .help(state.nodes.isEmpty ? "没有可测速节点" : "测速全部节点")
            }

            HStack(spacing: 4) {
                ForEach([ProxyHubMode.smart, .loadBalance, .failover], id: \.self) { mode in
                    nodesHubModeCard(mode, activeMode: hubMode)
                }
            }
            if hubMode == .manual {
                Text(L10n.t("mac.nodes.hubManual.hint", lang))
                    .font(PanelMetrics.micro)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
        .onReceive(state.$hubModeRevision.receive(on: RunLoop.main)) { _ in
            // Keep optimistic highlight until settings catch up; only clear if modes match.
            if let pending = pendingHubMode, state.settings.proxyHubMode == pending {
                pendingHubMode = nil
            }
        }
    }

    private func nodesHubModeTint(_ mode: ProxyHubMode) -> Color {
        switch mode {
        case .smart:
            return Color(red: 0.22, green: 0.58, blue: 1.0)
        case .loadBalance:
            return Color(red: 0.18, green: 0.78, blue: 0.58)
        case .failover:
            return Color(red: 1.0, green: 0.52, blue: 0.22)
        case .manual:
            return BashXTheme.secondaryLabel(for: appearance)
        }
    }

    private func nodesHubModeCard(_ mode: ProxyHubMode, activeMode: ProxyHubMode) -> some View {
        let on = activeMode == mode
        let tint = nodesHubModeTint(mode)
        return Button {
            pendingHubMode = mode
            Task {
                await state.setProxyHubMode(mode)
                await MainActor.run {
                    if pendingHubMode == mode {
                        pendingHubMode = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: on
                                    ? [tint, tint.opacity(0.65)]
                                    : [tint.opacity(0.42), tint.opacity(0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 18, height: 18)
                        .shadow(color: on ? tint.opacity(0.45) : .clear, radius: 3, y: 1)
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title(lang: lang))
                        .font(.system(size: 9.5, weight: on ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(on ? tint : BashXTheme.primaryLabel(for: appearance))
                        .lineLimit(1)
                    Text(mode.subtitle(lang: lang))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(on ? tint.opacity(0.85) : BashXTheme.tertiaryLabel(for: appearance))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background {
                Group {
                    if on {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(appearance == .dark ? 0.38 : 0.22),
                                        tint.opacity(appearance == .dark ? 0.22 : 0.10),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: tint.opacity(0.28), radius: 5, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(BashXTheme.secondaryFill(for: appearance).opacity(0.55))
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .background(Circle().fill(BashXTheme.card(for: appearance)).padding(-1))
                        .offset(x: 2, y: -3)
                }
            }
            .scaleEffect(on ? 1.02 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PanelPressButtonStyle())
        .help("\(mode.subtitle(lang: lang)) — 切换 PROXY 策略（智能选路/负载均衡/故障转移）")
        .animation(.spring(response: 0.22, dampingFraction: 0.84), value: on)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(key: nil, title: "全部", flag: "🌐", count: state.nodes.count)
                ForEach(state.categorySummary, id: \.key) { item in
                    categoryChip(key: item.key, title: item.title, flag: item.flag, count: item.count)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .background(BashXTheme.sidebarTint(for: appearance).opacity(0.55))
    }

    private func categoryChip(key: String?, title: String, flag: String, count: Int) -> some View {
        let selected = state.selectedCategoryKey == key
        return Button {
            state.selectedCategoryKey = key
        } label: {
            HStack(spacing: 3) {
                Text(flag).font(.system(size: 11))
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium, design: .rounded))
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? BashXTheme.accent(for: appearance) : BashXTheme.tertiaryLabel(for: appearance))
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? BashXTheme.accentSoft(for: appearance) : BashXTheme.card(for: appearance))
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? BashXTheme.accent(for: appearance).opacity(0.40) : BashXTheme.separator(for: appearance), lineWidth: selected ? 1 : 0.5)
            )
        }
        .buttonStyle(PanelPressButtonStyle())
        .help(key == nil ? "显示全部地区" : "按地区筛选")
        .contextMenu {
            if let key {
                Button("测速「\(title)」") {
                    Task { await state.runSpeedTest(forCategoryKey: key) }
                }
                .disabled(state.isTesting || count == 0)
            }
        }
        .animation(nil, value: selected)
    }

    private var subscriptionsPane: some View {
        PanelSubscriptionsHost(state: state) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    subscriptionsHeader

                    if state.settings.subscriptions.isEmpty {
                        subscriptionsEmptyState
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(state.settings.subscriptions) { sub in
                                SubscriptionManageCard(
                                    subscriptionId: sub.id,
                                    index: state.settings.subscriptions.firstIndex(where: { $0.id == sub.id }) ?? 0
                                )
                                .environmentObject(state)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .transaction { $0.animation = nil }
        }
    }

    private var subscriptionsHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("订阅")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("\(state.settings.subscriptions.filter(\.enabled).count)/\(state.settings.subscriptions.count) 启用 · 勾选左侧可多选合并")
                    .font(PanelMetrics.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            Spacer()
            Button {
                Task { await state.updateAllSubscriptions() }
            } label: {
                Label(state.isBusy ? "更新中…" : "全部更新", systemImage: "arrow.clockwise")
                    .font(PanelMetrics.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state.isBusy || state.settings.subscriptions.isEmpty)
            Button {
                openAddSubscription()
            } label: {
                Label("添加订阅", systemImage: "plus")
                    .font(PanelMetrics.caption)
                    .fontWeight(.semibold)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(BashXTheme.accent(for: appearance))
            .contentShape(Rectangle())
        }
        .padding(.bottom, 1)
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

    private var nodesOptionsMenu: some View {
        Menu {
            Button {
                state.setNodeDisplayMode(.list)
            } label: {
                Label("列表视图", systemImage: state.settings.nodeDisplayMode == .list ? "checkmark" : "list.bullet")
            }
            Button {
                state.setNodeDisplayMode(.card)
            } label: {
                Label("卡片视图", systemImage: state.settings.nodeDisplayMode == .card ? "checkmark" : "square.grid.2x2")
            }
            Divider()
            Button {
                sortByDelayBinding.wrappedValue = true
            } label: {
                Label("按延迟排序", systemImage: state.sortByDelay ? "checkmark" : "timer")
            }
            Button {
                sortByDelayBinding.wrappedValue = false
            } label: {
                Label("按名称排序", systemImage: state.sortByDelay ? "textformat" : "checkmark")
            }
            Divider()
            Button {
                Task { await state.runSpeedTest() }
            } label: {
                Label(state.isTesting ? "测速中…" : "全部测速", systemImage: "gauge.with.dots.needle.67percent")
            }
            .disabled(state.isTesting || state.nodes.isEmpty)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(BashXTheme.secondaryFill(for: appearance))
                }
        }
        .menuStyle(.borderlessButton)
        .help("视图与排序")
    }
}

/// Isolated rules editor — observes AppState so text appears immediately (MainView itself is not Observable).
private struct RulesEditorPane: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance

    private enum Layer: String, CaseIterable, Identifiable {
        case prepend = "自定义前置"
        case base = "基础规则"
        var id: String { rawValue }
    }

    @State private var layer: Layer = .base
    @State private var draft = ""
    @State private var prependDraft = ""
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

            Picker("", selection: $layer) {
                ForEach(Layer.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: layer) { _ in
                reloadActiveDraft()
            }

            if state.settings.proxyMode != .rule {
                Text("当前是\(state.settings.proxyMode.title)模式，分流规则不会生效。请在侧栏切回「规则」。")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.warn(for: appearance))
            } else if layer == .prepend {
                Text("Clash Verge Merge：自定义规则写在智能规则之上；更新订阅 /「应用智能规则」不会覆盖本页。勿写 MATCH。")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            } else if state.settings.videoAdBlockEnabled {
                Text("已开启去广告：运行时会自动前置约 \(VideoAdBlock.ruleCount) 条 REJECT（含视频站与电商跳转，编辑区不显示）。")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            ZStack {
                TextEditor(text: activeDraftBinding)
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
                if layer == .base {
                    Button("应用智能规则 v\(ChinaSmartRules.version)") {
                        Task {
                            await state.applyChinaSmartRules()
                            reloadFromState()
                        }
                    }
                    .controlSize(.small)
                    .help("仅覆盖「基础规则」；自定义前置规则保留")
                } else {
                    Button("清空前置") {
                        prependDraft = ""
                        scheduleValidate()
                    }
                    .controlSize(.small)
                    .disabled(prependDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()

                Button("保存并生效") {
                    Task { await saveActive() }
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(!dirty && issues.isEmpty)
            }
        }
        .padding(16)
        .onAppear { reloadFromState() }
        .onReceive(state.$rulesText.receive(on: RunLoop.main)) { text in
            guard layer == .base, !dirty, text != draft, !text.isEmpty else { return }
            draft = text
            refreshMeta(for: text)
        }
    }

    private var activeDraftBinding: Binding<String> {
        Binding(
            get: { layer == .prepend ? prependDraft : draft },
            set: { newValue in
                if layer == .prepend {
                    prependDraft = newValue
                } else {
                    draft = newValue
                    state.rulesText = newValue
                }
                scheduleValidate()
            }
        )
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
        prependDraft = state.settings.rulesPrepend.joined(separator: "\n")
        ready = true
        reloadActiveDraft()
    }

    private func reloadActiveDraft() {
        let text = layer == .prepend ? prependDraft : draft
        refreshMeta(for: text)
    }

    private func saveActive() async {
        if layer == .prepend {
            await state.saveRulesPrependFromEditor(prependDraft)
            prependDraft = state.settings.rulesPrepend.joined(separator: "\n")
        } else {
            state.rulesText = draft
            await state.saveRulesFromEditor()
            draft = state.rulesText
        }
        reloadActiveDraft()
    }

    private func scheduleValidate() {
        validateTask?.cancel()
        validateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let text = layer == .prepend ? prependDraft : draft
            refreshMeta(for: text)
        }
    }

    private func refreshMeta(for text: String) {
        let parsed = ClashRuleSyntax.parseLines(text)
        if layer == .prepend {
            dirty = parsed != state.settings.rulesPrepend
        } else {
            dirty = parsed != state.settings.rules
        }
        issues = ClashRuleSyntax.validate(text)
        let prependCount = state.settings.rulesPrepend.count
        let baseCount = layer == .base ? parsed.count : state.settings.rules.count
        let extra = state.settings.videoAdBlockEnabled ? VideoAdBlock.ruleCount : 0
        let runtime = (layer == .prepend ? parsed.count : prependCount) + baseCount + extra
        var parts: [String] = []
        if state.settings.rulesVersion > 0 {
            parts.append("智能规则基准 v\(state.settings.rulesVersion)")
        }
        parts.append("前置 \(layer == .prepend ? parsed.count : prependCount) 条")
        parts.append("基础 \(baseCount) 条")
        parts.append("生效约 \(runtime) 条")
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
                    .font(PanelMetrics.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 48, maxWidth: 120, alignment: .trailing)
            }
        }
        .onAppear { text = state.statusText }
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            let next = state.statusText
            if next != text { text = next }
        }
        .transaction { $0.animation = nil }
    }
}

/// Sidebar traffic — isolated so only this block redraws on ~1Hz ticks.
private struct PanelSidebarTraffic: View {
    @ObservedObject var panel: PanelRateStore
    @Environment(\.bashxAppearance) private var appearance
    let coreRunning: Bool
    var onOpenMonitor: () -> Void

    private var live: Bool { panel.isLive && coreRunning }
    private var downTint: Color { BashXTheme.accent(for: appearance) }
    private var upTint: Color { Color(red: 0.98, green: 0.58, blue: 0.28) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(downTint.opacity(appearance == .dark ? 0.28 : 0.16))
                        .frame(width: 24, height: 24)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(downTint)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("实时流量")
                        .font(PanelMetrics.body)
                    Text(live ? "点击查看监控" : "等待内核连接")
                        .font(PanelMetrics.micro)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Circle()
                        .fill(live ? BashXTheme.good(for: appearance) : BashXTheme.tertiaryLabel(for: appearance))
                        .frame(width: 5, height: 5)
                    Text(live ? "LIVE" : "OFF")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(live ? BashXTheme.good(for: appearance) : BashXTheme.tertiaryLabel(for: appearance))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule(style: .continuous)
                        .fill(live
                              ? BashXTheme.good(for: appearance).opacity(0.14)
                              : BashXTheme.secondaryFill(for: appearance))
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 9)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenMonitor)

            TrafficChartView(
                samples: panel.samples,
                downTint: downTint,
                upTint: upTint,
                appearance: appearance,
                live: live,
                style: .compact
            )
            .frame(height: 72)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenMonitor)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    ratePill(symbol: "arrow.down", value: panel.downMbps, tint: downTint)
                    ratePill(symbol: "arrow.up", value: panel.upMbps, tint: upTint)
                }
                TrafficSessionTotalsView(
                    panel: panel,
                    downTint: downTint,
                    upTint: upTint,
                    appearance: appearance,
                    compact: true
                )
                .padding(.horizontal, 1)
            }
            .padding(.horizontal, 9)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .background {
            RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    downTint.opacity(live ? 0.28 : 0.10),
                                    upTint.opacity(live ? 0.14 : 0.05),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        }
        .help("点击查看流量监控；累积行双击重置")
        .transaction { $0.animation = nil }
    }

    private func ratePill(symbol: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text("\(value)/s")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(appearance == .dark ? 0.16 : 0.10))
        }
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
            .onReceive(state.$chromeRevision.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
            .onReceive(state.$hubModeRevision.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
            .onReceive(state.$isTesting.receive(on: RunLoop.main)) { _ in
                revision &+= 1
            }
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
    @State private var testingTick = 0

    var body: some View {
        let _ = testingTick
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
        .onReceive(state.$isTesting.receive(on: RunLoop.main)) { _ in
            testingTick &+= 1
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
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 1)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelect(node.name) }
                                }
                            }
                        } header: {
                            categoryHeader(group)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .background(BashXTheme.card(for: appearance))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .contextMenu {
                Button("复制节点信息") { state.copySelectedProxyLine() }
                Button("打开配置目录") { state.openConfigFolder() }
            }
        }
    }

    private var cardPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5, pinnedViews: [.sectionHeaders]) {
                ForEach(groups) { group in
                    Section {
                        if !collapsed.contains(group.key) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 156, maximum: 260), spacing: 8)],
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
                        categoryHeader(group)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(BashXTheme.canvas(for: appearance))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func categoryHeader(_ group: NodeCategory.Group) -> some View {
        let isCollapsed = collapsed.contains(group.key)
        let best = group.nodes.lazy.compactMap(\.delayMs).filter { $0 > 0 }.min()
        return HStack(spacing: 6) {
            Button {
                toggle(group.key)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                        .frame(width: 9)
                    Text(group.flag)
                        .font(.system(size: 11))
                    Text(group.title)
                        .font(PanelMetrics.caption)
                        .fontWeight(.semibold)
                    Text("\(group.nodes.count)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    Spacer(minLength: 4)
                    if let best {
                        Text("\(best) ms")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(BashXTheme.delayColor(best, appearance: appearance))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelPressButtonStyle())

            Button {
                Task {
                    await state.runSpeedTest(nodes: group.nodes, label: group.title, groupKey: group.key)
                    await state.selectFastestNodeIfAvailable()
                }
            } label: {
                HStack(spacing: 4) {
                    if state.isTesting && state.speedTestScopeKey == group.key {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text(state.isTesting && state.speedTestScopeKey == group.key ? "测速中" : "测速")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    Capsule(style: .continuous)
                        .fill(BashXTheme.accent(for: appearance))
                }
            }
            .buttonStyle(.plain)
            .disabled(state.isTesting || group.nodes.isEmpty)
            .help("仅测速「\(group.title)」分组（\(group.nodes.count) 个节点）")
        }
        .padding(.vertical, 3)
    }

    private func nodeCard(_ node: ProxyNode, group: NodeCategory.Group) -> some View {
        let selected = node.name == selectedNodeName
        let switching = switchingNodeName == node.name
        let highlighted = selected || switching
        let delay = node.delayMs
        return Button {
            onSelect(node.name)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(group.flag)
                        .font(.system(size: 14))
                        .frame(width: 18, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 11, weight: highlighted ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(node.name)
                        Text(group.title)
                            .font(PanelMetrics.micro)
                            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                            .lineLimit(1)
                    }

                    if switching {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    } else if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BashXTheme.accent(for: appearance))
                    }
                }

                HStack(spacing: 5) {
                    Text(shortType(node.type))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(highlighted ? BashXTheme.accent(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(highlighted
                                      ? BashXTheme.accent(for: appearance).opacity(0.14)
                                      : BashXTheme.secondaryFill(for: appearance))
                        )
                    Spacer(minLength: 0)
                    Text(delayText(delay))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(
                            delay.map { BashXTheme.delayColor($0, appearance: appearance) }
                                ?? BashXTheme.tertiaryLabel(for: appearance)
                        )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                    .fill(highlighted ? BashXTheme.accentSoft(for: appearance) : BashXTheme.card(for: appearance))
                    .overlay(
                        RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
                            .strokeBorder(
                                highlighted
                                    ? BashXTheme.accent(for: appearance).opacity(0.40)
                                    : BashXTheme.separator(for: appearance),
                                lineWidth: highlighted ? 1 : 0.5
                            )
                    )
            }
        }
        .buttonStyle(PanelPressButtonStyle())
        .help(node.name)
    }

    private func delayText(_ delay: Int?) -> String {
        guard let ms = delay else { return "—" }
        if ms < 0 { return "超时" }
        return "\(ms) ms"
    }

    private func nodeRow(_ node: ProxyNode, index: Int) -> some View {
        let selected = node.name == selectedNodeName
        let switching = switchingNodeName == node.name
        let highlighted = selected || switching
        return HStack(spacing: 8) {
            Group {
                if switching {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Circle()
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 1)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 16)

            Text(node.name)
                .font(.system(size: 12, weight: highlighted ? .semibold : .regular, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(shortType(node.type))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                .frame(width: 48, alignment: .center)

            delayBadge(node)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? BashXTheme.accentSoft(for: appearance).opacity(0.5) : Color.clear)
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
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 52, alignment: .trailing)
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
