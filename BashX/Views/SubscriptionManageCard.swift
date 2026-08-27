import AppKit
import SwiftUI

struct SubscriptionManageCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance
    let subscriptionId: UUID
    var index: Int
    var showActions: Bool = true

    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private var sub: Subscription {
        state.settings.subscriptions.first(where: { $0.id == subscriptionId })
            ?? Subscription(name: "—", url: "")
    }

    private var onlyThisEnabled: Bool {
        sub.enabled && state.settings.subscriptions.filter(\.enabled).count == 1
    }

    private var accent: Color { BashXTheme.accent(for: appearance) }

    private var monogram: String {
        let trimmed = sub.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        return String(first).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let info = sub.userInfo {
                SubscriptionTrafficBlock(info: info)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, showActions ? 4 : 14)
            } else if sub.updatedAt != nil {
                Text("未识别到流量信息 · 点更新再试")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                Color.clear.frame(height: 8)
            }

            if showActions {
                footer
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            sub.enabled
                                ? (onlyThisEnabled ? accent.opacity(0.35) : accent.opacity(0.2))
                                : BashXTheme.separator(for: appearance),
                            lineWidth: sub.enabled ? 1.2 : 0.5
                        )
                )
                .shadow(
                    color: Color.black.opacity(appearance == .dark ? 0.25 : 0.05),
                    radius: 10,
                    y: 3
                )
        }
        .opacity(sub.enabled ? 1 : 0.68)
        .transaction { $0.animation = nil }
        .contextMenu {
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
            Button("复制链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(sub.url, forType: .string)
            }
            Button("在 Finder 中显示缓存") {
                state.revealSubscriptionFile(id: subscriptionId)
            }
            Button("删除", role: .destructive) {
                state.removeSubscription(subscriptionId)
            }
        }
        .onValueChange(isEditingName) { editing in
            if editing {
                DispatchQueue.main.async { nameFocused = true }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
            } label: {
                SubscriptionEnableControl(
                    enabled: sub.enabled,
                    monogram: monogram,
                    size: 40,
                    emphasized: onlyThisEnabled
                )
            }
            .buttonStyle(PanelPressButtonStyle())
            .help(sub.enabled ? "已合并到节点列表 · 点击停用" : "点击合并到节点列表（可多选）")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isEditingName {
                        TextField("订阅名称", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .focused($nameFocused)
                            .onSubmit { commitRename() }
                        Button("保存") { commitRename() }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .controlSize(.mini)
                        Button("取消") { cancelRename() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    } else {
                        Text(sub.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .onTapGesture(count: 2) { beginRename() }
                        Button { beginRename() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("编辑名称")
                        if sub.enabled {
                            Text(onlyThisEnabled ? "当前" : "已启用")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accent))
                        }
                    }
                }

                Text(displayHost)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(sub.url)
                    .textSelection(.enabled)

                subscriptionCacheRow
            }

            Spacer(minLength: 8)

            if !isEditingName {
                statusBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var displayHost: String {
        if let url = URL(string: sub.url), let host = url.host, !host.isEmpty {
            return host
        }
        return sub.url
    }

    private var subscriptionCacheRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(state.subscriptionCacheExists(for: subscriptionId)
                 ? state.subscriptionCachePathLabel(for: subscriptionId)
                 : "尚未缓存 · \(Paths.shortPath(Paths.subscriptionsCacheDir))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button {
                state.revealSubscriptionFile(id: subscriptionId)
            } label: {
                Text("打开目录")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help("在 Finder 中显示订阅缓存文件")
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerChip(
                onlyThisEnabled ? "已选用" : "仅用此订阅",
                icon: "scope",
                emphasized: onlyThisEnabled
            ) {
                Task { await state.switchToSubscription(subscriptionId) }
            }
            .disabled(onlyThisEnabled || state.isBusy)
            .help("只启用这一个订阅，停用其他")

            footerChip("更新", icon: "arrow.clockwise") {
                Task { await state.updateSubscription(subscriptionId) }
            }
            .disabled(state.isBusy)

            footerChip("复制", icon: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(sub.url, forType: .string)
                state.statusText = "已复制订阅链接"
            }

            footerChip("目录", icon: "folder") {
                state.revealSubscriptionFile(id: subscriptionId)
            }
            .help("在 Finder 中显示订阅缓存文件")

            Spacer(minLength: 0)

            Button {
                state.removeSubscription(subscriptionId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BashXTheme.bad.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(BashXTheme.bad.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help("删除订阅")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BashXTheme.secondaryFill(for: appearance))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    private func footerChip(_ title: String, icon: String, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(emphasized ? accent : .primary.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(emphasized ? accent.opacity(0.12) : Color.primary.opacity(0.04))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                emphasized ? accent.opacity(0.25) : Color.primary.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let text: String = {
            if !sub.enabled { return "已停用" }
            if let updated = sub.updatedAt {
                return updated.formatted(.relative(presentation: .named))
            }
            return "未更新"
        }()
        HStack(spacing: 4) {
            Circle()
                .fill(sub.enabled ? BashXTheme.good(for: appearance) : Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(sub.enabled ? .secondary : .tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.04))
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
