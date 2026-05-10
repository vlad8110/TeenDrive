/*
 File: PairingQRCodeView.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Creates a crisp QR code image from the teen pairing payload so a parent can scan it.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingQRCodeView: View {
    let payload: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Image(uiImage: qrImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 220)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
    }

    private var qrImage: UIImage {
        // Generate a high-resolution QR image so it remains crisp when scaled in SwiftUI.
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        return UIImage(cgImage: cgImage)
    }
}
