import SwiftUI

/// Plugin marketplace for Mac settings.
struct PluginMarketPane: View {
    @EnvironmentObject private var state: AppState
    private var appearance: AppAppearance { state.settings.appearance }
    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("plugin.market.title"))
                .font(.title2.weight(.bold))
            Text(t("plugin.market.hint"))
                .font(.callout)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Task { await state.setAllPluginsEnabled(true) }
                } label: {
                    Label(t("plugin.market.enableAll"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BashXTheme.accent(for: appearance))
                )

                Button {
                    Task { await state.setAllPluginsEnabled(false) }
                } label: {
                    Label(t("plugin.market.disableAll"), systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(appearance == .dark ? 0.1 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(BashXTheme.accent(for: appearance).opacity(0.25), lineWidth: 0.8)
                        )
                )
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(PluginEngine.catalog) { plugin in
                        pluginCard(plugin)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(20)
    }

    private func pluginCard(_ plugin: PluginEngine.Plugin) -> some View {
        let on = state.settings.enabledPluginIds.contains(plugin.id)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: plugin.symbol)
                .font(.title2)
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.headline)
                    Text(plugin.tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                Text(plugin.summary)
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: t("plugin.market.rules"), "\(plugin.ruleCount)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if plugin.scriptHeavy {
                    Text(t("plugin.market.scriptNote"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { on },
                set: { v in Task { await state.setPluginEnabled(plugin.id, enabled: v) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(appearance == .dark ? 0.08 : 0.04))
        )
    }
}
