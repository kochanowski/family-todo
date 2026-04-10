import Foundation

@MainActor
enum StartupLaunchDirector {
    static func primeLocalLaunchRoute(
        userSession: UserSession,
        householdStore: HouseholdStore,
        onboardingState: OnboardingState
    ) {
        guard onboardingState.currentState != .onboarding else { return }
        guard userSession.hasActiveSession else { return }

        householdStore.setSyncMode(userSession.syncMode)

        let startupUserId: String? = if userSession.isGuest {
            userSession.userId ?? "local-guest"
        } else {
            userSession.userId
        }

        guard let startupUserId else { return }

        if let restoredHousehold = householdStore.resolveStartupHouseholdLocally(
            userId: startupUserId,
            preferredHouseholdId: userSession.currentHouseholdID
        ), userSession.currentHouseholdID != restoredHousehold.id {
            userSession.setCurrentHousehold(restoredHousehold.id)
        }

        if let householdId = userSession.currentHouseholdID,
           householdStore.isRecoverySuppressed(for: householdId),
           !householdStore.hasPendingJoinProtection(for: householdId, userId: userSession.userId)
        {
            householdStore.clearCurrentHousehold()
            userSession.clearCurrentHousehold()
            return
        }

        guard userSession.currentHouseholdID != nil || householdStore.currentHousehold != nil else {
            return
        }

        if !userSession.isGuest,
           userSession.needsDisplayNamePrompt,
           let userId = userSession.userId,
           let restoredDisplayName = householdStore.resolveMembershipDisplayNameLocally(
               userId: userId,
               preferredHouseholdId: userSession.currentHouseholdID
           )
        {
            userSession.applyProfileUpdate(displayName: restoredDisplayName)
        }

        guard !userSession.needsDisplayNamePrompt else { return }

        onboardingState.restoreMainAppForRecoveredSession(
            syncMethod: userSession.isGuest ? .local : .iCloud
        )
    }
}
