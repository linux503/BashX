import AppKit
import Combine
import SwiftUI

/// Owns app services for `StateObject` lifecycle WITHOUT forwarding @Published churn.
/// Forwarding AppState/traffic into BashXApp.body rebuilds MenuBarExtra and dismisses submenus.
@MainActor
final class AppHub: ObservableObject {
    let state = AppState()
    let trafficRoot = TrafficRoot()
}

/// Traffic + menu-bar chrome. App scene does not observe this — only the label view does.
@MainActor
final class TrafficRoot {
    let monitor = TrafficMonitor()
    let menuRates = MenuBarRateStore()
    let chrome = MenuBarChrome()
    private var watchdog: Timer?
    private var didAttach = false

    init() {
        monitor.menuBarRates = menuRates
    }

    /// Idempotent — safe to call from launch, syncTraffic, and label onAppear.
    func attachIfNeeded(state: AppState) {
        let isInitialAttach = !didAttach
        if !didAttach {
            didAttach = true
            menuRates.onRatesUpdated = { [weak chrome] in chrome?.refresh(force: false) }
            chrome.bind(rates: menuRates, state: state)
        }
        // `attachIfNeeded` is also called by the watchdog.  Forcing a bitmap
        // render on every watchdog pass keeps the main thread busy even when
        // neither the state nor the traffic label changed.
        chrome.refresh(force: isInitialAttach)
    }

    func startWatchdog(sync: @escaping () -> Void) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in sync() }
        }
    }
}

/// Publishes only the status-item image. Pauses while the dropdown is open (prevents submenu flash).
@MainActor
final class MenuBarChrome: ObservableObject {
    @Published private(set) var image: NSImage = MenuBarStatusImage.placeholder()
    @Published private(set) var help: String = "BashX"

    private weak var rates: MenuBarRateStore?
    private weak var state: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var menuOpen = false
    private var lastKey = ""
    private var pendingWhileOpen = false
    private var trafficRefreshWork: DispatchWorkItem?

    func bind(rates: MenuBarRateStore, state: AppState?) {
        self.rates = rates
        if let state { self.state = state }
        cancellables.removeAll()
        Publishers.CombineLatest(rates.$menuDown, rates.$menuUp)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.scheduleTrafficRefresh() }
            .store(in: &cancellables)
        rates.$coreRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: false) }
            .store(in: &cancellables)
        state?.$settings
            .map(\.showMenuBarTraffic)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)
        state?.$settings
            .map(\.logoStyle)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)
        state?.$chromeRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Ignore chrome bumps while dropdown is open (prevents icon+menu flash).
                guard let self, !self.menuOpen else { return }
                self.refresh(force: false)
            }
            .store(in: &cancellables)
        state?.$coreRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .bashxMenuBarChromeNeedsRefresh)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: true) }
            .store(in: &cancellables)
        refresh(force: true)
    }

    /// Traffic SSE is hot — coalesce menu-bar bitmap redraws (esp. Apple Silicon lag).
    private func scheduleTrafficRefresh() {
        trafficRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh(force: false)
        }
        trafficRefreshWork = work
        // Status-item bitmap swaps look like "menu flashing". Keep ≤1 redraw / 2.5s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        if !open, pendingWhileOpen {
            pendingWhileOpen = false
            refresh(force: true)
        }
    }

    func refresh(force: Bool) {
        guard let rates, let state else { return }
        if menuOpen, !force {
            pendingWhileOpen = true
            return
        }
        let style = state.settings.logoStyle
        let show = state.settings.showMenuBarTraffic
        let down = rates.menuDown
        let up = rates.menuUp
        let alive = rates.coreRunning
        let dimmed = show && !alive && isZeroRate(down) && isZeroRate(up)
        let key = "\(style.rawValue)|\(show)|\(down)|\(up)|\(dimmed)"
        guard force || key != lastKey else { return }
        lastKey = key
        image = MenuBarStatusImage.render(
            style: style,
            down: down,
            up: up,
            showTraffic: show,
            dimmed: dimmed
        )
        help = alive ? rates.help : "BashX · 未连接"
    }

    private func isZeroRate(_ rate: String) -> Bool {
        rate == "0.0K" || rate == "0B" || rate == "0"
    }
}

/// Tracks MenuBarExtra dropdown open/close via NSMenu notifications.
@MainActor
final class MenuBarDropdownTracking {
    static let shared = MenuBarDropdownTracking()

    private enum Note {
        static let willOpen = Notification.Name("NSMenuWillOpen")
        static let didEndTracking = Notification.Name("NSMenuDidEndTracking")
    }

    private(set) var isOpen = false
    private var subscribers: [(id: UUID, onOpen: () -> Void, onClose: () -> Void)] = []
    private var observerInstalled = false
    private var closeTask: Task<Void, Never>?

    private init() {}

    func subscribe(onOpen: @escaping () -> Void, onClose: @escaping () -> Void) -> UUID {
        installObserverIfNeeded()
        let id = UUID()
        subscribers.append((id, onOpen, onClose))
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers.removeAll { $0.id == id }
    }

    private func noteOpened() {
        guard !isOpen else { return }
        isOpen = true
        subscribers.forEach { $0.onOpen() }
    }

    private func noteClosed() {
        guard isOpen else { return }
        isOpen = false
        subscribers.forEach { $0.onClose() }
    }

    private func installObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        NotificationCenter.default.addObserver(
            forName: Note.willOpen,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMenuWillOpen() }
        }
        NotificationCenter.default.addObserver(
            forName: Note.didEndTracking,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMenuDidEndTracking() }
        }
    }

    private func handleMenuWillOpen() {
        closeTask?.cancel()
        noteOpened()
    }

    /// `didEndTracking` also fires when entering nested submenus — debounce and cancel on the next `willOpen`.
    private func handleMenuDidEndTracking() {
        closeTask?.cancel()
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard let self, !Task.isCancelled else { return }
            self.noteClosed()
        }
    }
}

@main
struct BashXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var hub = AppHub()

    private var state: AppState { hub.state }
    private var traffic: TrafficMonitor { hub.trafficRoot.monitor }
    private var menuRates: MenuBarRateStore { hub.trafficRoot.menuRates }

    var body: some Scene {
        MenuBarExtra {
            MenuBarExtraContent(
                state: state,
                appDelegate: appDelegate,
                syncTraffic: syncTraffic,
                chrome: hub.trafficRoot.chrome
            )
            .equatable()
        } label: {
            // SwiftUI template Image — NSImageView templates often render invisible in the menu bar.
            MenuBarStatusLabel(chrome: hub.trafficRoot.chrome)
                .onAppear {
                    hub.trafficRoot.attachIfNeeded(state: state)
                    appDelegate.bind(state, trafficRoot: hub.trafficRoot, syncTraffic: syncTraffic)
                    state.refreshLaunchAtLogin()
                    syncTraffic()
                    hub.trafficRoot.startWatchdog(sync: syncTraffic)
                    IconManager.applyBundledAppIcon()
                    AppActivation.preferDockIcon = state.settings.showDockIcon
                    AppActivation.applyPolicy()
                }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsSceneHost(state: state)
                .onAppear { appDelegate.bind(state) }
        }
    }

    private func syncTraffic() {
        hub.trafficRoot.attachIfNeeded(state: state)
        traffic.menuBarRates = menuRates
        traffic.configure(
            controller: state.settings.externalController,
            secret: state.settings.secret
        )
        let alive = state.coreRunning || state.isCoreVisiblyAlive
        menuRates.setCoreRunning(alive)
        if alive {
            traffic.startTraffic()
        } else {
            traffic.stopTrafficOnly()
        }
        appDelegate.traffic = traffic
        PanelPresenter.shared.traffic = traffic
        PanelPresenter.shared.menuRates = menuRates
        PanelPresenter.shared.rebindOpenPanelIfNeeded(state: state)
        hub.trafficRoot.chrome.refresh(force: false)
    }
}

/// Settings observes AppState directly — must not live in BashXApp.body dependency on hub publishes.
private struct SettingsSceneHost: View {
    @ObservedObject var state: AppState

    var body: some View {
        BashXThemed(appearance: state.settings.appearance) {
            SettingsView()
                .environmentObject(state)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 560)
        }
    }
}

/// Isolates menu content from AppState @Published churn (prevents submenu flash).
private struct MenuBarExtraContent: View, Equatable {
    let state: AppState
    let appDelegate: AppDelegate
    let syncTraffic: () -> Void
    let chrome: MenuBarChrome

    @State private var trackingID: UUID?

    static func == (lhs: MenuBarExtraContent, rhs: MenuBarExtraContent) -> Bool {
        lhs.state === rhs.state && lhs.chrome === rhs.chrome
    }

    var body: some View {
        MenuBarView(state: state)
            .onAppear {
                if trackingID == nil {
                    trackingID = MenuBarDropdownTracking.shared.subscribe(
                        onOpen: { chrome.setMenuOpen(true) },
                        onClose: { chrome.setMenuOpen(false) }
                    )
                }
                appDelegate.bind(state, trafficRoot: nil, syncTraffic: syncTraffic)
                // Do NOT ensureCoreRunning / syncTraffic / refreshLaunchAtLogin here —
                // those publish AppState and remount this NSMenu (endless flash).
            }
            .onDisappear {
                if let trackingID {
                    MenuBarDropdownTracking.shared.unsubscribe(trackingID)
                    self.trackingID = nil
                }
            }
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var chrome: MenuBarChrome

    var body: some View {
        // Do NOT stack `.renderingMode(.template)` on an NSImage that is already
        // `isTemplate == true` — on some Macs that combination draws fully transparent.
        Group {
            if chrome.image.size.width > 0.5, chrome.image.size.height > 0.5 {
                Image(nsImage: chrome.image)
                    .interpolation(.high)
                    .frame(height: 24)
            } else {
                // Absolute fallback so the status item never disappears.
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            }
        }
        .help(chrome.help)
        .transaction { $0.animation = nil }
        .accessibilityLabel("BashX")
    }
}

/// Draws icon + two-line rates into a single status-item image (stable width).
enum MenuBarStatusImage {
    static func placeholder() -> NSImage {
        // Narrow placeholder — wide traffic glyphs often get pushed into the menu-bar overflow (❯❯).
        render(style: .default, down: "0.0K", up: "0.0K", showTraffic: false, dimmed: false)
    }

    static func render(
        style: LogoStyle,
        down: String,
        up: String,
        showTraffic: Bool,
        dimmed: Bool
    ) -> NSImage {
        // Keep a stable menu-bar size across macOS versions (16–18pt looks native).
        let iconPt: CGFloat = 18
        let gap: CGFloat = showTraffic ? 3 : 0
        let rateW: CGFloat = showTraffic ? 40 : 0
        let widthPt = iconPt + gap + rateW
        let heightPt: CGFloat = 18
        let alpha: CGFloat = dimmed ? 0.45 : 1
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 2)
        let pxW = max(1, Int((widthPt * scale).rounded()))
        let pxH = max(1, Int((heightPt * scale).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW,
            pixelsHigh: pxH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return assetFallback()
        }
        rep.size = NSSize(width: widthPt, height: heightPt)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else {
            return assetFallback()
        }
        NSGraphicsContext.current = gc
        gc.imageInterpolation = .high

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: widthPt, height: heightPt).fill()

        let icon = LogoRenderer.templateImage(style: style, size: iconPt)
        icon.isTemplate = false // draw as black bitmap into our template canvas
        let iconRect = NSRect(
            x: 0,
            y: (heightPt - iconPt) / 2,
            width: iconPt,
            height: iconPt
        )
        icon.draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: alpha,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        if showTraffic {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
            // Template images must be black; menu bar applies the system tint.
            let color = NSColor.black.withAlphaComponent(alpha)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            // Bitmap origin is bottom-left: higher Y = visually higher in the menu bar.
            let downLine = "↓\(sanitize(down))" as NSString
            let upLine = "↑\(sanitize(up))" as NSString
            let rateX = iconPt + gap
            let lineGap: CGFloat = 9
            downLine.draw(at: NSPoint(x: rateX, y: heightPt - lineGap), withAttributes: attrs)
            upLine.draw(at: NSPoint(x: rateX, y: heightPt - lineGap * 2), withAttributes: attrs)
        }

        let image = NSImage(size: NSSize(width: widthPt, height: heightPt))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func assetFallback() -> NSImage {
        if let img = NSImage(named: "MenuBarIcon") {
            let copy = img.copy() as? NSImage ?? img
            copy.isTemplate = true
            copy.size = NSSize(width: 22, height: 22)
            return copy
        }
        let img = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            NSColor.black.setFill()
            let inset = rect.insetBy(dx: 3, dy: 3)
            NSBezierPath(ovalIn: inset).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    private static func sanitize(_ rate: String) -> String {
        rate
            .replacingOccurrences(of: "\u{2007}", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Strong hold so quit cleanup always works (weak was often nil).
    private(set) var state: AppState?
    var traffic: TrafficMonitor?
    private weak var trafficRoot: TrafficRoot?
    private var syncTraffic: (() -> Void)?
    private var didCleanup = false
    private var stateCancellables = Set<AnyCancellable>()

    func bind(_ state: AppState, trafficRoot: TrafficRoot? = nil, syncTraffic: (() -> Void)? = nil) {
        self.state = state
        if let trafficRoot { self.trafficRoot = trafficRoot }
        if let syncTraffic {
            self.syncTraffic = syncTraffic
            stateCancellables.removeAll()
            state.$coreRunning
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.syncTraffic?() }
                .store(in: &stateCancellables)
            state.$chromeRevision
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.syncTraffic?() }
                .store(in: &stateCancellables)
            // Only traffic-relevant settings — delay-cache writes must not restart SSE.
            state.$settings
                .map { s in
                    (s.showMenuBarTraffic, s.menuNodeLimit, s.mixedPort, s.externalController, s.secret, s.appearance)
                }
                .removeDuplicates { $0 == $1 }
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.syncTraffic?() }
                .store(in: &stateCancellables)
        }
        SettingsOpener.register(state)
        GlobalHotkeys.shared.install(state: state)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Prefer settings file — AppDelegate.state is often still nil here (bound from MenuBarExtra later).
        // Never default to accessory when the user wants a Dock icon, or the icon "keeps vanishing".
        let preferDock = resolvedPreferDockIcon()
        AppActivation.preferDockIcon = preferDock
        AppActivation.applyPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Never block launch on xattr — large bundles hitch the main thread.
        stripDownloadQuarantineIfNeeded()
        let preferDock = resolvedPreferDockIcon()
        AppActivation.preferDockIcon = preferDock
        AppActivation.applyPolicy()
        // No macOS application menu strip — panel + menu-bar extra are enough.
        NSApp.mainMenu = NSMenu()
        IconManager.applyBundledAppIcon()
        IconManager.refreshDockIconCacheIfNeeded()
        // Re-assert Dock policy after icon cache refresh (must not leave accessory).
        AppActivation.preferDockIcon = preferDock
        AppActivation.applyPolicy()
        LogoRenderer.warmCache()
        if let state {
            trafficRoot?.attachIfNeeded(state: state)
        }
        // Force status-item redraw after menu bar is up (cold start often skips label onAppear).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            AppActivation.preferDockIcon = self.resolvedPreferDockIcon()
            AppActivation.applyPolicy()
            guard let state = self.state else { return }
            self.trafficRoot?.attachIfNeeded(state: state)
            self.syncTraffic?()
            NotificationCenter.default.post(name: .bashxMenuBarChromeNeedsRefresh, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            AppActivation.preferDockIcon = self.resolvedPreferDockIcon()
            AppActivation.applyPolicy()
            guard let state = self.state else { return }
            self.trafficRoot?.attachIfNeeded(state: state)
            self.syncTraffic?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, let state = self.state else { return }
            self.trafficRoot?.attachIfNeeded(state: state)
            self.syncTraffic?()
        }
    }

    /// Dock preference: live AppState if bound, else settings on disk (defaults to on).
    private func resolvedPreferDockIcon() -> Bool {
        if let state { return state.settings.showDockIcon }
        return SettingsStore.load().showDockIcon
    }

    /// DMG/browser downloads are quarantined — child mihomo may fail to exec until cleared.
    private func stripDownloadQuarantineIfNeeded() {
        let bundle = Bundle.main.bundlePath
        let mihomo = CoreInstaller.bundledPath.path
        DispatchQueue.global(qos: .utility).async {
            // Prefer clearing the binary first (fast), then the rest of the bundle.
            for path in [mihomo, bundle] where FileManager.default.fileExists(atPath: path) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                process.arguments = ["-cr", path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }
    }

    /// Menu-bar / LSUIElement app — never quit just because the last NSWindow closed
    /// (TUN password sheet briefly promotes to .regular; closing it used to exit BashX).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock icon click (or Finder reopen) → show the control panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let state else { return true }
        PanelPresenter.shared.open(
            state: state,
            traffic: traffic,
            menuRates: trafficRoot?.menuRates
        )
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCleanup else { return .terminateNow }
        didCleanup = true
        traffic?.stopAll()
        GlobalHotkeys.shared.unregister()
        state?.prepareForQuit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !didCleanup else { return }
        didCleanup = true
        traffic?.stopAll()
        GlobalHotkeys.shared.unregister()
        state?.prepareForQuit()
    }
}

enum IconManager {
    /// Always use the bundled AppIcon (yellow mark from Assets + logo.png) — never runtime gradients.
    static func applyBundledAppIcon() {
        NSApp.applicationIconImage = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
        refreshBundleIconCache()
    }

    /// After upgrade, re-register the bundle icon. Never kill Dock — that makes the whole
    /// Dock vanish and looks like BashX "lost" the Dock icon on every update.
    static func refreshDockIconCacheIfNeeded() {
        let key = "bashx.dockIconCacheVersion"
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "1"
        guard UserDefaults.standard.string(forKey: key) != ver else { return }
        UserDefaults.standard.set(ver, forKey: key)
        refreshBundleIconCache(forceDockRestart: false)
    }

    private static func refreshBundleIconCache(forceDockRestart: Bool = false) {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
        LSRegisterURL(url, true)
        // Intentionally never killall Dock — forceDockRestart kept for API compat only.
        _ = forceDockRestart
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

extension Notification.Name {
    /// Posted after launch so MenuBarChrome redraws once the status item is on-screen.
    static let bashxMenuBarChromeNeedsRefresh = Notification.Name("bashx.menuBarChromeNeedsRefresh")
}
