import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct InviteQRCodeView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var inviteURL: URL?
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
                } else if let errorMessage {
                    ThemedEmptyStateView(
                        title: "Invite unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: errorMessage
                    )
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
                            .font(themeStore.font(for: .inlineTitle))
                            .foregroundStyle(themeStore.contentPrimaryColor)

                        if let inviteCode {
                            VStack(spacing: 8) {
                                Text("Invite code")
                                    .font(themeStore.font(for: .bodySmall))
                                    .foregroundStyle(themeStore.contentSecondaryColor)
                                Text(inviteCode)
                                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }

                        Text(inviteURL.absoluteString)
                            .font(themeStore.font(for: .bodySmall))
                            .foregroundStyle(themeStore.contentSecondaryColor)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            if let inviteCode {
                                Button {
                                    UIPasteboard.general.string = inviteCode
                                } label: {
                                    Label("Copy invite code", systemImage: "number")
                                        .font(themeStore.font(for: .buttonLabel))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button {
                                UIPasteboard.general.string = inviteURL.absoluteString
                            } label: {
                                Label("Copy invite link", systemImage: "doc.on.doc")
                                    .font(themeStore.font(for: .buttonLabel))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
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
            inviteCode = try? await householdStore.fetchOrCreateInviteCode()
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
