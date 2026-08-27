import Foundation

enum SettingsStore {
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: Paths.settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func save(_ settings: AppSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        do {
            try data.write(to: Paths.settingsURL, options: .atomic)
            #if os(macOS)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Paths.settingsURL.path
            )
            if FileManager.default.fileExists(atPath: Paths.configURL.path) {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: Paths.configURL.path
                )
            }
            #endif
            return true
        } catch {
            return false
        }
    }
}
