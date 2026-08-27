import SwiftUI

/// Premium VPN home — brand → connect → location → live traffic.
struct HomeView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @State private var showNodePicker = false
    @State private var showQuickTools = false
    @State private var brandAppear = false

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
                    ToolbarItem(placement: .topBarLeading) {
                        modeMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await state.updateAllSubscriptions() }
                        } label: {
                            if state.isBusy {
                                ProgressView().tint(IOSTheme.accent)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(IOSTheme.accentDeep)
                            }
                        }
                        .disabled(state.isBusy)
                        .accessibilityLabel("更新订阅")
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { brandAppear = true }
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
                text: vpn.statusText,
                tone: vpn.isConnected ? .connected : (vpn.isBusyConnecting ? .connecting : .idle)
            )
            .scaleEffect(brandAppear ? 1 : 0.9)
            .opacity(brandAppear ? 1 : 0)

            IOSConnectControl(
                isConnected: vpn.isConnected,
                isBusy: vpn.isBusyConnecting,
                isEnabled: !state.nodes.isEmpty || vpn.isConnected
            ) {
                Task { await state.toggleVPN() }
            }
            .padding(.top, 4)

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

    private var heroSubtitle: String {
        if vpn.isConnected {
            return "已加密连接 · 流量受保护"
        }
        if vpn.isBusyConnecting {
            return "正在建立安全隧道…"
        }
        if state.nodes.isEmpty {
            return "添加订阅后一键连接全球节点"
        }
        return "一键连接 · 智能分流保护隐私"
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
                    Text("连接位置")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(state.settings.selectedNodeName ?? "选择节点")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let node = state.selectedNode {
                        Text("\(node.type.uppercased()) · \(node.delayText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(IOSTheme.delay(node.delayMs))
                    } else if state.nodes.isEmpty {
                        Text("请先添加订阅")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(state.nodes.count) 个节点可用")
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

    // MARK: - Quick tools (secondary, below fold)

    private var quickTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showQuickTools.toggle() }
            } label: {
                HStack {
                    Text("快捷控制")
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
                            title: "测速",
                            icon: "gauge.with.dots.needle.50percent",
                            disabled: state.nodes.isEmpty || state.isTesting
                        ) { Task { await state.testSpeeds() } }
                        miniTool(
                            title: "最快",
                            icon: "bolt.fill",
                            disabled: state.nodes.isEmpty || state.isTesting
                        ) { Task { await state.testSpeeds(selectFastest: true) } }
                        miniTool(
                            title: "节点",
                            icon: "list.bullet",
                            disabled: false
                        ) { showNodePicker = true }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !state.statusText.isEmpty, state.statusText != "就绪" {
                Text(state.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var modeMenu: some View {
        let current = state.settings.proxyMode
        return Menu {
            ForEach(ProxyMode.allCases) { mode in
                Button {
                    state.setMode(mode)
                } label: {
                    if mode == current {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IOSTheme.proxyModeColor(current))
                Text(current.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThickMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.72))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
        }
        .accessibilityLabel("分流模式，当前\(current.title)")
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

    var body: some View {
        NavigationStack {
            List {
                if let fastest = state.fastestNode {
                    Section {
                        nodeButton(fastest, badge: "最快")
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
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("测速") { Task { await state.testSpeeds() } }
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
                    Text("\(node.type.uppercased()) · \(node.server)")
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
