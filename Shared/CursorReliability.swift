import Foundation
#if os(macOS)
import AppKit
#endif

/// Keep Cursor IDE / agent streams usable while BashX is running.
enum CursorReliability {
    /// Prefer API host used by the IDE agent — marketing site is a weak liveness signal.
    static let probeURL = "https://api2.cursor.sh"
    static let fallbackProbeURL = "https://cursor.com"
    static let autoTestURL = "https://api2.cursor.sh"

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
