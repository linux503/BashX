import SwiftUI

/// Bottom-left chip on the home panel when a newer release is available.
struct HomeUpdateBanner: View {
    @ObservedObject private var updater = AppUpdateController.shared
    @Environment(\.bashxAppearance) private var appearance
    let lang: AppLanguage

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        Group {
            if updater.shouldShowHomeBanner {
                banner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: updater.shouldShowHomeBanner)
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BashXTheme.accent(for: appearance))

            Text(message)
                .font(PanelMetrics.caption)
                .foregroundStyle(BashXTheme.primaryLabel(for: appearance))
                .lineLimit(1)

            if case .downloading(let progress) = updater.phase {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .frame(width: 52)
            } else if canUpgrade {
                Button(t("mac.update.bannerUpgrade")) {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(BashXTheme.accent(for: appearance))
            }

            Button {
                updater.dismissHomeBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t("mac.update.bannerDismiss"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BashXTheme.card(for: appearance).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BashXTheme.accent(for: appearance).opacity(0.35), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(appearance == .dark ? 0.28 : 0.08), radius: 8, y: 2)
        }
    }

    private var canUpgrade: Bool {
        if case .available = updater.phase { return true }
        return false
    }

    private var iconName: String {
        if case .downloading = updater.phase { return "arrow.down.circle" }
        return "sparkles"
    }

    private var message: String {
        switch updater.phase {
        case .available(let info):
            return t("mac.update.banner").replacingOccurrences(of: "%@", with: info.version)
        case .downloading(let progress):
            let pct = Int(progress * 100)
            return t("mac.update.bannerDownloading").replacingOccurrences(of: "%@", with: "\(pct)")
        default:
            return t("mac.update.banner")
        }
    }
}
