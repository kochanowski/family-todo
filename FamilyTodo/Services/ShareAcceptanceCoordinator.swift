import CloudKit
import Foundation

@MainActor
final class ShareAcceptanceCoordinator: ObservableObject {
    enum PendingInviteSource: String {
        case systemMetadata
        case onOpenURL
        case manual
    }

    private enum StorageKeys {
        static let pendingInviteCode = "ShareAcceptanceCoordinator.pendingInviteCode"
        static let pendingInviteSource = "ShareAcceptanceCoordinator.pendingInviteSource"
        static let pendingInviteTimestamp = "ShareAcceptanceCoordinator.pendingInviteTimestamp"
    }

    @Published private(set) var pendingMetadata: CKShare.Metadata?
    @Published private(set) var pendingInviteCode: String?
    @Published private(set) var pendingSource: PendingInviteSource?
    @Published private(set) var pendingTimestampISO8601: String?
    @Published private(set) var isProcessing = false
    @Published var lastErrorMessage: String?

    private let userDefaults: UserDefaults
    private let timestampFormatter = ISO8601DateFormatter()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        restorePending()
    }

    func enqueue(metadata: CKShare.Metadata) {
        pendingInviteCode = nil
        pendingMetadata = metadata
        lastErrorMessage = nil
        markPending(source: .systemMetadata, inviteCode: nil)
    }

    func enqueue(inviteURL: URL) {
        enqueue(rawInviteCode: inviteURL.absoluteString, source: .onOpenURL)
    }

    func enqueue(rawInviteCode: String) {
        enqueue(rawInviteCode: rawInviteCode, source: .manual)
    }

    func processPendingIfPossible(
        userSession: UserSession,
        householdStore: HouseholdStore,
        onboardingState: OnboardingState
    ) async {
        guard !isProcessing else { return }
        guard onboardingState.currentState == .mainApp else { return }
        guard userSession.hasActiveSession,
              userSession.syncMode == .cloud,
              let userId = userSession.userId,
              let displayName = userSession.confirmedMembershipDisplayName
        else {
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

    func restorePending() {
        guard
            let storedInviteCode = userDefaults.string(forKey: StorageKeys.pendingInviteCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !storedInviteCode.isEmpty
        else {
            return
        }

        pendingInviteCode = storedInviteCode
        if let storedSourceRaw = userDefaults.string(forKey: StorageKeys.pendingInviteSource),
           let storedSource = PendingInviteSource(rawValue: storedSourceRaw)
        {
            pendingSource = storedSource
        }
        pendingTimestampISO8601 = userDefaults.string(forKey: StorageKeys.pendingInviteTimestamp)
    }

    func clearPendingPersistent() {
        userDefaults.removeObject(forKey: StorageKeys.pendingInviteCode)
        userDefaults.removeObject(forKey: StorageKeys.pendingInviteSource)
        userDefaults.removeObject(forKey: StorageKeys.pendingInviteTimestamp)
    }

    func resetForDevelopment() {
        pendingMetadata = nil
        pendingInviteCode = nil
        pendingSource = nil
        pendingTimestampISO8601 = nil
        lastErrorMessage = nil
        clearPendingPersistent()
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
            clearPendingState()
            lastErrorMessage = nil

            if let household = householdStore.currentHousehold {
                userSession.setCurrentHousehold(household.id)
                await NotificationService.shared.requestCollaborationAuthorizationIfNeeded()
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
                withInviteInput: inviteCode,
                userId: userId,
                displayName: displayName
            )
            clearPendingState()
            lastErrorMessage = nil

            if let household = householdStore.currentHousehold {
                userSession.setCurrentHousehold(household.id)
                await NotificationService.shared.requestCollaborationAuthorizationIfNeeded()
                onboardingState.completeHouseholdSetup(withHousehold: true)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func enqueue(rawInviteCode: String, source: PendingInviteSource) {
        let trimmedInviteCode = rawInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInviteCode.isEmpty else { return }

        let normalizedInviteCode =
            (try? InviteInputNormalizer.normalize(trimmedInviteCode)) ?? trimmedInviteCode

        pendingMetadata = nil
        pendingInviteCode = normalizedInviteCode
        lastErrorMessage = nil
        markPending(source: source, inviteCode: normalizedInviteCode)
    }

    private func markPending(source: PendingInviteSource, inviteCode: String?) {
        let timestamp = timestampFormatter.string(from: Date())
        pendingSource = source
        pendingTimestampISO8601 = timestamp

        userDefaults.set(source.rawValue, forKey: StorageKeys.pendingInviteSource)
        userDefaults.set(timestamp, forKey: StorageKeys.pendingInviteTimestamp)

        guard let inviteCode,
              !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            userDefaults.removeObject(forKey: StorageKeys.pendingInviteCode)
            return
        }

        userDefaults.set(inviteCode, forKey: StorageKeys.pendingInviteCode)
    }

    private func clearPendingState() {
        pendingMetadata = nil
        pendingInviteCode = nil
        pendingSource = nil
        pendingTimestampISO8601 = nil
        clearPendingPersistent()
    }
}
