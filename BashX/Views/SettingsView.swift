import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, plugins, network, appearance, about

    var id: String { rawValue }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.t("mac.tab.general", lang)
        case .plugins: return L10n.t("plugin.market.title", lang)
        case .network: return L10n.t("mac.tab.network", lang)
        case .appearance: return L10n.t("mac.tab.appearance", lang)
        case .about: return L10n.t("mac.tab.about", lang)
        }
    }

    func icon() -> String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .plugins: return "puzzlepiece.extension"
        case .network: return "network"
        case .appearance: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @ObservedObject private var updater = AppUpdateController.shared
    @State private var tab: SettingsTab = .general
    @State private var showGeneralAdvanced = false
    @State private var showNetworkSpeed = false
    @State private var showNetworkCore = false
    @State private var showLaunchLog = true

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
                        case .plugins: PluginMarketPane()
                        case .network: networkTab
                        case .appearance: appearanceTab
                        case .about: aboutTab
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .onAppear { state.refreshLaunchAtLogin() }
        .onAppear { state.refreshLaunchDiagnostics() }
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
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon())
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.title(lang: lang))
                            .font(.system(size: 11, weight: tab == item ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(tab == item ? BashXTheme.accent(for: appearance) : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == item ? BashXTheme.accent(for: appearance).opacity(0.12) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - 常用

    private var generalTab: some View {
        Form {
            if state.launchHasError {
                launchDiagnosticSection
            }

            Section {
                HStack(spacing: 8) {
                    ForEach(ProxyMode.allCases) { mode in
                        settingsProxyModeButton(mode)
                    }
                }
                .padding(.vertical, 4)

                Toggle(t("mac.sec.systemProxy"), isOn: Binding(
                    get: { state.systemProxyOn },
                    set: { v in Task { await state.setSystemProxy(v) } }
                ))
                .help(t("mac.systemProxy.hint").replacingOccurrences(of: "%@", with: "\(state.settings.mixedPort)"))

                Toggle(t("mac.tun"), isOn: Binding(
                    get: { state.settings.tunEnabled },
                    set: { v in Task { await state.setTUN(v) } }
                ))
                .help(t("mac.tun.hint"))

                Toggle(t("mac.adblock"), isOn: Binding(
                    get: { state.settings.videoAdBlockEnabled },
                    set: { v in Task { await state.setVideoAdBlock(v) } }
                ))
                .help(t("mac.adblock.hint"))

                Toggle(t("mac.launchAtLogin"), isOn: Binding(
                    get: { state.launchAtLoginOn },
                    set: { state.setLaunchAtLogin($0) }
                ))
            } header: {
                Text(t("mac.sec.proxyMode"))
            }

            Section {
                Toggle(t("mac.autoSpeed"), isOn: Binding(
                    get: { state.settings.autoSpeedTestEnabled },
                    set: { state.setAutoSpeedTestEnabled($0) }
                ))
                .disabled(state.nodes.isEmpty)

                Toggle(t("mac.autoFastest"), isOn: Binding(
                    get: { state.settings.autoSelectFastest },
                    set: { state.setAutoSelectFastest($0) }
                ))
            } header: {
                Text(t("mac.sec.speedQuick"))
            }

            Section {
                DisclosureGroup(isExpanded: $showGeneralAdvanced) {
                    Toggle(t("mac.closeConnOnSwitch"), isOn: Binding(
                        get: { state.settings.closeConnectionsOnSwitch },
                        set: { state.setCloseConnectionsOnSwitch($0) }
                    ))
                    .help(t("mac.closeConnOnSwitch.hint"))

                    Toggle(t("mac.httpSubs"), isOn: Binding(
                        get: { state.settings.allowInsecureHTTPSubscriptions },
                        set: {
                            state.settings.allowInsecureHTTPSubscriptions = $0
                            state.persist()
                            state.statusText = $0 ? t("mac.httpSubs.on") : t("mac.httpSubs.off")
                        }
                    ))
                    .help(t("mac.httpSubs.hint"))

                    Picker(t("mac.dns.picker"), selection: Binding(
                        get: { state.settings.dnsPreference },
                        set: { v in Task { await state.setDnsPreference(v) } }
                    )) {
                        ForEach(DnsPreference.allCases) { pref in
                            Text(pref.title(lang: lang)).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help(state.settings.dnsPreference.subtitle(lang: lang))

                    if SystemProxy.hasSnapshot() {
                        Button(t("mac.restoreProxy")) {
                            let ok = SystemProxy.restoreFromSnapshot()
                            state.statusText = ok ? t("mac.restoreProxy.ok") : t("mac.restoreProxy.none")
                        }
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

                    HStack(spacing: 10) {
                        Button {
                            state.openConfigFolder()
                        } label: {
                            Label(t("mac.openConfig"), systemImage: "folder")
                        }
                        Button {
                            state.openDashboard()
                        } label: {
                            Label(t("mac.openDashboard"), systemImage: "safari")
                        }
                        .disabled(!state.coreRunning)
                    }
                } label: {
                    Text(t("mac.sec.advanced"))
                }
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(10)
    }

    private var launchDiagnosticSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("mac.launchDiag.title"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(state.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .lineLimit(2)
                }
            }

            DisclosureGroup(isExpanded: $showLaunchLog) {
                ScrollView {
                    Text(state.launchDiagnosticReport.isEmpty ? t("mac.launchDiag.empty") : state.launchDiagnosticReport)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            } label: {
                Text(t("mac.launchDiag.detail"))
            }

            HStack(spacing: 10) {
                Button(t("mac.launchDiag.copy")) {
                    state.copyLaunchDiagnosticReport()
                }
                Button(t("mac.launchDiag.openLog")) {
                    state.openLaunchDiagnosticLog()
                }
                Button(t("mac.core.repair")) {
                    Task { await state.installOrRepairCore() }
                }
                .disabled(state.isBusy)
            }
        } header: {
            Text(t("mac.launchDiag.header"))
        }
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
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? color.opacity(0.14) : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
        .help(mode.subtitle(lang: lang))
    }

    // MARK: - 网络（外置代理 + 测速 + 内核）

    private var networkTab: some View {
        Form {
            Section {
                LabeledContent(t("mac.proxy.core")) {
                    Text(state.coreRunning ? t("common.running") : t("common.stopped"))
                        .foregroundStyle(state.coreRunning ? BashXTheme.good(for: appearance) : .secondary)
                }
                LabeledContent(t("mac.proxy.address")) {
                    Text(state.externalProxyAddress)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("mixed-port", value: $state.settings.mixedPort, format: .number)
                Toggle(t("mac.proxy.allowLan"), isOn: Binding(
                    get: { state.settings.allowLan },
                    set: { v in Task { await state.setAllowLan(v) } }
                ))
                .help(t("mac.proxy.lanHint"))

                HStack(spacing: 8) {
                    Button(t("mac.copyHTTP")) { state.copyExternalProxy(kind: .http) }
                    Button(t("mac.copySOCKS")) { state.copyExternalProxy(kind: .socks) }
                    Button(t("mac.copyEnv")) { state.copyExternalProxy(kind: .exportEnv) }
                }
            } header: {
                Text(t("mac.proxy.ports"))
            }

            Section {
                DisclosureGroup(isExpanded: $showNetworkSpeed) {
                    TextField(t("mac.timeout"), value: $state.settings.testTimeoutMs, format: .number)
                    TextField(t("mac.concurrency"), value: $state.settings.concurrency, format: .number)
                    TextField(t("mac.testURL"), text: $state.settings.testURL)

                    Toggle(t("mac.turbo"), isOn: Binding(
                        get: { state.settings.turboMode },
                        set: { v in Task { await state.setTurboMode(v) } }
                    ))
                    .help(t("mac.turbo.hint"))

                    Toggle(t("mac.sniffing"), isOn: Binding(
                        get: { state.settings.domainSniffing },
                        set: { v in Task { await state.setDomainSniffing(v) } }
                    ))
                    .disabled(!state.settings.turboMode)
                    .help(t("mac.sniffing.hint"))

                    TextField(t("mac.autoInterval"), value: Binding(
                        get: { state.settings.autoSpeedTestIntervalMinutes },
                        set: { state.setAutoSpeedTestIntervalMinutes($0) }
                    ), format: .number)
                    .disabled(!state.settings.autoSpeedTestEnabled)
                } label: {
                    Text(t("mac.tab.speed"))
                }

                DisclosureGroup(isExpanded: $showNetworkCore) {
                    TextField(t("mac.core.binary"), text: $state.settings.clashBinaryPath)
                    TextField("external-controller", text: $state.settings.externalController)
                    SecureField("secret", text: $state.settings.secret)

                    Picker(t("mac.core.stack"), selection: $state.settings.tunStack) {
                        Text("mixed").tag("mixed")
                        Text("system").tag("system")
                        Text("gvisor").tag("gvisor")
                    }
                    .help(t("mac.core.tunHint"))

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
                } label: {
                    Text(t("mac.tab.core"))
                }
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(10)
    }

    // MARK: - 外观

    private var appearanceTab: some View {
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
                .pickerStyle(.segmented)

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
            }

            Section {
                Stepper(
                    t("mac.menuNodeLimit").replacingOccurrences(of: "%@", with: "\(state.settings.menuNodeLimit)"),
                    value: Binding(
                        get: { state.settings.menuNodeLimit },
                        set: { state.setMenuNodeLimit($0) }
                    ),
                    in: 5...50
                )

                Toggle(t("mac.menuTraffic"), isOn: Binding(
                    get: { state.settings.showMenuBarTraffic },
                    set: { state.setShowMenuBarTraffic($0) }
                ))
                .help(t("mac.menuTraffic.hint"))

                Toggle(t("mac.dockIcon"), isOn: Binding(
                    get: { state.settings.showDockIcon },
                    set: { state.setShowDockIcon($0) }
                ))
                .help(t("mac.dockIcon.hint"))

                LogoStylePicker(
                    selection: Binding(
                        get: { state.settings.logoStyle },
                        set: { state.setLogoStyle($0) }
                    ),
                    appearance: appearance
                )
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(10)
    }

    // MARK: - 关于

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                aboutHero
                aboutUpdateSection

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(t("mac.about.version")) {
                        Text(AppVersion.display)
                            .font(.body.monospacedDigit())
                            .textSelection(.enabled)
                    }
                    LabeledContent(t("mac.about.rules")) {
                        Text("v\(ChinaSmartRules.version)")
                            .font(.body.monospacedDigit())
                    }
                    Button(t("mac.openConfig")) { state.openConfigFolder() }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BashXTheme.card(for: appearance))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                        )
                }
            }
            .padding(18)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t("mac.update.title"), systemImage: "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
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
                    Button(t("mac.update.retry")) {
                        Task { await updater.check() }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            Label(t("mac.update.upToDate").replacingOccurrences(of: "%@", with: remote), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(BashXTheme.good)
                .fixedSize(horizontal: false, vertical: true)
        case .ahead:
            Label(t("mac.update.ahead").replacingOccurrences(of: "%@", with: AppVersion.short), systemImage: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .fixedSize(horizontal: false, vertical: true)
        case .available(let info):
            VStack(alignment: .leading, spacing: 4) {
                Text(t("mac.update.available").replacingOccurrences(of: "%1", with: info.version))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                if info.fileSize > 0 {
                    Text(t("mac.update.pkgSize").replacingOccurrences(of: "%@", with: AppUpdateService.formatSize(info.fileSize)))
                        .font(.caption2)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
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
        HStack(spacing: 14) {
            LogoIconView(style: state.settings.logoStyle, size: 36, colored: true, panel: true)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BashXTheme.accentSoft(for: appearance))
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("BashX")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(t("mac.about.tagline"))
                    .font(.system(size: 12))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
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
