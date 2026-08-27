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

    init() {
        monitor.menuBarRates = menuRates
    }

    /// Late-bind state after AppHub creates both.
    func attach(state: AppState) {
        chrome.bind(rates: menuRates, state: state)
        chrome.refresh(force: true)
    }

    func startWatchdog(sync: @escaping () -> Void) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
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

    func bind(rates: MenuBarRateStore, state: AppState?) {
        self.rates = rates
        if let state { self.state = state }
        cancellables.removeAll()
        rates.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: false) }
            .store(in: &cancellables)
        state?.$chromeRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh(force: false) }
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
        let dimmed = show && !alive && down == "0.0K" && up == "0.0K"
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
                    hub.trafficRoot.attach(state: state)
                    appDelegate.bind(state, syncTraffic: syncTraffic)
                    state.refreshLaunchAtLogin()
                    syncTraffic()
                    hub.trafficRoot.startWatchdog(sync: syncTraffic)
                    IconManager.applyAppIcon(style: state.settings.logoStyle)
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
        traffic.configure(
            controller: state.settings.externalController,
            secret: state.settings.secret
        )
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

    static func == (lhs: MenuBarExtraContent, rhs: MenuBarExtraContent) -> Bool {
        lhs.state === rhs.state && lhs.chrome === rhs.chrome
    }

    var body: some View {
        MenuBarView(state: state)
            .background(MenuBarLifecycleHook(
                onOpen: { chrome.setMenuOpen(true) },
                onClose: { chrome.setMenuOpen(false) }
            ))
            .onAppear {
                chrome.setMenuOpen(true)
                appDelegate.bind(state, syncTraffic: syncTraffic)
                state.refreshLaunchAtLogin()
                syncTraffic()
                Task { _ = await state.ensureCoreRunning() }
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
                    .frame(height: 18)
            } else {
                // Absolute fallback so the status item never disappears.
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
        }
        .help(chrome.help)
        .transaction { $0.animation = nil }
        .accessibilityLabel("BashX")
    }
}

/// Tracks menu open/close so status-item rates freeze while the dropdown is visible.
private struct MenuBarLifecycleHook: NSViewRepresentable {
    var onOpen: () -> Void
    var onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HookView()
        view.onOpen = onOpen
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HookView else { return }
        view.onOpen = onOpen
        view.onClose = onClose
    }

    private final class HookView: NSView {
        var onOpen: (() -> Void)?
        var onClose: (() -> Void)?
        private var opened = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                if !opened {
                    opened = true
                    onOpen?()
                }
            } else if opened {
                opened = false
                onClose?()
            }
        }
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
        let iconPt: CGFloat = 16
        let gap: CGFloat = showTraffic ? 3 : 0
        let rateW: CGFloat = showTraffic ? 42 : 0
        let widthPt = iconPt + gap + rateW
        let heightPt: CGFloat = 18
        let alpha: CGFloat = dimmed ? 0.45 : 1
        // Always bake @2x pixels — `lockFocus` produces empty/invisible templates on some Macs.
        let scale: CGFloat = 2
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
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            // Template images must be black; menu bar applies the system tint.
            let color = NSColor.black.withAlphaComponent(alpha)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let downLine = "↓\(sanitize(down))" as NSString
            let upLine = "↑\(sanitize(up))" as NSString
            let rateX = iconPt + gap
            downLine.draw(at: NSPoint(x: rateX, y: heightPt / 2 + 0.5), withAttributes: attrs)
            upLine.draw(at: NSPoint(x: rateX, y: 0.5), withAttributes: attrs)
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
            copy.size = NSSize(width: 16, height: 16)
            return copy
        }
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
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
    private var syncTraffic: (() -> Void)?
    private var didCleanup = false
    private var stateCancellables = Set<AnyCancellable>()

    func bind(_ state: AppState, syncTraffic: (() -> Void)? = nil) {
        self.state = state
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
            state.$settings
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.syncTraffic?() }
                .store(in: &stateCancellables)
        }
        SettingsOpener.register(state)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register as accessory early so MenuBarExtra is created even when Dock icon is off.
        // Doing this only in didFinishLaunching can leave a blank/missing status item on some Macs.
        let preferDock = state?.settings.showDockIcon ?? false
        AppActivation.preferDockIcon = preferDock
        AppActivation.applyPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.preferDockIcon = state?.settings.showDockIcon ?? false
        AppActivation.applyPolicy()
        IconManager.applyAppIcon(style: state?.settings.logoStyle ?? .default)
        LogoRenderer.warmCache()
        // Force a fresh status-item bitmap after the menu bar is up (avoids first-frame blank icon).
        DispatchQueue.main.async { [weak self] in
            self?.syncTraffic?()
            NotificationCenter.default.post(name: .bashxMenuBarChromeNeedsRefresh, object: nil)
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
    /// Multi-resolution dock / Finder icon (Ventura scales 16–512 pt cleanly).
    static func dockIcon(style: LogoStyle = .default) -> NSImage {
        let sizes: [(pixels: Int, points: CGFloat)] = [
            (512, 512), (256, 256), (128, 128), (64, 64), (32, 32), (16, 16),
        ]
        let image = NSImage(size: NSSize(width: 512, height: 512))
        for item in sizes {
            let rendered = LogoRenderer.appIcon(style: style, pixels: item.pixels)
            guard let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: item.points, height: item.points)
            image.addRepresentation(rep)
        }
        return image
    }

    /// Apply dock / panel app icon for the selected logo style.
    static func applyAppIcon(style: LogoStyle = .default) {
        let image = dockIcon(style: style)
        NSApp.applicationIconImage = image
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    /// Non-blocking dock icon update (logo picker / settings).
    static func applyAppIconAsync(style: LogoStyle = .default) {
        Task.detached(priority: .utility) {
            let image = dockIcon(style: style)
            await MainActor.run {
                NSApp.applicationIconImage = image
                NSApp.dockTile.contentView = nil
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

extension Notification.Name {
    /// Posted after launch so MenuBarChrome redraws once the status item is on-screen.
    static let bashxMenuBarChromeNeedsRefresh = Notification.Name("bashx.menuBarChromeNeedsRefresh")
}
