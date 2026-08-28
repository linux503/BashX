import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import VisionKit
import AVFoundation

enum QRCodeImage {
    static func uiImage(from string: String, dimension: CGFloat = 512) -> UIImage? {
        guard let cg = QRCodeGenerator.cgImage(from: string, dimension: dimension) else { return nil }
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

// MARK: - QR scan (add subscription)

enum SubscriptionURLParser {
    static func extract(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                return trimmed
            }
            if scheme == "bashx" {
                if let sub = url.queryItems?.first(where: { $0.name == "url" })?.value {
                    return extract(from: sub)
                }
                if !url.path.isEmpty, url.path != "/" {
                    return extract(from: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                }
            }
        }

        if trimmed.contains("://"), let decoded = trimmed.removingPercentEncoding, decoded != trimmed {
            return extract(from: decoded)
        }

        return nil
    }
}

private extension URL {
    var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}

private struct ScannerUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SubscriptionQRScannerSheet: View {
    @EnvironmentObject private var state: IOSAppState
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    private enum CameraPhase {
        case checking
        case ready
        case denied
        case unavailable
    }

    @State private var cameraPhase: CameraPhase = .checking

    private var lang: AppLanguage { state.settings.uiLanguage }
    private func t(_ key: String) -> String { L10n.t(key, lang) }

    var body: some View {
        NavigationStack {
            Group {
                switch cameraPhase {
                case .checking:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    ScannerUnavailableView(
                        title: t("subs.scan.noCamera.title"),
                        message: t("subs.scan.noCamera.msg")
                    )
                case .unavailable:
                    ScannerUnavailableView(
                        title: t("subs.scan.unavailable.title"),
                        message: t("subs.scan.unavailable.msg")
                    )
                case .ready:
                    SubscriptionQRScannerRepresentable { url in
                        onScan(url)
                        dismiss()
                    }
                    .ignoresSafeArea()
                }
            }
            .navigationTitle(t("subs.scan.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if cameraPhase == .ready {
                    Text(t("subs.scan.hint"))
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 28)
                }
            }
        }
        .id(lang.id)
        .task { await prepareCamera() }
    }

    @MainActor
    private func prepareCamera() async {
        guard DataScannerViewController.isSupported else {
            cameraPhase = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPhase = DataScannerViewController.isAvailable ? .ready : .unavailable
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                cameraPhase = DataScannerViewController.isAvailable ? .ready : .unavailable
            } else {
                cameraPhase = .denied
            }
        default:
            cameraPhase = .denied
        }
    }
}

private struct SubscriptionQRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        context.coordinator.startIfPossible()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        weak var scanner: DataScannerViewController?
        private var didEmit = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func startIfPossible() {
            guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else { return }
            guard let scanner else { return }
            do {
                try scanner.startScanning()
            } catch {
                // Camera busy or unavailable — ignore; sheet already gated on permission.
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didEmit else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      let url = SubscriptionURLParser.extract(from: payload) else { continue }
                didEmit = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dataScanner.stopScanning()
                DispatchQueue.main.async { [onScan] in
                    onScan(url)
                }
                return
            }
        }
    }
}
