import SwiftUI

struct SettingsViewIOS: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @State private var showTunnelLog = false
    @State private var tunnelLogText = ""

    private var lang: AppLanguage { state.settings.uiLanguage }

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(t("lang.title"), selection: Binding(
                        get: { state.settings.uiLanguage },
                        set: { state.setUiLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(item.pickerTitle).tag(item)
                        }
                    }
                } header: {
                    Text(t("ios.sec.language"))
                } footer: {
                    Text(t("lang.footer"))
                }

                Section {
                    Toggle(t("ios.disguise.toggle"), isOn: Binding(
                        get: { state.settings.iosDisguiseEnabled },
                        set: { state.setDisguiseEnabled($0) }
                    ))
                    if state.settings.iosDisguiseEnabled {
                        Text(t("ios.disguise.hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            state.lockApp()
                        } label: {
                            Label(t("ios.disguise.lockNow"), systemImage: "lock.fill")
                        }
                    }
                } header: {
                    Text(t("ios.sec.privacy"))
                }

                Section {
                    if IOSIconManager.supportsAlternateIcons {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(t("ios.icon.hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            IOSLogoStylePicker(selection: Binding(
                                get: { state.settings.logoStyle },
                                set: { state.setLogoStyle($0) }
                            ))
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    } else {
                        Text(t("ios.icon.unsupported"))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(t("ios.sec.icon"))
                }

                Section {
                    LabeledContent(t("ios.conn.status"), value: vpn.statusText)
                    if vpn.isConnected {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            LabeledContent(t("ios.conn.duration")) {
                                Text(IOSTheme.formatDuration(vpn.connectionDuration))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent(t("ios.conn.down")) {
                            Text(ByteFormat.size(vpn.downloadBytes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent(t("ios.conn.up")) {
                            Text(ByteFormat.size(vpn.uploadBytes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(t("ios.conn.node")) {
                        Text(state.settings.selectedNodeName ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    LabeledContent(t("ios.conn.ip")) {
                        HStack(spacing: 8) {
                            Text(state.outboundIPLoading ? t("common.loading") : state.outboundIP)
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
                    Text(t("ios.sec.connection"))
                }

                Section {
                    Button {
                        Task { await vpn.reconnect() }
                    } label: {
                        Label(t("ios.conn.reconnect"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(vpn.isBusyConnecting)

                    Button(role: .destructive) {
                        vpn.disconnect()
                    } label: {
                        Label(t("ios.conn.disconnect"), systemImage: "xmark.circle")
                    }
                    .disabled(!vpn.isConnected && !vpn.isBusyConnecting)
                }

                Section {
                    Stepper(value: $state.settings.testTimeoutMs, in: 1000...8000, step: 500) {
                        LabeledContent(t("ios.speed.timeout")) {
                            Text("\(state.settings.testTimeoutMs) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $state.settings.concurrency, in: 2...16) {
                        LabeledContent(t("ios.speed.concurrency")) {
                            Text("\(state.settings.concurrency)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text(t("ios.sec.speed"))
                }

                Section {
                    Picker(t("ios.proxy.picker"), selection: Binding(
                        get: { state.settings.iosTunnelCapture ? "tun" : "proxy" },
                        set: { state.setIosTunnelCapture($0 == "tun") }
                    )) {
                        Text(t("ios.proxy.tun")).tag("tun")
                        Text(t("ios.proxy.http")).tag("proxy")
                    }
                    Text(state.settings.iosTunnelCapture ? t("ios.proxy.tun.hint") : t("ios.proxy.http.hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(t("ios.sec.proxyMode"))
                } footer: {
                    Text(String(format: t("ios.proxy.footer"), "\(AppConstants.mixedPort)"))
                }

                Section {
                    Picker("DNS", selection: Binding(
                        get: { state.settings.dnsPreference },
                        set: { state.setDnsPreference($0) }
                    )) {
                        ForEach(DnsPreference.allCases) { pref in
                            Text(pref.title(lang: lang)).tag(pref)
                        }
                    }
                    Text(state.settings.dnsPreference.subtitle(lang: lang))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(t("ios.sec.dns"))
                } footer: {
                    Text(t("ios.dns.footer"))
                }

                Section {
                    LabeledContent(t("ios.routing.version")) {
                        Text("v\(state.settings.rulesVersion > 0 ? state.settings.rulesVersion : ChinaSmartRules.version)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    LabeledContent(t("ios.routing.count")) {
                        Text("\(state.effectiveRuntimeRules().count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Toggle(t("ios.routing.adblock"), isOn: Binding(
                        get: { state.settings.videoAdBlockEnabled },
                        set: { state.setVideoAdBlock($0) }
                    ))
                    Button {
                        state.applySmartRules()
                    } label: {
                        Label(
                            String(format: t("ios.routing.restore"), "\(ChinaSmartRules.version)"),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                } header: {
                    Text(t("ios.sec.routing"))
                } footer: {
                    Text(t("ios.routing.footer"))
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(t("ios.controls.title"), systemImage: "switch.2")
                            .font(.body.weight(.semibold))
                        Text(t("ios.controls.body"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: {
                    Text(t("ios.sec.controls"))
                }

                Section {
                    LabeledContent("App Group") {
                        statusBadge(
                            Paths.usesAppGroup ? t("ios.diag.config.ok") : t("ios.diag.config.missing"),
                            ok: Paths.usesAppGroup
                        )
                    }
                    if let err = MihomoConfigCheck.validateFile() {
                        Text("\(t("ios.diag.config"))：\(err)")
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.bad)
                    }
                    if let tunnelErr = TunnelDiagnostics.lastFailureMessage() {
                        Text(tunnelErr)
                            .font(.footnote)
                            .foregroundStyle(IOSTheme.bad)
                    }
                    Button {
                        tunnelLogText = TunnelLogReader.lastLines()
                        showTunnelLog = true
                    } label: {
                        Label(t("ios.diag.log"), systemImage: "doc.text")
                    }
                } header: {
                    Text(t("ios.sec.diagnostics"))
                }

                Section {
                    LabeledContent(t("ios.about.version"), value: appVersion)
                } header: {
                    Text(t("ios.sec.about"))
                } footer: {
                    Text(t("ios.about.footer"))
                }
            }
            .navigationTitle(t("ios.settings.nav"))
            .navigationBarTitleDisplayMode(.large)
            .tint(IOSTheme.accent)
            .id(lang.id)
            .onChange(of: state.settings.testTimeoutMs) { _ in state.persist() }
            .onChange(of: state.settings.concurrency) { _ in state.persist() }
            .sheet(isPresented: $showTunnelLog) {
                NavigationStack {
                    ScrollView {
                        Text(tunnelLogText.isEmpty ? t("ios.diag.log.empty") : tunnelLogText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(IOSTheme.groupedBackground)
                    .navigationTitle(t("ios.diag.log"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("common.done")) { showTunnelLog = false }
                        }
                    }
                    .task {
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
