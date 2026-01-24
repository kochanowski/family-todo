#if !CI
    import AuthenticationServices
#endif
import SwiftUI

/// Sign in screen with Apple authentication
struct SignInView: View {
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App branding
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

            // Authentication state
            VStack(spacing: 16) {
                switch userSession.authService.authenticationState {
                case .authenticating:
                    ProgressView("Signing in...")
                        .progressViewStyle(.circular)

                case let .error(error):
                    VStack(spacing: 12) {
                        Text(error.localizedDescription)
                            .font(.callout)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        signInButton
                        guestButton
                        guestFootnote
                    }

                case .unauthenticated:
                    VStack(spacing: 12) {
                        signInButton
                        guestButton
                        guestFootnote
                    }

                case .authenticated:
                    // This should not be visible when authenticated
                    // but included for completeness
                    Text("Signed in")
                        .foregroundColor(.green)
                }
            }
            .padding(.bottom, 60)
        }
        .padding()
    }

    // MARK: - Subviews

    private var signInButton: some View {
        Button(action: {
            userSession.signIn()
        }) {
            SignInWithAppleButtonView()
                .frame(height: 50)
                .frame(maxWidth: 280)
        }
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
}

/// Custom Sign in with Apple button using ASAuthorizationAppleIDButton
#if !CI
    struct SignInWithAppleButtonView: UIViewRepresentable {
        func makeUIView(context _: Context) -> ASAuthorizationAppleIDButton {
            let button = ASAuthorizationAppleIDButton(
                authorizationButtonType: .signIn,
                authorizationButtonStyle: .black
            )
            return button
        }

        func updateUIView(_: ASAuthorizationAppleIDButton, context _: Context) {
            // No updates needed
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

// MARK: - Preview

#Preview {
    SignInView()
        .environmentObject(UserSession.shared)
}
