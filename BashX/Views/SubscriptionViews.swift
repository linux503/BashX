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
            GlassDivider()
                .padding(.vertical, 18)

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
            .animation(.easeInOut(duration: 0.2), value: phase)

            if phase == .form || phase == .failure {
                actionBar
                    .padding(.top, 20)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BashXTheme.card(for: appearance))
                .shadow(color: .black.opacity(appearance == .dark ? 0.35 : 0.08), radius: 24, y: 8)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(14)
        }
        .onAppear {
            autoPasteIfNeeded()
            focusedField = .url
        }
        .onDisappear {
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
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("关闭")
        .keyboardShortcut(.cancelAction)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                Image(systemName: headerIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(headerIconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 36)
            Spacer(minLength: 0)
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

    private var headerIconColor: Color {
        switch phase {
        case .success: return BashXTheme.good(for: appearance)
        case .failure: return BashXTheme.bad
        default: return accent
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
        VStack(alignment: .leading, spacing: 18) {
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
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
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
                .padding(.leading, 30)
        }
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        monospaced: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: monospaced ? .monospaced : .rounded))
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.field(for: appearance))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            focusedField == field ? accent.opacity(0.45) : BashXTheme.separator(for: appearance),
                            lineWidth: focusedField == field ? 1.2 : 0.5
                        )
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
                monospaced: true
            )
            .overlay {
                if urlValidationHint != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.bad.opacity(0.5), lineWidth: 1.2)
                }
            }
            .onSubmit { if canSubmit { commit() } }

            HStack {
                if let hint = urlValidationHint {
                    Label(hint, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(BashXTheme.bad)
                } else if !trimmedURL.isEmpty {
                    Label("链接格式正确", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(BashXTheme.good(for: appearance))
                }
                Spacer()
                Button {
                    pasteFromClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10, weight: .semibold))
                        Text("从剪贴板粘贴")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.10))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(accent.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text("添加后会自动")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("拉取节点 · 识别已用/总量/到期 · 合并到节点列表")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.10), accent.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.12), lineWidth: 0.5)
                )
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(accent)
            VStack(alignment: .leading, spacing: 10) {
                loadingStep("验证链接", done: true)
                loadingStep("拉取订阅内容", done: false, active: true)
                loadingStep("解析节点与流量", done: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isPresented = false
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
        HStack(spacing: 10) {
            Button("取消") { isPresented = false }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Spacer()
            Button(phase == .failure ? "重试" : "添加并更新") {
                commit()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
            .disabled(!canSubmit)
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
                    phase = .success
                    onAdded?()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                usageRing
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(info.usedText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        Text("/ \(info.totalText)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text(percentLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(barColor)
                    }

                    // Fixed-height bar — avoids GeometryReader layout flicker.
                    usageBar

                    HStack(spacing: 16) {
                        metricInline(label: "剩余", value: info.remainingText, color: remainingColor)
                        metricInline(
                            label: "到期",
                            value: info.expireDetailText,
                            color: info.isExpired ? BashXTheme.bad : BashXTheme.warn
                        )
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BashXTheme.secondaryFill(for: appearance))
        }
        .transaction { $0.animation = nil }
    }

    private var percentLabel: String {
        guard info.usedRatio != nil else { return "—" }
        return String(format: "%.0f%%", ratio * 100)
    }

    private var usageRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, ratio))
                .stroke(
                    AngularGradient(
                        colors: [barColor.opacity(0.55), barColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(info.usedRatio == nil ? "∞" : String(format: "%.0f", ratio * 100))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(barColor)
                if info.usedRatio != nil {
                    Text("%")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var usageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.65), barColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * CGFloat(max(0, min(1, ratio)))))
            }
        }
        .frame(height: 5)
    }

    private var remainingColor: Color {
        guard let r = info.usedRatio else { return BashXTheme.good(for: appearance) }
        if r >= 0.9 { return BashXTheme.bad }
        if r >= 0.7 { return BashXTheme.warn }
        return BashXTheme.good(for: appearance)
    }

    private var barColor: Color {
        guard let r = info.usedRatio else { return accent }
        if r >= 0.9 { return BashXTheme.bad }
        if r >= 0.7 { return BashXTheme.warn }
        return accent
    }

    private func metricInline(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Subscription enable toggle

/// Circular merge toggle — replaces the old square checkmark control.
struct SubscriptionEnableControl: View {
    @Environment(\.bashxAppearance) private var appearance

    let enabled: Bool
    var monogram: String = ""
    var size: CGFloat = 40
    var emphasized: Bool = false

    private var accent: Color { BashXTheme.accent(for: appearance) }

    var body: some View {
        ZStack {
            if enabled {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(Color.white.opacity(appearance == .dark ? 0.22 : 0.35), lineWidth: 1)
                if size >= 28 {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.34, weight: .black))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.28, height: size * 0.28)
                }
            } else {
                Circle()
                    .fill(Color.primary.opacity(appearance == .dark ? 0.08 : 0.05))
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3.5, 2.5])
                    )
                if size >= 28, !monogram.isEmpty {
                    Text(monogram)
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.75))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.55))
                }
            }

            if enabled, emphasized {
                Circle()
                    .strokeBorder(accent.opacity(0.45), lineWidth: 2)
                    .padding(-4)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: enabled ? accent.opacity(0.28) : .clear, radius: emphasized ? 6 : 4, y: 2)
        .animation(.easeOut(duration: 0.16), value: enabled)
    }
}

