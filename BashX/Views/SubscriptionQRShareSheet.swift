import AppKit
import SwiftUI

struct SubscriptionQRShareSheet: View {
    let name: String
    let url: String
    let lang: AppLanguage
    @Environment(\.bashxAppearance) private var appearance
    @Environment(\.dismiss) private var dismiss

    private func t(_ key: String) -> String { L10n.t(key, lang) }

    private var qrImage: NSImage? {
        guard let cg = QRCodeGenerator.cgImage(from: url) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("qr.title"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            VStack(spacing: 16) {
                Text(name.isEmpty ? t("qr.defaultName") : name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let qrImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                } else {
                    Text(t("qr.fail"))
                        .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                }

                Text(t("qr.hint"))
                    .font(.footnote)
                    .foregroundStyle(BashXTheme.secondaryLabel(for: appearance))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Text(url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(BashXTheme.tertiaryLabel(for: appearance))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    } label: {
                        Label(t("subs.copyLink"), systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        guard let qrImage else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([qrImage])
                    } label: {
                        Label(t("qr.copyImage"), systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(qrImage == nil)

                    ShareLink(item: url) {
                        Label(t("qr.share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BashXTheme.accent(for: appearance))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 380)
        .background(BashXTheme.card(for: appearance))
    }
}
