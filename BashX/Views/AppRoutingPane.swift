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
    @State private var showAddGroup = false
    @State private var newGroupName = ""

    private var lang: AppLanguage { state.settings.uiLanguage }
    private var rules: [AppRoutingRule] { state.settings.appRoutingRules }
    private var customGroups: [String] {
        state.settings.appRoutingCustomGroups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        let _ = refreshTick
        return VStack(spacing: 0) {
            header
            Rectangle()
                .fill(BashXTheme.hairline(for: appearance))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    routingManagerSection
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BashXTheme.canvas(for: appearance))
        .onReceive(state.$appRoutingRevision.receive(on: RunLoop.main)) { _ in
            refreshTick &+= 1
        }
        .alert("添加分组", isPresented: $showAddGroup) {
            TextField("例如：工作 / 海外 / 直播", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("添加") {
                state.addAppRoutingCustomGroup(newGroupName)
                newGroupName = ""
            }
        } message: {
            Text("给自定义应用建一个分组，后面可以把应用移进去。")
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
                    .font(PanelMetrics.heroTitle)
                Text(L10n.t("mac.apps.subtitle", lang))
                    .font(PanelMetrics.caption)
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
                showAddGroup = true
            } label: {
                Label("添加分组", systemImage: "folder.badge.plus")
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

    private var configuredCountText: String {
        "\(rules.filter(\.enabled).count)/\(rules.count)"
    }

    private func presetRule(for preset: AppRoutingRules.CommonAppPreset) -> AppRoutingRule? {
        rules.first { AppRoutingRules.ruleMatches(preset: preset, rule: $0) }
    }

    private var customRules: [AppRoutingRule] {
        rules.filter { rule in
            !AppRoutingRules.commonPresets.contains { preset in
                AppRoutingRules.ruleMatches(preset: preset, rule: rule)
            }
        }
    }

    private func customRules(in group: String) -> [AppRoutingRule] {
        customRules.filter { $0.groupName.caseInsensitiveCompare(group) == .orderedSame }
    }

    private var ungroupedCustomRules: [AppRoutingRule] {
        customRules.filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var routingManagerSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Label("应用管理", systemImage: "square.grid.2x2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BashXTheme.primaryLabel(for: appearance))

                    Spacer(minLength: 0)

                    Text("\(L10n.t("mac.apps.custom", lang)) \(configuredCountText)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BashXTheme.secondaryFill(for: appearance))
                        )
                }

                Text(L10n.t("mac.apps.presetsHint", lang))
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))

                routingTableHeader

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AppRoutingRules.PresetCategory.allCases) { category in
                        presetCategoryBlock(category)
                    }
                }

                if !customGroups.isEmpty || !customRules.isEmpty {
                    Rectangle()
                        .fill(BashXTheme.hairline(for: appearance))
                        .frame(height: 1)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        sectionMiniHeader(
                            "自定义分组",
                            systemImage: "folder"
                        )

                        if !customGroups.isEmpty {
                            customGroupStrip
                        }

                        ForEach(customGroups, id: \.self) { group in
                            let grouped = customRules(in: group)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(group)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                                    Text("\(grouped.count)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(BashXTheme.secondaryFill(for: appearance))
                                        )
                                    Spacer(minLength: 0)
                                    Button(role: .destructive) {
                                        Task { await state.removeAppRoutingCustomGroup(group) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                                }

                                if grouped.isEmpty {
                                    Text("这个分组里还没有应用")
                                        .font(.caption2)
                                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(BashXTheme.secondaryFill(for: appearance).opacity(0.6))
                                        )
                                } else {
                                    LazyVStack(spacing: 8) {
                                        ForEach(grouped) { rule in
                                            customRuleRow(rule)
                                        }
                                    }
                                }
                            }
                        }

                        if !ungroupedCustomRules.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("未分组")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                                LazyVStack(spacing: 8) {
                                    ForEach(ungroupedCustomRules) { rule in
                                        customRuleRow(rule)
                                    }
                                }
                            }
                        }
                    }
                } else if rules.isEmpty {
                    compactEmptyHint
                }
            }
        }
    }

    private var routingTableHeader: some View {
        HStack(spacing: 10) {
            Text("状态")
                .frame(width: 28, alignment: .leading)
            Text("应用")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("当前线路")
                .frame(width: 78, alignment: .center)
            Text("切换到")
                .frame(width: 118, alignment: .center)
            Text("操作")
                .frame(width: 52, alignment: .center)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
        .padding(.horizontal, 12)
    }

    private func presetCategoryBlock(_ category: AppRoutingRules.PresetCategory) -> some View {
        let presets = AppRoutingRules.presets(in: category)
        let configured = presets.filter { presetRule(for: $0) != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(category.title(lang: lang))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                Spacer(minLength: 0)
                Text("\(configured)/\(presets.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BashXTheme.secondaryFill(for: appearance))
                    )
            }

            LazyVStack(spacing: 6) {
                ForEach(presets) { preset in
                    PresetRoutingRow(
                        preset: preset,
                        rule: presetRule(for: preset),
                        lang: lang,
                        appearance: appearance,
                        routeOptions: routeOptions,
                        onAdd: {
                            Task { await state.addAppRoutingPreset(preset) }
                        },
                        onToggle: { enabled in
                            guard let rule = presetRule(for: preset) else { return }
                            Task { await state.setAppRoutingRuleEnabled(id: rule.id, enabled: enabled) }
                        },
                        onTargetChange: { target in
                            guard var rule = presetRule(for: preset) else { return }
                            rule.proxyTarget = target
                            Task { await state.upsertAppRoutingRule(rule) }
                        },
                        onDelete: {
                            guard let rule = presetRule(for: preset) else { return }
                            Task { await state.removeAppRoutingRule(id: rule.id) }
                        }
                    )
                }
            }
        }
    }

    private var customGroupStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(customGroups, id: \.self) { group in
                    Text(group)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(BashXTheme.secondaryFill(for: appearance))
                        )
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func customRuleRow(_ rule: AppRoutingRule) -> some View {
        AppRoutingRow(
            rule: rule,
            lang: lang,
            appearance: appearance,
            routeOptions: routeOptions,
            groupOptions: customGroups,
            onToggle: { enabled in
                Task { await state.setAppRoutingRuleEnabled(id: rule.id, enabled: enabled) }
            },
            onTargetChange: { target in
                var next = rule
                next.proxyTarget = target
                Task { await state.upsertAppRoutingRule(next) }
            },
            onGroupChange: { group in
                Task { await state.setAppRoutingRuleGroup(id: rule.id, groupName: group) }
            },
            onDelete: {
                Task { await state.removeAppRoutingRule(id: rule.id) }
            }
        )
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
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

    private func sectionMiniHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BashXTheme.accent(for: appearance))
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private var compactEmptyHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("mac.apps.empty", lang))
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.t("mac.apps.emptyHint", lang))
                    .font(.caption)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.secondaryFill(for: appearance).opacity(0.7))
        )
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

private struct PresetRoutingRow: View {
    private static let stateWidth: CGFloat = 28
    private static let routeWidth: CGFloat = 78
    private static let pickerWidth: CGFloat = 118
    private static let actionWidth: CGFloat = 52

    let preset: AppRoutingRules.CommonAppPreset
    let rule: AppRoutingRule?
    let lang: AppLanguage
    let appearance: AppAppearance
    let routeOptions: [String]
    var onAdd: () -> Void
    var onToggle: (Bool) -> Void
    var onTargetChange: (String) -> Void
    var onDelete: () -> Void

    private var installed: Bool { rule != nil }
    private var routeValue: String { rule?.proxyTarget ?? preset.proxyTarget }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let rule {
                    Toggle(isOn: Binding(get: { rule.enabled }, set: onToggle)) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BashXTheme.accent(for: appearance))
                        .frame(width: 14, alignment: .center)
                }
            }
            .frame(width: Self.stateWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.label(lang: lang))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(installed ? preset.processName : "点击添加到已配置")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(AppRoutingRules.presetTitle(routeValue, lang: lang))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(BashXTheme.accentSoft(for: appearance))
                )
                .frame(width: Self.routeWidth)

            if let rule {
                Picker("", selection: Binding(
                    get: { rule.proxyTarget },
                    set: onTargetChange
                )) {
                    ForEach(routeOptions, id: \.self) { option in
                        Text(routeLabel(option)).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: Self.pickerWidth)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                .frame(width: Self.actionWidth)
            } else {
                Color.clear
                    .frame(width: Self.pickerWidth)
                Button("添加", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(BashXTheme.accent(for: appearance))
                    .frame(width: Self.actionWidth)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(installed
                      ? BashXTheme.secondaryFill(for: appearance).opacity(0.72)
                      : BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance), lineWidth: 0.5)
                )
        }
        .opacity(rule?.enabled == false ? 0.55 : 1)
    }

    private func routeLabel(_ option: String) -> String {
        if AppRoutingRules.routePresets.contains(where: { $0.id == option }) {
            return AppRoutingRules.presetTitle(option, lang: lang)
        }
        return option.count > 14 ? String(option.prefix(13)) + "…" : option
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
    private static let stateWidth: CGFloat = 28
    private static let groupWidth: CGFloat = 92
    private static let routeWidth: CGFloat = 78
    private static let pickerWidth: CGFloat = 118
    private static let actionWidth: CGFloat = 52

    let rule: AppRoutingRule
    let lang: AppLanguage
    let appearance: AppAppearance
    let routeOptions: [String]
    let groupOptions: [String]
    var onToggle: (Bool) -> Void
    var onTargetChange: (String) -> Void
    var onGroupChange: (String) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { rule.enabled }, set: onToggle)) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .frame(width: Self.stateWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.label.isEmpty ? rule.processName : rule.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(rule.processName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { rule.groupName },
                set: onGroupChange
            )) {
                Text("未分组").tag("")
                ForEach(groupOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: Self.groupWidth)

            Text(AppRoutingRules.presetTitle(rule.proxyTarget, lang: lang))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BashXTheme.accent(for: appearance))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(BashXTheme.accentSoft(for: appearance))
                )
                .frame(width: Self.routeWidth)

            Picker("", selection: Binding(
                get: { rule.proxyTarget },
                set: onTargetChange
            )) {
                ForEach(routeOptions, id: \.self) { option in
                    Text(routeLabel(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: Self.pickerWidth)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            .frame(width: Self.actionWidth)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.secondaryFill(for: appearance).opacity(0.7))
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
