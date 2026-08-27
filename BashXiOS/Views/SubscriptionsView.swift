import SwiftUI
import UIKit

struct SubscriptionsView: View {
    @EnvironmentObject private var state: IOSAppState
    @State private var showAdd = false
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Group {
                if state.settings.subscriptions.isEmpty {
                    IOSEmptyState(
                        systemImage: "link.badge.plus",
                        title: "添加订阅开始使用",
                        message: "粘贴 Clash / 机场订阅链接，更新后即可连接。",
                        actionTitle: "添加订阅"
                    ) { showAdd = true }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                } else {
                    List {
                        ForEach(state.settings.subscriptions) { sub in
                            subscriptionRow(sub)
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                state.removeSubscription(id: state.settings.subscriptions[i].id)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await state.updateAllSubscriptions()
                    }
                }
            }
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("全部更新") {
                        Task { await state.updateAllSubscriptions() }
                    }
                    .disabled(state.isBusy || state.settings.subscriptions.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(IOSTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    private func subscriptionRow(_ sub: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sub.name.isEmpty ? "未命名订阅" : sub.name)
                        .font(.headline)
                    if let updated = sub.updatedAt {
                        Text("更新于 \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未更新")
                            .font(.caption2)
                            .foregroundStyle(IOSTheme.warn)
                    }
                }
                Spacer()
                Toggle("启用", isOn: bindingEnabled(sub.id))
                    .labelsHidden()
                    .tint(IOSTheme.accent)
            }

            Text(sub.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let ratio = sub.userInfo?.usedRatio {
                ProgressView(value: ratio)
                    .tint(IOSTheme.accent)
            }

            HStack {
                if let info = sub.trafficSummary {
                    Text(info)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await state.updateSubscription(id: sub.id) }
                } label: {
                    Text(state.isBusy ? "更新中" : "更新")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(IOSTheme.accent.opacity(0.14)))
                        .foregroundStyle(IOSTheme.accentDeep)
                }
                .buttonStyle(.plain)
                .disabled(state.isBusy)
            }
        }
        .padding(.vertical, 6)
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（可选）", text: $name)
                    TextField("订阅 URL", text: $url, axis: .vertical)
                        .lineLimit(4...8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        if let clip = UIPasteboard.general.string?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           clip.lowercased().hasPrefix("http") {
                            url = clip
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text("支持 Clash YAML 与 Base64 节点列表。")
                }
            }
            .navigationTitle("添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        state.addSubscription(name: name, url: url)
                        name = ""
                        url = ""
                        showAdd = false
                    }
                    .fontWeight(.semibold)
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func bindingEnabled(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { state.settings.subscriptions.first(where: { $0.id == id })?.enabled ?? true },
            set: { newValue in
                if let i = state.settings.subscriptions.firstIndex(where: { $0.id == id }) {
                    state.settings.subscriptions[i].enabled = newValue
                    state.reloadNodesFromCache()
                    state.writeConfig()
                    state.persist()
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        )
    }
}
