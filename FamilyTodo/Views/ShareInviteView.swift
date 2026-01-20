import CloudKit
import SwiftUI

/// View for generating and sharing invite links to household
struct ShareInviteView: View {
    @EnvironmentObject var householdStore: HouseholdStore
    @State private var shareURL: URL?
    @State private var isLoading = false
    @State private var showShareSheet = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            Spacer()

            shareContent

            Spacer()
        }
        .padding()
        .navigationTitle("Invite Member")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            if let error {
                Text(error.localizedDescription)
            }
        }
        .task {
            await loadExistingShare()
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Invite Family Member")
                .font(.title2.bold())

            Text(
                "Share this link to invite someone to your household. They'll be able to see and manage tasks together with you."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var shareContent: some View {
        if isLoading {
            ProgressView("Loading...")
        } else if let url = shareURL {
            shareButtonSection(url: url)
        } else {
            createShareButton
        }
    }

    private func shareButtonSection(url: URL) -> some View {
        VStack(spacing: 16) {
            Button {
                showShareSheet = true
            } label: {
                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("or copy the link:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    UIPasteboard.general.string = url.absoluteString
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var createShareButton: some View {
        Button {
            createShare()
        } label: {
            Label("Generate Invite Link", systemImage: "link.badge.plus")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Actions

    private func loadExistingShare() async {
        isLoading = true
        do {
            shareURL = try await householdStore.getShareURL()
        } catch {
            // No existing share, that's OK
        }
        isLoading = false
    }

    private func createShare() {
        Task {
            isLoading = true
            do {
                let share = try await householdStore.createShare()
                shareURL = share.url
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }
}

// MARK: - ShareSheet

/// UIKit ActivityViewController wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ShareInviteView()
            .environmentObject(HouseholdStore())
    }
}
