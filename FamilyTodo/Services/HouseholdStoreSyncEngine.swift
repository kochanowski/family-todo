import CloudKit
import Foundation

@MainActor
final class HouseholdStoreSyncEngine: HouseholdSyncEngine {
    private unowned let store: HouseholdStore
    private let userIdProvider: @MainActor () -> String?
    private let preferredHouseholdIdProvider: @MainActor () -> UUID?

    init(
        store: HouseholdStore,
        userIdProvider: @escaping @MainActor () -> String?,
        preferredHouseholdIdProvider: @escaping @MainActor () -> UUID?
    ) {
        self.store = store
        self.userIdProvider = userIdProvider
        self.preferredHouseholdIdProvider = preferredHouseholdIdProvider
    }

    func runSync(for reason: HouseholdSyncReason) async -> HouseholdSyncPassResult {
        let context: RemoteCloudChangeContext = switch reason {
        case let .remotePush(remoteContext):
            remoteCloudChangeContext(from: remoteContext)
        default:
            .unknown
        }

        return await store.runRemoteSyncPass(
            userId: userIdProvider(),
            preferredHouseholdId: preferredHouseholdIdProvider(),
            reason: reason,
            context: context
        )
    }

    private func remoteCloudChangeContext(
        from context: HouseholdSyncRemoteContext
    ) -> RemoteCloudChangeContext {
        let scope: CKDatabase.Scope? = switch context {
        case .sharedDatabase:
            .shared
        case .privateDatabase:
            .private
        case .unknown:
            nil
        }

        return RemoteCloudChangeContext(
            databaseScope: scope,
            notificationType: .database,
            receivedAt: Date()
        )
    }
}
