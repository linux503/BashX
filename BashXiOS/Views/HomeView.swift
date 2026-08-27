import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @State private var showNodePicker = false

    var body: some View {
        GeometryReader { geo in
            let buttonOuter = min(200, geo.size.width * 0.48)
            let buttonInner = min(172, geo.size.width * 0.42)

            ZStack {
                background.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Spacer(minLength: 10)

                    connectHero(outer: buttonOuter, inner: buttonInner)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 10)

                    bottomPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? 0 : 8)
            }
        }
        .sheet(isPresented: $showNodePicker) {
            NodeQuickPickerSheet()
                .environmentObject(state)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.88, green: 0.95, blue: 0.95),
                    Color(red: 0.95, green: 0.98, blue: 0.98),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(IOSTheme.accent.opacity(vpn.isConnected ? 0.20 : 0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 48)
                .offset(y: -60)
                .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BashX")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(IOSTheme.ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(vpn.isConnected ? IOSTheme.good : (vpn.isBusyConnecting ? IOSTheme.warn : Color.secondary.opacity(0.45)))
                        .frame(width: 7, height: 7)
                    Text(vpn.statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(vpn.isConnected ? IOSTheme.good : .secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                Task { await state.updateAllSubscriptions() }
            } label: {
                Group {
                    if state.isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(IOSTheme.accentDeep)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.9)))
            }
            .disabled(state.isBusy)
            .accessibilityLabel("更新订阅")
        }
    }

    private func connectHero(outer: CGFloat, inner: CGFloat) -> some View {
        VStack(spacing: 16) {
            Button {
                Task { await state.toggleVPN() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 12)
                        .frame(width: outer, height: outer)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: vpn.isConnected
                                    ? [IOSTheme.good, IOSTheme.accentDeep]
                                    : vpn.isBusyConnecting
                                    ? [IOSTheme.warn, IOSTheme.accent]
                                    : [IOSTheme.accent, IOSTheme.accentDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: inner, height: inner)
                        .shadow(color: (vpn.isConnected ? IOSTheme.good : IOSTheme.accent).opacity(0.38), radius: 20, y: 10)

                    VStack(spacing: 8) {
                        if vpn.isBusyConnecting || state.isPreparingGeodata {
                            ProgressView().tint(.white).scaleEffect(1.15)
                        } else {
                            Image(systemName: vpn.isConnected ? "checkmark" : "power")
                                .font(.system(size: 40, weight: .bold))
                        }
                        Text(vpn.isConnected ? "已连接" : (state.isPreparingGeodata ? "准备中" : vpn.isBusyConnecting ? "请稍候" : "连接"))
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled((state.nodes.isEmpty && !vpn.isConnected) || state.isPreparingGeodata)
            .opacity(state.nodes.isEmpty && !vpn.isConnected ? 0.5 : 1)
            .accessibilityLabel(vpn.isConnected ? "断开 VPN" : "连接 VPN")

            Button {
                showNodePicker = true
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(state.settings.selectedNodeName ?? "未选择节点")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(IOSTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    if let node = state.selectedNode {
                        Text("\(node.type.uppercased()) · \(node.delayText)")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(IOSTheme.delay(node.delayMs))
                    } else if state.nodes.isEmpty {
                        Text("先添加订阅并更新节点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("轻触切换节点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .disabled(state.nodes.isEmpty)

            if vpn.isConnected {
                HStack(spacing: 10) {
                    trafficPill(title: "↓", value: ByteFormat.size(vpn.downloadBytes))
                    trafficPill(title: "↑", value: ByteFormat.size(vpn.uploadBytes))
                    Button {
                        Task { await state.refreshOutboundIP() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            if state.outboundIPLoading {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Text(state.outboundIP)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                            }
                        }
                        .foregroundStyle(IOSTheme.ink.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }

            if let err = vpn.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(IOSTheme.bad)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vpn.isConnected)
    }

    private func trafficPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.caption.weight(.bold))
            Text(value).font(.caption.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(IOSTheme.ink.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.85)))
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            Picker("模式", selection: Binding(
                get: { state.settings.proxyMode },
                set: { state.setMode($0) }
            )) {
                ForEach(ProxyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                miniStat("节点", "\(state.nodes.count)")
                miniStat("订阅", "\(state.settings.subscriptions.count)")
                Button {
                    Task { await state.testSpeeds(selectFastest: true) }
                } label: {
                    VStack(spacing: 4) {
                        Text(state.isTesting ? "\(state.testedCount)" : "测速")
                            .font(.headline.monospacedDigit())
                        Text(state.isTesting ? "进行中" : "并选最快")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }
                .buttonStyle(.plain)
                .disabled(state.nodes.isEmpty || state.isTesting)
            }

            Text(state.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 16, y: -2)
        )
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
    }
}

struct NodeQuickPickerSheet: View {
    @EnvironmentObject private var state: IOSAppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let fastest = state.fastestNode {
                    Section("最快") {
                        Button {
                            state.selectNode(fastest.name)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fastest.name).foregroundStyle(.primary)
                                    Text(fastest.delayText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(IOSTheme.delay(fastest.delayMs))
                                }
                                Spacer()
                                Image(systemName: "bolt.fill").foregroundStyle(IOSTheme.accent)
                            }
                        }
                    }
                }
                ForEach(state.categoryGroups.prefix(8)) { group in
                    Section("\(group.flag) \(group.title)") {
                        ForEach(group.nodes.prefix(12)) { node in
                            Button {
                                state.selectNode(node.name)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(node.name).foregroundStyle(.primary).lineLimit(1)
                                    Spacer()
                                    Text(node.delayText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(IOSTheme.delay(node.delayMs))
                                    if state.settings.selectedNodeName == node.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(IOSTheme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
