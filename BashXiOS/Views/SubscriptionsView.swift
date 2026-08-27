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
                        systemImage: "tray.full",
                        title: "添加订阅",
                        message: "粘贴 Clash 或机场订阅链接，更新后即可获取节点。",
                        actionTitle: "添加订阅"
                    ) { showAdd = true }
                } else {
                    List {
                        Section {
                            summaryHeader
                        }
                        ForEach(state.settings.subscriptions) { sub in
                            Section {
                                subscriptionRow(sub)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                state.removeSubscription(id: state.settings.subscriptions[i].id)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await state.updateAllSubscriptions() }
                }
            }
            .background {
                IOSPageBackground { Color.clear }
            }
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(state.settings.subscriptions.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加订阅")
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.settings.subscriptions.count)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("订阅")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.nodes.count)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("节点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await state.updateAllSubscriptions() }
            } label: {
                Label("全部更新", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(state.isBusy)
        }
        .padding(.vertical, 4)
    }

    private func subscriptionRow(_ sub: Subscription) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.name.isEmpty ? "未命名订阅" : sub.name)
                        .font(.headline)
                    if let updated = sub.updatedAt {
                        Text(updated.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未更新")
                            .font(.caption)
                            .foregroundStyle(IOSTheme.warn)
                    }
                }
                Spacer()
                Toggle("启用", isOn: bindingEnabled(sub.id))
                    .labelsHidden()
            }

            Text(sub.url)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            if let ratio = sub.userInfo?.usedRatio {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: ratio)
                    if let info = sub.trafficSummary {
                        Text(info)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let info = sub.trafficSummary {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await state.updateSubscription(id: sub.id) }
            } label: {
                Text(state.isBusy ? "更新中…" : "更新此订阅")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(state.isBusy)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                UIPasteboard.general.string = sub.url
            } label: {
                Label("复制链接", systemImage: "doc.on.doc")
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（可选）", text: $name)
                    TextField("订阅 URL", text: $url, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text("支持 Clash YAML 与 Base64 节点列表。")
                }
                Section {
                    Button {
                        if let clip = UIPasteboard.general.string?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           clip.lowercased().hasPrefix("http") {
                            url = clip
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
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
        .presentationDetents([.medium])
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
