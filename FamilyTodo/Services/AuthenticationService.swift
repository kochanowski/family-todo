import AuthenticationServices
import CloudKit
import Foundation

/// Service responsible for handling Sign in with Apple authentication
/// and CloudKit user identity management
@MainActor
final class AuthenticationService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var authenticationState: AuthenticationState = .unauthenticated
    @Published private(set) var currentUser: AuthenticatedUser?

    // MARK: - Private Properties

    private let cloudKitContainer: CKContainer
    private var currentNonce: String?

    // MARK: - Initialization

    init(cloudKitContainer: CKContainer = CKContainer(identifier: "iCloud.com.example.familytodo")) {
        self.cloudKitContainer = cloudKitContainer
        super.init()
    }

    // MARK: - Authentication State

    enum AuthenticationState {
        case unauthenticated
        case authenticating
        case authenticated(userID: String)
        case error(AuthenticationError)
    }

    enum AuthenticationError: LocalizedError {
        case cancelled
        case failed(Error)
        case cloudKitNotAvailable
        case userNotFound

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Authentication was cancelled"
            case .failed(let error):
                return "Authentication failed: \(error.localizedDescription)"
            case .cloudKitNotAvailable:
                return "CloudKit is not available. Please check your iCloud settings."
            case .userNotFound:
                return "User not found in CloudKit"
            }
        }
    }

    // MARK: - Authenticated User Model

    struct AuthenticatedUser: Identifiable {
        let id: String // CloudKit Record ID
        let appleUserID: String
        let email: String?
        let displayName: String?
        let givenName: String?
        let familyName: String?
    }

    // MARK: - Public Methods

    /// Initiates Sign in with Apple flow
    func signInWithApple() {
        authenticationState = .authenticating

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Signs out the current user
    func signOut() {
        currentUser = nil
        authenticationState = .unauthenticated
    }

    /// Checks CloudKit account status and fetches user identity
    func checkCloudKitStatus() async {
        do {
            let status = try await cloudKitContainer.accountStatus()

            switch status {
            case .available:
                try await fetchCloudKitUserIdentity()
            case .noAccount:
                authenticationState = .error(.cloudKitNotAvailable)
            case .restricted:
                authenticationState = .error(.cloudKitNotAvailable)
            case .couldNotDetermine:
                authenticationState = .error(.cloudKitNotAvailable)
            case .temporarilyUnavailable:
                authenticationState = .error(.cloudKitNotAvailable)
            @unknown default:
                authenticationState = .error(.cloudKitNotAvailable)
            }
        } catch {
            authenticationState = .error(.failed(error))
        }
    }

    // MARK: - Private Methods

    private func fetchCloudKitUserIdentity() async throws {
        let userRecordID = try await cloudKitContainer.userRecordID()
        let userID = userRecordID.recordName

        // Update authentication state
        authenticationState = .authenticated(userID: userID)

        // Note: Apple ID credentials are stored separately by Sign in with Apple
        // We only store the CloudKit user ID for data association
        currentUser = AuthenticatedUser(
            id: userID,
            appleUserID: userID, // Simplified for now
            email: nil, // Will be populated from Sign in with Apple credentials
            displayName: nil,
            givenName: nil,
            familyName: nil
        )
    }

    private func handleAppleIDCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        do {
            // Fetch CloudKit user identity
            try await fetchCloudKitUserIdentity()

            // Update user with Apple ID information
            if let currentUser = currentUser {
                let updatedUser = AuthenticatedUser(
                    id: currentUser.id,
                    appleUserID: credential.user,
                    email: credential.email,
                    displayName: [credential.fullName?.givenName, credential.fullName?.familyName]
                        .compactMap { $0 }
                        .joined(separator: " "),
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )

                self.currentUser = updatedUser
            }
        } catch {
            authenticationState = .error(.failed(error))
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            await self.handleAppleIDCredential(credential)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { [weak self] in
            guard let self = self else { return }

            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                await self.updateAuthenticationState(.error(.cancelled))
            } else {
                await self.updateAuthenticationState(.error(.failed(error)))
            }
        }
    }

    // Helper to update state from nonisolated context
    private func updateAuthenticationState(_ newState: AuthenticationState) async {
        authenticationState = newState
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    @MainActor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window found for presenting Sign in with Apple")
        }
        return window
    }
}
