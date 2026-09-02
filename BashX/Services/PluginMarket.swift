import Foundation

/// Thin facade — catalog & merge live in `PluginEngine`.
enum PluginMarket {
    typealias Plugin = PluginEngine.Plugin

    static var catalog: [Plugin] { PluginEngine.catalogForCurrentPlatform }

    static func plugin(id: String) -> Plugin? {
        PluginEngine.plugin(id: id)
    }

    static func enabledRules(ids: [String]) -> [String] {
        PluginEngine.rules(forEnabledIds: ids)
    }

    static func merge(into base: [String], enabledIds: [String]) -> [String] {
        PluginEngine.merge(into: base, enabledIds: enabledIds)
    }
}
