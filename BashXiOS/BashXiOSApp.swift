import SwiftUI

@main
struct BashXiOSApp: App {
    @StateObject private var state = IOSAppState()

    var body: some Scene {
        WindowGroup {
            RootContainer()
                .environmentObject(state)
                .environmentObject(state.vpn)
                .tint(IOSTheme.accent)
                .onOpenURL { state.handleOpenURL($0) }
        }
    }
}

private struct RootContainer: View {
    @EnvironmentObject private var state: IOSAppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if state.showsDisguise {
                DisguiseGalleryView {
                    state.unlockApp()
                }
            } else {
                RootTabView()
            }
        }
        .task {
            // Cold start: onChange(scenePhase) may not fire for the initial .active.
            await state.vpn.recoverIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                state.lockApp()
            } else if phase == .active {
                Task { await state.vpn.recoverIfNeeded() }
            }
        }
        .onAppear {
            // Cold start always behind camouflage when enabled.
            if state.settings.iosDisguiseEnabled {
                state.isAppUnlocked = false
            }
        }
    }
}
