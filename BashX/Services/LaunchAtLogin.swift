import Foundation
import ServiceManagement

enum LaunchAtLogin {
    /// Register / unregister as a Login Item (macOS 13+ SMAppService).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            return false
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "已开启"
        case .requiresApproval:
            return "需在「系统设置 → 通用 → 登录项」中允许"
        case .notRegistered:
            return "未开启"
        case .notFound:
            return "当前构建不支持登录项"
        @unknown default:
            return "未知状态"
        }
    }
}
