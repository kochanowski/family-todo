#if !CI
    import AuthenticationServices
#endif
import SwiftUI
import UIKit

/// Sign in screen with Apple authentication.
struct SignInView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var isResolvingAuthRoute = false

    var body: some View {
        Group {
            if shouldShowLaunchContinuation {
                LaunchContinuationView()
            } else {
                signInContent
            }
        }
        .task(id: authRoutingKey) {
            await handleAuthRoutingIfNeeded()
        }
    }

    private var signInContent: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                housePulseLogo

                Text("HousePulse")
                    .font(themeStore.font(for: .screenHeader))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                Text("Share tasks, stay organized, live better together")
                    .font(themeStore.font(for: .listRowTitle))
                    .foregroundStyle(themeStore.contentSecondaryColor)
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
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .padding(.bottom, 60)
        }
        .padding()
        .appAdaptiveWidth(
            maxWidth: AppChromeMetrics.regularFormMaxWidth,
            alignment: .top
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var shouldShowLaunchContinuation: Bool {
        guard case .authenticated = userSession.authService.authenticationState else {
            return false
        }

        return !userSession.needsDisplayNamePrompt
    }

    private var housePulseLogo: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 116, height: 116)

            Image(systemName: "house.fill")
                .font(.system(size: 66, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .offset(y: 8)
        }
        .accessibilityHidden(true)
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
                .font(themeStore.font(for: .bodyStrong))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try again") {
                userSession.signIn()
            }
            .font(themeStore.font(for: .buttonLabel))
            .buttonStyle(.borderedProminent)

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
            onboardingState.completeAuth(
                syncMethod: .local,
                isGuest: true,
                hasHousehold: userSession.currentHouseholdID != nil
            )
        }
        .font(themeStore.font(for: .buttonLabel))
        .buttonStyle(.bordered)
        .frame(maxWidth: 280)
    }

    private var guestFootnote: some View {
        Text("Local-only mode. Data stays on this device.")
            .font(themeStore.font(for: .bodySmall))
            .foregroundStyle(themeStore.contentSecondaryColor)
    }

    private func userFacingErrorMessage(for error: AuthenticationService.AuthenticationError) -> String {
        switch error {
        case .cloudKitNotAvailable:
            "Sign in could not be completed. Check iCloud settings and try again."
        case .userNotFound:
            "Sign in succeeded, but no CloudKit user was found. Please try again."
        case .failed:
            "Sign in with Apple failed. Please try again."
        case .cancelled:
            ""
        }
    }

    private var authRoutingKey: String {
        [
            onboardingState.currentState.rawValue,
            userSession.sessionMode.rawValue,
            userSession.userId ?? "none",
            userSession.currentHouseholdID?.uuidString ?? "none",
            userSession.hasConfirmedDisplayName ? "named" : "unnamed",
            householdStore.isModelContextReady ? "contextReady" : "contextMissing",
        ].joined(separator: "|")
    }

    private func handleAuthRoutingIfNeeded() async {
        guard onboardingState.currentState == .auth || onboardingState.currentState == .householdSetup else {
            return
        }
        guard !isResolvingAuthRoute else { return }

        if userSession.isGuest {
            onboardingState.completeAuth(
                syncMethod: .local,
                isGuest: true,
                hasHousehold: userSession.currentHouseholdID != nil
            )
            return
        }

        guard userSession.isAuthenticated else { return }
        guard householdStore.isModelContextReady else { return }

        isResolvingAuthRoute = true
        defer { isResolvingAuthRoute = false }

        if let userId = userSession.userId {
            householdStore.setSyncMode(.cloud)

            if let restoredHousehold = householdStore.resolveStartupHouseholdLocally(
                userId: userId,
                preferredHouseholdId: userSession.currentHouseholdID
            ) {
                if userSession.currentHouseholdID != restoredHousehold.id {
                    userSession.setCurrentHousehold(restoredHousehold.id)
                }
            }

            if let household = householdStore.currentHousehold,
               userSession.currentHouseholdID != household.id
            {
                userSession.setCurrentHousehold(household.id)
            }
        }

        if let householdId = userSession.currentHouseholdID,
           householdStore.isRecoverySuppressed(for: householdId)
        {
            householdStore.clearCurrentHousehold()
            userSession.clearCurrentHousehold()
        }

        let hasHousehold = userSession.currentHouseholdID != nil || householdStore.currentHousehold != nil
        onboardingState.completeAuth(syncMethod: .iCloud, isGuest: false, hasHousehold: hasHousehold)
    }
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
        .environmentObject(OnboardingState())
        .environmentObject(HouseholdStore())
        .environmentObject(ThemeStore())
}
