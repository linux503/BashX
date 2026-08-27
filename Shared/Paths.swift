import Foundation

enum Paths {
    #if os(iOS)
    /// App Group container — required for app ↔ extension config sharing.
    static var appGroupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
    }

    static var usesAppGroup: Bool { appGroupContainer != nil }
    #endif

    static var supportDir: URL {
        #if os(iOS)
        let fm = FileManager.default
        let base: URL
        if let group = appGroupContainer {
            // Must live under Library/ so Mac can pull logs via devicectl,
            // and to follow App Group layout rules on newer iOS.
            base = group.appendingPathComponent("Library", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            migrateLegacyRootIfNeeded(group: group, libraryBase: base)
        } else {
            base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        let dir = base.appendingPathComponent("BashX", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BashX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #endif
    }

    #if os(iOS)
    /// Old builds wrote to `<group>/BashX` (not under Library). Move once.
    private static func migrateLegacyRootIfNeeded(group: URL, libraryBase: URL) {
        let fm = FileManager.default
        let legacy = group.appendingPathComponent("BashX", isDirectory: true)
        let dest = libraryBase.appendingPathComponent("BashX", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path) else { return }
        if !fm.fileExists(atPath: dest.path) {
            try? fm.createDirectory(at: libraryBase, withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: dest)
            return
        }
        // Dest exists — copy missing children then remove legacy.
        if let kids = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            for child in kids {
                let target = dest.appendingPathComponent(child.lastPathComponent)
                if !fm.fileExists(atPath: target.path) {
                    try? fm.copyItem(at: child, to: target)
                }
            }
        }
        try? fm.removeItem(at: legacy)
    }
    #endif

    static var settingsURL: URL { supportDir.appendingPathComponent("settings.json") }
    static var configURL: URL { supportDir.appendingPathComponent("config.yaml") }
    static var lastSubscriptionURL: URL { supportDir.appendingPathComponent("subscription.yaml") }
    static var rulesURL: URL { supportDir.appendingPathComponent("rules.txt") }
    static var tunnelLogURL: URL { supportDir.appendingPathComponent("tunnel.log") }

    static func subscriptionCacheURL(id: UUID) -> URL {
        supportDir.appendingPathComponent("subs").appendingPathComponent("\(id.uuidString).bin")
    }

    static var subscriptionsCacheDir: URL {
        let dir = supportDir.appendingPathComponent("subs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Mihomo home inside the App Group (used by Packet Tunnel).
    static var mihomoHomeDir: URL {
        let dir = supportDir.appendingPathComponent("mihomo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var mihomoConfigURL: URL {
        mihomoHomeDir.appendingPathComponent("config.yaml")
    }
}
