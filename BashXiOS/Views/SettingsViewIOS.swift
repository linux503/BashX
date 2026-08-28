import SwiftUI

struct SettingsViewIOS: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager
    @State private var showAdvanced = false
    @State private var showTunnelLog = false
    @State private var tunnelLogText = ""

    private var lang: AppLanguage { state.settings.uiLanguage }

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var hasDiagnosticsIssue: Bool {
        MihomoConfigCheck.validateFile() != nil || TunnelDiagnostics.lastFailureMessage() != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                if IOSIconManager.supportsAlternateIcons {
                    iconSection
                }
                privacySection
                networkSection
                advancedSection
                aboutSection
            }
            .navigationTitle(t("ios.settings.nav"))
            .navigationBarTitleDisplayMode(.large)
            .tint(IOSTheme.accent)
            .id(lang.id)
            .onChange(of: state.settings.testTimeoutMs) { _ in state.persist() }
            .onChange(of: state.settings.concurrency) { _ in state.persist() }
            .sheet(isPresented: $showTunnelLog) {
                tunnelLogSheet
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
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
            Text(t("ios.sec.general"))
        }
    }

    private var iconSection: some View {
        Section {
            IOSLogoStylePicker(selection: Binding(
                get: { state.settings.logoStyle },
                set: { state.setLogoStyle($0) }
            ))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text(t("ios.sec.icon"))
        } footer: {
            Text(t("ios.icon.hint"))
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(t("ios.disguise.toggle"), isOn: Binding(
                get: { state.settings.iosDisguiseEnabled },
                set: { state.setDisguiseEnabled($0) }
            ))
            if state.settings.iosDisguiseEnabled {
                Button(role: .destructive) {
                    state.lockApp()
                } label: {
                    Label(t("ios.disguise.lockNow"), systemImage: "lock.fill")
                }
            }
        } header: {
            Text(t("ios.sec.privacy"))
        } footer: {
            if state.settings.iosDisguiseEnabled {
                Text(t("ios.disguise.hint"))
            }
        }
    }

    private var networkSection: some View {
        Section {
            Picker("DNS", selection: Binding(
                get: { state.settings.dnsPreference },
                set: { state.setDnsPreference($0) }
            )) {
                ForEach(DnsPreference.allCases) { pref in
                    Text(pref.title(lang: lang)).tag(pref)
                }
            }

            Toggle(t("ios.routing.adblock"), isOn: Binding(
                get: { state.settings.videoAdBlockEnabled },
                set: { state.setVideoAdBlock($0) }
            ))
        } header: {
            Text(t("ios.sec.network"))
        } footer: {
            Text(state.settings.dnsPreference.subtitle(lang: lang))
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(t("ios.sec.advanced"), isExpanded: $showAdvanced) {
                Picker(t("ios.proxy.picker"), selection: Binding(
                    get: { state.settings.iosTunnelCapture ? "tun" : "proxy" },
                    set: { state.setIosTunnelCapture($0 == "tun") }
                )) {
                    Text(t("ios.proxy.tun")).tag("tun")
                    Text(t("ios.proxy.http")).tag("proxy")
                }

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

                Button {
                    state.applySmartRules()
                } label: {
                    Label(
                        String(format: t("ios.routing.restore"), "\(ChinaSmartRules.version)"),
                        systemImage: "arrow.counterclockwise"
                    )
                }

                if hasDiagnosticsIssue {
                    diagnosticsBlock
                }

                Button {
                    tunnelLogText = TunnelLogReader.lastLines()
                    showTunnelLog = true
                } label: {
                    Label(t("ios.diag.log"), systemImage: "doc.text")
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticsBlock: some View {
        if let err = MihomoConfigCheck.validateFile() {
            Label {
                Text("\(t("ios.diag.config"))：\(err)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.footnote)
            .foregroundStyle(IOSTheme.bad)
        }
        if let tunnelErr = TunnelDiagnostics.lastFailureMessage() {
            Label {
                Text(tunnelErr)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.footnote)
            .foregroundStyle(IOSTheme.bad)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(t("ios.about.version"), value: appVersion)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("ios.about.footerShort"))
                Text(t("ios.controls.body"))
            }
        }
    }

    private var tunnelLogSheet: some View {
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
