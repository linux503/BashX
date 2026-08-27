import AppIntents
import Foundation

/// Shortcuts + Control Center: toggle BashX VPN.
struct ToggleBashXVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "切换 BashX VPN"
    static var description = IntentDescription("连接或断开 BashX VPN")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let nowOn = try await VPNQuickControl.toggle()
        return .result(dialog: IntentDialog(stringLiteral: nowOn ? "BashX 已连接" : "BashX 已断开"))
    }
}

struct ConnectBashXVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "连接 BashX VPN"
    static var description = IntentDescription("启动 BashX VPN")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await VPNQuickControl.setConnected(true)
        return .result(dialog: IntentDialog("BashX 已连接"))
    }
}

struct DisconnectBashXVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "断开 BashX VPN"
    static var description = IntentDescription("停止 BashX VPN")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await VPNQuickControl.setConnected(false)
        return .result(dialog: IntentDialog("BashX 已断开"))
    }
}

struct BashXAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleBashXVPNIntent(),
            phrases: [
                "切换 \(.applicationName) VPN",
                "打开 \(.applicationName)",
                "关闭 \(.applicationName) VPN",
            ],
            shortTitle: "切换 VPN",
            systemImageName: "shield.lefthalf.filled"
        )
        AppShortcut(
            intent: ConnectBashXVPNIntent(),
            phrases: [
                "连接 \(.applicationName)",
                "打开 \(.applicationName) VPN",
            ],
            shortTitle: "连接 VPN",
            systemImageName: "checkmark.shield.fill"
        )
        AppShortcut(
            intent: DisconnectBashXVPNIntent(),
            phrases: [
                "断开 \(.applicationName)",
                "关闭 \(.applicationName)",
            ],
            shortTitle: "断开 VPN",
            systemImageName: "xmark.shield.fill"
        )
    }
}
