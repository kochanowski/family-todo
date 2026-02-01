import SwiftUI

// MARK: - Launch State

enum LaunchState: String {
    case onboarding
    case syncChoice
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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("syncMethod") private var syncMethodRaw = SyncMethod.none.rawValue
    @AppStorage("householdStatus") private var householdStatusRaw = HouseholdStatus.none.rawValue
    @AppStorage("lastLaunchState") private var lastLaunchStateRaw = LaunchState.onboarding.rawValue

    @Published var currentState: LaunchState = .onboarding

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
        determineInitialState()
    }

    // MARK: - State Determination

    private func determineInitialState() {
        if hasCompletedOnboarding {
            currentState = .mainApp
        } else {
            // Resume from last state if user quit mid-flow
            let lastState = LaunchState(rawValue: lastLaunchStateRaw) ?? .onboarding
            switch lastState {
            case .householdSetup:
                // User quit during household setup, resume there
                currentState = .householdSetup
            case .syncChoice:
                currentState = .syncChoice
            default:
                currentState = .onboarding
            }
        }
    }

    // MARK: - Transitions

    func completeOnboarding() {
        HapticManager.selection()
        currentState = .syncChoice
        lastLaunchStateRaw = LaunchState.syncChoice.rawValue
    }

    func selectSyncMethod(_ method: SyncMethod) {
        HapticManager.mediumTap()
        syncMethod = method
        currentState = .householdSetup
        lastLaunchStateRaw = LaunchState.householdSetup.rawValue
    }

    func completeHouseholdSetup(withHousehold: Bool) {
        HapticManager.success()
        householdStatus = withHousehold ? .active : .none
        hasCompletedOnboarding = true
        currentState = .mainApp
        lastLaunchStateRaw = LaunchState.mainApp.rawValue
    }

    func skipHouseholdSetup() {
        HapticManager.lightTap()
        householdStatus = .none
        hasCompletedOnboarding = true
        currentState = .mainApp
        lastLaunchStateRaw = LaunchState.mainApp.rawValue
    }

    // MARK: - Household Management (for empty state actions)

    func openHouseholdSetup() {
        currentState = .householdSetup
    }

    func activateHousehold() {
        householdStatus = .active
        objectWillChange.send()
    }

    // MARK: - Debug

    #if DEBUG
        func resetOnboarding() {
            hasCompletedOnboarding = false
            syncMethodRaw = SyncMethod.none.rawValue
            householdStatusRaw = HouseholdStatus.none.rawValue
            lastLaunchStateRaw = LaunchState.onboarding.rawValue
            currentState = .onboarding
        }
    #endif
}
