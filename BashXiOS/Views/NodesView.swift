import SwiftUI
import UIKit

struct NodesView: View {
    @EnvironmentObject private var state: IOSAppState
    @EnvironmentObject private var vpn: VPNManager

    var body: some View {
        NavigationStack {
            Group {
                if state.nodes.isEmpty {
                    IOSEmptyState(
                        systemImage: "point.3.connected.trianglepath.dotted",
                        title: "暂无节点",
                        message: "在「订阅」页添加链接并更新，节点会按地区显示在这里。"
                    )
                } else {
                    List {
                        if state.filteredNodes.isEmpty {
                            Section {
                                Text("没有匹配的节点")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        } else {
                            ForEach(state.categoryGroups) { group in
                                Section {
                                    ForEach(group.nodes) { node in
                                        nodeRow(node)
                                    }
                                } header: {
                                    Text("\(group.flag) \(group.title) · \(group.nodes.count)")
                                        .textCase(nil)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await state.testSpeeds() }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        categoryChips
                            .padding(.vertical, 8)
                            .background(.bar)
                    }
                }
            }
            .background {
                IOSPageBackground { Color.clear }
            }
            .searchable(text: $state.searchText, prompt: "搜索节点")
            .navigationTitle("节点")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.sortByDelay.toggle()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Label(
                            state.sortByDelay ? "按延迟" : "按名称",
                            systemImage: state.sortByDelay ? "timer" : "textformat.abc"
                        )
                        .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("测速全部") { Task { await state.testSpeeds() } }
                        Button("测速并选最快") { Task { await state.testSpeeds(selectFastest: true) } }
                        if vpn.isConnected, let name = state.settings.selectedNodeName {
                            Button("同步到 VPN") { Task { await vpn.selectNode(name) } }
                        }
                    } label: {
                        if state.isTesting {
                            ProgressView()
                        } else {
                            Image(systemName: "gauge.with.dots.needle.50percent")
                        }
                    }
                    .disabled(state.nodes.isEmpty || state.isTesting)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", key: nil, flag: nil)
                ForEach(state.categorySummaries, id: \.key) { item in
                    chip("\(item.title) \(item.count)", key: item.key, flag: item.flag)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, key: String?, flag: String?) -> some View {
        let selected = state.selectedCategoryKey == key
        return Button {
            state.selectedCategoryKey = key
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 4) {
                if let flag { Text(flag) }
                Text(title).fontWeight(.medium)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? AnyShapeStyle(IOSTheme.accentGradient) : AnyShapeStyle(IOSTheme.tertiaryFill)))
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func nodeRow(_ node: ProxyNode) -> some View {
        let selected = state.settings.selectedNodeName == node.name
        return Button {
            state.selectNode(node.name)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(node.type.uppercased()) · \(node.server)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(node.delayText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(IOSTheme.delay(node.delayMs))
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(IOSTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = node.name
            } label: {
                Label("复制名称", systemImage: "doc.on.doc")
            }
            Button {
                state.selectNode(node.name)
            } label: {
                Label("设为当前节点", systemImage: "checkmark.circle")
            }
        }
    }
}
