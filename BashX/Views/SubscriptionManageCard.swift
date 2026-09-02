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
    private var good: Color { BashXTheme.good(for: appearance) }

    /// Soft left stripe + fill tint by status.
    private var statusTint: Color {
        if !sub.enabled { return BashXTheme.tertiaryLabel(for: appearance) }
        if onlyThisEnabled { return accent }
        return good
    }

    private var cardFill: Color {
        if !sub.enabled {
            return BashXTheme.field(for: appearance).opacity(appearance == .dark ? 0.55 : 0.7)
        }
        if onlyThisEnabled {
            return accent.opacity(appearance == .dark ? 0.16 : 0.10)
        }
        return BashXTheme.card(for: appearance)
    }

    private var cardStroke: Color {
        if onlyThisEnabled {
            return accent.opacity(appearance == .dark ? 0.45 : 0.32)
        }
        if sub.enabled {
            return good.opacity(appearance == .dark ? 0.28 : 0.18)
        }
        return BashXTheme.separator(for: appearance)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [statusTint, statusTint.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
                    } label: {
                        SubscriptionEnableControl(
                            enabled: sub.enabled,
                            size: 22,
                            emphasized: onlyThisEnabled
                        )
                    }
                    .buttonStyle(PanelPressButtonStyle())
                    .help(sub.enabled ? "点击停用" : "点击启用并合并")

                    VStack(alignment: .leading, spacing: 4) {
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
                        .padding(.leading, 32)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardStroke, lineWidth: onlyThisEnabled ? 1.2 : 0.8)
                )
                .shadow(
                    color: onlyThisEnabled
                        ? accent.opacity(appearance == .dark ? 0.22 : 0.12)
                        : Color.black.opacity(appearance == .dark ? 0.18 : 0.04),
                    radius: onlyThisEnabled ? 8 : 3,
                    y: 1
                )
        }
        .opacity(sub.enabled ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }

                statusBadge
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if onlyThisEnabled {
            Text("当前")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
        } else if sub.enabled {
            Text("启用")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(good)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(good.opacity(appearance == .dark ? 0.22 : 0.14)))
        } else {
            Text("停用")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(BashXTheme.secondaryFill(for: appearance))
                )
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(displayHost)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(accent.opacity(appearance == .dark ? 0.18 : 0.10))
                )
                .help(sub.url)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                .lineLimit(1)
        }
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
        HStack(spacing: 5) {
            iconAction(
                systemImage: onlyThisEnabled ? "checkmark.circle.fill" : "checkmark.circle",
                help: onlyThisEnabled ? "已选用" : "仅用此订阅",
                tint: onlyThisEnabled ? accent : BashXTheme.secondaryLabel(for: appearance),
                fill: onlyThisEnabled
                    ? accent.opacity(appearance == .dark ? 0.22 : 0.12)
                    : BashXTheme.secondaryFill(for: appearance),
                disabled: onlyThisEnabled || state.isBusy
            ) {
                Task { await state.switchToSubscription(subscriptionId) }
            }

            iconAction(
                systemImage: "arrow.clockwise",
                help: "更新",
                tint: accent,
                fill: accent.opacity(appearance == .dark ? 0.18 : 0.10),
                disabled: state.isBusy
            ) {
                Task { await state.updateSubscription(subscriptionId) }
            }

            Menu {
                contextActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(BashXTheme.secondaryFill(for: appearance))
                    )
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
        fill: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelPressButtonStyle())
        .disabled(disabled)
        .help(help)
    }

    private func compactTraffic(_ info: SubscriptionUserInfo) -> some View {
        let ratio = info.usedRatio ?? 0
        let bar = trafficColor(ratio: info.usedRatio)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(info.usedText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(bar)
                Text("/ \(info.totalText)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

                if info.usedRatio != nil {
                    Text(String(format: "%.0f%%", ratio * 100))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(bar)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(bar.opacity(appearance == .dark ? 0.22 : 0.14)))
                }

                Spacer(minLength: 4)

                Text(info.expireDetailText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(
                        info.isExpired
                            ? BashXTheme.bad(for: appearance)
                            : BashXTheme.tertiaryLabel(for: appearance)
                    )
                    .lineLimit(1)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(bar.opacity(appearance == .dark ? 0.18 : 0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [bar.opacity(0.75), bar],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, geo.size.width * CGFloat(max(0, min(1, ratio)))))
                }
            }
            .frame(height: 4)
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
