import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct InviteQRCodeView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.dismiss) private var dismiss

    @State private var inviteURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Preparing invite...")
                } else if let errorMessage {
                    ContentUnavailableView("Invite unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if let inviteURL, let qrImage = qrImage(from: inviteURL.absoluteString) {
                    VStack(spacing: 20) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.secondarySystemBackground))
                            )

                        Text("Scan this QR code to join household")
                            .font(.headline)

                        Text(inviteURL.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .padding(.horizontal)

                        Button {
                            UIPasteboard.general.string = inviteURL.absoluteString
                        } label: {
                            Label("Copy invite link", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Invite QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadInviteURL()
        }
    }

    private func loadInviteURL() async {
        isLoading = true
        defer { isLoading = false }

        do {
            inviteURL = try await householdStore.fetchInviteURL()
            errorMessage = nil
        } catch {
            errorMessage = "Could not prepare invite. Check CloudKit diagnostics in Profile."
        }
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
