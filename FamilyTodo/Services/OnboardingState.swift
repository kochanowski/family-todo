import SwiftUI

// MARK: - Launch State

enum LaunchState: String {
    case onboarding
    case auth
    case householdSetup
    case mainApp
}

// MARK: - Sync Method

enum SyncMethod: String {
    case iCloud
    case local
    case none
}

// MARK: - Household Status

enum HouseholdStatus: String {
    case none
    case active
}

// MARK: - Onboarding State

@MainActor
final class OnboardingState: ObservableObject {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var legacyHasCompletedOnboarding = false
    @AppStorage("syncMethod") private var syncMethodRaw = SyncMethod.none.rawValue
    @AppStorage("householdStatus") private var householdStatusRaw = HouseholdStatus.none.rawValue
    @AppStorage("lastLaunchState") private var lastLaunchStateRaw = LaunchState.onboarding.rawValue
    @AppStorage("shouldPresentPostSetupPaywall") private var shouldPresentPostSetupPaywallRaw = false

    @Published var currentState: LaunchState = .onboarding

    var shouldPresentPostSetupPaywall: Bool {
        shouldPresentPostSetupPaywallRaw
    }

    var syncMethod: SyncMethod {
        get { SyncMethod(rawValue: syncMethodRaw) ?? .none }
        set {
            syncMethodRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var householdStatus: HouseholdStatus {
        get { HouseholdStatus(rawValue: householdStatusRaw) ?? .none }
        set {
            householdStatusRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    init() {
        migrateLegacyIfNeeded()
        determineInitialState()
    }

    // MARK: - State Determination

    private func migrateLegacyIfNeeded() {
        if !hasSeenOnboarding, legacyHasCompletedOnboarding {
            hasSeenOnboarding = true
            if lastLaunchStateRaw == "syncChoice" {
                lastLaunchStateRaw = LaunchState.auth.rawValue
            }
        }
    }

    private func determineInitialState() {
        guard hasSeenOnboarding else {
            currentState = .onboarding
            return
        }

        switch lastLaunchStateRaw {
        case LaunchState.onboarding.rawValue:
            currentState = .auth
        case LaunchState.auth.rawValue:
            currentState = .auth
        case LaunchState.householdSetup.rawValue:
            currentState = syncMethod == .local ? .householdSetup : .auth
        case LaunchState.mainApp.rawValue:
            currentState = .mainApp
        case "syncChoice":
            currentState = .auth
        default:
            currentState = .auth
        }
    }

    private func persistLaunchState(_ state: LaunchState) {
        // Household setup is a runtime destination for cloud users.
        // On cold launch we always re-run recovery before deciding they truly need setup.
        if state == .householdSetup, syncMethod != .local {
            lastLaunchStateRaw = LaunchState.auth.rawValue
            return
        }

        lastLaunchStateRaw = state.rawValue
    }

    // MARK: - Transitions

    func completeOnboarding() {
        HapticManager.selection()
        hasSeenOnboarding = true
        currentState = .auth
        lastLaunchStateRaw = LaunchState.auth.rawValue
    }

    func completeAuth(syncMethod method: SyncMethod, isGuest: Bool, hasHousehold: Bool) {
        HapticManager.mediumTap()
        hasSeenOnboarding = true
        syncMethod = method
        householdStatus = hasHousehold ? .active : .none

        if isGuest {
            currentState = .mainApp
        } else {
            currentState = hasHousehold ? .mainApp : .householdSetup
        }
        persistLaunchState(currentState)
    }

    func completeHouseholdSetup(withHousehold: Bool) {
        HapticManager.success()
        hasSeenOnboarding = true
        householdStatus = withHousehold ? .active : .none
        if withHousehold {
            shouldPresentPostSetupPaywallRaw = true
        }
        currentState = .mainApp
        lastLaunchStateRaw = LaunchState.mainApp.rawValue
    }

    func consumePostSetupPaywall() {
        guard shouldPresentPostSetupPaywallRaw else { return }
        shouldPresentPostSetupPaywallRaw = false
        objectWillChange.send()
    }

    func restoreMainAppForRecoveredSession(syncMethod method: SyncMethod) {
        hasSeenOnboarding = true
        syncMethod = method
        householdStatus = .active
        currentState = .mainApp
        persistLaunchState(.mainApp)
    }

    func skipHouseholdSetup() {
        HapticManager.lightTap()
        hasSeenOnboarding = true
        householdStatus = .none
        currentState = .mainApp
        lastLaunchStateRaw = LaunchState.mainApp.rawValue
    }

    // MARK: - Household Management (for empty state actions)

    func openHouseholdSetup() {
        hasSeenOnboarding = true
        currentState = .householdSetup
        persistLaunchState(.householdSetup)
    }

    func openAuth() {
        currentState = .auth
        lastLaunchStateRaw = LaunchState.auth.rawValue
    }

    func activateHousehold() {
        householdStatus = .active
        objectWillChange.send()
    }

    // MARK: - Legacy Compatibility

    /// Temporary compatibility method for old SyncSelectionView call sites.
    func selectSyncMethod(_ method: SyncMethod) {
        completeAuth(syncMethod: method, isGuest: method == .local, hasHousehold: false)
    }

    func resetOnboarding() {
        hasSeenOnboarding = false
        legacyHasCompletedOnboarding = false
        syncMethodRaw = SyncMethod.none.rawValue
        householdStatusRaw = HouseholdStatus.none.rawValue
        shouldPresentPostSetupPaywallRaw = false
        lastLaunchStateRaw = LaunchState.onboarding.rawValue
        currentState = .onboarding
    }
}
