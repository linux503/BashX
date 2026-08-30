import Foundation
#if os(macOS)
import AppKit
#endif

/// Keep Cursor IDE / agent streams usable while BashX is running.
enum CursorReliability {
    static let probeURL = "https://cursor.com"
    static let fallbackProbeURL = "https://api2.cursor.sh"
    static let autoTestURL = "https://cursor.com"

    static func isCursorRunning() -> Bool {
        #if os(macOS)
        NSWorkspace.shared.runningApplications.contains { app in
            let bid = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            return bid.contains("230313mzl4w4u92") || name == "cursor"
        }
        #else
        false
        #endif
    }
}
