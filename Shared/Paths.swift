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

    /// User-facing path with `~` for home (menu / panel labels).
    static func shortPath(_ url: URL) -> String {
        let full = url.path
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if full.hasPrefix(home + "/") {
            return "~/" + full.dropFirst(home.count + 1)
        }
        #endif
        return full
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

    /// Keep support files from growing without bound (core.log, tunnel.log).
    static func trimLogIfNeeded(_ url: URL, maxBytes: Int = 2 * 1024 * 1024) {
        guard maxBytes > 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxBytes else { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let keep = min(maxBytes, 512 * 1024)
        try? handle.seek(toOffset: UInt64(max(0, size.intValue - keep)))
        let tail = handle.readDataToEndOfFile()
        try? Data().write(to: url)
        if let out = try? FileHandle(forWritingTo: url) {
            defer { try? out.close() }
            out.write(tail)
        }
    }

    static func trimSupportLogs() {
        trimLogIfNeeded(supportDir.appendingPathComponent("core.log"))
        trimLogIfNeeded(supportDir.appendingPathComponent("launch.log"))
        trimLogIfNeeded(supportDir.appendingPathComponent("tunnel.log"), maxBytes: 1024 * 1024)
    }
}
