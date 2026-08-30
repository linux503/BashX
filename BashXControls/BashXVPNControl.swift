import AppIntents
import SwiftUI
import WidgetKit

struct SetBashXVPNIntent: SetValueIntent {
    static var title: LocalizedStringResource = "BashX VPN"
    static var description = IntentDescription("在控制中心开关 BashX VPN")

    @Parameter(title: "已连接")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await VPNQuickControl.setConnected(value)
        return .result()
    }
}

struct BashXVPNStatusProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        await VPNQuickControl.isConnected()
    }
}

/// Control Center / Lock Screen button (iOS 18+).
struct BashXVPNControl: ControlWidget {
    static let kind = VPNQuickControl.controlKind

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: BashXVPNStatusProvider()
        ) { isOn in
            ControlWidgetToggle(
                "BashX",
                isOn: isOn,
                action: SetBashXVPNIntent()
            ) { on in
                Label {
                    Text(on ? "已连接" : "未连接")
                } icon: {
                    Image("bashx.mark")
                        .symbolRenderingMode(.monochrome)
                }
            }
            .tint(Color(red: 1.0, green: 0.82, blue: 0.14))
        }
        .displayName("BashX VPN")
        .description("一键连接或断开 BashX")
    }
}
