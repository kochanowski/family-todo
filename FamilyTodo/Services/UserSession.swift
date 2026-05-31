import Combine
import Foundation
import PostHog

enum SyncMode: Equatable {
    case cloud
    case localOnly
}

enum SessionMode: String, Equatable {
    case signedOut
    case signedIn
    case guest
}

enum DisplayNameValidationError: LocalizedError, Equatable {
    case empty
    case tooShort
    case tooLong
    case invalidCharacters

    var errorDescription: String? {
        switch self {
        case .empty:
            "Display name cannot be empty."
        case .tooShort:
            "Display name must have at least 2 characters."
        case .tooLong:
            "Display name must be at most 24 characters."
        case .invalidCharacters:
            "Display name contains unsupported characters."
        }
    }
}

enum DisplayNameValidator {
    static let minLength = 2
    static let maxLength = 24

    private static let allowedCharacters = CharacterSet.letters
        .union(.decimalDigits)
        .union(CharacterSet(charactersIn: " ._-'"))

    static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func normalizedKey(_ raw: String) -> String {
        normalize(raw)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func validate(_ raw: String) throws -> String {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { throw DisplayNameValidationError.empty }
        guard normalized.count >= minLength else { throw DisplayNameValidationError.tooShort }
        guard normalized.count <= maxLength else { throw DisplayNameValidationError.tooLong }
        guard normalized.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw DisplayNameValidationError.invalidCharacters
        }
        return normalized
    }
}

@MainActor
protocol AuthenticationServiceType: ObservableObject {
    var authenticationState: AuthenticationService.AuthenticationState { get }
    var currentUser: AuthenticationService.AuthenticatedUser? { get }
    var latestDiagnostics: AuthDiagnosticsSnapshot? { get }

    func signInWithApple()
    func signOut()
    func checkCloudKitStatus() async
    func diagnosticsReportJSON() -> String
    func clearDiagnosticsHistory()

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
    @Published private(set) var preferredDisplayName: String?
    @Published private(set) var hasConfirmedDisplayName = false

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
        if let preferredDisplayName,
           !preferredDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return preferredDisplayName
        }
        return user?.displayName ?? user?.givenName
    }

    var confirmedMembershipDisplayName: String? {
        if isGuest {
            return try? DisplayNameValidator.validate(guestDisplayName ?? "Guest")
        }

        guard hasConfirmedDisplayName,
              let preferredDisplayName,
              let validated = try? DisplayNameValidator.validate(preferredDisplayName)
        else {
            return nil
        }

        return validated
    }

    var suggestedDisplayNameForPrompt: String {
        if let preferredDisplayName,
           let validated = try? DisplayNameValidator.validate(preferredDisplayName)
        {
            return validated
        }

        if let authDisplayName = user?.displayName,
           let validated = try? DisplayNameValidator.validate(authDisplayName)
        {
            return validated
        }

        if let givenName = user?.givenName,
           let validated = try? DisplayNameValidator.validate(givenName)
        {
            return validated
        }

        return ""
    }

    var needsDisplayNamePrompt: Bool {
        isAuthenticated && confirmedMembershipDisplayName == nil
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
        restoreSignedInSessionIfNeeded()
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
            AppAnalytics.capture("user_signed_out", sessionMode: .guest)
            PostHogSDK.shared.reset()
            endGuestSession()
            return
        }
        AppAnalytics.capture("user_signed_out", sessionMode: .signedIn)
        PostHogSDK.shared.reset()
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

        clearSignedInSessionDefaults()
        userDefaults.set(true, forKey: StorageKeys.guestSessionEnabled)
        userDefaults.set(guestId, forKey: StorageKeys.guestUserId)
        userDefaults.set(displayName, forKey: StorageKeys.guestDisplayName)

        sessionMode = .guest
        currentUserID = guestId
        guestDisplayName = displayName
        user = nil
        preferredDisplayName = nil
        hasConfirmedDisplayName = true

        AppAnalytics.identifyUser(
            guestId,
            sessionMode: .guest,
            displayName: displayName,
            hasConfirmedDisplayName: true
        )
        AppAnalytics.capture(
            "guest_session_started",
            properties: ["display_name": displayName],
            sessionMode: .guest
        )

        restoreHouseholdSelection()
    }

    func confirmDisplayName(_ displayName: String) {
        guard let trimmed = try? DisplayNameValidator.validate(displayName) else { return }

        if isGuest {
            guestDisplayName = trimmed
            userDefaults.set(trimmed, forKey: StorageKeys.guestDisplayName)
            hasConfirmedDisplayName = true
            return
        }

        guard let userId = currentUserID else { return }
        var values = userDefaults.dictionary(forKey: StorageKeys.preferredDisplayNameByUserId) as? [String: String] ?? [:]
        values[userId] = trimmed
        userDefaults.set(values, forKey: StorageKeys.preferredDisplayNameByUserId)
        preferredDisplayName = trimmed
        hasConfirmedDisplayName = true
    }

    /// Applies a profile name update to the live session immediately.
    /// This keeps all observing views in sync right after successful CloudKit writes.
    func applyProfileUpdate(displayName: String) {
        guard let trimmed = try? DisplayNameValidator.validate(displayName) else { return }

        if isGuest {
            guestDisplayName = trimmed
            userDefaults.set(trimmed, forKey: StorageKeys.guestDisplayName)
            hasConfirmedDisplayName = true
            return
        }

        guard let userId = currentUserID else { return }
        var values = userDefaults.dictionary(forKey: StorageKeys.preferredDisplayNameByUserId)
            as? [String: String] ?? [:]
        values[userId] = trimmed
        userDefaults.set(values, forKey: StorageKeys.preferredDisplayNameByUserId)
        preferredDisplayName = trimmed
        hasConfirmedDisplayName = true

        if let existingUser = user {
            user = AuthenticationService.AuthenticatedUser(
                id: existingUser.id,
                appleUserID: existingUser.appleUserID,
                email: existingUser.email,
                displayName: trimmed,
                givenName: existingUser.givenName,
                familyName: existingUser.familyName
            )
        }
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
            persistSignedInSession(userID: userID)
            restorePreferredDisplayName(for: userID)

            let userDisplayName = authService.currentUser?.displayName ?? authService.currentUser?.givenName
            AppAnalytics.identifyUser(
                userID,
                sessionMode: .signedIn,
                displayName: userDisplayName,
                hasConfirmedDisplayName: hasConfirmedDisplayName
            )
            AppAnalytics.capture("user_signed_in", sessionMode: .signedIn)
            AppAnalytics.activationMilestone(.signedIn, sessionMode: .signedIn)

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
        preferredDisplayName = nil
        hasConfirmedDisplayName = false
        userDefaults.removeObject(forKey: StorageKeys.currentHouseholdId)
        clearSignedInSessionDefaults()
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
        preferredDisplayName = nil
        hasConfirmedDisplayName = true

        restoreHouseholdSelection()
    }

    private func restoreSignedInSessionIfNeeded() {
        guard !isGuest else { return }
        guard userDefaults.bool(forKey: StorageKeys.signedInSessionEnabled) else { return }
        guard let userId = userDefaults.string(forKey: StorageKeys.lastSignedInUserId),
              !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            clearSignedInSessionDefaults()
            return
        }

        sessionMode = .signedIn
        currentUserID = userId
        user = authService.currentUser
        guestDisplayName = nil
        restorePreferredDisplayName(for: userId)
        restoreHouseholdSelection()
    }

    private func restorePreferredDisplayName(for userId: String) {
        let values = userDefaults.dictionary(forKey: StorageKeys.preferredDisplayNameByUserId) as? [String: String] ?? [:]
        if let name = values[userId],
           let validated = try? DisplayNameValidator.validate(name)
        {
            preferredDisplayName = validated
            hasConfirmedDisplayName = true
        } else {
            preferredDisplayName = nil
            hasConfirmedDisplayName = false
        }
    }

    private func clearGuestSessionDefaults() {
        userDefaults.removeObject(forKey: StorageKeys.guestSessionEnabled)
        userDefaults.removeObject(forKey: StorageKeys.guestUserId)
        userDefaults.removeObject(forKey: StorageKeys.guestDisplayName)
    }

    private func persistSignedInSession(userID: String) {
        userDefaults.set(true, forKey: StorageKeys.signedInSessionEnabled)
        userDefaults.set(userID, forKey: StorageKeys.lastSignedInUserId)
    }

    private func clearSignedInSessionDefaults() {
        userDefaults.removeObject(forKey: StorageKeys.signedInSessionEnabled)
        userDefaults.removeObject(forKey: StorageKeys.lastSignedInUserId)
    }

    private enum StorageKeys {
        static let currentHouseholdId = "currentHouseholdID"
        static let guestSessionEnabled = "guestSessionEnabled"
        static let guestUserId = "guestUserId"
        static let guestDisplayName = "guestDisplayName"
        static let signedInSessionEnabled = "signedInSessionEnabled"
        static let lastSignedInUserId = "lastSignedInUserId"
        static let preferredDisplayNameByUserId = "preferredDisplayNameByUserId"
    }
}
