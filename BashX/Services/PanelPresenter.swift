import AppKit
import SwiftUI

/// Keeps activation policy in sync with dock-icon preference and open windows.
enum AppActivation {
    static let panelID = "bashx.main"
    static let settingsID = "bashx.settings"
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
            return id == panelID || id == settingsID
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
            self?.present(state: state, intent: intent)
        }
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
        SettingsOpener.register(state)
        let monitor = resolvedTraffic()
        let rates = resolvedRates()

        monitor.configure(
            controller: state.settings.externalController,
            secret: state.settings.secret
        )

        if intent != .none {
            state.panelIntent = intent
        }
        IconManager.applyAppIcon(style: state.settings.logoStyle)

        let root = panelRoot(state: state, monitor: monitor, rates: rates)

        if let host {
            host.rootView = root
            if let window {
                // Grow undersized panels after upgrades (keep larger user-resized windows).
                let preferred = Self.defaultSize
                let current = window.contentLayoutRect.size
                if current.width < preferred.width - 20 || current.height < preferred.height - 20 {
                    window.setContentSize(preferred)
                    AppActivation.centerWindow(window)
                }
            }
        } else {
            let controller = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: controller)
            win.title = "BashX"
            win.setContentSize(Self.defaultSize)
            win.minSize = Self.minimumSize
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.titlebarAppearsTransparent = false
            win.titleVisibility = .visible
            win.isReleasedWhenClosed = false
            win.center()
            win.identifier = NSUserInterfaceItemIdentifier(AppActivation.panelID)
            let delegate = BashXWindowDelegate { [weak self] in
                self?.traffic?.chartSamplesEnabled = false
                self?.traffic?.stopConnectionsAndLogs()
                AppActivation.refreshAfterWindowClosed()
            }
            win.delegate = delegate
            windowDelegate = delegate
            host = controller
            window = win
        }

        AppActivation.promoteForWindow()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

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

final class BashXWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
