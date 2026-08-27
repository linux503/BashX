import AppKit
import SwiftUI

/// Keeps activation policy in sync with dock-icon preference and open windows.
enum AppActivation {
    static let panelID = "bashx.main"
    static let settingsID = "bashx.settings"
    static let addSubscriptionID = "bashx.addSubscription"
    @MainActor static var preferDockIcon = false

    @MainActor
    static func applyPolicy() {
        NSApp.setActivationPolicy(preferDockIcon ? .regular : .accessory)
    }

    @MainActor
    static func promoteForWindow() {
        if preferDockIcon {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    static func refreshAfterWindowClosed() {
        let hasVisible = NSApp.windows.contains { window in
            guard window.isVisible else { return false }
            let id = window.identifier?.rawValue ?? ""
            return id == panelID || id == settingsID || id == addSubscriptionID
        }
        if !hasVisible, !preferDockIcon {
            NSApp.setActivationPolicy(.accessory)
        } else if preferDockIcon {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @MainActor
    static func centerWindow(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrameOrigin(frame.origin)
    }

    @MainActor
    static func window(withID id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id }
    }

    /// Closes stray duplicates (e.g. race while menu bar is dismissing).
    @MainActor
    static func closeDuplicateWindows(withID id: String, keeping keep: NSWindow?) {
        for win in NSApp.windows where win.identifier?.rawValue == id && win !== keep {
            win.orderOut(nil)
            win.close()
        }
    }
}

@MainActor
final class SettingsPresenter {
    static let shared = SettingsPresenter()

    private var window: NSWindow?
    private var host: NSHostingController<AnyView>?
    private var windowDelegate: BashXWindowDelegate?

    func open(state: AppState, deferForMenuDismiss: Bool = false) {
        if deferForMenuDismiss {
            DispatchQueue.main.async { [weak self] in
                self?.present(state: state)
            }
        } else {
            present(state: state)
        }
    }

    func refreshAppearance(state: AppState) {
        guard let host else { return }
        host.rootView = settingsRoot(state: state)
    }

    private func settingsRoot(state: AppState) -> AnyView {
        AnyView(
            BashXThemed(appearance: state.settings.appearance) {
                SettingsView()
                    .environmentObject(state)
                    .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 660)
            }
        )
    }

    private func present(state: AppState) {
        SettingsOpener.register(state)

        let root = settingsRoot(state: state)

        if host == nil {
            let controller = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: controller)
            win.title = "BashX 设置"
            win.setContentSize(NSSize(width: 680, height: 660))
            win.minSize = NSSize(width: 620, height: 560)
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.titlebarAppearsTransparent = false
            win.titleVisibility = .visible
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            win.identifier = NSUserInterfaceItemIdentifier(AppActivation.settingsID)
            let delegate = BashXWindowDelegate { [weak self] in
                self?.window?.orderOut(nil)
                AppActivation.refreshAfterWindowClosed()
            }
            win.delegate = delegate
            windowDelegate = delegate
            host = controller
            window = win
        } else {
            host?.rootView = root
        }

        AppActivation.promoteForWindow()
        if let window {
            AppActivation.centerWindow(window)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

@MainActor
final class PanelPresenter {
    static let shared = PanelPresenter()

    private static let defaultSize = NSSize(width: 1280, height: 860)
    private static let minimumSize = NSSize(width: 1100, height: 680)

    private var window: NSWindow?
    private var host: NSHostingController<AnyView>?
    private var windowDelegate: BashXWindowDelegate?

    /// Fallbacks so the panel never crashes when opened before traffic sync.
    private let fallbackTraffic = TrafficMonitor()
    private let fallbackRates = MenuBarRateStore()
    /// True when the live hosting tree still observes `fallbackRates` (needs one-time rebind).
    private var panelBoundToFallbackRates = false
    private var isPresenting = false
    private var pendingPresent: (state: AppState, intent: AppState.PanelIntent)?

    var traffic: TrafficMonitor?
    var menuRates: MenuBarRateStore?

    func open(
        state: AppState,
        traffic: TrafficMonitor? = nil,
        menuRates: MenuBarRateStore? = nil,
        intent: AppState.PanelIntent = .none
    ) {
        if let traffic { self.traffic = traffic }
        if let menuRates { self.menuRates = menuRates }

        // Defer until the menu bar dropdown has dismissed (fixes "panel won't open" after install).
        DispatchQueue.main.async { [weak self] in
            self?.enqueuePresent(state: state, intent: intent)
        }
    }

    private func enqueuePresent(state: AppState, intent: AppState.PanelIntent) {
        if isPresenting {
            pendingPresent = (state, intent)
            return
        }
        isPresenting = true
        present(state: state, intent: intent)
        isPresenting = false
        if let pending = pendingPresent {
            pendingPresent = nil
            enqueuePresent(state: pending.state, intent: pending.intent)
        }
    }

    private func bindExistingPanelIfNeeded() {
        guard window == nil || host == nil,
              let existing = AppActivation.window(withID: AppActivation.panelID)
        else { return }
        window = existing
        host = existing.contentViewController as? NSHostingController<AnyView>
        panelBoundToFallbackRates = (menuRates == nil)
    }

    func refreshAppearance(state: AppState) {
        guard let host else { return }
        let monitor = resolvedTraffic()
        let rates = resolvedRates()
        host.rootView = panelRoot(state: state, monitor: monitor, rates: rates)
    }

    private func panelRoot(state: AppState, monitor: TrafficMonitor, rates: MenuBarRateStore) -> AnyView {
        AnyView(
            BashXThemed(appearance: state.settings.appearance) {
                MainView(state: state, monitor: monitor, rates: rates)
                    .environmentObject(state)
                    .frame(
                        minWidth: Self.minimumSize.width,
                        minHeight: Self.minimumSize.height
                    )
            }
        )
    }

    private func present(state: AppState, intent: AppState.PanelIntent) {
        bindExistingPanelIfNeeded()
        AppActivation.closeDuplicateWindows(withID: AppActivation.panelID, keeping: window)

        SettingsOpener.register(state)
        AddSubscriptionOpener.register(state)
        let monitor = resolvedTraffic()
        let rates = resolvedRates()

        monitor.configure(
            controller: state.settings.externalController,
            secret: state.settings.secret
        )
        // configure() may cancel the SSE task when controller/secret changes — restart if core is up.
        if state.isCoreVisiblyAlive || state.coreRunning {
            monitor.startTraffic()
        }

        if intent != .none {
            state.panelIntent = intent
        }
        IconManager.applyAppIcon(style: state.settings.logoStyle)

        if host == nil || window == nil {
            let root = panelRoot(state: state, monitor: monitor, rates: rates)
            let controller = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: controller)
            win.title = "BashX"
            win.setContentSize(Self.defaultSize)
            win.minSize = Self.minimumSize
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.titlebarAppearsTransparent = false
            win.titleVisibility = .visible
            win.isReleasedWhenClosed = false
            // Ventura: keep mouse events on the content view (sheet/modal bugs otherwise).
            win.acceptsMouseMovedEvents = true
            win.isMovableByWindowBackground = false
            win.center()
            win.identifier = NSUserInterfaceItemIdentifier(AppActivation.panelID)
            let delegate = BashXWindowDelegate { [weak self] in
                guard let self else { return }
                self.traffic?.chartSamplesEnabled = false
                self.traffic?.stopConnectionsAndLogs()
                AddSubscriptionPresenter.shared.close()
                self.window?.orderOut(nil)
                AppActivation.refreshAfterWindowClosed()
            }
            win.delegate = delegate
            windowDelegate = delegate
            host = controller
            window = win
            panelBoundToFallbackRates = (menuRates == nil)
        } else if let host, let window {
            // One-time upgrade if panel was created before syncTraffic wired the live rate store.
            if panelBoundToFallbackRates, let menuRates {
                host.rootView = panelRoot(state: state, monitor: monitor, rates: menuRates)
                panelBoundToFallbackRates = false
            }
            // Do NOT replace rootView on every open — resets @State and can freeze hit-testing on Ventura.
            let preferred = Self.defaultSize
            let current = window.contentLayoutRect.size
            if current.width < preferred.width - 20 || current.height < preferred.height - 20 {
                window.setContentSize(preferred)
                AppActivation.centerWindow(window)
            }
        }

        AppActivation.closeDuplicateWindows(withID: AppActivation.panelID, keeping: window)
        AppActivation.promoteForWindow()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        // Add-subscription sheet is opened once from MainView.consumePanelIntent().

        Task { _ = await state.ensureCoreRunning() }
    }

    private func resolvedTraffic() -> TrafficMonitor {
        if let traffic { return traffic }
        return fallbackTraffic
    }

    private func resolvedRates() -> MenuBarRateStore {
        if let menuRates { return menuRates }
        return fallbackRates
    }
}

/// Dedicated window for add-subscription — SwiftUI `.sheet` is unreliable in LSUIElement panels on Ventura.
@MainActor
final class AddSubscriptionPresenter {
    static let shared = AddSubscriptionPresenter()

    private var window: NSWindow?
    private var host: NSHostingController<AnyView>?
    private var windowDelegate: BashXWindowDelegate?
    private weak var boundState: AppState?

    func open(state: AppState, deferForMenuDismiss: Bool = false) {
        boundState = state
        if deferForMenuDismiss {
            DispatchQueue.main.async { [weak self] in
                self?.present(state: state)
            }
        } else {
            present(state: state)
        }
    }

    func close() {
        window?.orderOut(nil)
        AppActivation.refreshAfterWindowClosed()
    }

    private func present(state: AppState) {
        let root = AnyView(
            BashXThemed(appearance: state.settings.appearance) {
                AddSubscriptionSheet(
                    isPresented: Binding(
                        get: { true },
                        set: { [weak self] open in
                            if !open { self?.close() }
                        }
                    )
                )
                .environmentObject(state)
            }
        )

        if host == nil {
            let controller = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: controller)
            win.title = "添加订阅"
            win.styleMask = [.titled, .closable]
            win.titlebarAppearsTransparent = false
            win.titleVisibility = .visible
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 520, height: 420))
            win.minSize = NSSize(width: 480, height: 360)
            win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            win.identifier = NSUserInterfaceItemIdentifier(AppActivation.addSubscriptionID)
            win.level = .floating
            win.acceptsMouseMovedEvents = true
            let delegate = BashXWindowDelegate { [weak self] in
                self?.window?.orderOut(nil)
                AppActivation.refreshAfterWindowClosed()
            }
            win.delegate = delegate
            windowDelegate = delegate
            host = controller
            window = win
        } else {
            host?.rootView = root
        }

        AppActivation.promoteForWindow()
        if let window {
            AppActivation.centerWindow(window)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

enum AddSubscriptionOpener {
    private static weak var boundState: AppState?

    @MainActor
    static func register(_ state: AppState) {
        boundState = state
    }

    @MainActor
    static func open(state: AppState? = nil, fromMenuBar: Bool = false) {
        let resolved = state ?? boundState
        guard let resolved else { return }
        AddSubscriptionPresenter.shared.open(state: resolved, deferForMenuDismiss: fromMenuBar)
    }
}

final class BashXWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
