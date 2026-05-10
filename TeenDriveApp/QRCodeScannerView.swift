/*
 File: QRCodeScannerView.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Wraps AVFoundation camera scanning in SwiftUI so a parent can read a teen pairing QR code.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import AVFoundation
import SwiftUI

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    /*
     Purpose:
     Creates the bridge object that receives AVFoundation scanner callbacks.
    */
    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    /*
     Purpose:
     Creates and configures the UIKit scanner controller for SwiftUI.
    */
    func makeUIViewController(context: Context) -> ScannerViewController {
        let viewController = ScannerViewController()
        viewController.delegate = context.coordinator
        return viewController
    }

    /*
     Purpose:
     Satisfies the SwiftUI representable contract; scanner updates are driven by the camera session.
    */
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onScan: (String) -> Void
        private var didScan = false

        /*
         Purpose:
         Initializes this type with the state or dependencies needed before it is used.
        */
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        /*
         Purpose:
         Handles QR metadata found by the camera and reports the scanned string once.
        */
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didScan,
                  let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  metadataObject.type == .qr,
                  let value = metadataObject.stringValue else {
                return
            }

            didScan = true
            onScan(value)
        }
    }
}

final class ScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /*
     Purpose:
     Configures the camera preview and metadata output after the scanner view loads.
    */
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureScanner()
    }

    /*
     Purpose:
     Keeps the camera preview layer sized to the scanner view bounds.
    */
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    /*
     Purpose:
     Starts the camera session when the scanner screen becomes visible.
    */
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }

    /*
     Purpose:
     Stops the camera session when the scanner screen leaves the screen.
    */
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    /*
     Purpose:
     Builds the camera input, QR metadata output, and preview layer.
    */
    private func configureScanner() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showUnavailableMessage()
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showUnavailableMessage()
            return
        }

        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    /*
     Purpose:
     Shows a fallback message when camera scanning cannot be started.
    */
    private func showUnavailableMessage() {
        let label = UILabel()
        label.text = "Camera unavailable"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
