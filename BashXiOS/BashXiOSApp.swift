import SwiftUI

@main
struct BashXiOSApp: App {
    @StateObject private var state = IOSAppState()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(state)
                .environmentObject(state.vpn)
                .preferredColorScheme(.light)
                .tint(IOSTheme.accent)
        }
    }
}
