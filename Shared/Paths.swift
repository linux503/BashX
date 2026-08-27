import Foundation

enum Paths {
    static var supportDir: URL {
        #if os(iOS)
        let base: URL = {
            if let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
            ) {
                return group
            }
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }()
        let dir = base.appendingPathComponent("BashX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BashX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #endif
    }

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
