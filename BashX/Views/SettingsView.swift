import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, speed, proxy, core, appearance, about

    var id: String { rawValue }

    var title: String { title(lang: .current) }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.t("mac.tab.general", lang)
        case .speed: return L10n.t("mac.tab.speed", lang)
        case .proxy: return L10n.t("mac.tab.proxy", lang)
        case .core: return L10n.t("mac.tab.core", lang)
        case .appearance: return L10n.t("mac.tab.appearance", lang)
        case .about: return L10n.t("mac.tab.about", lang)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @ObservedObject private var updater = AppUpdateController.shared
    @State private var tab: SettingsTab = .general

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        BashXThemed(appearance: state.settings.appearance) {
            SettingsCardShell {
                VStack(spacing: 0) {
                    settingsTabBar
                    Divider().opacity(0.45)
                    Group {
                        switch tab {
                        case .general: generalTab
                        case .speed: speedTestTab
                        case .proxy: proxyTab
                        case .core: coreTab
                        case .appearance: appearanceTab
                        case .about: aboutTab
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .onAppear { state.refreshLaunchAtLogin() }
        .onDisappear {
            let port = min(65535, max(1024, state.settings.mixedPort))
            if port != state.settings.mixedPort {
                state.settings.mixedPort = port
            }
            state.persist()
            state.writeConfig()
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.title(lang: lang))
                        .font(.system(size: 13, weight: tab == item ? .semibold : .medium))
                        .foregroundStyle(tab == item ? BashXTheme.accent(for: appearance) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tab == item ? BashXTheme.accent(for: appearance).opacity(0.12) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - 常用

    private var generalTab: some View {
        Form {
            Section(t("mac.sec.proxyMode")) {
                HStack(spacing: 10) {
                    ForEach(ProxyMode.allCases) { mode in
                        settingsProxyModeButton(mode)
                    }
                }
                .padding(.vertical, 6)

                Toggle(t("mac.sec.systemProxy"), isOn: Binding(
                    get: { state.systemProxyOn },
                    set: { v in Task { await state.setSystemProxy(v) } }
                ))
                Text(t("mac.systemProxy.hint").replacingOccurrences(of: "%@", with: "\(state.settings.mixedPort)"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                if SystemProxy.hasSnapshot() {
                    Button(t("mac.restoreProxy")) {
                        let ok = SystemProxy.restoreFromSnapshot()
                        state.statusText = ok ? t("mac.restoreProxy.ok") : t("mac.restoreProxy.none")
                    }
                }

                Toggle(t("mac.closeConnOnSwitch"), isOn: Binding(
                    get: { state.settings.closeConnectionsOnSwitch },
                    set: { state.setCloseConnectionsOnSwitch($0) }
                ))
                Text(t("mac.closeConnOnSwitch.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Toggle(t("mac.tun"), isOn: Binding(
                    get: { state.settings.tunEnabled },
                    set: { v in Task { await state.setTUN(v) } }
                ))
                Text(t("mac.tun.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                HStack {
                    Text(TunPrivilege.statusText)
                        .font(.caption)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button(TunPrivilege.isReady ? t("mac.tun.reinstall") : t("mac.tun.install")) {
                        do {
                            try TunPrivilege.install()
                            state.statusText = t("mac.tun.ready")
                        } catch {
                            state.statusText = error.localizedDescription
                        }
                    }
                    if TunPrivilege.isInstalledOnDisk {
                        Button(t("mac.tun.remove"), role: .destructive) {
                            do {
                                try TunPrivilege.uninstall()
                                state.statusText = t("mac.tun.removed")
                            } catch {
                                state.statusText = error.localizedDescription
                            }
                        }
                    }
                }

                Toggle(t("mac.adblock"), isOn: Binding(
                    get: { state.settings.videoAdBlockEnabled },
                    set: { v in Task { await state.setVideoAdBlock(v) } }
                ))
                Text(t("mac.adblock.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Toggle(t("mac.httpSubs"), isOn: Binding(
                    get: { state.settings.allowInsecureHTTPSubscriptions },
                    set: {
                        state.settings.allowInsecureHTTPSubscriptions = $0
                        state.persist()
                        state.statusText = $0 ? t("mac.httpSubs.on") : t("mac.httpSubs.off")
                    }
                ))
                Text(t("mac.httpSubs.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.sec.dns")) {
                Picker(t("mac.dns.picker"), selection: Binding(
                    get: { state.settings.dnsPreference },
                    set: { v in Task { await state.setDnsPreference(v) } }
                )) {
                    ForEach(DnsPreference.allCases) { pref in
                        Text(pref.title(lang: lang)).tag(pref)
                    }
                }
                .pickerStyle(.segmented)

                Text(state.settings.dnsPreference.subtitle(lang: lang))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text(t("mac.dns.reloadHint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }

            Section(t("mac.sec.shortcuts")) {
                Button {
                    state.openConfigFolder()
                } label: {
                    Label(t("mac.openConfig"), systemImage: "folder")
                }
                Text(t("mac.openConfig.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Button {
                    state.openDashboard()
                } label: {
                    Label(t("mac.openDashboard"), systemImage: "safari")
                }
                .disabled(!state.coreRunning)
                Text(t("mac.openDashboard.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.sec.launch")) {
                Toggle(t("mac.launchAtLogin"), isOn: Binding(
                    get: { state.settings.launchAtLoginEnabled },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Text(LaunchAtLogin.statusText)
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text(t("mac.launchAtLogin.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.sec.speedQuick")) {
                Toggle(t("mac.autoSpeed"), isOn: Binding(
                    get: { state.settings.autoSpeedTestEnabled },
                    set: { state.setAutoSpeedTestEnabled($0) }
                ))
                .disabled(state.nodes.isEmpty)
                Toggle(t("mac.autoFastest"), isOn: Binding(
                    get: { state.settings.autoSelectFastest },
                    set: { state.setAutoSelectFastest($0) }
                ))
                Text(t("mac.speedQuick.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    private func settingsProxyModeButton(_ mode: ProxyMode) -> some View {
        let selected = state.settings.proxyMode == mode
        let color = BashXTheme.proxyModeColor(mode, appearance: appearance)
        return Button {
            Task { await state.setProxyMode(mode) }
        } label: {
            Text(mode.title(lang: lang))
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? color : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? color.opacity(0.14) : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
        .help(mode.subtitle(lang: lang))
    }

    // MARK: - 测速

    private var speedTestTab: some View {
        Form {
            Section(t("mac.sec.speed")) {
                TextField(t("mac.timeout"), value: $state.settings.testTimeoutMs, format: .number)
                TextField(t("mac.concurrency"), value: $state.settings.concurrency, format: .number)
                TextField(t("mac.testURL"), text: $state.settings.testURL)
            }

            Section(t("mac.sec.perf")) {
                Toggle(t("mac.turbo"), isOn: Binding(
                    get: { state.settings.turboMode },
                    set: { v in Task { await state.setTurboMode(v) } }
                ))
                Text(t("mac.turbo.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Toggle(t("mac.sniffing"), isOn: Binding(
                    get: { state.settings.domainSniffing },
                    set: { v in Task { await state.setDomainSniffing(v) } }
                ))
                .disabled(!state.settings.turboMode)
                Text(t("mac.sniffing.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.sec.auto")) {
                Toggle(t("mac.autoSpeed"), isOn: Binding(
                    get: { state.settings.autoSpeedTestEnabled },
                    set: { state.setAutoSpeedTestEnabled($0) }
                ))
                TextField(t("mac.autoInterval"), value: Binding(
                    get: { state.settings.autoSpeedTestIntervalMinutes },
                    set: { state.setAutoSpeedTestIntervalMinutes($0) }
                ), format: .number)
                .disabled(!state.settings.autoSpeedTestEnabled)
                Toggle(t("mac.autoFastest"), isOn: Binding(
                    get: { state.settings.autoSelectFastest },
                    set: { state.setAutoSelectFastest($0) }
                ))
                Text(t("mac.autoSpeed.detail"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - Proxy

    private var proxyTab: some View {
        Form {
            Section(t("mac.proxy.status")) {
                LabeledContent(t("mac.proxy.core")) {
                    Text(state.coreRunning ? t("common.running") : t("common.stopped"))
                        .foregroundStyle(state.coreRunning ? BashXTheme.good(for: appearance) : .secondary)
                }
            }

            Section(t("mac.proxy.ports")) {
                LabeledContent(t("mac.proxy.address")) {
                    Text(state.externalProxyAddress)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("HTTP") {
                    Text(state.externalProxyHTTPURL)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("SOCKS5") {
                    Text(state.externalProxySOCKSURL)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("mixed-port", value: $state.settings.mixedPort, format: .number)
                Toggle(t("mac.proxy.allowLan"), isOn: Binding(
                    get: { state.settings.allowLan },
                    set: { v in Task { await state.setAllowLan(v) } }
                ))
                Text(t("mac.proxy.lanHint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text(t("mac.proxy.portHint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.proxy.copy")) {
                HStack {
                    Button(t("mac.copyHost")) { state.copyExternalProxy(kind: .hostPort) }
                    Button(t("mac.copyHTTP")) { state.copyExternalProxy(kind: .http) }
                    Button(t("mac.copySOCKS")) { state.copyExternalProxy(kind: .socks) }
                    Button(t("mac.copyEnv")) { state.copyExternalProxy(kind: .exportEnv) }
                }
            }

            Section(t("mac.proxy.example")) {
                Text("export https_proxy=\(state.externalProxyHTTPURL)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("curl -x \(state.externalProxyHTTPURL) https://www.google.com")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - Core

    private var coreTab: some View {
        Form {
            Section(t("mac.core.paths")) {
                TextField(t("mac.core.binary"), text: $state.settings.clashBinaryPath)
                TextField("external-controller", text: $state.settings.externalController)
                SecureField("secret", text: $state.settings.secret)
                Text(t("mac.core.defaultPorts"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("TUN") {
                Picker(t("mac.core.stack"), selection: $state.settings.tunStack) {
                    Text("mixed").tag("mixed")
                    Text("system").tag("system")
                    Text("gvisor").tag("gvisor")
                }
                Text(t("mac.core.tunHint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.core.maint")) {
                LabeledContent(t("mac.proxy.status")) {
                    Text(coreStatusText)
                        .foregroundStyle(state.coreRunning ? BashXTheme.good(for: appearance) : .secondary)
                }
                Button(t("mac.openDashboard")) {
                    state.openDashboard()
                }
                .disabled(!state.coreRunning)
                Text(t("mac.core.dashHint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text(t("mac.core.bundled"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                if state.coreRunning || state.isCoreVisiblyAlive {
                    Button(t("mac.core.stop")) {
                        state.stopCore(force: true)
                    }
                } else if !state.coreConnecting {
                    Button(t("mac.core.start")) {
                        Task { await state.ensureCoreRunning() }
                    }
                }
                Button(t("mac.core.repair")) {
                    Task { await state.installOrRepairCore() }
                }
                .disabled(state.isBusy)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    private var coreStatusText: String {
        if state.coreRunning { return t("common.running") }
        if state.coreConnecting { return t("common.connecting") }
        return t("common.stopped")
    }

    // MARK: - 外观

    private var appearanceTab: some View {
        Form {
            Section(t("lang.title")) {
                Picker(t("lang.title"), selection: Binding(
                    get: { state.settings.uiLanguage },
                    set: { state.setUiLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.pickerTitle).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Text(t("lang.footer"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section(t("mac.appearance.section")) {
                Picker(t("mac.appearance.theme"), selection: Binding(
                    get: { state.settings.appearance },
                    set: { state.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title(lang: lang)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(t("mac.nodeDisplay"), selection: Binding(
                    get: { state.settings.nodeDisplayMode },
                    set: { state.setNodeDisplayMode($0) }
                )) {
                    ForEach(NodeDisplayMode.allCases) { mode in
                        Text(mode.title(lang: lang)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(t("mac.menuNode.hint").replacingOccurrences(of: "%@", with: "\(state.settings.menuNodeLimit)"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Stepper(
                    t("mac.menuNodeLimit").replacingOccurrences(of: "%@", with: "\(state.settings.menuNodeLimit)"),
                    value: Binding(
                        get: { state.settings.menuNodeLimit },
                        set: { state.setMenuNodeLimit($0) }
                    ),
                    in: 5...50
                )

                Text(t("mac.hotkeys.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Toggle(t("mac.menuTraffic"), isOn: Binding(
                    get: { state.settings.showMenuBarTraffic },
                    set: { state.setShowMenuBarTraffic($0) }
                ))
                Text(t("mac.menuTraffic.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                LogoStylePicker(
                    selection: Binding(
                        get: { state.settings.logoStyle },
                        set: { state.setLogoStyle($0) }
                    ),
                    appearance: appearance
                )

                Toggle(t("mac.dockIcon"), isOn: Binding(
                    get: { state.settings.showDockIcon },
                    set: { state.setShowDockIcon($0) }
                ))
                Text(t("mac.dockIcon.hint"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Text(t("mac.appearance.footer"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - 关于

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                aboutHero

                aboutUpdateSection

                VStack(alignment: .leading, spacing: 10) {
                    aboutFeatureRow("tray.full.fill", t("mac.about.f1"), t("mac.about.f1d"))
                    aboutFeatureRow("network", t("mac.about.f2"), t("mac.about.f2d"))
                    aboutFeatureRow("slider.horizontal.3", t("mac.about.f3"), t("mac.about.f3d"))
                    aboutFeatureRow("gauge.with.dots.needle.67percent", t("mac.about.f4"), t("mac.about.f4d"))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BashXTheme.card(for: appearance))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent(t("mac.about.version")) {
                        Text(AppVersion.display)
                            .font(.body.monospacedDigit())
                            .textSelection(.enabled)
                    }
                    LabeledContent(t("mac.about.rules")) {
                        Text("v\(ChinaSmartRules.version)")
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("Logo") {
                        Text(state.settings.logoStyle.title)
                            .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    }
                    Divider()
                    LabeledContent(t("mac.about.configDir")) {
                        Text(Paths.supportDir.path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    Button(t("mac.openConfig")) { state.openConfigFolder() }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BashXTheme.card(for: appearance))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                        )
                }

                Text(t("mac.about.footer"))
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .onAppear {
            Task {
                let stale = updater.lastChecked.map { Date().timeIntervalSince($0) > 3600 } ?? true
                if stale || updater.phase == .idle {
                    await updater.check(silent: true)
                }
            }
        }
    }

    private var aboutUpdateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(t("mac.update.title"), systemImage: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let checked = updater.lastChecked {
                    Text(t("mac.update.lastCheck").replacingOccurrences(of: "%@", with: checked.formatted(date: .omitted, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
            }

            updateStatusView

            HStack(spacing: 10) {
                Button {
                    Task { await updater.check() }
                } label: {
                    Text(updaterCheckButtonTitle)
                }
                .disabled(isUpdaterBusy)

                if case .available = updater.phase {
                    Button {
                        Task { await updater.downloadAndInstall() }
                    } label: {
                        Text(t("mac.update.download"))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BashXTheme.accent(for: appearance))
                    .disabled(isUpdaterBusy)
                }

                if case .failed = updater.phase {
                    Button(t("mac.update.openReleases")) {
                        updater.openReleasesPage()
                    }
                }
            }

            Text(t("mac.update.footer"))
                .font(.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updater.phase {
        case .idle:
            Text(t("mac.update.idle"))
                .font(.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(t("mac.update.checking"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
        case .upToDate(let remote):
            Label(t("mac.update.upToDate").replacingOccurrences(of: "%1", with: AppVersion.short).replacingOccurrences(of: "%2", with: remote), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(BashXTheme.good)
                .fixedSize(horizontal: false, vertical: true)
        case .ahead(let remote):
            Label(t("mac.update.ahead").replacingOccurrences(of: "%1", with: AppVersion.short).replacingOccurrences(of: "%2", with: remote), systemImage: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .fixedSize(horizontal: false, vertical: true)
        case .available(let info):
            VStack(alignment: .leading, spacing: 4) {
                Text(t("mac.update.available").replacingOccurrences(of: "%1", with: info.version).replacingOccurrences(of: "%2", with: AppVersion.short))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                if info.fileSize > 0 {
                    Text(t("mac.update.pkgSize").replacingOccurrences(of: "%@", with: AppUpdateService.formatSize(info.fileSize)))
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                }
                if let notes = info.releaseNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                        .lineLimit(3)
                }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(t("mac.update.downloading").replacingOccurrences(of: "%@", with: "\(Int(progress * 100))"))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        case .downloaded:
            Label(t("mac.update.downloaded"), systemImage: "externaldrive.fill.badge.checkmark")
                .font(.caption)
                .foregroundStyle(BashXTheme.good)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isUpdaterBusy: Bool {
        switch updater.phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    private var updaterCheckButtonTitle: String {
        switch updater.phase {
        case .checking: return t("mac.update.checkingBtn")
        default: return t("mac.update.check")
        }
    }

    private var aboutHero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BashXTheme.accent(for: appearance).opacity(0.22),
                                BashXTheme.accentSoft(for: appearance),
                                BashXTheme.card(for: appearance)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(BashXTheme.accent(for: appearance).opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: BashXTheme.accent(for: appearance).opacity(0.18), radius: 12, y: 4)

                LogoIconView(style: state.settings.logoStyle, size: 40, colored: true, panel: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("BashX")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(t("mac.about.tagline"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text(t("mac.about.subtitle"))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    BashXTheme.accent(for: appearance).opacity(0.35),
                                    BashXTheme.separator(for: appearance)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        }
    }

    private func aboutFeatureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BashXTheme.accentSoft(for: appearance))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Opens settings via a dedicated window (reliable for LSUIElement / menu-bar apps).
enum SettingsOpener {
    private static weak var boundState: AppState?

    @MainActor
    static func register(_ state: AppState) {
        boundState = state
    }

    @MainActor
    static func open(state: AppState? = nil, fromMenuBar: Bool = false) {
        let resolved = state ?? boundState
        guard let resolved else {
            AppActivation.promoteForWindow()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        }
        SettingsPresenter.shared.open(state: resolved, deferForMenuDismiss: fromMenuBar)
    }
}
