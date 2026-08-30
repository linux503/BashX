import SwiftUI
import UIKit

struct SubscriptionsView: View {
    @EnvironmentObject private var state: IOSAppState
    @State private var showScan = false
    @State private var addPayload: AddSheetPayload?
    @State private var qrShareSub: Subscription?

    private struct AddSheetPayload: Identifiable {
        let id = UUID()
        var url: String
    }

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private func openAddSheet(url: String = "") {
        addPayload = AddSheetPayload(url: url)
    }

    private func applyScannedURL(_ scanned: String) {
        let parsed = SubscriptionURL.extracted(from: scanned)
            ?? scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.isEmpty else { return }
        showScan = false
        openAddSheet(url: parsed)
    }

    private var enabledCount: Int {
        state.settings.subscriptions.filter(\.enabled).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.settings.subscriptions.isEmpty {
                    VStack(spacing: 0) {
                        IOSEmptyState(
                            systemImage: "tray.full",
                            title: t("subs.empty.title"),
                            message: t("subs.empty.msg"),
                            actionTitle: t("subs.add")
                        ) { openAddSheet() }
                        Button {
                            showScan = true
                        } label: {
                            Label(t("subs.scan"), systemImage: "qrcode.viewfinder")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, -36)
                        .padding(.bottom, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            summaryHeader
                                .padding(.horizontal, 20)
                                .padding(.top, 8)

                            ForEach(state.settings.subscriptions) { sub in
                                subscriptionCard(sub)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, 28)
                    }
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
                    if !state.settings.subscriptions.isEmpty {
                        Button {
                            Task { await state.updateAllSubscriptions() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(state.isBusy)
                        .accessibilityLabel(t("subs.updateAll"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { openAddSheet() } label: {
                            Label(t("subs.addManual"), systemImage: "link")
                        }
                        Button {
                            showScan = true
                        } label: {
                            Label(t("subs.scan"), systemImage: "qrcode.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(IOSTheme.accent)
                    }
                    .accessibilityLabel(t("subs.add"))
                }
            }
            .sheet(item: $addPayload) { payload in
                AddSubscriptionSheet(
                    lang: lang,
                    initialURL: payload.url,
                    onRequestScan: {
                        addPayload = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showScan = true
                        }
                    },
                    onSaved: { addPayload = nil }
                )
                .environmentObject(state)
            }
            .sheet(isPresented: $showScan) {
                SubscriptionQRScannerSheet { scanned in
                    applyScannedURL(scanned)
                }
                .environmentObject(state)
            }
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
            let parsed = SubscriptionURL.extracted(from: pending) ?? pending
            state.pendingSubscriptionURL = nil
            openAddSheet(url: parsed)
        } else {
            openAddSheet()
        }
    }

    private var summaryHeader: some View {
        IOSCard(padding: 16) {
            HStack(spacing: 0) {
                summaryMetric(
                    value: "\(state.settings.subscriptions.count)",
                    label: t("subs.title"),
                    tint: IOSTheme.accent
                )
                summaryDivider
                summaryMetric(
                    value: "\(enabledCount)",
                    label: t("subs.enabled"),
                    tint: IOSTheme.good
                )
                summaryDivider
                summaryMetric(
                    value: "\(state.nodes.count)",
                    label: t("subs.nodes"),
                    tint: IOSTheme.accentDeep
                )
            }
        }
    }

    private func summaryMetric(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    private func subscriptionCard(_ sub: Subscription) -> some View {
        let enabled = sub.enabled
        let ratio = sub.userInfo?.usedRatio

        return IOSCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: enabled
                                        ? [IOSTheme.accent, IOSTheme.accentDeep]
                                        : [Color.secondary.opacity(0.35), Color.secondary.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        Image(systemName: enabled ? "link.circle.fill" : "link.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sub.name.isEmpty ? t("subs.unnamed") : sub.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(enabled ? .primary : .secondary)
                        if let updated = sub.updatedAt {
                            Text(updated.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(t("subs.never"), systemImage: "clock.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(IOSTheme.warn)
                        }
                    }
                    Spacer(minLength: 8)
                    Toggle(t("subs.enabled"), isOn: bindingEnabled(sub.id))
                        .labelsHidden()
                        .tint(IOSTheme.accent)
                }

                Text(sub.url)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(IOSTheme.tertiaryFill.opacity(0.7))
                    )

                if let ratio {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: trafficColors(ratio),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, ratio)))))
                            }
                        }
                        .frame(height: 6)

                        if let info = sub.trafficSummary {
                            Text(info)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let info = sub.trafficSummary {
                    Text(info)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    let rowBusy = state.updatingSubscriptionID == sub.id
                    let bulkBusy = state.isBusy
                    Button {
                        Task { await state.updateSubscription(id: sub.id) }
                    } label: {
                        HStack(spacing: 6) {
                            if rowBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(rowBusy ? t("subs.updating") : t("subs.updateOne"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(IOSTheme.accentGradient)
                    )
                    .disabled(rowBusy || bulkBusy)
                    .opacity(rowBusy || bulkBusy ? 0.65 : 1)

                    Button {
                        qrShareSub = sub
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(IOSTheme.accentDeep)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(IOSTheme.accentSoft)
                    )

                    ShareLink(item: sub.url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(IOSTheme.accentDeep)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(IOSTheme.accentSoft)
                    )
                }
            }
        }
        .opacity(enabled ? 1 : 0.72)
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
            Divider()
            Button(role: .destructive) {
                state.removeSubscription(id: sub.id)
            } label: {
                Label(lang == .zh ? "删除" : "Delete", systemImage: "trash")
            }
        }
    }

    private func trafficColors(_ ratio: Double) -> [Color] {
        if ratio >= 0.9 { return [IOSTheme.bad.opacity(0.75), IOSTheme.bad] }
        if ratio >= 0.7 { return [IOSTheme.warn.opacity(0.75), IOSTheme.warn] }
        return [IOSTheme.accentBright, IOSTheme.accent]
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

// MARK: - Add subscription sheet (own @State — avoids toolbar .disabled stuck after QR scan)

private struct AddSubscriptionSheet: View {
    @EnvironmentObject private var state: IOSAppState
    @Environment(\.dismiss) private var dismiss

    let lang: AppLanguage
    let initialURL: String
    let onRequestScan: () -> Void
    let onSaved: () -> Void

    @State private var name = ""
    @State private var url = ""

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        SubscriptionURL.normalized(trimmedURL, allowInsecureHTTP: true) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("subs.nameOptional"), text: $name)
                    TextField(t("subs.url"), text: $url, axis: .vertical)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("subs.formHint"))
                        if !trimmedURL.isEmpty, !canSave {
                            Text(lang == .zh ? "链接格式无效，请检查是否为 http(s) 订阅地址" : "Invalid URL — use an http(s) subscription link")
                                .foregroundStyle(IOSTheme.warn)
                        }
                    }
                }

                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            Label(t("subs.add"), systemImage: "checkmark.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }

                Section {
                    Button(action: onRequestScan) {
                        Label(t("subs.scan"), systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        if let clip = UIPasteboard.general.string?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           let parsed = SubscriptionURL.extracted(from: clip) {
                            url = parsed
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
                    Button(t("common.cancel")) {
                        onSaved()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("subs.add"), action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            url = initialURL
        }
    }

    private func save() {
        guard let normalized = SubscriptionURL.normalized(trimmedURL, allowInsecureHTTP: true) else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        state.addSubscription(name: name, url: normalized)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved()
        dismiss()
    }
}
