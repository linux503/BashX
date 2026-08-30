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
        SubscriptionURL.extracted(from: raw)
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
                    SubscriptionQRScannerRepresentable { scanned in
                        onScan(scanned)
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

struct SubscriptionQRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> QRScannerHostViewController {
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
        let host = QRScannerHostViewController(scanner: scanner)
        let coordinator = context.coordinator
        host.onReadyToScan = { [weak coordinator] in
            coordinator?.startIfPossible()
        }
        return host
    }

    func updateUIViewController(_ uiViewController: QRScannerHostViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: QRScannerHostViewController, coordinator: Coordinator) {
        coordinator.stopScanning()
    }

    /// Host VC — defer `startScanning()` until on-screen (early start in `makeUIViewController` can crash).
    final class QRScannerHostViewController: UIViewController {
        let scanner: DataScannerViewController
        var onReadyToScan: (() -> Void)?
        private var didSignalReady = false

        init(scanner: DataScannerViewController) {
            self.scanner = scanner
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            addChild(scanner)
            scanner.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scanner.view)
            NSLayoutConstraint.activate([
                scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
                scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didSignalReady else { return }
            didSignalReady = true
            onReadyToScan?()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        weak var scanner: DataScannerViewController?
        private var didEmit = false
        private var isScanning = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func startIfPossible() {
            guard !isScanning, !didEmit else { return }
            guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else { return }
            guard let scanner else { return }
            do {
                try scanner.startScanning()
                isScanning = true
            } catch {
                // Camera busy — `becameAvailable` may retry.
            }
        }

        func stopScanning() {
            guard let scanner else { return }
            if isScanning {
                scanner.stopScanning()
                isScanning = false
            }
            self.scanner = nil
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameAvailable: Bool) {
            if becameAvailable {
                startIfPossible()
            } else {
                isScanning = false
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didEmit else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      let url = SubscriptionURLParser.extract(from: payload) else { continue }
                didEmit = true
                isScanning = false
                dataScanner.stopScanning()
                DispatchQueue.main.async { [onScan] in
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onScan(url)
                }
                return
            }
        }
    }
}
