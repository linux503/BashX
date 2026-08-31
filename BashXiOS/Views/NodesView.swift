import SwiftUI
import UIKit

struct NodesView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    /// Only regions that actually have nodes — keeps the strip compact.
    private var activeCategories: [(key: String, title: String, flag: String, count: Int)] {
        NodeCategory.fixedChipSummaries(among: state.nodes).filter { $0.count > 0 }
    }

    private var selectedNode: ProxyNode? {
        state.nodes.first { $0.name == state.settings.selectedNodeName }
    }

    private var testedCount: Int {
        state.nodes.filter { ($0.delayMs ?? -1) >= 0 }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.nodes.isEmpty {
                    IOSEmptyState(
                        systemImage: "point.3.connected.trianglepath.dotted",
                        title: t("nodes.empty.title"),
                        message: t("nodes.empty.msg")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            nodesSummaryCard
                                .padding(.horizontal, 16)
                                .padding(.top, 2)

                            if !activeCategories.isEmpty {
                                regionFilterStrip
                            }

                            LazyVStack(spacing: 8, pinnedViews: [.sectionHeaders]) {
                                if state.filteredNodes.isEmpty {
                                    Text(t("nodes.noMatch"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 40)
                                } else {
                                    ForEach(state.categoryGroups) { group in
                                        Section {
                                            VStack(spacing: 6) {
                                                ForEach(group.nodes) { node in
                                                    nodeCard(node, flag: group.flag)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 4)
                                        } header: {
                                            sectionHeader(group)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 28)
                    }
                    .refreshable { await state.testSpeeds() }
                }
            }
            .background {
                IOSPageBackground { Color.clear }
            }
            .searchable(text: $state.searchText, prompt: t("nodes.search"))
            .navigationTitle(t("nodes.title"))
            .id(lang.id)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.sortByDelay.toggle()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Image(systemName: state.sortByDelay ? "timer" : "textformat.abc")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(IOSTheme.accentDeep)
                    }
                    .accessibilityLabel(state.sortByDelay ? t("nodes.sortDelay") : t("nodes.sortName"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        regionFilterMenu
                        Button {
                            Task { await state.testSpeeds() }
                        } label: {
                            if state.isTesting {
                                ProgressView()
                            } else {
                                Image(systemName: "gauge.with.dots.needle.50percent")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(IOSTheme.accentDeep)
                            }
                        }
                        .disabled(state.nodes.isEmpty || state.isTesting)
                    }
                }
            }
        }
    }

    // MARK: - Summary

    private var nodesSummaryCard: some View {
        IOSCard(padding: 8) {
            HStack(spacing: 6) {
                summaryStat(
                    icon: "server.rack",
                    value: "\(state.nodes.count)",
                    label: lang == .zh ? "全部" : "Total",
                    tint: IOSTheme.accent
                )
                summaryStat(
                    icon: "checkmark.seal.fill",
                    value: selectedNode.map { $0.delayText } ?? "—",
                    label: lang == .zh ? "当前" : "Current",
                    tint: IOSTheme.good
                )
                summaryStat(
                    icon: "speedometer",
                    value: "\(testedCount)",
                    label: lang == .zh ? "已测" : "Tested",
                    tint: IOSTheme.accentDeep
                )
            }
        }
    }

    private func summaryStat(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 13, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.06))
        )
    }

    // MARK: - Region filter

    private var regionFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                regionChip(title: lang == .zh ? "全部" : "All", key: nil, flag: "🌐", count: state.nodes.count)
                ForEach(activeCategories, id: \.key) { item in
                    regionChip(title: item.title, key: item.key, flag: item.flag, count: item.count)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }

    private var regionFilterMenu: some View {
        Menu {
            Button {
                state.selectedCategoryKey = nil
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                if state.selectedCategoryKey == nil {
                    Label(lang == .zh ? "全部地区" : "All regions", systemImage: "checkmark")
                } else {
                    Text(lang == .zh ? "全部地区" : "All regions")
                }
            }
            if !activeCategories.isEmpty {
                Divider()
                ForEach(activeCategories, id: \.key) { item in
                    Button {
                        state.selectedCategoryKey = item.key
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        if state.selectedCategoryKey == item.key {
                            Label("\(item.flag) \(item.title) (\(item.count))", systemImage: "checkmark")
                        } else {
                            Text("\(item.flag) \(item.title) (\(item.count))")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: state.selectedCategoryKey == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(IOSTheme.accentDeep)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel(lang == .zh ? "地区筛选" : "Region filter")
    }

    private func regionChip(title: String, key: String?, flag: String, count: Int) -> some View {
        let selected = state.selectedCategoryKey == key
        return Button {
            state.selectedCategoryKey = key
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Text(flag).font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selected ? Color.white.opacity(0.22) : Color.primary.opacity(0.06))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        selected
                            ? AnyShapeStyle(IOSTheme.accentGradient)
                            : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
                    .shadow(color: selected ? IOSTheme.accent.opacity(0.22) : .clear, radius: 6, y: 2)
            }
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ group: NodeCategory.Group) -> some View {
        HStack(spacing: 8) {
            Text(group.flag)
                .font(.callout)
                .frame(width: 28, height: 28)
                .background(Circle().fill(IOSTheme.accentSoft))
            Text(group.title)
                .font(.system(size: 13, design: .rounded).weight(.bold))
                .foregroundStyle(IOSTheme.ink)
            Text("\(group.nodes.count)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(IOSTheme.accentDeep)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(IOSTheme.accentSoft))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.4)
                }
        }
    }

    private func nodeCard(_ node: ProxyNode, flag: String) -> some View {
        let selected = state.settings.selectedNodeName == node.name
        let delayColor = IOSTheme.delay(node.delayMs)

        return Button {
            state.selectNode(node.name)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            selected
                                ? AnyShapeStyle(IOSTheme.accentGradient)
                                : AnyShapeStyle(IOSTheme.tertiaryFill)
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: selected ? IOSTheme.accent.opacity(0.22) : .clear, radius: 4, y: 1)
                    Text(flag).font(.system(size: 15))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 14, design: .rounded).weight(selected ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(node.endpointSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(node.delayText)
                        .font(.system(size: 12, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(delayColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(delayColor.opacity(0.12)))

                    if selected {
                        Label(lang == .zh ? "当前" : "On", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(IOSTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selected ? IOSTheme.accent.opacity(0.5) : Color.primary.opacity(0.05),
                                lineWidth: selected ? 1.2 : 0.5
                            )
                    )
                    .shadow(
                        color: selected ? IOSTheme.accent.opacity(0.12) : Color.black.opacity(0.03),
                        radius: selected ? 8 : 3,
                        y: selected ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = node.name
            } label: {
                Label(t("nodes.copyName"), systemImage: "doc.on.doc")
            }
            Button {
                state.selectNode(node.name)
            } label: {
                Label(t("nodes.setCurrent"), systemImage: "checkmark.circle")
            }
            if vpn.isConnected {
                Button {
                    Task { await state.testSpeeds() }
                } label: {
                    Label(t("home.test"), systemImage: "gauge.with.dots.needle.50percent")
                }
            }
        }
    }
}
