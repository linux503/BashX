import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeImage {
    static func uiImage(from string: String, dimension: CGFloat = 512) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excluded: [UIActivity.ActivityType] = []

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excluded
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SubscriptionQRShareSheet: View {
    let name: String
    let url: String
    @EnvironmentObject private var state: IOSAppState
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }
    private var qrImage: UIImage? { QRCodeImage.uiImage(from: url) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(name.isEmpty ? t("qr.defaultName") : name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                } else {
                    Text(t("qr.fail"))
                        .foregroundStyle(.secondary)
                }

                Text(t("qr.hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = url
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label(t("subs.copyLink"), systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showShare = true
                    } label: {
                        Label(t("qr.share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(qrImage == nil)
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .navigationTitle(t("qr.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let qrImage {
                    ActivityShareSheet(items: [qrImage, url])
                }
            }
        }
        .id(lang.id)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
