import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var vpn: VPNManager

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: vpn.isConnected ? "checkmark.shield.fill" : "house.fill")
                }
            NodesView()
                .tabItem { Label("节点", systemImage: "point.3.connected.trianglepath.dotted") }
            SubscriptionsView()
                .tabItem { Label("订阅", systemImage: "tray.full.fill") }
            SettingsViewIOS()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(IOSTheme.accent)
    }
}
