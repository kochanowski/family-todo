import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct InviteQRCodeView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Preparing invite...")
                        .font(themeStore.font(for: .bodyStrong))
                } else if let errorMessage {
                    ThemedEmptyStateView(
                        title: "Invite unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: errorMessage
                    )
                } else if let inviteCode, let qrImage = qrImage(from: inviteCode) {
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

                        Text("Scan this QR code to join with the 8-character invite code")
                            .font(themeStore.font(for: .inlineTitle))
                            .foregroundStyle(themeStore.contentPrimaryColor)

                        VStack(spacing: 8) {
                            Text("Invite code")
                                .font(themeStore.font(for: .bodySmall))
                                .foregroundStyle(themeStore.contentSecondaryColor)
                            Text(inviteCode)
                                .font(.system(size: 30, weight: .bold, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        VStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = inviteCode
                            } label: {
                                Label("Copy invite code", systemImage: "number")
                                    .font(themeStore.font(for: .buttonLabel))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(themeStore.font(for: .buttonLabel))
                }
                ToolbarItem(placement: .principal) {
                    Text("Invite QR")
                        .font(themeStore.font(for: .inlineTitle))
                        .foregroundStyle(themeStore.contentPrimaryColor)
                }
            }
        }
        .task {
            await loadInviteCode()
        }
    }

    private func loadInviteCode() async {
        isLoading = true
        defer { isLoading = false }

        do {
            inviteCode = try await householdStore.fetchOrCreateInviteCode()
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
