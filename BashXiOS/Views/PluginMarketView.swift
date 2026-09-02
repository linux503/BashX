import SwiftUI

/// Plugin marketplace for iOS.
struct PluginMarketViewIOS: View {
    @EnvironmentObject private var state: IOSAppState
    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        List {
            Section {
                Text(t("plugin.market.hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)

                HStack(spacing: 10) {
                    Button {
                        state.setAllPluginsEnabled(true)
                    } label: {
                        Label(t("plugin.market.enableAll"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(IOSTheme.accentGradient)
                    )

                    Button {
                        state.setAllPluginsEnabled(false)
                    } label: {
                        Label(t("plugin.market.disableAll"), systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(IOSTheme.accentDeep)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(IOSTheme.accentSoft)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(IOSTheme.accent.opacity(0.2), lineWidth: 0.8)
                            )
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Section(t("plugin.market.section")) {
                ForEach(PluginEngine.catalogForCurrentPlatform) { plugin in
                    pluginRow(plugin)
                }
            }
        }
        .navigationTitle(t("plugin.market.title"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(IOSTheme.accent)
    }

    private func pluginRow(_ plugin: PluginEngine.Plugin) -> some View {
        let on = state.settings.enabledPluginIds.contains(plugin.id)
        return Toggle(isOn: Binding(
            get: { on },
            set: { state.setPluginEnabled(plugin.id, enabled: $0) }
        )) {
            HStack(spacing: 12) {
                Image(systemName: plugin.symbol)
                    .font(.title3)
                    .foregroundStyle(IOSTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(.body.weight(.semibold))
                        Text(plugin.tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(plugin.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(format: t("plugin.market.rules"), "\(plugin.ruleCount)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if plugin.scriptHeavy {
                        Text(t("plugin.market.scriptNote"))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
