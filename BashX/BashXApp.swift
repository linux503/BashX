import AppKit
import Combine
import SwiftUI

/// Holds TrafficMonitor without forwarding its publishes to the App scene.
/// Mirrors menu rates into @Published fields — MenuBarExtra label often ignores nested ObservableObject.
@MainActor
final class TrafficRoot: ObservableObject {
    let monitor = TrafficMonitor()
    let menuRates = MenuBarRateStore()

    @Published private(set) var menuDown = "0.0K"
    @Published private(set) var menuUp = "0.0K"
    @Published private(set) var menuHelp = "BashX · 未连接"
    @Published private(set) var coreAlive = false
    /// Bumped on each rate tick so MenuBarExtra label remounts when SwiftUI skips redraw.
    @Published private(set) var refreshToken = 0

    private var cancellables = Set<AnyCancellable>()
    private var watchdog: Timer?

    init() {
        monitor.menuBarRates = menuRates
        menuRates.$menuDown
            .combineLatest(menuRates.$menuUp, menuRates.$help, menuRates.$coreRunning)
            .receive(on: RunLoop.main)
            .sink { [weak self] down, up, help, alive in
                guard let self else { return }
                self.menuDown = down
                self.menuUp = up
                self.menuHelp = help
                self.coreAlive = alive
                self.refreshToken &+= 1
            }
            .store(in: &cancellables)
    }

    /// Recover if traffic stream never started or core came up later.
    func startWatchdog(sync: @escaping () -> Void) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in sync() }
        }
    }
}

@main
struct BashXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var trafficRoot = TrafficRoot()

    private var traffic: TrafficMonitor { trafficRoot.monitor }
    private var menuRates: MenuBarRateStore { trafficRoot.menuRates }

    var body: some Scene {
        MenuBarExtra {
            MenuBarExtraContent(state: state, appDelegate: appDelegate, syncTraffic: syncTraffic)
                .equatable()
        } label: {
            MenuBarTrafficLabel(
                trafficRoot: trafficRoot,
                logoStyle: state.settings.logoStyle,
                showTraffic: state.settings.showMenuBarTraffic
            )
            .onAppear {
                appDelegate.bind(state, syncTraffic: syncTraffic)
                state.refreshLaunchAtLogin()
                syncTraffic()
                trafficRoot.startWatchdog(sync: syncTraffic)
                IconManager.applyAppIcon(style: state.settings.logoStyle)
            }
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: state.coreRunning) { _, _ in syncTraffic() }
        .onChange(of: state.chromeRevision) { _, _ in syncTraffic() }
        .onChange(of: state.settings.externalController) { _, _ in syncTraffic() }
        .onChange(of: state.settings.secret) { _, _ in syncTraffic() }
        .onChange(of: state.settings.mixedPort) { _, _ in syncTraffic() }
        .onChange(of: state.settings.showMenuBarTraffic) { _, _ in
            syncTraffic()
        }

        Settings {
            BashXThemed(appearance: state.settings.appearance) {
                SettingsView()
                    .environmentObject(state)
                    .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 560)
            }
                .onAppear { appDelegate.bind(state) }
        }
    }

    private func syncTraffic() {
        traffic.configure(
            controller: state.settings.externalController,
            secret: state.settings.secret
        )
        // Port-alive counts even if UI flag briefly lags — otherwise rates stay at 0 forever.
        let alive = state.coreRunning
            || state.isCoreVisiblyAlive
            || CoreHealth.mixedPortAlive(port: state.settings.mixedPort)
        menuRates.setCoreRunning(alive)
        if alive {
            traffic.startTraffic()
        } else {
            traffic.stopTrafficOnly()
        }
        appDelegate.traffic = traffic
        PanelPresenter.shared.traffic = traffic
        PanelPresenter.shared.menuRates = menuRates
    }
}

/// Isolates menu content from AppState @Published churn (prevents submenu flash).
private struct MenuBarExtraContent: View, Equatable {
    let state: AppState
    let appDelegate: AppDelegate
    let syncTraffic: () -> Void

    static func == (lhs: MenuBarExtraContent, rhs: MenuBarExtraContent) -> Bool {
        lhs.state === rhs.state
    }

    var body: some View {
        MenuBarView(state: state)
            .onAppear {
                appDelegate.bind(state, syncTraffic: syncTraffic)
                state.refreshLaunchAtLogin()
                syncTraffic()
                Task { _ = await state.ensureCoreRunning() }
            }
    }
}

/// Menu-bar: icon + ↓/↑ rates. Width is reserved so the status item does not jitter.
private struct MenuBarTrafficLabel: View {
    @ObservedObject var trafficRoot: TrafficRoot
    let logoStyle: LogoStyle
    let showTraffic: Bool

    private let rateFont = Font.system(size: 9, weight: .medium, design: .monospaced)
    private let trafficWidth: CGFloat = 72
    private let fieldWidth: CGFloat = 26

    private var ratesVisible: Bool {
        showTraffic && (trafficRoot.coreAlive || trafficRoot.menuDown != "0.0K" || trafficRoot.menuUp != "0.0K")
    }

    var body: some View {
        HStack(spacing: 2) {
            LogoIconView(style: logoStyle, size: 16)
            if showTraffic {
                HStack(spacing: 1) {
                    Text("↓")
                    Text(trafficRoot.menuDown)
                        .frame(width: fieldWidth, alignment: .trailing)
                    Text("↑")
                    Text(trafficRoot.menuUp)
                        .frame(width: fieldWidth, alignment: .trailing)
                }
                .font(rateFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: trafficWidth, alignment: .leading)
                .clipped()
                .opacity(ratesVisible ? 1 : 0.45)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 18, alignment: .center)
        .help(trafficRoot.coreAlive ? trafficRoot.menuHelp : "BashX · 未连接")
        .id("\(logoStyle.rawValue)-\(showTraffic)-\(trafficRoot.refreshToken)")
        .transaction { $0.animation = nil }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Strong hold so quit cleanup always works (weak was often nil).
    private(set) var state: AppState?
    var traffic: TrafficMonitor?
    private var syncTraffic: (() -> Void)?
    private var didCleanup = false

    func bind(_ state: AppState, syncTraffic: (() -> Void)? = nil) {
        self.state = state
        if let syncTraffic { self.syncTraffic = syncTraffic }
        SettingsOpener.register(state)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.preferDockIcon = state?.settings.showDockIcon ?? false
        AppActivation.applyPolicy()
        IconManager.applyAppIcon(style: state?.settings.logoStyle ?? .default)
        LogoRenderer.warmCache()
        DispatchQueue.main.async { [weak self] in
            self?.syncTraffic?()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCleanup else { return .terminateNow }
        didCleanup = true
        traffic?.stopAll()
        state?.prepareForQuit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !didCleanup else { return }
        didCleanup = true
        traffic?.stopAll()
        state?.prepareForQuit()
    }
}

enum IconManager {
    /// Apply dock / panel app icon for the selected logo style.
    static func applyAppIcon(style: LogoStyle = .default) {
        let image = LogoRenderer.appIcon(style: style, pixels: 256)
        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
    }

    /// Non-blocking dock icon update (logo picker / settings).
    static func applyAppIconAsync(style: LogoStyle = .default) {
        Task.detached(priority: .utility) {
            let image = LogoRenderer.appIcon(style: style, pixels: 256)
            await MainActor.run {
                NSApp.applicationIconImage = image
                NSApp.dockTile.display()
            }
        }
    }
}

enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// e.g. `0.1.3 (4)`
    static var display: String { "\(short) (\(build))" }

    /// e.g. `BashX 0.1.3`
    static var title: String { "BashX \(short)" }
}
