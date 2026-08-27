import SwiftUI
import UIKit

struct SubscriptionsView: View {
    @EnvironmentObject private var state: IOSAppState
    @State private var showAdd = false
    @State private var name = ""
    @State private var url = ""
    @State private var qrShareSub: Subscription?

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        NavigationStack {
            Group {
                if state.settings.subscriptions.isEmpty {
                    IOSEmptyState(
                        systemImage: "tray.full",
                        title: t("subs.empty.title"),
                        message: t("subs.empty.msg"),
                        actionTitle: t("subs.add")
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
            .navigationTitle(t("subs.title"))
            .id(lang.id)
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
                    .accessibilityLabel(t("subs.add"))
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
            .sheet(item: $qrShareSub) { sub in
                SubscriptionQRShareSheet(name: sub.name, url: sub.url)
            }
            .onAppear { consumePendingAdd() }
            .onChange(of: state.pendingShowAddSubscription) { pending in
                if pending { consumePendingAdd() }
            }
        }
    }

    private func consumePendingAdd() {
        guard state.pendingShowAddSubscription else { return }
        state.pendingShowAddSubscription = false
        if let pending = state.pendingSubscriptionURL {
            url = pending
            state.pendingSubscriptionURL = nil
        }
        showAdd = true
    }

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.settings.subscriptions.count)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(t("subs.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider().frame(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.nodes.count)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(t("subs.nodes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await state.updateAllSubscriptions() }
            } label: {
                Label(t("subs.updateAll"), systemImage: "arrow.clockwise")
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
                    Text(sub.name.isEmpty ? t("subs.unnamed") : sub.name)
                        .font(.headline)
                    if let updated = sub.updatedAt {
                        Text(updated.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(t("subs.never"))
                            .font(.caption)
                            .foregroundStyle(IOSTheme.warn)
                    }
                }
                Spacer()
                Toggle(t("subs.enabled"), isOn: bindingEnabled(sub.id))
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
                Text(state.isBusy ? t("subs.updating") : t("subs.updateOne"))
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
                Label(t("subs.copyLink"), systemImage: "doc.on.doc")
            }
            Button {
                qrShareSub = sub
            } label: {
                Label(t("subs.qrShare"), systemImage: "qrcode")
            }
            ShareLink(item: sub.url) {
                Label(t("subs.shareLink"), systemImage: "square.and.arrow.up")
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("subs.nameOptional"), text: $name)
                    TextField(t("subs.url"), text: $url, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text(t("subs.formHint"))
                }
                Section {
                    Button {
                        if let clip = UIPasteboard.general.string?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           clip.lowercased().hasPrefix("http") {
                            url = clip
                        }
                    } label: {
                        Label(t("subs.paste"), systemImage: "doc.on.clipboard")
                    }
                }
            }
            .navigationTitle(t("subs.addTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("subs.add")) {
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
