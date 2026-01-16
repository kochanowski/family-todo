import CloudKit
import Combine
import Foundation
import SwiftUI

/// Global user session manager that coordinates authentication state
/// and user-specific data across the application
@MainActor
final class UserSession: ObservableObject {
    // MARK: - Singleton

    static let shared = UserSession()

    // MARK: - Published Properties

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUserID: String?
    @Published private(set) var currentHouseholdID: UUID?
    @Published private(set) var user: AuthenticationService.AuthenticatedUser?

    // MARK: - Dependencies

    let authService: AuthenticationService
    private let cloudKitManager: CloudKitManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        self.authService = AuthenticationService()
        self.cloudKitManager = CloudKitManager()

        // Observe authentication state changes
        setupAuthObserver()
    }

    // MARK: - Public Methods

    /// Initiates the authentication flow
    func signIn() {
        authService.signInWithApple()
    }

    /// Signs out the current user
    func signOut() {
        authService.signOut()
        clearSession()
    }

    /// Checks CloudKit availability and attempts to restore session
    func checkAuthenticationStatus() async {
        await authService.checkCloudKitStatus()
    }

    /// Sets the current household for the user
    func setCurrentHousehold(_ householdID: UUID) {
        self.currentHouseholdID = householdID
        UserDefaults.standard.set(householdID.uuidString, forKey: "currentHouseholdID")
    }

    /// Clears the current household selection
    func clearCurrentHousehold() {
        self.currentHouseholdID = nil
        UserDefaults.standard.removeObject(forKey: "currentHouseholdID")
    }

    // MARK: - Private Methods

    private func setupAuthObserver() {
        // Observe authentication service state changes using Combine
        authService.objectWillChange
            .sink { [weak self] _ in
                _Concurrency.Task { [weak self] in
                    await self?.handleAuthStateChange()
                }
            }
            .store(in: &cancellables)
    }

    private func handleAuthStateChange() async {
        switch authService.authenticationState {
        case .authenticated(let userID):
            isAuthenticated = true
            currentUserID = userID
            user = authService.currentUser

            // Restore household selection if exists
            restoreHouseholdSelection()

        case .unauthenticated, .error:
            clearSession()

        case .authenticating:
            // Do nothing, wait for final state
            break
        }
    }

    private func clearSession() {
        isAuthenticated = false
        currentUserID = nil
        currentHouseholdID = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: "currentHouseholdID")
    }

    private func restoreHouseholdSelection() {
        if let householdIDString = UserDefaults.standard.string(forKey: "currentHouseholdID"),
           let householdID = UUID(uuidString: householdIDString) {
            self.currentHouseholdID = householdID
        }
    }
}
