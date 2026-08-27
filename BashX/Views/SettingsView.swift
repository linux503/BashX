import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, speed, proxy, core, appearance, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "常用"
        case .speed: return "测速"
        case .proxy: return "外置代理"
        case .core: return "内核"
        case .appearance: return "外观"
        case .about: return "关于"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @StateObject private var updater = AppUpdateController()
    @State private var tab: SettingsTab = .general

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
                    Text(item.title)
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
            Section("代理模式") {
                HStack(spacing: 10) {
                    ForEach(ProxyMode.allCases) { mode in
                        settingsProxyModeButton(mode)
                    }
                }
                .padding(.vertical, 6)

                Toggle("系统代理", isOn: Binding(
                    get: { state.systemProxyOn },
                    set: { v in Task { await state.setSystemProxy(v) } }
                ))
                Text("开启前会备份原有代理；关闭时自动恢复。指向 127.0.0.1:\(state.settings.mixedPort)。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                if SystemProxy.hasSnapshot() {
                    Button("恢复网络代理备份") {
                        let ok = SystemProxy.restoreFromSnapshot()
                        state.statusText = ok ? "已恢复开启前的系统代理设置" : "没有可恢复的备份"
                    }
                }

                Toggle("TUN 模式", isOn: Binding(
                    get: { state.settings.tunEnabled },
                    set: { v in Task { await state.setTUN(v) } }
                ))
                Text("增强模式，可接管更多流量。首次会安装 TUN 权限（输一次管理员密码），之后开关无需再输。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                HStack {
                    Text(TunPrivilege.statusText)
                        .font(.caption)
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button(TunPrivilege.isReady ? "重新安装授权" : "安装 TUN 授权") {
                        do {
                            try TunPrivilege.install()
                            state.statusText = "TUN 权限已就绪，之后开 TUN 无需密码"
                        } catch {
                            state.statusText = error.localizedDescription
                        }
                    }
                    if TunPrivilege.isInstalledOnDisk {
                        Button("移除授权", role: .destructive) {
                            do {
                                try TunPrivilege.uninstall()
                                state.statusText = "已移除 TUN 权限"
                            } catch {
                                state.statusText = error.localizedDescription
                            }
                        }
                    }
                }

                Toggle("视频广告过滤", isOn: Binding(
                    get: { state.settings.videoAdBlockEnabled },
                    set: { v in Task { await state.setVideoAdBlock(v) } }
                ))
                Text("域名级 REJECT。需「规则」模式（开过滤时会自动切回）。无法拦截与正片同 CDN 的贴片广告。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Toggle("允许不安全 HTTP 订阅", isOn: Binding(
                    get: { state.settings.allowInsecureHTTPSubscriptions },
                    set: {
                        state.settings.allowInsecureHTTPSubscriptions = $0
                        state.persist()
                        state.statusText = $0 ? "已允许明文 HTTP 订阅（不推荐）" : "仅允许 HTTPS 订阅"
                    }
                ))
                Text("默认仅 HTTPS。开启后才接受 http:// 订阅链接。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("DNS 优选") {
                Picker("解析策略", selection: Binding(
                    get: { state.settings.dnsPreference },
                    set: { v in Task { await state.setDnsPreference(v) } }
                )) {
                    ForEach(DnsPreference.allCases) { pref in
                        Text(pref.title).tag(pref)
                    }
                }
                .pickerStyle(.segmented)

                Text(state.settings.dnsPreference.subtitle)
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text("修改后自动写入 config.yaml 并重载内核。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }

            Section("启动") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { state.settings.launchAtLoginEnabled },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Text(LaunchAtLogin.statusText)
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text("开启后登录 Mac 会自动运行 BashX（菜单栏）。若提示需批准，请到「系统设置 → 通用 → 登录项」。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("测速快捷") {
                Toggle("自动测速", isOn: Binding(
                    get: { state.settings.autoSpeedTestEnabled },
                    set: { state.setAutoSpeedTestEnabled($0) }
                ))
                .disabled(state.nodes.isEmpty)
                Toggle("测速后自动选用最快节点", isOn: Binding(
                    get: { state.settings.autoSelectFastest },
                    set: { state.setAutoSelectFastest($0) }
                ))
                Text("更细的超时 / 并发 / 间隔请到「测速」页。")
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
            Text(mode.title)
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
        .help(mode.subtitle)
    }

    // MARK: - 测速

    private var speedTestTab: some View {
        Form {
            Section("参数") {
                TextField("超时 (ms)", value: $state.settings.testTimeoutMs, format: .number)
                TextField("并发数", value: $state.settings.concurrency, format: .number)
                TextField("测速 URL（预留）", text: $state.settings.testURL)
            }

            Section("性能") {
                Toggle("极速模式", isOn: Binding(
                    get: { state.settings.turboMode },
                    set: { v in Task { await state.setTurboMode(v) } }
                ))
                Text("开启后启用 mihomo 多连接并发、懒测速，下载/多线程场景更快。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Toggle("域名嗅探", isOn: Binding(
                    get: { state.settings.domainSniffing },
                    set: { v in Task { await state.setDomainSniffing(v) } }
                ))
                .disabled(!state.settings.turboMode)
                Text("帮助非浏览器应用正确分流；极少数软件可能不兼容。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("自动") {
                Toggle("自动测速", isOn: Binding(
                    get: { state.settings.autoSpeedTestEnabled },
                    set: { state.setAutoSpeedTestEnabled($0) }
                ))
                TextField("自动测速间隔（分钟）", value: Binding(
                    get: { state.settings.autoSpeedTestIntervalMinutes },
                    set: { state.setAutoSpeedTestIntervalMinutes($0) }
                ), format: .number)
                .disabled(!state.settings.autoSpeedTestEnabled)
                Toggle("测速后自动选用最快节点", isOn: Binding(
                    get: { state.settings.autoSelectFastest },
                    set: { state.setAutoSelectFastest($0) }
                ))
                Text("开启后按延迟把最快节点排到前面；自动测速会定时重测。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - 外置代理

    private var proxyTab: some View {
        Form {
            Section("端口") {
                LabeledContent("地址") {
                    Text("127.0.0.1:\(state.settings.mixedPort)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("mixed-port", value: $state.settings.mixedPort, format: .number)
                Toggle("允许局域网连接", isOn: Binding(
                    get: { state.settings.allowLan },
                    set: { v in Task { await state.setAllowLan(v) } }
                ))
                Text("开启后 mixed-port 可被局域网访问；会自动确保 API secret，并把 external-controller 限制在 127.0.0.1。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text("HTTP 与 SOCKS5 共用 mixed-port。本机填 127.0.0.1、端口 \(state.settings.mixedPort)。改端口后需重启内核。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("复制") {
                HStack {
                    Button("复制地址") { state.copyExternalProxy(kind: .hostPort) }
                    Button("复制 HTTP") { state.copyExternalProxy(kind: .http) }
                    Button("复制 SOCKS5") { state.copyExternalProxy(kind: .socks) }
                    Button("复制环境变量") { state.copyExternalProxy(kind: .exportEnv) }
                }
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - 内核

    private var coreTab: some View {
        Form {
            Section("路径与 API") {
                TextField("mihomo/clash 路径", text: $state.settings.clashBinaryPath)
                TextField("external-controller", text: $state.settings.externalController)
                SecureField("secret", text: $state.settings.secret)
                Text("默认使用 17890/19090，避免和 Stash/ClashX 的 7890/9090 冲突。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("TUN") {
                Picker("协议栈", selection: $state.settings.tunStack) {
                    Text("mixed").tag("mixed")
                    Text("system").tag("system")
                    Text("gvisor").tag("gvisor")
                }
                Text("开启 TUN 时启动内核会请求一次管理员权限；退出软件不再要求密码。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }

            Section("维护") {
                Text("mihomo 已内置在 App 中，启动时自动安装并运行，无需手动下载。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Button("修复内置内核") {
                    Task { await state.installOrRepairCore() }
                }
                .disabled(state.isBusy)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 12.5))
        .padding(14)
    }

    // MARK: - 外观

    private var appearanceTab: some View {
        Form {
            Section("外观") {
                Picker("界面主题", selection: Binding(
                    get: { state.settings.appearance },
                    set: { state.setAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("节点展示", selection: Binding(
                    get: { state.settings.nodeDisplayMode },
                    set: { state.setNodeDisplayMode($0) }
                )) {
                    ForEach(NodeDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("菜单栏固定展示延迟最快的前 10 个节点；面板内仍显示全部。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Toggle("菜单栏显示网速", isOn: Binding(
                    get: { state.settings.showMenuBarTraffic },
                    set: { state.setShowMenuBarTraffic($0) }
                ))
                Text("在 Logo 旁显示 ↓/↑。若菜单栏图标「消失」，多半被挤进右侧 ❯❯，关掉此项或点 ❯❯ 查看；也可开「程序坞显示图标」。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                LogoStylePicker(
                    selection: Binding(
                        get: { state.settings.logoStyle },
                        set: { state.setLogoStyle($0) }
                    ),
                    appearance: appearance
                )

                Toggle("程序坞显示图标", isOn: Binding(
                    get: { state.settings.showDockIcon },
                    set: { state.setShowDockIcon($0) }
                ))
                Text("关闭后仅保留菜单栏图标；开启后 BashX 会常驻程序坞。")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                Text("主题、展示方式切换后立即生效；Logo 同步到菜单栏。")
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
                    aboutFeatureRow("tray.full.fill", "多订阅合并", "勾选多个订阅，节点自动合并到同一列表")
                    aboutFeatureRow("network", "系统代理 / TUN", "一键接管系统流量，可选增强模式")
                    aboutFeatureRow("slider.horizontal.3", "规则 / 全局 / 直连", "BashX 智能规则分流，支持视频广告过滤")
                    aboutFeatureRow("gauge.with.dots.needle.67percent", "测速与菜单栏", "延迟测速、最快节点、网速可开关展示")
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
                    LabeledContent("版本") {
                        Text(AppVersion.display)
                            .font(.body.monospacedDigit())
                            .textSelection(.enabled)
                    }
                    LabeledContent("智能规则") {
                        Text("v\(ChinaSmartRules.version)")
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("Logo") {
                        Text(state.settings.logoStyle.title)
                            .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    }
                    Divider()
                    LabeledContent("配置目录") {
                        Text(Paths.supportDir.path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    Button("打开配置目录") { state.openConfigFolder() }
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

                Text("macOS 菜单栏代理工具 · 内核基于 mihomo / Clash Meta")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .onAppear {
            if case .idle = updater.phase {
                Task { await updater.check(silent: true) }
            }
        }
    }

    private var aboutUpdateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("软件更新", systemImage: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let checked = updater.lastChecked {
                    Text("上次检查 \(checked.formatted(date: .omitted, time: .shortened))")
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
                        Text("下载并安装")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BashXTheme.accent(for: appearance))
                    .disabled(isUpdaterBusy)
                }
            }

            Text("检查到新版本后可直接下载安装，完成后请重启 BashX。")
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
            Text("点击「检查更新」获取最新版本。")
                .font(.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在检查更新…")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
        case .upToDate:
            Label("已是最新版本（\(AppVersion.display)）", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(BashXTheme.good)
        case .available(let info):
            VStack(alignment: .leading, spacing: 4) {
                Text("发现新版本 \(info.version)（当前 \(AppVersion.short)）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                if info.fileSize > 0 {
                    Text("安装包 \(AppUpdateService.formatSize(info.fileSize))")
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
                Text("正在下载… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        case .downloaded:
            Label("下载完成，已打开安装包。请将 BashX 拖入「应用程序」后重启。", systemImage: "externaldrive.fill.badge.checkmark")
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
        case .checking: return "检查中…"
        default: return "检查更新"
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
                Text("轻量菜单栏代理客户端")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                Text("订阅管理 · 智能分流 · 系统代理 · 流量监控")
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
