#if !CI
import AuthenticationServices
#endif
import SwiftUI
import UIKit

/// Sign in screen with Apple authentication.
struct SignInView: View {
    @EnvironmentObject private var userSession: UserSession

    @State private var showDiagnosticsSheet = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checklist")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Family To-Do")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Share tasks, stay organized, live better together")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 16) {
                switch userSession.authService.authenticationState {
                case .authenticating:
                    ProgressView("Signing in...")
                        .progressViewStyle(.circular)

                case let .error(error):
                    if case .cancelled = error {
                        defaultAuthActions
                    } else {
                        errorActions(error)
                    }

                case .unauthenticated:
                    defaultAuthActions

                case .authenticated:
                    Text("Signed in")
                        .foregroundColor(.green)
                }
            }
            .padding(.bottom, 60)
        }
        .padding()
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .topTrailing) {
            Button("Debug") {
                showDiagnosticsSheet = true
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showDiagnosticsSheet) {
            SignInDiagnosticsSheet(
                authDiagnosticsJSON: userSession.authService.diagnosticsReportJSON(),
                startupRecoveryEvent: UserDefaults.standard.string(
                    forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey
                ) ?? "No startup recovery event recorded.",
                startupBootstrapDiagnostics: UserDefaults.standard.string(
                    forKey: SwiftDataContainerFactory.bootstrapDiagnosticsUserDefaultsKey
                ) ?? "No startup bootstrap diagnostics recorded.",
                onClearDiagnostics: clearDiagnostics
            )
        }
    }

    private var defaultAuthActions: some View {
        VStack(spacing: 12) {
            signInButton
            guestButton
            guestFootnote
        }
    }

    private func errorActions(_ error: AuthenticationService.AuthenticationError) -> some View {
        VStack(spacing: 12) {
            Text(userFacingErrorMessage(for: error))
                .font(.callout)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("Try again") {
                    userSession.signIn()
                }
                .buttonStyle(.borderedProminent)

                Button("Open diagnostics") {
                    showDiagnosticsSheet = true
                }
                .buttonStyle(.bordered)
            }

            guestButton
            guestFootnote
        }
    }

    private var signInButton: some View {
        Button(
            action: {
                userSession.signIn()
            },
            label: {
                SignInWithAppleButtonView()
                    .frame(height: 50)
                    .frame(maxWidth: 280)
            }
        )
    }

    private var guestButton: some View {
        Button("Continue without account") {
            userSession.startGuestSession()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: 280)
    }

    private var guestFootnote: some View {
        Text("Local-only mode. Data stays on this device.")
            .font(.footnote)
            .foregroundColor(.secondary)
    }

    private func userFacingErrorMessage(for error: AuthenticationService.AuthenticationError) -> String {
        switch error {
        case .cloudKitNotAvailable:
            return "Sign in could not be completed. Check iCloud settings and try again."
        case .userNotFound:
            return "Sign in succeeded, but no CloudKit user was found. Please try again."
        case .failed:
            return "Sign in with Apple failed. Please try again or open diagnostics."
        case .cancelled:
            return ""
        }
    }

    private func clearDiagnostics() {
        userSession.authService.clearDiagnosticsHistory()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        defaults.removeObject(forKey: SwiftDataContainerFactory.bootstrapDiagnosticsUserDefaultsKey)
    }
}

private struct SignInDiagnosticsSheet: View {
    let authDiagnosticsJSON: String
    let startupRecoveryEvent: String
    let startupBootstrapDiagnostics: String
    let onClearDiagnostics: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var copied = false
    @State private var cleared = false

    private var diagnosticsReport: String {
        [
            "=== Auth/CloudKit diagnostics ===",
            authDiagnosticsJSON,
            "",
            "=== Startup store diagnostics: lastStoreRecoveryEvent ===",
            startupRecoveryEvent,
            "",
            "=== Startup store diagnostics: lastStoreBootstrapDiagnostics ===",
            startupBootstrapDiagnostics,
        ].joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    diagnosticsSection(
                        title: "Auth/CloudKit diagnostics",
                        value: authDiagnosticsJSON
                    )

                    diagnosticsSection(
                        title: "Startup store diagnostics",
                        value: [
                            "lastStoreRecoveryEvent:",
                            startupRecoveryEvent,
                            "",
                            "lastStoreBootstrapDiagnostics:",
                            startupBootstrapDiagnostics,
                        ].joined(separator: "\n")
                    )

                    if copied {
                        Text("Diagnostics copied to clipboard.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if cleared {
                        Text("Diagnostics history cleared.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button("Copy diagnostics") {
                        UIPasteboard.general.string = diagnosticsReport
                        copied = true
                    }
                    .buttonStyle(.bordered)

                    Button("Share diagnostics") {
                        showShareSheet = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear diagnostics") {
                        onClearDiagnostics()
                        cleared = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: [diagnosticsReport])
        }
    }

    @ViewBuilder
    private func diagnosticsSection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

// Custom Sign in with Apple button using ASAuthorizationAppleIDButton
#if !CI
struct SignInWithAppleButtonView: UIViewRepresentable {
    func makeUIView(context _: Context) -> ASAuthorizationAppleIDButton {
        ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .black
        )
    }

    func updateUIView(_: ASAuthorizationAppleIDButton, context _: Context) {
        // No updates needed.
    }
}
#else
struct SignInWithAppleButtonView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "applelogo")
            Text("Sign in with Apple")
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color.black)
        .foregroundColor(.white)
        .cornerRadius(10)
    }
}
#endif

#Preview {
    SignInView()
        .environmentObject(UserSession.shared)
}
