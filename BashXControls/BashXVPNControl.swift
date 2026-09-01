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
                isOn ? "已连接" : "BashX",
                isOn: isOn,
                action: SetBashXVPNIntent()
            ) { on in
                // Custom SF Symbol — bold hex + X (see scripts/gen_control_symbol.py)
                Label(on ? "已连接" : "未连接", image: "bashx.mark")
                    .symbolRenderingMode(.monochrome)
            }
            .tint(isOn
                  ? Color(red: 0.20, green: 0.78, blue: 0.45)
                  : Color(red: 1.0, green: 0.78, blue: 0.12))
        }
        .displayName("BashX")
        .description("一键连接或断开 BashX VPN")
    }
}
