import SwiftUI
import UIKit

struct NodesView: View {
    @EnvironmentObject private var state: IOSAppState

    var body: some View {
        NavigationStack {
            Group {
                if state.nodes.isEmpty {
                    IOSEmptyState(
                        systemImage: "point.3.connected.trianglepath.dotted",
                        title: "暂无节点",
                        message: "到「订阅」添加并更新后，这里会按地区列出全部线路。"
                    )
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                } else {
                    VStack(spacing: 0) {
                        categoryChips
                            .padding(.top, 4)
                            .padding(.bottom, 8)

                        List {
                            if state.filteredNodes.isEmpty {
                                Text("没有匹配的节点")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 28)
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(state.categoryGroups) { group in
                                    Section {
                                        ForEach(group.nodes) { node in
                                            nodeRow(node)
                                        }
                                    } header: {
                                        Text("\(group.flag) \(group.title) · \(group.nodes.count)")
                                            .font(.caption.weight(.semibold))
                                            .textCase(nil)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await state.testSpeeds()
                        }
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                }
            }
            .searchable(text: $state.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索节点")
            .navigationTitle("节点")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.sortByDelay.toggle()
                    } label: {
                        Image(systemName: state.sortByDelay ? "timer" : "textformat.abc")
                    }
                    .accessibilityLabel(state.sortByDelay ? "按延迟排序" : "按名称排序")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("测速") {
                            Task { await state.testSpeeds() }
                        }
                        Button("测速并选最快") {
                            Task { await state.testSpeeds(selectFastest: true) }
                        }
                    } label: {
                        if state.isTesting {
                            ProgressView()
                        } else {
                            Image(systemName: "gauge.with.dots.needle.33percent")
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
                chip(title: "全部", key: nil, flag: nil)
                ForEach(state.categorySummaries, id: \.key) { item in
                    chip(title: "\(item.title) \(item.count)", key: item.key, flag: item.flag)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, key: String?, flag: String?) -> some View {
        let selected = state.selectedCategoryKey == key
        return Button {
            state.selectedCategoryKey = key
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 4) {
                if let flag { Text(flag).font(.caption) }
                Text(title).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selected ? IOSTheme.accent : Color(.secondarySystemGroupedBackground))
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func nodeRow(_ node: ProxyNode) -> some View {
        let selected = state.settings.selectedNodeName == node.name
        return Button {
            state.selectNode(node.name)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(selected ? IOSTheme.accent : Color.clear)
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 4) {
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
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(IOSTheme.delay(node.delayMs))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 16))
        .listRowBackground(
            (selected ? IOSTheme.accent.opacity(0.08) : Color(.systemBackground))
        )
    }
}
