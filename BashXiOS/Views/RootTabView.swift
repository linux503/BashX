import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager

    private var lang: AppLanguage { state.settings.uiLanguage }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $state.selectedTab) {
            HomeView()
                .tabItem {
                    Label(
                        L10n.t("tab.home", lang),
                        systemImage: vpn.isConnected ? "checkmark.shield.fill" : "house.fill"
                    )
                }
                .tag(0)
            NodesView()
                .tabItem {
                    Label(L10n.t("tab.nodes", lang), systemImage: "point.3.connected.trianglepath.dotted")
                }
                .tag(1)
            SubscriptionsView()
                .tabItem {
                    Label(L10n.t("tab.subscriptions", lang), systemImage: "tray.full.fill")
                }
                .tag(2)
            SettingsViewIOS()
                .tabItem {
                    Label(L10n.t("tab.settings", lang), systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(IOSTheme.accent)
        .id(lang.id)
    }
}
