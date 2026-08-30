import AppKit
import SwiftUI

struct AddSubscriptionSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.bashxAppearance) private var appearance
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var url = ""
    @State private var phase: Phase = .form
    @State private var errorMessage = ""
    @State private var successNodeCount = 0
    @State private var autoCloseTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?
    var onAdded: (() -> Void)? = nil

    private enum Phase {
        case form, loading, success, failure
    }

    private enum Field {
        case name, url
    }

    private var accent: Color { BashXTheme.accent(for: appearance) }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urlValidationHint: String? {
        let raw = trimmedURL
        guard !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http://"), !state.settings.allowInsecureHTTPSubscriptions {
            return "明文 HTTP 需在设置中开启「允许不安全 HTTP 订阅」"
        }
        if AppState.normalizedSubscriptionURL(
            raw,
            allowInsecureHTTP: state.settings.allowInsecureHTTPSubscriptions
        ) == nil {
            return "请输入以 https:// 开头的有效链接"
        }
        if state.hasDuplicateSubscription(url: raw) {
            return "该链接已在订阅列表中"
        }
        return nil
    }

    private var canSubmit: Bool {
        !trimmedURL.isEmpty && urlValidationHint == nil && phase == .form
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 20)

            Group {
                switch phase {
                case .form:
                    formContent
                case .loading:
                    loadingContent
                case .success:
                    successContent
                case .failure:
                    failureContent
                }
            }
            .animation(.easeInOut(duration: 0.22), value: phase)

            if phase == .form || phase == .failure {
                actionBar
                    .padding(.top, 22)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 460)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BashXTheme.card(for: appearance))
                // Soft brand wash at the top — less flat than plain white.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(appearance == .dark ? 0.14 : 0.08),
                                accent.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(color: .black.opacity(appearance == .dark ? 0.45 : 0.12), radius: 28, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(appearance == .dark ? 0.12 : 0.55),
                            accent.opacity(appearance == .dark ? 0.18 : 0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(16)
        }
        .onAppear {
            if state.settings.subscriptions.isEmpty {
                autoPasteIfNeeded()
            }
            focusedField = .url
        }
        .onDisappear {
            autoCloseTask?.cancel()
            autoCloseTask = nil
            phase = .form
            name = ""
            url = ""
            errorMessage = ""
            successNodeCount = 0
        }
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(appearance == .dark ? 0.10 : 0.05))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .help("关闭")
        .keyboardShortcut(.cancelAction)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [headerBadgeColor, headerBadgeColor.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: headerBadgeColor.opacity(0.32), radius: 10, y: 4)
                Image(systemName: headerIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(headerTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 36)
            Spacer(minLength: 0)
        }
    }

    private var headerBadgeColor: Color {
        switch phase {
        case .success: return BashXTheme.good(for: appearance)
        case .failure: return BashXTheme.bad
        default: return accent
        }
    }

    private var headerIcon: String {
        switch phase {
        case .form: return "link.badge.plus"
        case .loading: return "arrow.down.circle"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .form: return "添加订阅"
        case .loading: return "正在添加…"
        case .success: return "添加成功"
        case .failure: return "添加失败"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .form: return "粘贴机场链接，自动识别流量与到期时间"
        case .loading: return state.statusText
        case .success: return "已加载 \(successNodeCount) 个节点"
        case .failure: return "请检查链接后重试"
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            formSection(number: 1, title: "粘贴订阅链接", detail: "支持 Clash / V2Ray 等格式") {
                urlField
            }

            formSection(number: 2, title: "命名（可选）", detail: "留空则自动识别机场名称") {
                inputField(
                    icon: "tag",
                    placeholder: "例如：机场 A",
                    text: $name,
                    field: .name,
                    monospaced: false
                )
            }

            hintCard
        }
    }

    private func formSection<Content: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(accent.opacity(0.12))
                            .overlay(
                                Circle()
                                    .strokeBorder(accent.opacity(0.22), lineWidth: 0.8)
                            )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            content()
                .padding(.leading, 32)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BashXTheme.field(for: appearance).opacity(appearance == .dark ? 0.55 : 0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(BashXTheme.separator(for: appearance).opacity(0.7), lineWidth: 0.5)
                )
        }
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        monospaced: Bool,
        trailing: AnyView? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focusedField == field ? accent : Color.secondary.opacity(0.55))
                .frame(width: 16)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: monospaced ? .monospaced : .rounded))
                .focused($focusedField, equals: field)
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            focusedField == field ? accent.opacity(0.50) : BashXTheme.separator(for: appearance),
                            lineWidth: focusedField == field ? 1.3 : 0.6
                        )
                )
                .shadow(
                    color: focusedField == field ? accent.opacity(0.12) : .clear,
                    radius: 6,
                    y: 1
                )
        }
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputField(
                icon: "link",
                placeholder: "https://...",
                text: $url,
                field: .url,
                monospaced: true,
                trailing: AnyView(
                    Button {
                        pasteFromClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10, weight: .semibold))
                            Text("粘贴")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(accent.opacity(0.12))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("从剪贴板粘贴")
                )
            )
            .overlay {
                if urlValidationHint != nil {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(BashXTheme.bad.opacity(0.55), lineWidth: 1.2)
                }
            }
            .onSubmit { if canSubmit { commit() } }

            if let hint = urlValidationHint {
                Label(hint, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BashXTheme.bad)
            } else if !trimmedURL.isEmpty {
                Label("链接格式正确", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(BashXTheme.good(for: appearance))
            }
        }
    }

    private var hintCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("添加后会自动")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("拉取节点 · 识别流量与到期 · 合并到节点列表")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(appearance == .dark ? 0.12 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.16), lineWidth: 0.6)
                )
        }
    }

    private var loadingContent: some View {
        let status = state.statusText
        let fetching = status.contains("更新") || status.contains("拉取") || status.contains("添加")
        let parsing = status.contains("解析") || status.contains("写入") || status.contains("应用")
            || status.contains("已更新") || status.contains("节点")
        return VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(accent)
            VStack(alignment: .leading, spacing: 10) {
                loadingStep("验证链接", done: true)
                loadingStep("拉取订阅内容", done: parsing && !fetching, active: fetching || !parsing)
                loadingStep("解析节点与流量", done: false, active: parsing && !fetching)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var successContent: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BashXTheme.good(for: appearance).opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(BashXTheme.good(for: appearance))
            }
            VStack(spacing: 6) {
                Text("订阅已加入列表")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("可在订阅页管理启用状态与更新")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .onAppear {
            autoCloseTask?.cancel()
            autoCloseTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { isPresented = false }
            }
        }
    }

    private var failureContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(BashXTheme.bad)
                Text(errorMessage)
                    .font(.system(size: 12, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BashXTheme.bad.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(BashXTheme.bad.opacity(0.15), lineWidth: 0.5)
                    )
            }

            formSection(number: 1, title: "重新粘贴链接", detail: "检查格式后重试") {
                urlField
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                isPresented = false
            } label: {
                Text("取消")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 84)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(appearance == .dark ? 0.10 : 0.06))
            }
            Spacer()
            Button {
                commit()
            } label: {
                Text(phase == .failure ? "重试" : "添加并更新")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(canSubmit ? Color.white : Color.primary.opacity(0.35))
                    .frame(minWidth: 120)
                    .padding(.vertical, 10)
                    .background {
                        Group {
                            if canSubmit {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, accent.opacity(0.82)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: accent.opacity(0.28), radius: 8, y: 3)
                            } else {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.primary.opacity(appearance == .dark ? 0.10 : 0.06))
                            }
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func loadingStep(_ title: String, done: Bool, active: Bool = false) -> some View {
        HStack(spacing: 12) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BashXTheme.good(for: appearance))
                } else if active {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18, height: 18)
            Text(title)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(active || done ? .primary : .secondary)
        }
    }

    private func autoPasteIfNeeded() {
        guard trimmedURL.isEmpty else { return }
        pasteFromClipboard(silent: true)
    }

    private func pasteFromClipboard(silent: Bool = false) {
        let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return }
        url = raw
        if AppState.normalizedSubscriptionURL(raw) != nil {
            focusedField = .name
        } else if !silent {
            focusedField = .url
        }
    }

    private func commit() {
        guard canSubmit || phase == .failure else { return }
        let u = trimmedURL
        let n = name
        phase = .loading
        errorMessage = ""

        Task {
            let outcome = await state.addSubscriptionAndFetch(name: n, url: u)
            await MainActor.run {
                switch outcome {
                case .success(let count):
                    successNodeCount = count
                    onAdded?()
                    if state.settings.subscriptions.count <= 1 {
                        phase = .success
                    } else {
                        isPresented = false
                    }
                case .invalidURL:
                    errorMessage = "链接格式无效；默认需 https://（HTTP 请先在设置中开启）"
                    phase = .failure
                case .duplicate:
                    errorMessage = "该订阅链接已在列表中，无需重复添加"
                    phase = .failure
                case .fetchFailed(let msg):
                    errorMessage = msg
                    phase = .failure
                }
            }
        }
    }
}

struct SubscriptionTrafficBlock: View {
    @Environment(\.bashxAppearance) private var appearance
    let info: SubscriptionUserInfo

    private var ratio: Double { info.usedRatio ?? 0 }
    private var accent: Color { BashXTheme.accent(for: appearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(info.usedText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("/ \(info.totalText)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(percentLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(barColor)
            }

            usageBar

            HStack(spacing: 12) {
                Text("剩余 \(info.remainingText)")
                    .foregroundStyle(remainingColor)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("到期 \(info.expireDetailText)")
                    .foregroundStyle(info.isExpired ? BashXTheme.bad(for: appearance) : BashXTheme.secondaryLabel(for: appearance))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .lineLimit(1)
        }
        .transaction { $0.animation = nil }
    }

    private var percentLabel: String {
        guard info.usedRatio != nil else { return "—" }
        return String(format: "%.0f%%", ratio * 100)
    }

    private var usageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BashXTheme.secondaryFill(for: appearance))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.7), barColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, geo.size.width * CGFloat(max(0, min(1, ratio)))))
            }
        }
        .frame(height: 4)
    }

    private var remainingColor: Color {
        guard let r = info.usedRatio else { return BashXTheme.good(for: appearance) }
        if r >= 0.9 { return BashXTheme.bad(for: appearance) }
        if r >= 0.7 { return BashXTheme.warn(for: appearance) }
        return BashXTheme.good(for: appearance)
    }

    private var barColor: Color {
        guard let r = info.usedRatio else { return accent }
        if r >= 0.9 { return BashXTheme.bad(for: appearance) }
        if r >= 0.7 { return BashXTheme.warn(for: appearance) }
        return accent
    }
}

// MARK: - Subscription enable toggle

/// Checkbox-style enable control for multi-select subscription merge.
struct SubscriptionEnableControl: View {
    @Environment(\.bashxAppearance) private var appearance

    let enabled: Bool
    var monogram: String = ""
    var size: CGFloat = 40
    var emphasized: Bool = false

    private var accent: Color { BashXTheme.accent(for: appearance) }
    private var corner: CGFloat { max(4, size * 0.22) }
    private var boxSize: CGFloat { size }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(enabled ? accent : Color.primary.opacity(appearance == .dark ? 0.06 : 0.04))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    enabled
                        ? accent.opacity(emphasized ? 1 : 0.85)
                        : Color.primary.opacity(appearance == .dark ? 0.35 : 0.28),
                    lineWidth: enabled ? (emphasized ? 2 : 1.5) : 1.5
                )
            if enabled {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: boxSize, height: boxSize)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .animation(.easeOut(duration: 0.14), value: enabled)
        .accessibilityLabel(enabled ? "已启用" : "未启用")
        .accessibilityAddTraits(.isButton)
    }
}

