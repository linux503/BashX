import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum IOSIconManager {
    /// Asset catalog names: primary `AppIcon` (markX / brand) → nil;
    /// alternates are `AppIcon-{rawValue}` from INCLUDE_ALL_APPICON_ASSETS.
    static func alternateIconName(for style: LogoStyle) -> String? {
        style == LogoStyle.iosPrimary ? nil : "AppIcon-\(style.rawValue)"
    }

    static var supportsAlternateIcons: Bool {
        #if canImport(UIKit)
        UIApplication.shared.supportsAlternateIcons
        #else
        false
        #endif
    }

    /// Styles shown in Settings picker (phone-optimized).
    static var selectableStyles: [LogoStyle] { LogoStyle.iosCurated }

    @MainActor
    static func apply(style: LogoStyle) async {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let target = alternateIconName(for: style)
        if UIApplication.shared.alternateIconName == target { return }

        // Defer so SwiftUI finishes the tap before the system icon alert.
        try? await Task.sleep(nanoseconds: 250_000_000)

        let error = await withCheckedContinuation { (cont: CheckedContinuation<Error?, Never>) in
            UIApplication.shared.setAlternateIconName(target) { err in
                cont.resume(returning: err)
            }
        }
        if error != nil {
            // Restore primary so SpringBoard never shows a blank tile.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                UIApplication.shared.setAlternateIconName(nil) { _ in
                    cont.resume()
                }
            }
        }
        #endif
    }
}

extension LogoStyle {
    var iosPreviewImageName: String { "LogoPreview-\(rawValue)" }
}
