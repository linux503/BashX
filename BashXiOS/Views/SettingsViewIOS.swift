import SwiftUI

struct SettingsViewIOS: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @State private var showTunnelLog = false
    @State private var tunnelLogText = ""

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if IOSIconManager.supportsAlternateIcons {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("专为手机主屏幕优化的 8 款图标。切换后桌面图标会立即更换；若仍是空白，请删掉 App 重装一次。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            IOSLogoStylePicker(selection: Binding(
                                get: { state.settings.logoStyle },
                                set: { state.setLogoStyle($0) }
                            ))
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    } else {
                        Text("当前系统不支持更换图标")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("App 图标")
                }

                Section {
                    LabeledContent("连接", value: vpn.statusText)
                    if vpn.isConnected {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            LabeledContent("时长") {
                                Text(IOSTheme.formatDuration(vpn.connectionDuration))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("下行累计") {
                            Text(ByteFormat.size(vpn.downloadBytes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("上行累计") {
                            Text(ByteFormat.size(vpn.uploadBytes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("节点") {
                        Text(state.settings.selectedNodeName ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    LabeledContent("出站 IP") {
                        HStack(spacing: 8) {
                            Text(state.outboundIPLoading ? "查询中…" : state.outboundIP)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button {
                                Task { await state.refreshOutboundIP() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!vpn.isConnected)
                        }
                    }
                } header: {
                    Text("连接")
                }

                Section {
                    Button {
                        Task { await vpn.reconnect() }
                    } label: {
                        Label("重新连接 VPN", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(vpn.isBusyConnecting)

                    Button(role: .destructive) {
                        vpn.disconnect()
                    } label: {
                        Label("断开 VPN", systemImage: "xmark.circle")
                    }
                    .disabled(!vpn.isConnected && !vpn.isBusyConnecting)
                }

                Section {
                    Stepper(value: $state.settings.testTimeoutMs, in: 1000...8000, step: 500) {
                        LabeledContent("超时") {
                            Text("\(state.settings.testTimeoutMs) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $state.settings.concurrency, in: 2...16) {
                        LabeledContent("并发") {
                            Text("\(state.settings.concurrency)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("测速")
                }

                Section {
                    Picker("DNS", selection: Binding(
                        get: { state.settings.dnsPreference },
                        set: { state.setDnsPreference($0) }
                    )) {
                        ForEach(DnsPreference.allCases) { pref in
                            Text(pref.title).tag(pref)
                        }
                    }
                    Text(state.settings.dnsPreference.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("DNS")
                } footer: {
                    Text("修改 DNS 后请重新连接 VPN。")
                }

                Section {
                    LabeledContent("规则版本") {
                        Text("v\(state.settings.rulesVersion > 0 ? state.settings.rulesVersion : ChinaSmartRules.version)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    LabeledContent("生效条数") {
                        Text("\(state.effectiveRuntimeRules().count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Toggle("视频广告过滤", isOn: Binding(
                        get: { state.settings.videoAdBlockEnabled },
                        set: { state.setVideoAdBlock($0) }
                    ))
                    Button {
                        state.applySmartRules()
                    } label: {
                        Label("恢复智能规则 v\(ChinaSmartRules.version)", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("分流")
                } footer: {
                    Text("规则模式：国内微信/QQ 等直连，谷歌/Telegram 等走代理。全局模式全部走代理。")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("控制中心快捷开关", systemImage: "switch.2")
                            .font(.body.weight(.semibold))
                        Text("下拉控制中心 → 左上角「编辑」→ 添加「BashX VPN」，即可一键连接/断开。也可在「快捷指令」里搜索 BashX。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text("快捷控制")
                }

                Section {
                    LabeledContent("App Group") {
                        statusBadge(Paths.usesAppGroup ? "正常" : "异常", ok: Paths.usesAppGroup)
                    }
                    if let err = MihomoConfigCheck.validateFile() {
                        Text("配置：\(err)")
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.bad)
                    }
                    if let tunnelErr = TunnelDiagnostics.lastFailureMessage() {
                        Text("上次错误：\(tunnelErr)")
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.bad)
                    }
                    Button {
                        tunnelLogText = TunnelLogReader.lastLines()
                        showTunnelLog = true
                    } label: {
                        Label("隧道日志", systemImage: "doc.text")
                    }
                } header: {
                    Text("诊断")
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                } header: {
                    Text("关于")
                } footer: {
                    Text("BashX for iOS · Network Extension + Mihomo")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .tint(IOSTheme.accent)
            .onChange(of: state.settings.testTimeoutMs) { _ in state.persist() }
            .onChange(of: state.settings.concurrency) { _ in state.persist() }
            .sheet(isPresented: $showTunnelLog) {
                NavigationStack {
                    ScrollView {
                        Text(tunnelLogText.isEmpty ? "（无日志）" : tunnelLogText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(IOSTheme.groupedBackground)
                    .navigationTitle("隧道日志")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("刷新") {
                                tunnelLogText = TunnelLogReader.lastLines()
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: tunnelLogText.isEmpty ? "（无日志）" : tunnelLogText)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showTunnelLog = false }
                        }
                    }
                    .task {
                        // Also pull live copy from the extension if connected.
                        if let live = await vpn.fetchTunnelLog() {
                            tunnelLogText = live
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ok ? IOSTheme.good : IOSTheme.bad)
    }
}
