import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var vpn: VPNManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: vpn.isConnected ? "shield.checkered" : "shield.lefthalf.filled") }
            NodesView()
                .tabItem { Label("节点", systemImage: "list.bullet.rectangle.portrait") }
            SubscriptionsView()
                .tabItem { Label("订阅", systemImage: "link") }
            SettingsViewIOS()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(IOSTheme.accent)
    }
}
