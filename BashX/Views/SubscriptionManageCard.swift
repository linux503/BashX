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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let info = sub.userInfo {
                Divider().opacity(0.45)
                SubscriptionTrafficBlock(info: info)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else if sub.updatedAt != nil {
                Text("未识别流量 · 点更新")
                    .font(.caption2)
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            if showActions {
                Divider().opacity(0.45)
                footer
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            sub.enabled ? accent.opacity(onlyThisEnabled ? 0.32 : 0.18) : BashXTheme.separator(for: appearance),
                            lineWidth: sub.enabled ? 1 : 0.5
                        )
                )
        }
        .opacity(sub.enabled ? 1 : 0.72)
        .transaction { $0.animation = nil }
        .contextMenu { contextActions }
        .sheet(isPresented: $showQRShare) {
            SubscriptionQRShareSheet(name: sub.name, url: sub.url, lang: lang)
        }
        .onValueChange(isEditingName) { editing in
            if editing { DispatchQueue.main.async { nameFocused = true } }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                Task { await state.setSubscriptionEnabled(subscriptionId, enabled: !sub.enabled) }
            } label: {
                SubscriptionEnableControl(
                    enabled: sub.enabled,
                    size: 32,
                    emphasized: onlyThisEnabled
                )
            }
            .buttonStyle(PanelPressButtonStyle())
            .help(sub.enabled ? "点击停用" : "点击启用并合并")

            VStack(alignment: .leading, spacing: 3) {
                nameRow
                Text(displayHost)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(sub.url)
            }

            Spacer(minLength: 4)

            if !isEditingName {
                statusCaption
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var nameRow: some View {
        HStack(spacing: 5) {
            if isEditingName {
                TextField("名称", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .focused($nameFocused)
                    .onSubmit { commitRename() }
                Button("保存") { commitRename() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Button("取消") { cancelRename() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            } else {
                Text(sub.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }
                if sub.enabled {
                    Text(onlyThisEnabled ? "当前" : "已启用")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }
            }
        }
    }

    private var statusCaption: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
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

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                Task { await state.switchToSubscription(subscriptionId) }
            } label: {
                Text(onlyThisEnabled ? "已选用" : "仅用此订阅")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(onlyThisEnabled ? accent : BashXTheme.secondaryLabel(for: appearance))
            .disabled(onlyThisEnabled || state.isBusy)

            Text("·").foregroundStyle(.quaternary)

            Button {
                Task { await state.updateSubscription(subscriptionId) }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .disabled(state.isBusy)

            Text("·").foregroundStyle(.quaternary)

            Button {
                showQRShare = true
            } label: {
                Label(L10n.t("subs.qrShare", lang), systemImage: "qrcode")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))

            Spacer(minLength: 0)

            Menu {
                contextActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
