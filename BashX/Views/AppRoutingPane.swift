import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AppRoutingPane: View {
    let state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @State private var showPicker = false
    @State private var runningApps: [AppRoutingRules.RunningApp] = []
    @State private var refreshTick = 0

    private var lang: AppLanguage { state.settings.uiLanguage }
    private var rules: [AppRoutingRule] { state.settings.appRoutingRules }

    var body: some View {
        let _ = refreshTick
        return VStack(spacing: 0) {
            header
            Rectangle()
                .fill(BashXTheme.hairline(for: appearance))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    websiteProbeSection
                    presetSection

                    if !rules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("mac.apps.custom", lang))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                                .padding(.horizontal, 2)

                            LazyVStack(spacing: 8) {
                                ForEach(rules) { rule in
                                    AppRoutingRow(
                                        rule: rule,
                                        lang: lang,
                                        appearance: appearance,
                                        routeOptions: routeOptions,
                                        onToggle: { enabled in
                                            Task { await state.setAppRoutingRuleEnabled(id: rule.id, enabled: enabled) }
                                        },
                                        onTargetChange: { target in
                                            var next = rule
                                            next.proxyTarget = target
                                            Task { await state.upsertAppRoutingRule(next) }
                                        },
                                        onDelete: {
                                            Task { await state.removeAppRoutingRule(id: rule.id) }
                                        }
                                    )
                                }
                            }
                        }
                    } else {
                        emptyHint
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BashXTheme.canvas(for: appearance))
        .onReceive(state.$appRoutingRevision.receive(on: RunLoop.main)) { _ in
            refreshTick &+= 1
        }
        .sheet(isPresented: $showPicker) {
            RunningAppPicker(
                apps: runningApps,
                lang: lang,
                appearance: appearance,
                existingBundleIds: Set(rules.compactMap { $0.bundleId.isEmpty ? nil : $0.bundleId.lowercased() }),
                existingProcessNames: Set(rules.map { $0.processName.lowercased() })
            ) { app, target in
                let rule = AppRoutingRule(
                    label: app.label,
                    processName: app.processName,
                    bundleId: app.bundleId,
                    proxyTarget: target
                )
                Task { await state.upsertAppRoutingRule(rule) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("mac.apps.title", lang))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(L10n.t("mac.apps.subtitle", lang))
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
            }
            Spacer(minLength: 8)
            Button {
                Task { await state.addAllCommonAppRoutingPresets() }
            } label: {
                Label(L10n.t("mac.apps.addAll", lang), systemImage: "square.stack.3d.up.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                runningApps = AppRoutingRules.runningApps()
                showPicker = true
            } label: {
                Label(L10n.t("mac.apps.add", lang), systemImage: "plus.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(BashXTheme.accent(for: appearance))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BashXTheme.card(for: appearance).opacity(0.55))
    }

    private var websiteProbeSection: some View {
        let expanded = state.settings.panelShowWebsiteProbe
        return VStack(alignment: .leading, spacing: expanded ? 10 : 0) {
            Button {
                state.settings.panelShowWebsiteProbe.toggle()
                state.persist()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                    Text(L10n.t("probe.title", lang))
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if !expanded {
                        Text(L10n.t("mac.apps.probeHint", lang))
                            .font(.caption2)
                            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                            .lineLimit(1)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(L10n.t("mac.apps.probeHint", lang))
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                WebsiteProbeStripMac(state: state, compact: false, showTitle: false)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
                Text(L10n.t("mac.apps.presets", lang))
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(L10n.t("mac.apps.presetsHint", lang))
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            }

            ForEach(AppRoutingRules.PresetCategory.allCases) { category in
                presetCategoryBlock(category)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
    }

    private func presetCategoryBlock(_ category: AppRoutingRules.PresetCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.title(lang: lang))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))

            FlowLayout(spacing: 6) {
                ForEach(AppRoutingRules.presets(in: category)) { preset in
                    presetChip(preset)
                }
            }
        }
    }

    private func presetChip(_ preset: AppRoutingRules.CommonAppPreset) -> some View {
        let installed = AppRoutingRules.presetInstalled(preset, in: rules)
        let routeLabel = AppRoutingRules.presetTitle(preset.proxyTarget, lang: lang)

        return Button {
            guard !installed else { return }
            Task { await state.addAppRoutingPreset(preset) }
        } label: {
            HStack(spacing: 4) {
                if installed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(preset.label(lang: lang))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Text("→")
                    .font(.system(size: 9))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                Text(routeLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(BashXTheme.accent(for: appearance))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(installed
                          ? BashXTheme.good(for: appearance).opacity(0.12)
                          : BashXTheme.secondaryFill(for: appearance))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        installed
                            ? BashXTheme.good(for: appearance).opacity(0.35)
                            : BashXTheme.separator(for: appearance),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(installed)
        .help(installed
              ? L10n.t("mac.apps.added", lang)
              : L10n.t("mac.apps.addPreset", lang).replacingOccurrences(of: "%@", with: preset.label(lang: lang)))
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(BashXTheme.accent(for: appearance))
            Text(L10n.t("mac.apps.empty", lang))
                .font(.subheadline.weight(.medium))
            Text(L10n.t("mac.apps.emptyHint", lang))
                .font(.caption)
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var routeOptions: [String] {
        var options = AppRoutingRules.routePresets.map(\.id)
        for node in state.nodes.prefix(80) {
            if !options.contains(node.name) {
                options.append(node.name)
            }
        }
        return options
    }
}

/// Simple wrapping chip layout for preset buttons.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

private struct AppRoutingRow: View {
    let rule: AppRoutingRule
    let lang: AppLanguage
    let appearance: AppAppearance
    let routeOptions: [String]
    var onToggle: (Bool) -> Void
    var onTargetChange: (String) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { rule.enabled }, set: onToggle)) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.label.isEmpty ? rule.processName : rule.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(rule.processName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { rule.proxyTarget },
                set: onTargetChange
            )) {
                ForEach(routeOptions, id: \.self) { option in
                    Text(routeLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
        .opacity(rule.enabled ? 1 : 0.55)
    }

    private func routeLabel(_ option: String) -> String {
        if AppRoutingRules.routePresets.contains(where: { $0.id == option }) {
            return AppRoutingRules.presetTitle(option, lang: lang)
        }
        return option.count > 18 ? String(option.prefix(17)) + "…" : option
    }
}

private struct RunningAppPicker: View {
    let apps: [AppRoutingRules.RunningApp]
    let lang: AppLanguage
    let appearance: AppAppearance
    let existingBundleIds: Set<String>
    let existingProcessNames: Set<String>
    var onPick: (AppRoutingRules.RunningApp, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var target = "PROXY"

    private var filtered: [AppRoutingRules.RunningApp] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.label.localizedCaseInsensitiveContains(q)
                || $0.processName.localizedCaseInsensitiveContains(q)
                || $0.bundleId.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("mac.apps.pick", lang))
                    .font(.headline)
                Spacer()
                Button(L10n.t("common.cancel", lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            HStack(spacing: 8) {
                Text(L10n.t("mac.apps.routeTo", lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $target) {
                    ForEach(AppRoutingRules.routePresets, id: \.id) { preset in
                        Text(AppRoutingRules.presetTitle(preset.id, lang: lang)).tag(preset.id)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            TextField(L10n.t("mac.apps.search", lang), text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filtered) { app in
                let alreadyAdded = isAlreadyAdded(app)
                Button {
                    guard !alreadyAdded else { return }
                    onPick(app, target)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        #if os(macOS)
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app")
                                .frame(width: 24, height: 24)
                        }
                        #endif
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.label)
                            Text(app.processName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if alreadyAdded {
                            Text(L10n.t("mac.apps.added", lang))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(alreadyAdded)
            }
            .listStyle(.inset)
        }
        .frame(width: 420, height: 480)
        .background(BashXTheme.canvas(for: appearance))
    }

    private func isAlreadyAdded(_ app: AppRoutingRules.RunningApp) -> Bool {
        if !app.bundleId.isEmpty, existingBundleIds.contains(app.bundleId.lowercased()) {
            return true
        }
        return existingProcessNames.contains(app.processName.lowercased())
    }
}
