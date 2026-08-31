import SwiftUI
import UIKit

struct SubscriptionsView: View {
    @EnvironmentObject private var state: IOSAppState
    @State private var showScan = false
    @State private var addPayload: AddSheetPayload?
    @State private var qrShareSub: Subscription?
    @State private var renameTarget: Subscription?
    @State private var renameDraft = ""

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
                    emptyContent
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            summaryHeader
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            ForEach(Array(state.settings.subscriptions.enumerated()), id: \.element.id) { index, sub in
                                SubscriptionCardView(
                                    sub: sub,
                                    index: index,
                                    lang: lang,
                                    onRename: {
                                        renameDraft = sub.name
                                        renameTarget = sub
                                    },
                                    onShareQR: { qrShareSub = sub }
                                )
                                .environmentObject(state)
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.bottom, 24)
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
                                .foregroundStyle(IOSTheme.accentDeep)
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
                            .font(.title3)
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
            .alert(
                t("subs.renameTitle"),
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField(t("subs.renamePlaceholder"), text: $renameDraft)
                Button(t("common.cancel"), role: .cancel) { renameTarget = nil }
                Button(t("subs.renameSave")) {
                    if let id = renameTarget?.id {
                        state.renameSubscription(id, name: renameDraft)
                    }
                    renameTarget = nil
                }
            } message: {
                Text(lang == .zh ? "修改后仅影响显示名称，不会改动订阅链接。" : "Only changes the display name, not the subscription URL.")
            }
            .onAppear { consumePendingAdd() }
            .onChange(of: state.pendingShowAddSubscription) { pending in
                if pending { consumePendingAdd() }
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            IOSEmptyState(
                systemImage: "tray.full",
                title: t("subs.empty.title"),
                message: t("subs.empty.msg")
            )
            VStack(spacing: 12) {
                Button {
                    openAddSheet()
                } label: {
                    Label(t("subs.add"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    Capsule(style: .continuous)
                        .fill(IOSTheme.accentGradient)
                        .shadow(color: IOSTheme.accent.opacity(0.28), radius: 10, y: 4)
                )

                Button {
                    showScan = true
                } label: {
                    Label(t("subs.scan"), systemImage: "qrcode.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(IOSTheme.accentDeep)
                .background(
                    Capsule(style: .continuous)
                        .fill(IOSTheme.accentSoft)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(IOSTheme.accent.opacity(0.22), lineWidth: 0.8)
                        )
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, -48)
            Spacer(minLength: 40)
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

    // MARK: - Summary

    private var summaryHeader: some View {
        IOSCard(padding: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    summaryChip(
                        icon: "tray.full.fill",
                        value: "\(state.settings.subscriptions.count)",
                        label: t("subs.title"),
                        tint: IOSTheme.accent
                    )
                    summaryChip(
                        icon: "checkmark.circle.fill",
                        value: "\(enabledCount)",
                        label: t("subs.enabled"),
                        tint: IOSTheme.good
                    )
                    summaryChip(
                        icon: "server.rack",
                        value: "\(state.nodes.count)",
                        label: t("subs.nodes"),
                        tint: IOSTheme.accentDeep
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await state.updateAllSubscriptions() }
                    } label: {
                        Label(
                            state.isBusy ? t("subs.updating") : t("subs.updateAll"),
                            systemImage: state.isBusy ? "hourglass" : "arrow.triangle.2.circlepath"
                        )
                        .font(.system(size: 13, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(IOSTheme.accentGradient)
                                .shadow(color: IOSTheme.accent.opacity(0.22), radius: 6, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isBusy || state.settings.subscriptions.isEmpty)
                    .opacity(state.isBusy ? 0.65 : 1)

                    Button { openAddSheet() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(IOSTheme.accentDeep)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(IOSTheme.accentSoft)
                                    .overlay(Circle().strokeBorder(IOSTheme.accent.opacity(0.2), lineWidth: 0.8))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("subs.add"))
                }
            }
        }
    }

    private func summaryChip(icon: String, value: String, label: String, tint: Color) -> some View {
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
                .font(.system(size: 14, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Subscription card

private struct SubscriptionCardView: View {
    @EnvironmentObject private var state: IOSAppState
    let sub: Subscription
    let index: Int
    let lang: AppLanguage
    var onRename: () -> Void
    var onShareQR: () -> Void

    @State private var urlRevealed = false

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var enabled: Bool { sub.enabled }
    private var ratio: Double? { sub.userInfo?.usedRatio }

    /// Soft per-card accent — slight variation so the list doesn’t look flat.
    private var tint: Color {
        let palette: [Color] = [
            IOSTheme.accent,
            Color(red: 0.28, green: 0.72, blue: 0.88),
            Color(red: 0.42, green: 0.58, blue: 0.98),
            Color(red: 0.32, green: 0.76, blue: 0.58),
            Color(red: 0.95, green: 0.58, blue: 0.36),
            Color(red: 0.62, green: 0.48, blue: 0.92),
            Color(red: 0.18, green: 0.68, blue: 0.78),
            Color(red: 0.88, green: 0.42, blue: 0.55),
        ]
        return palette[index % palette.count]
    }

    private var maskedURL: String {
        guard let u = URL(string: sub.url), let host = u.host, !host.isEmpty else {
            return "••••••••••••••••"
        }
        let scheme = u.scheme ?? "https"
        let dots = String(repeating: "•", count: min(18, max(8, host.count)))
        return "\(scheme)://\(dots)/***"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: enabled
                                    ? [tint.opacity(0.95), tint, tint.opacity(0.72)]
                                    : [Color.secondary.opacity(0.28), Color.secondary.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(color: enabled ? tint.opacity(0.22) : .clear, radius: 4, y: 1)
                    Image(systemName: enabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(sub.name.isEmpty ? t("subs.unnamed") : sub.name)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(enabled ? .primary : .secondary)
                            .lineLimit(1)
                        statusBadge(enabled: enabled)
                    }
                    if let updated = sub.updatedAt {
                        Label(updated.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label(t("subs.never"), systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(IOSTheme.warn)
                    }
                }
                Spacer(minLength: 4)
                Toggle(t("subs.enabled"), isOn: bindingEnabled(sub.id))
                    .labelsHidden()
                    .tint(tint)
                    .scaleEffect(0.84)
            }

            urlRow

            if let ratio {
                VStack(alignment: .leading, spacing: 4) {
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
                    .frame(height: 4)

                    if let info = sub.trafficSummary {
                        Text(info)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let info = sub.trafficSummary {
                Text(info)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                let rowBusy = state.updatingSubscriptionID == sub.id
                let bulkBusy = state.isBusy
                Button {
                    Task { await state.updateSubscription(id: sub.id) }
                } label: {
                    HStack(spacing: 4) {
                        if rowBusy {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(rowBusy ? t("subs.updating") : t("subs.updateOne"))
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: tint.opacity(enabled ? 0.22 : 0.08), radius: 4, y: 1)
                )
                .disabled(rowBusy || bulkBusy)
                .opacity(rowBusy || bulkBusy ? 0.6 : 1)

                cardIconButton(systemImage: "pencil", action: onRename)
                cardIconButton(systemImage: "qrcode", action: onShareQR)

                ShareLink(item: sub.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(tint)
                        .background(
                            Circle()
                                .fill(tint.opacity(0.12))
                                .overlay(
                                    Circle()
                                        .strokeBorder(tint.opacity(0.18), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(enabled ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(enabled ? 0.22 : 0.10), lineWidth: 0.8)
                )
                .shadow(color: tint.opacity(enabled ? 0.10 : 0.03), radius: 8, y: 3)
        }
        .opacity(enabled ? 1 : 0.78)
        .contextMenu {
            Button(action: onRename) {
                Label(t("subs.rename"), systemImage: "pencil")
            }
            Button {
                UIPasteboard.general.string = sub.url
            } label: {
                Label(t("subs.copyLink"), systemImage: "doc.on.doc")
            }
            Button(action: onShareQR) {
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

    private var urlRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    urlRevealed.toggle()
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: urlRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint.opacity(0.85))
                    Text(urlRevealed ? sub.url : maskedURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(urlRevealed ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(urlRevealed ? t("subs.urlShown") : t("subs.urlHidden"))

            if urlRevealed {
                Button {
                    UIPasteboard.general.string = sub.url
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(5)
                        .background(Circle().fill(tint.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("subs.copyLink"))
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private func statusBadge(enabled: Bool) -> some View {
        Text(enabled ? t("subs.enabled") : (lang == .zh ? "已关闭" : "Off"))
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(enabled ? IOSTheme.good : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(enabled ? IOSTheme.good.opacity(0.14) : Color.primary.opacity(0.06))
            )
    }

    private func cardIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(tint)
                .background(
                    Circle()
                        .fill(tint.opacity(0.12))
                        .overlay(
                            Circle()
                                .strokeBorder(tint.opacity(0.18), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func trafficColors(_ ratio: Double) -> [Color] {
        if ratio >= 0.9 { return [IOSTheme.bad.opacity(0.75), IOSTheme.bad] }
        if ratio >= 0.7 { return [IOSTheme.warn.opacity(0.75), IOSTheme.warn] }
        return [tint.opacity(0.85), tint]
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
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                            Text(t("subs.add"))
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .foregroundStyle(canSave ? Color.white : Color.secondary)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canSave ? AnyShapeStyle(IOSTheme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
                            .padding(.vertical, 2)
                    )
                    .disabled(!canSave)
                }

                Section {
                    Button(action: onRequestScan) {
                        Label(t("subs.scan"), systemImage: "qrcode.viewfinder")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(IOSTheme.accentDeep)
                    }
                    Button {
                        if let clip = UIPasteboard.general.string?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           let parsed = SubscriptionURL.extracted(from: clip) {
                            url = parsed
                        }
                    } label: {
                        Label(t("subs.paste"), systemImage: "doc.on.clipboard")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(IOSTheme.accentDeep)
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
                        .disabled(!canSave)
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
