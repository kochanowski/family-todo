import Combine
import Foundation

enum SyncMode: Equatable {
    case cloud
    case localOnly
}

enum SessionMode: String, Equatable {
    case signedOut
    case signedIn
    case guest
}

@MainActor
protocol AuthenticationServiceType: ObservableObject {
    var authenticationState: AuthenticationService.AuthenticationState { get }
    var currentUser: AuthenticationService.AuthenticatedUser? { get }

    func signInWithApple()
    func signOut()
    func checkCloudKitStatus() async

    /// Provide type-erased publisher for observation
    func getChangePublisher() -> AnyPublisher<Void, Never>
}

extension AuthenticationService: AuthenticationServiceType {
    func getChangePublisher() -> AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}

/// Global user session manager that coordinates authentication state
/// and user-specific data across the application
@MainActor
final class UserSession: ObservableObject {
    // MARK: - Singleton

    static let shared = UserSession()

    // MARK: - Published Properties

    @Published private(set) var sessionMode: SessionMode = .signedOut
    @Published private(set) var currentUserID: String?
    @Published private(set) var currentHouseholdID: UUID?
    @Published private(set) var user: AuthenticationService.AuthenticatedUser?
    private var guestDisplayName: String?

    // MARK: - Computed Properties

    /// Convenience accessor for user ID
    var userId: String? {
        currentUserID
    }

    /// True when the user is signed in with iCloud/CloudKit
    var isAuthenticated: Bool {
        sessionMode == .signedIn
    }

    /// True when the user can access the app (signed in or guest)
    var hasActiveSession: Bool {
        sessionMode != .signedOut
    }

    /// True when the session is local-only (guest mode)
    var isGuest: Bool {
        sessionMode == .guest
    }

    var syncMode: SyncMode {
        isGuest ? .localOnly : .cloud
    }

    /// Convenience accessor for display name
    var displayName: String? {
        if isGuest {
            return guestDisplayName ?? "Guest"
        }
        return user?.displayName ?? user?.givenName
    }

    // MARK: - Dependencies

    let authService: any AuthenticationServiceType
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private let authServicePublisher: AnyPublisher<Void, Never>

    // MARK: - Initialization

    init(
        authService: (any AuthenticationServiceType)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let service = authService ?? AuthenticationService()
        self.authService = service
        self.userDefaults = userDefaults

        // Get type-erased publisher from service
        authServicePublisher = service.getChangePublisher()

        // Observe authentication state changes
        setupAuthObserver()
        restoreGuestSessionIfNeeded()
    }

    // MARK: - Public Methods

    /// Initiates the authentication flow
    func signIn() {
        if isGuest {
            endGuestSession()
        }
        authService.signInWithApple()
    }

    /// Signs out the current user
    func signOut() {
        if isGuest {
            endGuestSession()
            return
        }
        authService.signOut()
        clearSession()
    }

    /// Checks CloudKit availability and attempts to restore session
    func checkAuthenticationStatus() async {
        guard !isGuest else { return }
        await authService.checkCloudKitStatus()
    }

    /// Starts a local-only guest session
    func startGuestSession(displayName: String = "Guest") {
        let guestId = userDefaults.string(forKey: StorageKeys.guestUserId) ?? UUID().uuidString

        userDefaults.set(true, forKey: StorageKeys.guestSessionEnabled)
        userDefaults.set(guestId, forKey: StorageKeys.guestUserId)
        userDefaults.set(displayName, forKey: StorageKeys.guestDisplayName)

        sessionMode = .guest
        currentUserID = guestId
        guestDisplayName = displayName
        user = nil

        restoreHouseholdSelection()
    }

    /// Ends the guest session and returns to signed-out state
    func endGuestSession() {
        clearGuestSessionDefaults()
        clearSession()
    }

    /// Sets the current household for the user
    func setCurrentHousehold(_ householdID: UUID) {
        currentHouseholdID = householdID
        userDefaults.set(householdID.uuidString, forKey: StorageKeys.currentHouseholdId)
    }

    /// Clears the current household selection
    func clearCurrentHousehold() {
        currentHouseholdID = nil
        userDefaults.removeObject(forKey: StorageKeys.currentHouseholdId)
    }

    // MARK: - Private Methods

    private func setupAuthObserver() {
        // Observe authentication service state changes using Combine
        authServicePublisher
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                _Concurrency.Task { [weak self] in
                    await self?.handleAuthStateChange()
                }
            }
            .store(in: &cancellables)
    }

    private func handleAuthStateChange() async {
        switch authService.authenticationState {
        case let .authenticated(userID):
            sessionMode = .signedIn
            currentUserID = userID
            user = authService.currentUser
            guestDisplayName = nil
            clearGuestSessionDefaults()

            // Restore household selection if exists
            restoreHouseholdSelection()

        case .unauthenticated, .error:
            if !isGuest {
                clearSession()
            }

        case .authenticating:
            // Do nothing, wait for final state
            break
        }
    }

    private func clearSession() {
        sessionMode = .signedOut
        currentUserID = nil
        currentHouseholdID = nil
        user = nil
        guestDisplayName = nil
        userDefaults.removeObject(forKey: StorageKeys.currentHouseholdId)
    }

    private func restoreHouseholdSelection() {
        if let householdIDString = userDefaults.string(forKey: StorageKeys.currentHouseholdId),
           let householdID = UUID(uuidString: householdIDString)
        {
            currentHouseholdID = householdID
        }
    }

    private func restoreGuestSessionIfNeeded() {
        guard userDefaults.bool(forKey: StorageKeys.guestSessionEnabled) else { return }

        let guestId = userDefaults.string(forKey: StorageKeys.guestUserId) ?? UUID().uuidString
        let guestName = userDefaults.string(forKey: StorageKeys.guestDisplayName) ?? "Guest"

        userDefaults.set(guestId, forKey: StorageKeys.guestUserId)
        userDefaults.set(guestName, forKey: StorageKeys.guestDisplayName)

        sessionMode = .guest
        currentUserID = guestId
        guestDisplayName = guestName
        user = nil

        restoreHouseholdSelection()
    }

    private func clearGuestSessionDefaults() {
        userDefaults.removeObject(forKey: StorageKeys.guestSessionEnabled)
        userDefaults.removeObject(forKey: StorageKeys.guestUserId)
        userDefaults.removeObject(forKey: StorageKeys.guestDisplayName)
    }

    private enum StorageKeys {
        static let currentHouseholdId = "currentHouseholdID"
        static let guestSessionEnabled = "guestSessionEnabled"
        static let guestUserId = "guestUserId"
        static let guestDisplayName = "guestDisplayName"
    }
}
