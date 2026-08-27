import SwiftUI

/// Premium VPN home — brand → connect → location → live traffic.
struct HomeView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @State private var showNodePicker = false
    @State private var showQuickTools = false
    @State private var showModePicker = false
    @State private var brandAppear = false

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        NavigationStack {
            IOSPageBackground {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.top, 8)
                            .padding(.bottom, 16)

                        locationBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        proxyGroupsBar
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)

                        if vpn.isConnected {
                            IOSTrafficChart(
                                samples: vpn.trafficSamples,
                                uploadRate: vpn.uploadRate,
                                downloadRate: vpn.downloadRate,
                                uploadTotal: vpn.uploadBytes,
                                downloadTotal: vpn.downloadBytes,
                                isLive: true,
                                duration: vpn.connectionDuration
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        quickTools
                            .padding(.horizontal, 20)
                            .padding(.bottom, 36)
                    }
                }
                .background(Color.clear)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await state.updateAllSubscriptions() }
                        } label: {
                            if state.isBusy {
                                ProgressView().tint(IOSTheme.accent)
            .id(lang.id)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(IOSTheme.accentDeep)
                            }
                        }
                        .disabled(state.isBusy)
                        .accessibilityLabel(t("home.updateSubs"))
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .background(Color.clear)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: vpn.isConnected)
        .sheet(isPresented: $showNodePicker) {
            NodeQuickPickerSheet()
                .environmentObject(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showModePicker) {
            ProxyModePickerSheet(
                current: state.settings.proxyMode,
                onSelect: { mode in
                    state.setMode(mode)
                    showModePicker = false
                }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { brandAppear = true }
            if vpn.isConnected {
                state.scheduleProxyGroupsRefresh()
            }
        }
        .onChange(of: vpn.isConnected) { connected in
            if connected {
                state.scheduleProxyGroupsRefresh(delay: 0.6)
            }
        }
    }

    // MARK: - Hero (first viewport = one composition)

    private var heroLogoMark: some View {
        Group {
            if UIImage(named: state.settings.logoStyle.iosPreviewImageName) != nil {
                Image(state.settings.logoStyle.iosPreviewImageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(IOSTheme.accent)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: IOSTheme.accent.opacity(0.28), radius: 14, y: 6)
        .animation(.easeInOut(duration: 0.2), value: state.settings.logoStyle)
    }

    private var heroSection: some View {
        VStack(spacing: 20) {
            // Brand mark — hero-level, not nav chrome
            VStack(spacing: 10) {
                heroLogoMark
                    .scaleEffect(brandAppear ? 1 : 0.86)
                    .opacity(brandAppear ? 1 : 0)

                Text("BashX")
                    .font(IOSTheme.brandFont)
                    .foregroundStyle(IOSTheme.ink)
                    .tracking(-0.8)
                    .opacity(brandAppear ? 1 : 0)
                    .offset(y: brandAppear ? 0 : 8)

                Text(heroSubtitle)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .opacity(brandAppear ? 1 : 0)
            }

            IOSStatusPill(
                text: homeStatusText,
                tone: vpn.isConnected ? .connected : (vpn.isBusyConnecting ? .connecting : .idle)
            )
            .scaleEffect(brandAppear ? 1 : 0.9)
            .opacity(brandAppear ? 1 : 0)

            modePill
                .opacity(brandAppear ? 1 : 0)

            IOSConnectControl(
                isConnected: vpn.isConnected,
                isBusy: vpn.isBusyConnecting,
                isEnabled: true
            ) {
                Task { await state.toggleVPN() }
            }
            .padding(.top, 4)

            if state.nodes.isEmpty, !vpn.isConnected {
                firstUseGuide
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let err = vpn.lastError, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err).font(.caption).lineLimit(3)
                }
                .foregroundStyle(IOSTheme.bad)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous).fill(IOSTheme.bad.opacity(0.1))
                )
                .padding(.horizontal, 24)
            }

            if let hint = vpn.conflictVPNHint, !hint.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(IOSTheme.warn)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(IOSTheme.warn.opacity(0.12))
                )
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var homeStatusText: String {
        if vpn.isConnected || vpn.isBusyConnecting {
            return vpn.statusText
        }
        if state.nodes.isEmpty {
            return t("home.addSubFirst")
        }
        if state.settings.selectedNodeName == nil {
            return t("home.pickNode")
        }
        return vpn.statusText
    }

    private var heroSubtitle: String {
        if vpn.isConnected {
            return t("home.hero.connected")
        }
        if vpn.isBusyConnecting {
            return t("home.hero.connecting")
        }
        if state.nodes.isEmpty {
            return t("home.hero.empty")
        }
        return t("home.hero.ready")
    }

    private var modePill: some View {
        let current = state.settings.proxyMode
        let color = IOSTheme.proxyModeColor(current)
        return Button { showModePicker = true } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(current.title(lang: lang))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
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
        .accessibilityLabel(String(format: t("home.mode.a11y"), current.title(lang: lang)))
    }

    private var firstUseGuide: some View {
        VStack(spacing: 12) {
            Text(t("home.firstUse"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                guideStep(1, t("home.guide.1"))
                guideStep(2, t("home.guide.2"))
                guideStep(3, t("home.guide.3"))
            }
            Button {
                state.openAddSubscription()
            } label: {
                Text(t("home.goAddSub"))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(IOSTheme.accentGradient)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 24)
    }

    private func guideStep(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(IOSTheme.accent))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Location

    private var locationBar: some View {
        Button { showNodePicker = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(IOSTheme.accentGradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: IOSTheme.accent.opacity(0.35), radius: 8, y: 4)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(t("home.location"))
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(state.settings.selectedNodeName ?? t("home.selectNode"))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let node = state.selectedNode {
                        Text("\(node.type.uppercased()) · \(node.delayText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(IOSTheme.delay(node.delayMs))
                    } else if state.nodes.isEmpty {
                        Text(t("home.addSubFirst"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: t("home.nodesAvailable"), "\(state.nodes.count)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(IOSTheme.accent)
                    .padding(10)
                    .background(Circle().fill(IOSTheme.accentSoft))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
            }
        }
        .buttonStyle(.plain)
        .disabled(state.nodes.isEmpty)
        .opacity(state.nodes.isEmpty ? 0.55 : 1)
    }

    // MARK: - Proxy groups (GOOGLE / TELEGRAM / AUTO)

    @ViewBuilder
    private var proxyGroupsBar: some View {
        if !vpn.isConnected {
            EmptyView()
        } else if state.proxyGroups.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(t("home.loadingGroups"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(t("home.refresh")) {
                    state.scheduleProxyGroupsRefresh()
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(groupBarBackground)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("home.groups"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        state.scheduleProxyGroupsRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(IOSTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("home.refreshGroups"))
                }

                ForEach(state.proxyGroups) { group in
                    Menu {
                        ForEach(group.all.prefix(60), id: \.self) { name in
                            Button {
                                state.selectGroupProxy(group: group.name, name: name)
                            } label: {
                                if name == group.now {
                                    Label(shortGroupMember(name), systemImage: "checkmark")
                                } else {
                                    Text(shortGroupMember(name))
                                }
                            }
                        }
                        if group.all.count > 60 {
                            Text(String(format: t("home.groupsMore"), "\(group.all.count)"))
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(group.name)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(IOSTheme.accentDeep)
                                .frame(width: 88, alignment: .leading)
                            Text(shortGroupMember(group.now.isEmpty ? "—" : group.now))
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(groupBarBackground)
                    }
                }
            }
        }
    }

    private var groupBarBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(IOSTheme.cardStroke, lineWidth: 0.5)
            )
    }

    private func shortGroupMember(_ name: String) -> String {
        if name.count <= 22 { return name }
        return String(name.prefix(20)) + "…"
    }

    // MARK: - Quick tools (secondary, below fold)

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showQuickTools.toggle() }
            } label: {
                HStack {
                    Text(t("home.quick"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showQuickTools ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if showQuickTools {
                VStack(spacing: 12) {
                    dnsPicker
                    HStack(spacing: 10) {
                        miniTool(
                            title: t("home.test"),
                            icon: "gauge.with.dots.needle.50percent",
                            disabled: state.nodes.isEmpty || state.isTesting
                        ) { Task { await state.testSpeeds() } }
                        miniTool(
                            title: t("home.fastest"),
                            icon: "bolt.fill",
                            disabled: state.nodes.isEmpty || state.isTesting
                        ) { Task { await state.testSpeeds(selectFastest: true) } }
                        miniTool(
                            title: t("home.nodes"),
                            icon: "list.bullet",
                            disabled: false
                        ) { showNodePicker = true }
                    }
                    WebsiteProbeStrip()
                        .environmentObject(vpn)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 不展示「未连接/已连接」等 VPN 状态文案（状态pill 已有）；只留操作反馈。
            if shouldShowStatusHint(state.statusText) {
                Text(state.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func shouldShowStatusHint(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == L10n.t("status.ready", .zh) || t == L10n.t("status.ready", .en) {
            return false
        }
        let noise: Set<String> = [
            L10n.t("vpn.disconnected", .zh), L10n.t("vpn.disconnected", .en),
            L10n.t("vpn.connected", .zh), L10n.t("vpn.connected", .en),
            L10n.t("vpn.connecting", .zh), L10n.t("vpn.connecting", .en),
            L10n.t("connect.connecting", .zh), L10n.t("connect.connecting", .en),
            L10n.t("vpn.disconnecting", .zh), L10n.t("vpn.disconnecting", .en),
            L10n.t("vpn.reconnecting", .zh), L10n.t("vpn.reconnecting", .en),
            "未配置", "Not configured",
        ]
        return !noise.contains(t)
    }

    private var dnsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DNS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("DNS", selection: Binding(
                get: { state.settings.dnsPreference },
                set: { state.setDnsPreference($0) }
            )) {
                ForEach(DnsPreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(IOSTheme.cardBackground.opacity(0.7))
        }
    }

    private func miniTool(title: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(IOSTheme.accentDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(IOSTheme.accentSoft)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

struct NodeQuickPickerSheet: View {
    @EnvironmentObject private var state: IOSAppState
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        NavigationStack {
            List {
                if let fastest = state.fastestNode {
                    Section {
                        nodeButton(fastest, badge: t("home.fastest"))
                    }
                }
                ForEach(state.categoryGroups.prefix(10)) { group in
                    Section("\(group.flag) \(group.title)") {
                        ForEach(group.nodes.prefix(15)) { node in
                            nodeButton(node)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(t("home.pickLocation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.done")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("home.test")) { Task { await state.testSpeeds() } }
                        .disabled(state.isTesting || state.nodes.isEmpty)
                }
            }
        }
    }

    private func nodeButton(_ node: ProxyNode, badge: String? = nil) -> some View {
        Button {
            state.selectNode(node.name)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(node.name).foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(IOSTheme.accentSoft))
                                .foregroundStyle(IOSTheme.accentDeep)
                        }
                    }
                    Text(node.endpointSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(node.delayText)
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(IOSTheme.delay(node.delayMs))
                if state.settings.selectedNodeName == node.name {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(IOSTheme.accent)
                }
            }
        }
    }
}

// MARK: - Proxy mode picker

private struct ProxyModePickerSheet: View {
    let current: ProxyMode
    let onSelect: (ProxyMode) -> Void

    private func t(_ key: String) -> String { L10n.t(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("home.modeTitle"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(t("home.modeHint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                ForEach(ProxyMode.allCases) { mode in
                    let selected = mode == current
                    let color = IOSTheme.proxyModeColor(mode)
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(color.opacity(selected ? 0.22 : 0.12))
                                    .frame(width: 42, height: 42)
                                Image(systemName: modeIcon(mode))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(color)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(mode.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(color)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(selected ? color.opacity(0.55) : Color.clear, lineWidth: 1.5)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func modeIcon(_ mode: ProxyMode) -> String {
        switch mode {
        case .rule: return "slider.horizontal.3"
        case .global: return "globe.asia.australia.fill"
        case .direct: return "link"
        }
    }
}
