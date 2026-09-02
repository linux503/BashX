import AppKit
import SwiftUI

struct SubscriptionManageCard: View {
    let state: AppState
    @Environment(\.bashxAppearance) private var appearance
    let subscriptionId: UUID
    var index: Int
    var showActions: Bool = true

    @State private var isEditingName = false
    @State private var draftName = ""
    @State private var showQRShare = false
    @FocusState private var nameFocused: Bool

    private var lang: AppLanguage { state.settings.uiLanguage }

    private var sub: Subscription {
        state.settings.subscriptions.first(where: { $0.id == subscriptionId })
            ?? Subscription(name: "—", url: "")
    }

    private var onlyThisEnabled: Bool {
        sub.enabled && state.settings.subscriptions.filter(\.enabled).count == 1
    }

    private var accent: Color { BashXTheme.accent(for: appearance) }

    private var rowFill: Color {
        if !sub.enabled {
            return Color.clear
        }
        if onlyThisEnabled {
            return accent.opacity(appearance == .dark ? 0.12 : 0.08)
        }
        return index.isMultiple(of: 2)
            ? Color.primary.opacity(appearance == .dark ? 0.03 : 0.018)
            : Color.clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
                } label: {
                    SubscriptionEnableControl(
                        enabled: sub.enabled,
                        size: 20,
                        emphasized: onlyThisEnabled
                    )
                }
                .buttonStyle(PanelPressButtonStyle())
                .help(sub.enabled ? "点击停用" : "点击启用并合并")

                VStack(alignment: .leading, spacing: 2) {
                    nameRow
                    metaLine
                }

                Spacer(minLength: 8)

                if showActions, !isEditingName {
                    actionCluster
                }
            }

            if let info = sub.userInfo {
                compactTraffic(info)
                    .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            onlyThisEnabled
                                ? accent.opacity(0.28)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .opacity(sub.enabled ? 1 : 0.58)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transaction { $0.animation = nil }
        .contextMenu { contextActions }
        .sheet(isPresented: $showQRShare) {
            SubscriptionQRShareSheet(name: sub.name, url: sub.url, lang: lang)
        }
        .onValueChange(isEditingName) { editing in
            if editing { DispatchQueue.main.async { nameFocused = true } }
        }
    }

    @ViewBuilder
    private var nameRow: some View {
        HStack(spacing: 6) {
            if isEditingName {
                TextField("名称", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($nameFocused)
                    .onSubmit { commitRename() }
                    .frame(maxWidth: 220)
                Button("保存") { commitRename() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.mini)
                Button("取消") { cancelRename() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            } else {
                Text(sub.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }
                if onlyThisEnabled {
                    Text("当前")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.14)))
                } else if sub.enabled {
                    Text("启用")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(BashXTheme.secondaryFill(for: appearance))
                        )
                }
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(displayHost)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(sub.url)
            Text("·")
                .foregroundStyle(.quaternary)
            Text(statusText)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
    }

    private var statusText: String {
        if !sub.enabled { return "已停用" }
        if let updated = sub.updatedAt {
            return updated.formatted(.relative(presentation: .named))
        }
        return "未更新"
    }

    private var displayHost: String {
        if let url = URL(string: sub.url), let host = url.host, !host.isEmpty {
            return host
        }
        return sub.url
    }

    private var actionCluster: some View {
        HStack(spacing: 4) {
            iconAction(
                systemImage: onlyThisEnabled ? "checkmark.circle.fill" : "checkmark.circle",
                help: onlyThisEnabled ? "已选用" : "仅用此订阅",
                tint: onlyThisEnabled ? accent : BashXTheme.secondaryLabel(for: appearance),
                disabled: onlyThisEnabled || state.isBusy
            ) {
                Task { await state.switchToSubscription(subscriptionId) }
            }

            iconAction(
                systemImage: "arrow.clockwise",
                help: "更新",
                tint: BashXTheme.secondaryLabel(for: appearance),
                disabled: state.isBusy
            ) {
                Task { await state.updateSubscription(subscriptionId) }
            }

            Menu {
                contextActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("更多")
        }
    }

    private func iconAction(
        systemImage: String,
        help: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelPressButtonStyle())
        .disabled(disabled)
        .help(help)
    }

    private func compactTraffic(_ info: SubscriptionUserInfo) -> some View {
        let ratio = info.usedRatio ?? 0
        let bar = trafficColor(ratio: info.usedRatio)
        return HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BashXTheme.secondaryFill(for: appearance))
                    Capsule()
                        .fill(bar)
                        .frame(width: max(2, geo.size.width * CGFloat(max(0, min(1, ratio)))))
                }
            }
            .frame(height: 3)
            .frame(maxWidth: 120)

            Text("\(info.usedText) / \(info.totalText)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

            Text(info.expireDetailText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    info.isExpired
                        ? BashXTheme.bad(for: appearance)
                        : BashXTheme.tertiaryLabel(for: appearance)
                )
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func trafficColor(ratio: Double?) -> Color {
        guard let r = ratio else { return accent }
        if r >= 0.9 { return BashXTheme.bad(for: appearance) }
        if r >= 0.7 { return BashXTheme.warn(for: appearance) }
        return accent
    }

    @ViewBuilder
    private var contextActions: some View {
        Button("重命名") { beginRename() }
        Button("更新此订阅") {
            Task { await state.updateSubscription(subscriptionId) }
        }
        .disabled(state.isBusy)
        Button(sub.enabled ? "停用" : "启用") {
            Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
        }
        Button("仅用此订阅") {
            Task { await state.switchToSubscription(subscriptionId) }
        }
        Divider()
        Button("复制链接") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sub.url, forType: .string)
            state.statusText = "已复制订阅链接"
        }
        Button(L10n.t("subs.qrShare", lang)) {
            showQRShare = true
        }
        Button("打开缓存目录") {
            state.revealSubscriptionFile(id: subscriptionId)
        }
        Divider()
        Button("删除", role: .destructive) {
            state.removeSubscription(subscriptionId)
        }
    }

    private func beginRename() {
        draftName = sub.name
        isEditingName = true
    }

    private func cancelRename() {
        isEditingName = false
        draftName = sub.name
        nameFocused = false
    }

    private func commitRename() {
        state.renameSubscription(subscriptionId, name: draftName)
        isEditingName = false
        nameFocused = false
    }
}
