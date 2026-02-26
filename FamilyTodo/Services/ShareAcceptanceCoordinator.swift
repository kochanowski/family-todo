import CloudKit
import Foundation

@MainActor
final class ShareAcceptanceCoordinator: ObservableObject {
    @Published private(set) var pendingMetadata: CKShare.Metadata?
    @Published private(set) var pendingInviteCode: String?
    @Published private(set) var isProcessing = false
    @Published var lastErrorMessage: String?

    func enqueue(metadata: CKShare.Metadata) {
        pendingMetadata = metadata
    }

    func enqueue(inviteURL: URL) {
        pendingInviteCode = inviteURL.absoluteString
    }

    func enqueue(rawInviteCode: String) {
        pendingInviteCode = rawInviteCode
    }

    func processPendingIfPossible(
        userSession: UserSession,
        householdStore: HouseholdStore,
        onboardingState: OnboardingState
    ) async {
        guard !isProcessing else { return }
        guard userSession.hasActiveSession,
              userSession.syncMode == .cloud,
              let userId = userSession.userId
        else {
            return
        }

        guard let displayName = userSession.displayName,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            lastErrorMessage = "Set your display name before joining a household."
            return
        }

        if let metadata = pendingMetadata {
            await processMetadata(
                metadata,
                userId: userId,
                displayName: displayName,
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState
            )
            return
        }

        if let pendingInviteCode {
            await processInviteCode(
                pendingInviteCode,
                userId: userId,
                displayName: displayName,
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState
            )
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func processMetadata(
        _ metadata: CKShare.Metadata,
        userId: String,
        displayName: String,
        userSession: UserSession,
        householdStore: HouseholdStore,
        onboardingState: OnboardingState
    ) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            householdStore.setSyncMode(.cloud)
            try await householdStore.joinHousehold(
                metadata: metadata,
                userId: userId,
                displayName: displayName
            )
            pendingMetadata = nil
            lastErrorMessage = nil

            if let household = householdStore.currentHousehold {
                userSession.setCurrentHousehold(household.id)
                onboardingState.completeHouseholdSetup(withHousehold: true)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func processInviteCode(
        _ inviteCode: String,
        userId: String,
        displayName: String,
        userSession: UserSession,
        householdStore: HouseholdStore,
        onboardingState: OnboardingState
    ) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            householdStore.setSyncMode(.cloud)
            try await householdStore.joinHousehold(
                inviteCode: inviteCode,
                userId: userId,
                displayName: displayName
            )
            pendingInviteCode = nil
            lastErrorMessage = nil

            if let household = householdStore.currentHousehold {
                userSession.setCurrentHousehold(household.id)
                onboardingState.completeHouseholdSetup(withHousehold: true)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
