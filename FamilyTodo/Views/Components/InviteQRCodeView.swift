import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct InviteQRCodeCard: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let inviteCode: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 16) {
            if let qrImage = qrImage(from: inviteCode) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(themeStore.surfaceElevatedColor)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(themeStore.surfaceElevatedColor)
        )
    }

    private func qrImage(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
