import AVFoundation
import SwiftUI
import UIKit

struct QRCodeScannerView: View {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        QRCodeScannerRepresentable(onCodeScanned: onCodeScanned, onFailure: onFailure)
            .ignoresSafeArea()
    }
}

private struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context _: Context) -> QRCodeScannerViewController {
        let controller = QRCodeScannerViewController()
        controller.onCodeScanned = onCodeScanned
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_: QRCodeScannerViewController, context _: Context) {}
}

private final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScannedCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraPermissionAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func requestCameraPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.onFailure?("Camera permission is required to scan QR codes.")
                    }
                }
            }
        case .denied, .restricted:
            onFailure?("Camera access denied. Enable camera in Settings to scan QR code.")
        @unknown default:
            onFailure?("Camera is unavailable on this device.")
        }
    }

    private func configureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            onFailure?("Camera is unavailable on this device.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                onFailure?("Could not configure camera input.")
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                onFailure?("Could not configure QR scanner output.")
                return
            }

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            onFailure?("Could not access camera: \(error.localizedDescription)")
        }
    }

    func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection
    ) {
        guard !hasScannedCode else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              !value.isEmpty
        else {
            return
        }

        hasScannedCode = true
        session.stopRunning()
        onCodeScanned?(value)
    }
}
