import CloudKit
import Combine
import SwiftData
import SwiftUI
import UIKit

struct AcceptedShareContext {
    let household: Household
    let householdId: UUID
    let zoneID: CKRecordZone.ID
    let shareURL: URL?
}

struct RemoteShoppingItemState: Equatable {
    let title: String
    let isBought: Bool
    let boughtAt: Date?
    let restockCount: Int
    let sortOrder: Int
    let updatedAt: Date
}

struct RemoteShoppingBundleState: Equatable {
    let name: String
    let updatedAt: Date
}

struct RemoteMemberState: Equatable {
    let userId: String
    let displayName: String
    let role: Member.MemberRole
    let isActive: Bool
}

struct RemoteWorkItemState: Equatable {
    let logicalItemID: UUID
    let title: String
    let status: WorkItem.Status
    let assigneeId: UUID?
    let assigneeIds: [UUID]
    let completedAt: Date?
    let completedById: String?
    let order: Int
    let updatedAt: Date
}

struct RemoteBacklogCategoryState: Equatable {
    let title: String
    let sortOrder: Int
    let updatedAt: Date
}

struct RemoteVisibleContentSnapshot: Equatable {
    let membersByID: [UUID: RemoteMemberState]
    let shoppingItemsByID: [UUID: RemoteShoppingItemState]
    let shoppingBundlesByID: [UUID: RemoteShoppingBundleState]
    let workItemsByID: [UUID: RemoteWorkItemState]
    let backlogCategoriesByID: [UUID: RemoteBacklogCategoryState]

    init(
        membersByID: [UUID: RemoteMemberState] = [:],
        shoppingItemsByID: [UUID: RemoteShoppingItemState],
        shoppingBundlesByID: [UUID: RemoteShoppingBundleState],
        workItemsByID: [UUID: RemoteWorkItemState],
        backlogCategoriesByID: [UUID: RemoteBacklogCategoryState]
    ) {
        self.membersByID = membersByID
        self.shoppingItemsByID = shoppingItemsByID
        self.shoppingBundlesByID = shoppingBundlesByID
        self.workItemsByID = workItemsByID
        self.backlogCategoriesByID = backlogCategoriesByID
    }

    init(
        shoppingTitlesByID: [UUID: String],
        shoppingBundleIDs: Set<UUID>,
        workItemIDs: Set<UUID>,
        backlogCategoryIDs: Set<UUID>
    ) {
        self.init(
            shoppingItemsByID: Dictionary(
                uniqueKeysWithValues: shoppingTitlesByID.map { id, title in
                    (
                        id,
                        RemoteShoppingItemState(
                            title: title,
                            isBought: false,
                            boughtAt: nil,
                            restockCount: 0,
                            sortOrder: 0,
                            updatedAt: .distantPast
                        )
                    )
                }
            ),
            shoppingBundlesByID: Dictionary(
                uniqueKeysWithValues: shoppingBundleIDs.map { id in
                    (id, RemoteShoppingBundleState(name: "", updatedAt: .distantPast))
                }
            ),
            workItemsByID: Dictionary(
                uniqueKeysWithValues: workItemIDs.map { id in
                    (
                        id,
                        RemoteWorkItemState(
                            logicalItemID: id,
                            title: "",
                            status: .backlog,
                            assigneeId: nil,
                            assigneeIds: [],
                            completedAt: nil,
                            completedById: nil,
                            order: 0,
                            updatedAt: .distantPast
                        )
                    )
                }
            ),
            backlogCategoriesByID: Dictionary(
                uniqueKeysWithValues: backlogCategoryIDs.map { id in
                    (id, RemoteBacklogCategoryState(title: "", sortOrder: 0, updatedAt: .distantPast))
                }
            )
        )
    }

    var shoppingTitlesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: shoppingItemsByID.map { ($0.key, $0.value.title) })
    }

    var shoppingBundleIDs: Set<UUID> {
        Set(shoppingBundlesByID.keys)
    }

    var workItemIDs: Set<UUID> {
        Set(workItemsByID.keys)
    }

    var backlogCategoryIDs: Set<UUID> {
        Set(backlogCategoriesByID.keys)
    }

    var nextWorkItemCount: Int {
        workItemsByID.values.filter { $0.status == .next }.count
    }

    func diff(from previous: RemoteVisibleContentSnapshot) -> RemoteVisibleContentDiff {
        let addedShoppingIDs = Set(shoppingItemsByID.keys).subtracting(previous.shoppingItemsByID.keys)
        let addedShoppingTitles = addedShoppingIDs
            .compactMap { shoppingItemsByID[$0]?.title }
            .sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        let addedMemberIDs = Set(membersByID.keys).subtracting(previous.membersByID.keys)
        let removedMemberIDs = Set(previous.membersByID.keys).subtracting(membersByID.keys)
        let changedMemberIDs = Set(
            Set(membersByID.keys).intersection(previous.membersByID.keys).filter {
                membersByID[$0] != previous.membersByID[$0]
            }
        )
        let addedTaskIDs = taskIDs.subtracting(previous.taskIDs)
        let removedTaskIDs = previous.taskIDs.subtracting(taskIDs)
        let changedTaskIDs = Set(
            taskIDs.intersection(previous.taskIDs).filter { taskID in
                currentTasksByID[taskID] != previous.currentTasksByID[taskID]
            }
        )
        let addedIdeaIDs = ideaIDs.subtracting(previous.ideaIDs)
        let removedIdeaIDs = previous.ideaIDs.subtracting(ideaIDs)
        let changedIdeaIDs = Set(
            ideaIDs.intersection(previous.ideaIDs).filter { ideaID in
                currentIdeasByID[ideaID] != previous.currentIdeasByID[ideaID]
            }
        )
        let addedShoppingBundleIDs = shoppingBundleIDs.subtracting(previous.shoppingBundleIDs)
        let removedShoppingBundleIDs = previous.shoppingBundleIDs.subtracting(shoppingBundleIDs)
        let addedBacklogCategoryIDs = backlogCategoryIDs.subtracting(previous.backlogCategoryIDs)
        let removedBacklogCategoryIDs = previous.backlogCategoryIDs.subtracting(backlogCategoryIDs)

        return RemoteVisibleContentDiff(
            addedMemberIDs: addedMemberIDs,
            removedMemberIDs: removedMemberIDs,
            changedMemberIDs: changedMemberIDs,
            addedShoppingItemIDs: addedShoppingIDs,
            addedShoppingTitles: addedShoppingTitles,
            addedShoppingBundleIDs: addedShoppingBundleIDs,
            addedTaskIDs: addedTaskIDs,
            addedIdeaIDs: addedIdeaIDs,
            addedBacklogCategoryIDs: addedBacklogCategoryIDs,
            removedShoppingItemIDs: Set(previous.shoppingItemsByID.keys).subtracting(shoppingItemsByID.keys),
            removedShoppingBundleIDs: removedShoppingBundleIDs,
            removedTaskIDs: removedTaskIDs,
            removedIdeaIDs: removedIdeaIDs,
            removedBacklogCategoryIDs: removedBacklogCategoryIDs,
            changedShoppingItemIDs: Set(
                Set(shoppingItemsByID.keys).intersection(previous.shoppingItemsByID.keys).filter {
                    shoppingItemsByID[$0] != previous.shoppingItemsByID[$0]
                }
            ),
            changedShoppingBundleIDs: Set(
                Set(shoppingBundlesByID.keys).intersection(previous.shoppingBundlesByID.keys).filter {
                    shoppingBundlesByID[$0] != previous.shoppingBundlesByID[$0]
                }
            ),
            changedWorkItemIDs: Set(
                Set(workItemsByID.keys).intersection(previous.workItemsByID.keys).filter {
                    workItemsByID[$0] != previous.workItemsByID[$0]
                }
            ),
            changedTaskIDs: changedTaskIDs,
            changedIdeaIDs: changedIdeaIDs,
            changedBacklogCategoryIDs: Set(
                Set(backlogCategoriesByID.keys).intersection(previous.backlogCategoriesByID.keys).filter {
                    backlogCategoriesByID[$0] != previous.backlogCategoriesByID[$0]
                }
            )
        )
    }

    func taskContentDiff(from previous: RemoteVisibleContentSnapshot) -> RemoteTaskVisibleContentDiff {
        RemoteTaskVisibleContentDiff(
            addedTaskIDs: taskIDs.subtracting(previous.taskIDs),
            removedTaskIDs: previous.taskIDs.subtracting(taskIDs),
            changedTaskIDs: Set(
                taskIDs.intersection(previous.taskIDs).filter {
                    currentTasksByID[$0] != previous.currentTasksByID[$0]
                }
            )
        )
    }

    func ideaContentDiff(from previous: RemoteVisibleContentSnapshot) -> RemoteIdeaVisibleContentDiff {
        RemoteIdeaVisibleContentDiff(
            addedIdeaIDs: ideaIDs.subtracting(previous.ideaIDs),
            removedIdeaIDs: previous.ideaIDs.subtracting(ideaIDs),
            changedIdeaIDs: Set(
                ideaIDs.intersection(previous.ideaIDs).filter {
                    currentIdeasByID[$0] != previous.currentIdeasByID[$0]
                }
            )
        )
    }

    private var currentTasksByID: [UUID: RemoteWorkItemState] {
        workItemsByID.filter { $0.value.status != .idea }
    }

    private var currentIdeasByID: [UUID: RemoteWorkItemState] {
        workItemsByID.filter { $0.value.status == .idea }
    }

    private var taskIDs: Set<UUID> {
        Set(currentTasksByID.keys)
    }

    private var ideaIDs: Set<UUID> {
        Set(currentIdeasByID.keys)
    }
}

struct RemoteVisibleContentDiff: Equatable {
    let addedMemberIDs: Set<UUID>
    let removedMemberIDs: Set<UUID>
    let changedMemberIDs: Set<UUID>
    let addedShoppingItemIDs: Set<UUID>
    let addedShoppingTitles: [String]
    let addedShoppingBundleIDs: Set<UUID>
    let addedTaskIDs: Set<UUID>
    let addedIdeaIDs: Set<UUID>
    let addedBacklogCategoryIDs: Set<UUID>
    let removedShoppingItemIDs: Set<UUID>
    let removedShoppingBundleIDs: Set<UUID>
    let removedTaskIDs: Set<UUID>
    let removedIdeaIDs: Set<UUID>
    let removedBacklogCategoryIDs: Set<UUID>
    let changedShoppingItemIDs: Set<UUID>
    let changedShoppingBundleIDs: Set<UUID>
    let changedWorkItemIDs: Set<UUID>
    let changedTaskIDs: Set<UUID>
    let changedIdeaIDs: Set<UUID>
    let changedBacklogCategoryIDs: Set<UUID>

    var addedShoppingBundleCount: Int {
        addedShoppingBundleIDs.count
    }

    var addedWorkItemCount: Int {
        addedTaskIDs.count + addedIdeaIDs.count
    }

    var addedBacklogCategoryCount: Int {
        addedBacklogCategoryIDs.count
    }

    var removedShoppingItemCount: Int {
        removedShoppingItemIDs.count
    }

    var removedShoppingBundleCount: Int {
        removedShoppingBundleIDs.count
    }

    var removedWorkItemCount: Int {
        removedTaskIDs.count + removedIdeaIDs.count
    }

    var removedBacklogCategoryCount: Int {
        removedBacklogCategoryIDs.count
    }

    var totalAddedCount: Int {
        addedMemberIDs.count +
            addedShoppingTitles.count +
            addedShoppingBundleCount +
            addedWorkItemCount +
            addedBacklogCategoryCount
    }

    var hasAnyChange: Bool {
        !addedMemberIDs.isEmpty ||
            !removedMemberIDs.isEmpty ||
            !changedMemberIDs.isEmpty ||
            totalAddedCount > 0 ||
            removedShoppingItemCount > 0 ||
            removedShoppingBundleCount > 0 ||
            removedWorkItemCount > 0 ||
            removedBacklogCategoryCount > 0 ||
            !changedShoppingItemIDs.isEmpty ||
            !changedShoppingBundleIDs.isEmpty ||
            !changedTaskIDs.isEmpty ||
            !changedIdeaIDs.isEmpty ||
            !changedBacklogCategoryIDs.isEmpty
    }
}

struct RemoteTaskVisibleContentDiff: Equatable {
    let addedTaskIDs: Set<UUID>
    let removedTaskIDs: Set<UUID>
    let changedTaskIDs: Set<UUID>

    var addedTaskCount: Int {
        addedTaskIDs.count
    }

    var removedTaskCount: Int {
        removedTaskIDs.count
    }

    var hasAnyChange: Bool {
        addedTaskCount > 0 || removedTaskCount > 0 || !changedTaskIDs.isEmpty
    }
}

enum HouseholdSyncRole: Equatable {
    case owner
    case participant
}

struct HouseholdSyncContext: Equatable {
    let householdId: UUID
    let currentUserId: String
    let ownerUserId: String
    let role: HouseholdSyncRole
    let scope: CloudKitManager.HouseholdDatabaseScope
}

enum HouseholdSyncContextFactory {
    static func make(
        household: Household?,
        currentUserId: String?
    ) -> HouseholdSyncContext? {
        guard let household, let currentUserId else { return nil }
        return make(
            householdId: household.id,
            ownerUserId: household.ownerId,
            currentUserId: currentUserId
        )
    }

    static func make(
        householdId: UUID?,
        ownerUserId: String?,
        currentUserId: String?
    ) -> HouseholdSyncContext? {
        guard let householdId, let ownerUserId, let currentUserId else { return nil }
        let role: HouseholdSyncRole = currentUserId == ownerUserId ? .owner : .participant
        let scope: CloudKitManager.HouseholdDatabaseScope = switch role {
        case .owner:
            .ownerPrivate
        case .participant:
            .participantShared
        }
        return HouseholdSyncContext(
            householdId: householdId,
            currentUserId: currentUserId,
            ownerUserId: ownerUserId,
            role: role,
            scope: scope
        )
    }
}

struct RemoteIdeaVisibleContentDiff: Equatable {
    let addedIdeaIDs: Set<UUID>
    let removedIdeaIDs: Set<UUID>
    let changedIdeaIDs: Set<UUID>

    var hasAnyChange: Bool {
        !addedIdeaIDs.isEmpty || !removedIdeaIDs.isEmpty || !changedIdeaIDs.isEmpty
    }
}

struct RemoteVisibleContentResolution {
    let snapshot: RemoteVisibleContentSnapshot
    let diff: RemoteVisibleContentDiff
    let followUpPassCount: Int
    let cacheUpdatedAt: Date
}

struct RemoteSyncBaseline {
    let beforeSnapshot: HouseholdStore.RemoteCloudRefreshSnapshot
    let beforeVisibleContentSnapshot: RemoteVisibleContentSnapshot?
    let direction: HouseholdSyncDirection
}

struct RemoteSyncPassBuildContext {
    let reason: HouseholdSyncReason
    let cloudContext: RemoteCloudChangeContext
    let triggerReceivedAt: Date
    let refreshStartedAt: Date
    let baseline: RemoteSyncBaseline
    let refreshedHydrationSnapshot: HouseholdStore.JoinedHouseholdHydrationSnapshot?
    let visibleContentResolution: RemoteVisibleContentResolution?
}

protocol HouseholdCloudSyncing: Actor {
    func ensureReady() async
    func checkAvailability() async throws
    func setHouseholdScope(_ scope: CloudKitManager.HouseholdDatabaseScope)
    func getContainer() async -> CKContainer
    func resolveSubscriptionZone(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> CKRecordZone.ID?

    func ensureHouseholdOwnerZone(householdId: UUID) async throws -> CKRecordZone.ID
    func migrateHouseholdToCustomZoneIfNeeded(householdId: UUID) async throws
    func repairSharedHouseholdGraphIfNeeded(householdId: UUID) async throws
    func migrateMemberColorsIfNeeded(householdId: UUID) async

    func createHouseholdWithMember(
        _ household: Household,
        member: Member
    ) async throws -> (householdRecord: CKRecord, memberRecord: CKRecord)

    func saveHousehold(
        _ household: Household,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord
    func fetchHousehold(
        id: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> Household
    func deleteHousehold(
        id: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws
    func updateHouseholdMetadata(
        householdId: UUID,
        newName: String,
        newIconSymbol: String,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord

    func createShare(for household: Household) async throws -> CKShare
    func fetchShare(for householdId: UUID) async throws -> CKShare?
    func getShareURL(for householdId: UUID) async throws -> URL?

    func createInviteCode(for household: Household) async throws -> InviteToken
    func fetchInviteToken(code rawCode: String) async throws -> InviteToken
    func resolveInviteTargetHouseholdId(from input: NormalizedInviteInput) async throws -> UUID?
    func deleteInviteTokens(for householdId: UUID) async throws
    func redeemInviteCode(_ rawCode: String) async throws -> Household
    func acceptShare(inviteCode: String) async throws -> Household
    func acceptShare(metadata: CKShare.Metadata) async throws -> Household
    func resolveAcceptedShareContext(fromInviteCode rawCode: String) async throws -> AcceptedShareContext
    func resolveAcceptedShareContext(metadata: CKShare.Metadata) async throws -> AcceptedShareContext

    func saveMember(
        _ member: Member,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord
    func fetchMemberByUserId(
        _ userId: String,
        householdId: UUID?,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> Member?
    func fetchActiveMembersByUserId(
        _ userId: String,
        householdId: UUID?,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Member]
    func fetchMembers(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Member]
    func updateMemberState(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newRole: Member.MemberRole,
        isActive: Bool,
        colorHex: String,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> CKRecord
    func deleteMember(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func leaveSharedHousehold(householdId: UUID) async throws
    func deleteHouseholdZoneIfCustom(id householdId: UUID) async throws -> Bool
    func clearAllCachedZones(for householdId: UUID)

    func fetchTasks(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Task]
    func fetchUnifiedWorkItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [WorkItem]
    func deleteTask(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchShoppingItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [ShoppingItem]
    func deleteShoppingItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchShoppingBundles(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [ShoppingBundle]
    func deleteShoppingBundle(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchBacklogItems(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [BacklogItem]
    func deleteBacklogItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchBacklogCategories(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [BacklogCategory]
    func deleteBacklogCategory(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchAreas(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [Area]
    func deleteArea(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws

    func fetchRecurringChores(
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws -> [RecurringChore]
    func deleteRecurringChore(
        id: UUID,
        householdId: UUID,
        scope explicitScope: CloudKitManager.HouseholdDatabaseScope?
    ) async throws
}

extension CloudKitManager: HouseholdCloudSyncing {
    func repairSharedHouseholdGraphIfNeeded(householdId: UUID) async throws {
        try await repairSharedHouseholdGraphIfNeeded(householdId: householdId, force: false)
    }
}

@MainActor
// swiftlint:disable type_body_length file_length
class HouseholdStore: ObservableObject {
    private enum DefaultsKey {
        static let suppressedHouseholdRecoveries = "suppressedHouseholdRecoveries"
        static let pendingExitOperations = "pendingHouseholdExitOperations"
    }

    static let pendingExitOperationsDefaultsKey = DefaultsKey.pendingExitOperations

    enum PendingExitOperationKind: String, Codable, Equatable {
        case leaveSharedHousehold
        case deleteOwnedHousehold
    }

    struct PendingExitOperation: Codable, Equatable {
        let kind: PendingExitOperationKind
        let householdId: UUID
        let userId: String?
    }

    private struct PendingHouseholdMetadataSync {
        let household: Household
        let userId: String
    }

    private enum JoinTargetResolution: Equatable {
        case sharedInvite
        case sameUserRecovery
    }

    private struct JoinTarget {
        let household: Household
        let resolution: JoinTargetResolution

        var householdId: UUID {
            household.id
        }
    }

    private struct ScopedMembership {
        let member: Member
        let source: RecoverableMembershipSource
    }

    struct JoinHydrationConfiguration {
        let initialHydrationBudgetNanoseconds: UInt64
        let initialRetryDelaysNanoseconds: [UInt64]
        let backgroundRetryDelaysNanoseconds: [UInt64]
        let pendingJoinGraceDuration: TimeInterval
        let ownerSharedFollowUpRetryDelaysNanoseconds: [UInt64]
        let participantSharedFollowUpRetryDelaysNanoseconds: [UInt64]

        init(
            initialHydrationBudgetNanoseconds: UInt64,
            initialRetryDelaysNanoseconds: [UInt64],
            backgroundRetryDelaysNanoseconds: [UInt64],
            pendingJoinGraceDuration: TimeInterval,
            ownerSharedFollowUpRetryDelaysNanoseconds: [UInt64] = [
                350_000_000,
                1_000_000_000,
                2_500_000_000,
            ],
            participantSharedFollowUpRetryDelaysNanoseconds: [UInt64] = [
                350_000_000,
                1_000_000_000,
                2_500_000_000,
            ]
        ) {
            self.initialHydrationBudgetNanoseconds = initialHydrationBudgetNanoseconds
            self.initialRetryDelaysNanoseconds = initialRetryDelaysNanoseconds
            self.backgroundRetryDelaysNanoseconds = backgroundRetryDelaysNanoseconds
            self.pendingJoinGraceDuration = pendingJoinGraceDuration
            self.ownerSharedFollowUpRetryDelaysNanoseconds = ownerSharedFollowUpRetryDelaysNanoseconds
            self.participantSharedFollowUpRetryDelaysNanoseconds =
                participantSharedFollowUpRetryDelaysNanoseconds
        }

        static let `default` = JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 5_000_000_000,
            initialRetryDelaysNanoseconds: [
                0,
                900_000_000,
                1_350_000_000,
                1_850_000_000,
            ],
            backgroundRetryDelaysNanoseconds: [
                1_000_000_000,
                2_000_000_000,
                4_000_000_000,
                8_000_000_000,
                15_000_000_000,
            ],
            pendingJoinGraceDuration: 30,
            ownerSharedFollowUpRetryDelaysNanoseconds: [
                350_000_000,
                1_000_000_000,
                2_500_000_000,
            ],
            participantSharedFollowUpRetryDelaysNanoseconds: [
                350_000_000,
                1_000_000_000,
                2_500_000_000,
            ]
        )
    }

    private struct PendingJoinState {
        let householdId: UUID
        let userId: String
        let startedAt: Date
        var expiresAt: Date
        var hasConfirmedRemoteMembership = false
        var hasCompletedHydrationPass = false
        var hasPublishedVisibleContentNotifications = false
    }

    struct JoinedHouseholdHydrationSnapshot: Equatable {
        let activeMemberCount: Int
        let currentUserHasCachedMembership: Bool
        let remoteMembershipConfirmed: Bool
        let taskCount: Int
        let ideaCount: Int
        let categoryCount: Int
        let shoppingItemCount: Int
        let bundleCount: Int

        var hasVisibleSharedContent: Bool {
            taskCount > 0 ||
                ideaCount > 0 ||
                categoryCount > 0 ||
                shoppingItemCount > 0 ||
                bundleCount > 0
        }
    }

    struct RemoteCloudRefreshSnapshot: Equatable {
        let currentHouseholdId: UUID?
        let observedHouseholdId: UUID?
        let householdName: String?
        let householdIconSymbol: String?
        let hydrationSnapshot: JoinedHouseholdHydrationSnapshot?
    }

    private enum JoinHydrationTimeoutError: Error {
        case timedOut
    }

    enum LeaveResolution: Equatable {
        case deleteHousehold
        case requireTransfer
        case deactivateMembership
    }

    enum SetupResolutionState: Equatable {
        case idle
        case loading(key: String)
        case resolved(key: String, householdCount: Int)

        func matches(key: String) -> Bool {
            switch self {
            case let .loading(storedKey):
                storedKey == key
            case let .resolved(storedKey, _):
                storedKey == key
            case .idle:
                false
            }
        }

        var resolvedHouseholdCount: Int? {
            switch self {
            case let .resolved(_, householdCount):
                householdCount
            case .idle, .loading:
                nil
            }
        }
    }

    enum RecoverableMembershipSource: String {
        case participantShared
        case ownerPrivate
    }

    @Published var currentHousehold: Household? {
        didSet {
            guard oldValue?.id != currentHousehold?.id else { return }
            resetInvitePresentationState()
        }
    }

    @Published var isLoading = false
    @Published var error: Error?
    @Published var share: CKShare?
    @Published var activeInviteCode: String?
    @Published private(set) var setupResolutionState: SetupResolutionState = .idle

    private var modelContext: ModelContext?
    private let cloudKit: any HouseholdCloudSyncing
    private lazy var householdRepository = HouseholdRepository(cloud: cloudKit)
    private var syncMode: SyncMode = .cloud
    private let userDefaults: UserDefaults
    private let recoverySuppressionDuration: TimeInterval
    private let joinHydrationConfiguration: JoinHydrationConfiguration
    private var isRefreshingCloudHousehold = false
    private var lastRemoteCloudRefreshSnapshot: RemoteCloudRefreshSnapshot?
    private var isReplayingPendingExitOperations = false
    private var pendingHouseholdMetadataSync: PendingHouseholdMetadataSync?
    private var isReplayingPendingHouseholdMetadataSync = false
    private let joinedHouseholdPrewarmOverride: ((Household, String, ModelContext?) async throws -> Void)?
    private var pendingJoinState: PendingJoinState?
    private var joinHydrationTask: _Concurrency.Task<Void, Never>?
    private var activeInviteToken: InviteToken?

    // Cache for sharing controller
    private var activeShare: CKShare?
    private(set) var activeContainer: CKContainer?

    init(
        modelContext: ModelContext? = nil,
        cloudKit: any HouseholdCloudSyncing = CloudKitManager.shared,
        joinedHouseholdPrewarmOverride: ((Household, String, ModelContext?) async throws -> Void)? = nil,
        userDefaults: UserDefaults = .standard,
        recoverySuppressionDuration: TimeInterval = 300,
        joinHydrationConfiguration: JoinHydrationConfiguration = .default
    ) {
        self.modelContext = modelContext
        self.cloudKit = cloudKit
        self.joinedHouseholdPrewarmOverride = joinedHouseholdPrewarmOverride
        self.userDefaults = userDefaults
        self.recoverySuppressionDuration = recoverySuppressionDuration
        self.joinHydrationConfiguration = joinHydrationConfiguration
    }

    deinit {
        joinHydrationTask?.cancel()
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
        if mode != .cloud {
            resetInvitePresentationState()
        }
    }

    func cacheInviteToken(_ token: InviteToken?) {
        activeInviteToken = token
        activeInviteCode = token?.code
    }

    private func resetInvitePresentationState() {
        share = nil
        activeContainer = nil
        activeShare = nil
        cacheInviteToken(nil)
    }

    var isModelContextReady: Bool {
        modelContext != nil
    }

    @discardableResult
    private func saveContextOrSetError(
        _ context: ModelContext? = nil,
        operation: String = "persist household cache",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        StoreContextSaver.saveContextOrSetError(
            context ?? modelContext,
            store: "HouseholdStore",
            operation: operation,
            file: file,
            line: line
        ) { [self] saveError in
            error = saveError
        }
    }

    // MARK: - Lifecycle

    /// Preferred entry point for restoring session household context.
    /// It loads cached data first and refreshes membership from CloudKit when enabled.
    func loadCurrentHouseholdAndMembership(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) async {
        restoreCachedHousehold(userId: userId, preferredHouseholdId: preferredHouseholdId)
        await refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
    }

    /// Launch-safe local-first resolver for startup routing.
    /// It never touches CloudKit and only inspects in-memory/current cached household state.
    @discardableResult
    func resolveStartupHouseholdLocally(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Household? {
        if let household = currentHousehold {
            guard !isRecoverySuppressed(for: household.id) else {
                clearCurrentHousehold()
                return nil
            }
            return household
        }

        return restoreCachedHousehold(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
    }

    @discardableResult
    func restoreCachedHousehold(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Household? {
        guard let cached = fetchCachedHousehold(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ) else {
            return nil
        }

        let restoredHousehold = cached.toHousehold()
        guard isValidCachedMembershipForRecoveredHousehold(
            householdId: restoredHousehold.id,
            userId: userId
        ) else {
            print(
                "DEBUG: Ignoring cached household \(restoredHousehold.id) because the current user has no cached membership."
            )
            removeHouseholdFromCache(id: restoredHousehold.id)
            currentHousehold = nil
            return nil
        }
        currentHousehold = restoredHousehold
        return restoredHousehold
    }

    func refreshCurrentHouseholdAndMembershipFromCloud(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) async {
        guard syncMode == .cloud else { return }
        guard !isRefreshingCloudHousehold else { return }

        isRefreshingCloudHousehold = true
        isLoading = true
        defer {
            isRefreshingCloudHousehold = false
            isLoading = false
        }

        do {
            await replayPendingExitOperationsIfNeeded()
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()

            let localHousehold = currentHousehold
            var resolvedCloudHousehold: Household?

            if let current = localHousehold {
                do {
                    await setCloudScope(for: current, userId: userId)
                    let fresh = try await cloudKit.fetchHousehold(
                        id: current.id,
                        scope: cloudScope(for: current, userId: userId)
                    )
                    if try await validateRecoveredMembershipOrAbandon(
                        household: fresh,
                        userId: userId
                    ) {
                        await cloudKit.migrateMemberColorsIfNeeded(householdId: fresh.id)
                        await refreshMemberCacheFromCloudIfNeeded(
                            household: fresh,
                            userId: userId
                        )
                        resolvedCloudHousehold = fresh
                    }
                } catch {
                    if shouldProtectPendingJoin(householdId: current.id, userId: userId) {
                        print(
                            "DEBUG: Preserving pending-join household \(current.id) despite refresh error: \(error)"
                        )
                        scheduleBackgroundJoinHydrationIfNeeded(
                            household: current,
                            userId: userId
                        )
                        resolvedCloudHousehold = current
                    }
                    print("DEBUG: Cached household refresh failed, retrying membership lookup: \(error)")
                }
            }

            if resolvedCloudHousehold == nil {
                print("DEBUG: Checking CloudKit for existing household membership...")
                resolvedCloudHousehold = try await resolveRecoverableCloudHousehold(
                    userId: userId,
                    preferredHouseholdId: preferredHouseholdId
                )
            }

            if let resolvedCloudHousehold {
                print("DEBUG: Found recoverable household in cloud: \(resolvedCloudHousehold.id)")
                await setCloudScope(for: resolvedCloudHousehold, userId: userId)
                if resolvedCloudHousehold.ownerId == userId {
                    try? await cloudKit.repairSharedHouseholdGraphIfNeeded(
                        householdId: resolvedCloudHousehold.id
                    )
                }
                await cloudKit.migrateMemberColorsIfNeeded(householdId: resolvedCloudHousehold.id)
                await refreshMemberCacheFromCloudIfNeeded(
                    household: resolvedCloudHousehold,
                    userId: userId
                )
                updateCache(with: resolvedCloudHousehold)
                currentHousehold = resolvedCloudHousehold
            } else {
                if let localHousehold,
                   shouldProtectPendingJoin(householdId: localHousehold.id, userId: userId)
                {
                    currentHousehold = localHousehold
                    scheduleBackgroundJoinHydrationIfNeeded(
                        household: localHousehold,
                        userId: userId
                    )
                    return
                }
                print("DEBUG: No existing membership found in cloud.")
            }
        } catch {
            print("Error loading household: \(error)")
            if currentHousehold == nil {
                self.error = error
            }
        }
    }

    func createHousehold(
        name: String,
        userId: String,
        displayName: String,
        iconSymbol: String = "house.fill"
    ) async throws -> Household {
        // CloudKit safety check
        precondition(
            syncMode == .localOnly || syncMode == .cloud,
            "Invalid sync mode for household creation"
        )

        try ensureUserCanStartSingleHouseholdLocally(userId: userId)
        if syncMode == .cloud, !shouldSkipRemoteSingleHouseholdDiscoveryForCreate {
            try await ensureUserCanStartSingleHouseholdRemotely(userId: userId)
        }

        isLoading = true
        defer { isLoading = false }

        let validatedDisplayName = try requiredMembershipDisplayName(from: displayName)
        let trimmedHouseholdName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHouseholdName.isEmpty else {
            throw HouseholdError.invalidInviteCode
        }
        if syncMode == .localOnly, modelContext == nil {
            throw HouseholdError.cacheNotAvailable
        }

        let newHousehold = Household(
            name: trimmedHouseholdName,
            iconSymbol: iconSymbol,
            ownerId: userId
        )

        let ownerMember = Member(
            householdId: newHousehold.id,
            userId: userId,
            displayName: validatedDisplayName,
            role: .owner,
            colorHex: MemberColorToken.randomHex()
        )

        // 1. Save to CloudKit (if cloud sync is enabled and available)
        if syncMode == .cloud {
            // Check CloudKit availability first
            try await cloudKit.checkAvailability()
            await cloudKit.setHouseholdScope(.ownerPrivate)

            // Batch: zone ensure + household + member in minimal round-trips
            _ = try await cloudKit.createHouseholdWithMember(newHousehold, member: ownerMember)
            updateCache(with: ownerMember)
            updateCache(with: newHousehold)
            currentHousehold = newHousehold
            runCreateHouseholdPostflight(household: newHousehold, userId: userId)
            return newHousehold
        }

        // 2. Cache the local owner membership for immediate UI availability.
        if syncMode == .localOnly {
            updateCache(with: ownerMember)
        }

        // 3. Update Cache
        updateCache(with: newHousehold)
        currentHousehold = newHousehold

        return newHousehold
    }

    // MARK: - Sharing

    func createShare() async throws -> (CKShare, CKContainer) {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        // Check availability and get container from CloudKitManager
        try await cloudKit.checkAvailability()
        await cloudKit.setHouseholdScope(.ownerPrivate)
        let share = try await cloudKit.createShare(for: household)
        let container = await cloudKit.getContainer()
        self.share = share
        activeContainer = container
        return (share, container)
    }

    func fetchInviteURL() async throws -> URL {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        try await cloudKit.checkAvailability()
        await cloudKit.setHouseholdScope(.ownerPrivate)

        if let existingURL = share?.url {
            return existingURL
        }

        if let existingShare = try await cloudKit.fetchShare(for: household.id) {
            share = existingShare
            activeContainer = await cloudKit.getContainer()
            if let existingURL = existingShare.url {
                return existingURL
            }
        }

        do {
            let (createdShare, container) = try await createShare()
            share = createdShare
            activeContainer = container
            if let createdURL = createdShare.url {
                return createdURL
            }
        } catch CloudKitManager.CloudKitManagerError.shareNotCreated {
            // Fallbacks below.
        }

        if let fallbackShare = try await cloudKit.fetchShare(for: household.id) {
            share = fallbackShare
            activeContainer = await cloudKit.getContainer()
            if let shareURL = fallbackShare.url {
                return shareURL
            }
        }

        if let shareURL = try await cloudKit.getShareURL(for: household.id) {
            return shareURL
        }

        throw CloudKitManager.CloudKitManagerError.shareNotCreated
    }

    func fetchOrCreateInviteCode() async throws -> String {
        let token = try await fetchOrCreateInviteToken()
        return token.code
    }

    func fetchOrCreateInviteToken() async throws -> InviteToken {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        if let activeInviteToken {
            if activeInviteToken.householdId == household.id,
               activeInviteToken.isActive(at: Date())
            {
                if activeInviteCode != activeInviteToken.code {
                    activeInviteCode = activeInviteToken.code
                }
                return activeInviteToken
            }
            cacheInviteToken(nil)
        }

        await cloudKit.setHouseholdScope(.ownerPrivate)
        let token = try await cloudKit.createInviteCode(for: household)
        cacheInviteToken(token)
        return token
    }

    // MARK: - Join Household

    func joinHousehold(inviteCode: String, userId: String, displayName: String) async throws {
        try await joinHousehold(
            withInviteInput: inviteCode,
            userId: userId,
            displayName: displayName
        )
    }

    func joinHousehold(withInviteInput input: String, userId: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        let validatedDisplayName = try requiredMembershipDisplayName(from: displayName)

        try await cloudKit.checkAvailability()
        let normalizedInvite = try InviteInputNormalizer.normalizeInput(input)
        let target = try await resolveJoinTarget(for: normalizedInvite, userId: userId)
        try await clearConflictingJoinStateBeforeTargetedJoin(
            targetHouseholdId: target.householdId,
            userId: userId
        )

        if target.resolution == .sameUserRecovery {
            await completeSameUserRecoveryJoin(
                household: target.household,
                userId: userId
            )
            return
        }

        await cloudKit.setHouseholdScope(.participantShared)
        await cloudKit.migrateMemberColorsIfNeeded(householdId: target.householdId)

        print("DEBUG: Join member upsert starting for household \(target.householdId) in participantShared scope.")
        let joinedMember: Member
        do {
            joinedMember = try await upsertMembership(
                householdId: target.householdId,
                userId: userId,
                displayName: validatedDisplayName,
                role: target.household.ownerId == userId ? .owner : .member,
                scope: .participantShared
            )
        } catch {
            logJoinError(stage: "memberUpsert", householdId: target.householdId, error: error)
            throw debugJoinFailure(
                prefix: "Member upsert failed",
                error: error
            )
        }

        print("DEBUG: Join member verification starting for household \(target.householdId) in participantShared scope.")
        let verifiedMember = try await verifyParticipantSharedMembership(
            householdId: target.householdId,
            userId: userId,
            expectedMember: joinedMember
        )

        updateCache(with: verifiedMember)
        updateCache(with: target.household)
        currentHousehold = target.household
        clearRecoveredJoinDiagnostics()
        beginPendingJoinProtection(
            householdId: target.household.id,
            userId: userId
        )
        await prewarmJoinedHouseholdGraphIfNeeded(household: target.household, userId: userId)
    }

    func joinHousehold(metadata: CKShare.Metadata, userId: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        let validatedDisplayName = try requiredMembershipDisplayName(from: displayName)

        try await cloudKit.checkAvailability()
        let target = try await resolveJoinTarget(for: metadata, userId: userId)
        try await clearConflictingJoinStateBeforeTargetedJoin(
            targetHouseholdId: target.householdId,
            userId: userId
        )

        if target.resolution == .sameUserRecovery {
            await completeSameUserRecoveryJoin(
                household: target.household,
                userId: userId
            )
            return
        }

        await cloudKit.setHouseholdScope(.participantShared)
        await cloudKit.migrateMemberColorsIfNeeded(householdId: target.householdId)

        print("DEBUG: Join member upsert starting for household \(target.householdId) in participantShared scope.")
        let joinedMember: Member
        do {
            joinedMember = try await upsertMembership(
                householdId: target.householdId,
                userId: userId,
                displayName: validatedDisplayName,
                role: target.household.ownerId == userId ? .owner : .member,
                scope: .participantShared
            )
        } catch {
            logJoinError(stage: "memberUpsert", householdId: target.householdId, error: error)
            throw debugJoinFailure(
                prefix: "Member upsert failed",
                error: error
            )
        }

        print("DEBUG: Join member verification starting for household \(target.householdId) in participantShared scope.")
        let verifiedMember = try await verifyParticipantSharedMembership(
            householdId: target.householdId,
            userId: userId,
            expectedMember: joinedMember
        )

        updateCache(with: verifiedMember)
        updateCache(with: target.household)
        currentHousehold = target.household
        clearRecoveredJoinDiagnostics()
        beginPendingJoinProtection(
            householdId: target.household.id,
            userId: userId
        )
        await prewarmJoinedHouseholdGraphIfNeeded(household: target.household, userId: userId)
    }

    // MARK: - Household Management

    func renameCurrentHousehold(_ name: String) async throws {
        guard let currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        try await updateCurrentHousehold(
            name: name,
            userId: currentHousehold.ownerId
        )
    }

    func updateCurrentHousehold(
        name: String,
        userId: String,
        iconSymbol: String? = nil
    ) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        guard household.ownerId == userId else {
            throw HouseholdError.notAuthorized
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HouseholdError.invalidInviteCode
        }

        let resolvedIconSymbol = iconSymbol ?? household.iconSymbol
        guard trimmedName != household.name || resolvedIconSymbol != household.iconSymbol else {
            return
        }

        error = nil

        let previousHousehold = household
        var updatedHousehold = household
        updatedHousehold.name = trimmedName
        updatedHousehold.iconSymbol = resolvedIconSymbol
        updatedHousehold.updatedAt = Date()

        currentHousehold = updatedHousehold
        guard updateCache(with: updatedHousehold) else {
            currentHousehold = previousHousehold
            _ = updateCache(with: previousHousehold)
            throw error ?? HouseholdError.cacheNotAvailable
        }

        guard syncMode == .cloud else {
            return
        }

        queueHouseholdMetadataSync(updatedHousehold, userId: userId)
    }

    private func queueHouseholdMetadataSync(_ household: Household, userId: String) {
        guard syncMode == .cloud else { return }
        pendingHouseholdMetadataSync = PendingHouseholdMetadataSync(
            household: household,
            userId: userId
        )
        replayPendingHouseholdMetadataSyncInBackground()
    }

    private func replayPendingHouseholdMetadataSyncInBackground() {
        guard syncMode == .cloud else {
            pendingHouseholdMetadataSync = nil
            return
        }
        guard !isReplayingPendingHouseholdMetadataSync else { return }

        isReplayingPendingHouseholdMetadataSync = true
        _ = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isReplayingPendingHouseholdMetadataSync = false }

            while let pendingSync = pendingHouseholdMetadataSync {
                pendingHouseholdMetadataSync = nil

                do {
                    let scope = cloudScope(for: pendingSync.household, userId: pendingSync.userId)
                    await setCloudScope(for: pendingSync.household, userId: pendingSync.userId)
                    _ = try await cloudKit.updateHouseholdMetadata(
                        householdId: pendingSync.household.id,
                        newName: pendingSync.household.name,
                        newIconSymbol: pendingSync.household.iconSymbol,
                        scope: scope
                    )
                } catch {
                    self.error = error
                }
            }
        }
    }

    func resolveMembershipDisplayName(userId: String) async -> String? {
        guard syncMode == .cloud else { return nil }

        if let household = currentHousehold {
            let scope = cloudScope(for: household, userId: userId)
            await setCloudScope(for: household, userId: userId)
            if let member = try? await cloudKit.fetchMemberByUserId(
                userId,
                householdId: household.id,
                scope: scope
            ),
                member.isActive
            {
                return member.displayName
            }
        }

        await cloudKit.setHouseholdScope(.participantShared)
        if let member = try? await cloudKit.fetchMemberByUserId(
            userId,
            householdId: nil,
            scope: .participantShared
        ),
            member.isActive
        {
            return member.displayName
        }

        await cloudKit.setHouseholdScope(.ownerPrivate)
        if let member = try? await cloudKit.fetchMemberByUserId(
            userId,
            householdId: nil,
            scope: .ownerPrivate
        ),
            member.isActive
        {
            return member.displayName
        }

        return nil
    }

    func leaveCurrentHousehold(
        userId: String,
        activeMembersSnapshot: [Member]? = nil
    ) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        switch try resolveLocalLeaveBehavior(
            for: household,
            userId: userId,
            activeMembersSnapshot: activeMembersSnapshot
        ) {
        case .deleteHousehold:
            try await deleteCurrentHousehold(requestedBy: userId)
            return
        case .requireTransfer:
            throw HouseholdError.transferOwnershipRequired
        case .deactivateMembership:
            break
        }

        let pendingOperation: PendingExitOperation? = if syncMode == .cloud {
            PendingExitOperation(
                kind: .leaveSharedHousehold,
                householdId: household.id,
                userId: userId
            )
        } else {
            nil
        }

        if let pendingOperation {
            enqueuePendingExitOperation(pendingOperation)
        }

        performLocalHouseholdExit(householdId: household.id)

        if pendingOperation != nil {
            replayPendingExitOperationsInBackground()
        }
    }

    func deleteCurrentHousehold(requestedBy userId: String) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        guard household.ownerId == userId else {
            throw HouseholdError.notAuthorized
        }

        let pendingOperation: PendingExitOperation? = if syncMode == .cloud {
            PendingExitOperation(
                kind: .deleteOwnedHousehold,
                householdId: household.id,
                userId: userId
            )
        } else {
            nil
        }

        if let pendingOperation {
            enqueuePendingExitOperation(pendingOperation)
        }

        performLocalHouseholdExit(householdId: household.id)

        if pendingOperation != nil {
            replayPendingExitOperationsInBackground()
        }
    }

    /// Removes the current household from CloudKit as part of a hard reset.
    /// Owner → deletes the entire household. Participant → deactivates membership and leaves.
    /// Errors are swallowed; local reset proceeds regardless of network state.
    func hardResetCloudHousehold(userId: String) async {
        guard syncMode == .cloud, let household = currentHousehold else { return }

        do {
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()

            if household.ownerId == userId {
                try await deleteRemoteOwnedHousehold(householdId: household.id)
            } else {
                try await leaveSharedHouseholdRemotely(
                    householdId: household.id,
                    userId: userId
                )
            }
        } catch {
            print("[HouseholdStore] Hard reset cloud cleanup non-fatal: \(error)")
        }
    }

    private func setCloudScope(for household: Household, userId: String) async {
        guard let syncContext = HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: userId
        ) else {
            await cloudKit.setHouseholdScope(.participantShared)
            return
        }
        await cloudKit.setHouseholdScope(syncContext.scope)
    }

    private func cloudScope(
        for household: Household,
        userId: String
    ) -> CloudKitManager.HouseholdDatabaseScope {
        HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: userId
        )?.scope ?? .participantShared
    }

    func currentSyncContext(userId: String?) -> HouseholdSyncContext? {
        HouseholdSyncContextFactory.make(
            household: currentHousehold,
            currentUserId: userId
        )
    }

    private func resolveLocalLeaveBehavior(
        for household: Household,
        userId: String,
        activeMembersSnapshot: [Member]?
    ) throws -> LeaveResolution {
        let activeMembers = resolvedActiveMembersForExit(
            householdId: household.id,
            activeMembersSnapshot: activeMembersSnapshot
        )

        guard let member = activeMembers.first(where: { $0.userId == userId }) else {
            if syncMode == .localOnly, household.ownerId == userId {
                return .deleteHousehold
            }
            throw HouseholdError.memberNotFound
        }

        return resolveLeaveBehavior(for: member, activeMembers: activeMembers)
    }

    private func performLocalHouseholdExit(householdId: UUID) {
        suppressRecovery(for: householdId)
        removeHouseholdFromCache(id: householdId)
        clearCurrentHousehold()
        _ = _Concurrency.Task { [cloudKit] in
            await cloudKit.clearAllCachedZones(for: householdId)
        }
    }

    private func replayPendingExitOperationsInBackground() {
        guard syncMode == .cloud else { return }
        _ = _Concurrency.Task { [self] in
            await replayPendingExitOperationsIfNeeded()
        }
    }

    private func replayPendingExitOperationsIfNeeded() async {
        guard syncMode == .cloud else { return }
        guard !isReplayingPendingExitOperations else { return }

        let operations = loadPendingExitOperations()
        guard !operations.isEmpty else { return }

        isReplayingPendingExitOperations = true
        defer { isReplayingPendingExitOperations = false }

        do {
            await cloudKit.ensureReady()
            try await cloudKit.checkAvailability()
        } catch {
            print("DEBUG: Pending household exit replay deferred: \(error)")
            return
        }

        for operation in operations {
            do {
                try await performRemoteExitOperation(operation)
                removePendingExitOperation(operation)
            } catch {
                print("DEBUG: Pending household exit replay failed for \(operation.householdId): \(error)")
            }
        }
    }

    private func performRemoteExitOperation(_ operation: PendingExitOperation) async throws {
        switch operation.kind {
        case .leaveSharedHousehold:
            guard let userId = operation.userId else {
                throw HouseholdError.memberNotFound
            }
            try await leaveSharedHouseholdRemotely(
                householdId: operation.householdId,
                userId: userId
            )
        case .deleteOwnedHousehold:
            try await deleteRemoteOwnedHousehold(householdId: operation.householdId)
        }
    }

    private func leaveSharedHouseholdRemotely(
        householdId: UUID,
        userId: String
    ) async throws {
        await cloudKit.setHouseholdScope(.participantShared)

        if let member = try? await cloudKit.fetchMemberByUserId(
            userId,
            householdId: householdId,
            scope: .participantShared
        ),
            member.householdId == householdId
        {
            do {
                _ = try await cloudKit.updateMemberState(
                    memberId: member.id,
                    householdId: member.householdId,
                    newDisplayName: member.displayName,
                    newRole: member.role,
                    isActive: false,
                    colorHex: member.colorHex,
                    scope: .participantShared
                )
            } catch {
                print("DEBUG: Member deactivation during leave failed: \(error)")
            }
        }

        try await cloudKit.leaveSharedHousehold(householdId: householdId)
        await cloudKit.clearAllCachedZones(for: householdId)
    }

    // swiftlint:disable cyclomatic_complexity
    private func deleteRemoteOwnedHousehold(householdId: UUID) async throws {
        await cloudKit.setHouseholdScope(.ownerPrivate)
        let deletedByZone = try await cloudKit.deleteHouseholdZoneIfCustom(id: householdId)

        if !deletedByZone {
            let members = try await cloudKit.fetchMembers(householdId: householdId, scope: .ownerPrivate)
            for member in members {
                try await cloudKit.deleteMember(
                    id: member.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let tasks = try await cloudKit.fetchTasks(householdId: householdId, scope: .ownerPrivate)
            for task in tasks {
                try await cloudKit.deleteTask(
                    id: task.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let shoppingItems = try await cloudKit.fetchShoppingItems(
                householdId: householdId,
                scope: .ownerPrivate
            )
            for item in shoppingItems {
                try await cloudKit.deleteShoppingItem(
                    id: item.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let shoppingBundles = try await cloudKit.fetchShoppingBundles(
                householdId: householdId,
                scope: .ownerPrivate
            )
            for bundle in shoppingBundles {
                try await cloudKit.deleteShoppingBundle(
                    id: bundle.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let backlogItems = try await cloudKit.fetchBacklogItems(
                householdId: householdId,
                scope: .ownerPrivate
            )
            for item in backlogItems {
                try await cloudKit.deleteBacklogItem(
                    id: item.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let categories = try await cloudKit.fetchBacklogCategories(
                householdId: householdId,
                scope: .ownerPrivate
            )
            for category in categories {
                try await cloudKit.deleteBacklogCategory(
                    id: category.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let areas = try await cloudKit.fetchAreas(householdId: householdId, scope: .ownerPrivate)
            for area in areas {
                try await cloudKit.deleteArea(
                    id: area.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            let recurringChores = try await cloudKit.fetchRecurringChores(
                householdId: householdId,
                scope: .ownerPrivate
            )
            for chore in recurringChores {
                try await cloudKit.deleteRecurringChore(
                    id: chore.id,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
            }

            try await cloudKit.deleteHousehold(id: householdId, scope: .ownerPrivate)
        }

        try await cloudKit.deleteInviteTokens(for: householdId)

        do {
            _ = try await cloudKit.fetchHousehold(id: householdId, scope: .ownerPrivate)
            throw NSError(
                domain: "HouseholdStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Household deletion could not be verified."]
            )
        } catch {
            guard isRecordMissingError(error) else { throw error }
        }

        await cloudKit.clearAllCachedZones(for: householdId)
    }

    // swiftlint:enable cyclomatic_complexity

    private func enqueuePendingExitOperation(_ operation: PendingExitOperation) {
        var operations = loadPendingExitOperations()
        if !operations.contains(operation) {
            operations.append(operation)
            savePendingExitOperations(operations)
        }
    }

    private func removePendingExitOperation(_ operation: PendingExitOperation) {
        let filtered = loadPendingExitOperations().filter { $0 != operation }
        savePendingExitOperations(filtered)
    }

    private func hasPendingExitOperation(for householdId: UUID) -> Bool {
        loadPendingExitOperations().contains(where: { $0.householdId == householdId })
    }

    private func loadPendingExitOperations() -> [PendingExitOperation] {
        guard let data = userDefaults.data(forKey: DefaultsKey.pendingExitOperations) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PendingExitOperation].self, from: data)
        } catch {
            print("DEBUG: Failed to decode pending household exit operations: \(error)")
            return []
        }
    }

    private func savePendingExitOperations(_ operations: [PendingExitOperation]) {
        if operations.isEmpty {
            userDefaults.removeObject(forKey: DefaultsKey.pendingExitOperations)
            return
        }

        do {
            let data = try JSONEncoder().encode(operations)
            userDefaults.set(data, forKey: DefaultsKey.pendingExitOperations)
        } catch {
            print("DEBUG: Failed to persist pending household exit operations: \(error)")
        }
    }

    private func resolveJoinTarget(
        for normalizedInvite: NormalizedInviteInput,
        userId: String
    )
        async throws -> JoinTarget
    {
        let previewHouseholdId = try await cloudKit.resolveInviteTargetHouseholdId(from: normalizedInvite)
        if let previewHouseholdId,
           let recoveredHousehold = try await resolveSameUserRecoveredHousehold(
               householdId: previewHouseholdId,
               userId: userId
           )
        {
            return JoinTarget(household: recoveredHousehold, resolution: .sameUserRecovery)
        }

        do {
            let acceptedShareContext = try await cloudKit.resolveAcceptedShareContext(
                fromInviteCode: normalizedInvite.inviteCode
            )
            return JoinTarget(household: acceptedShareContext.household, resolution: .sharedInvite)
        } catch {
            if let previewHouseholdId,
               isDeferredAcceptedShareBootstrapError(error),
               let recoveredHousehold = try await resolveAcceptedSharedHouseholdAfterBootstrapGap(
                   householdId: previewHouseholdId
               )
            {
                clearRecoveredJoinDiagnostics()
                return JoinTarget(household: recoveredHousehold, resolution: .sharedInvite)
            }
            throw error
        }
    }

    private func resolveJoinTarget(for metadata: CKShare.Metadata, userId: String) async throws -> JoinTarget {
        let metadataHouseholdId = UUID(uuidString: metadata.rootRecordID.recordName)
        if let metadataHouseholdId,
           let recoveredHousehold = try await resolveSameUserRecoveredHousehold(
               householdId: metadataHouseholdId,
               userId: userId
           )
        {
            return JoinTarget(household: recoveredHousehold, resolution: .sameUserRecovery)
        }

        do {
            let acceptedShareContext = try await cloudKit.resolveAcceptedShareContext(metadata: metadata)
            guard metadataHouseholdId == acceptedShareContext.household.id else {
                throw HouseholdError.invalidInviteCode
            }
            return JoinTarget(household: acceptedShareContext.household, resolution: .sharedInvite)
        } catch {
            if let metadataHouseholdId,
               isDeferredAcceptedShareBootstrapError(error),
               let recoveredHousehold = try await resolveAcceptedSharedHouseholdAfterBootstrapGap(
                   householdId: metadataHouseholdId
               )
            {
                clearRecoveredJoinDiagnostics()
                return JoinTarget(household: recoveredHousehold, resolution: .sharedInvite)
            }
            throw error
        }
    }

    private func resolveSameUserRecoveredHousehold(
        householdId: UUID,
        userId: String
    ) async throws -> Household? {
        if let currentHousehold,
           currentHousehold.id == householdId,
           currentHousehold.ownerId == userId
        {
            return currentHousehold
        }

        let memberships = try await householdRepository.fetchActiveScopedMemberships(
            userId: userId,
            householdId: householdId
        )

        for membership in memberships {
            if let recoveredHousehold = try await recoverableHousehold(from: membership) {
                return recoveredHousehold
            }
        }

        return nil
    }

    private func resolveAcceptedSharedHouseholdAfterBootstrapGap(
        householdId: UUID
    ) async throws -> Household? {
        let retryDelaysNanoseconds: [UInt64] = [
            0,
            500_000_000,
            1_000_000_000,
            2_000_000_000,
            4_000_000_000,
            8_000_000_000,
        ]

        var lastError: Error?
        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            await cloudKit.setHouseholdScope(.participantShared)
            do {
                return try await cloudKit.fetchHousehold(
                    id: householdId,
                    scope: .participantShared
                )
            } catch {
                lastError = error
                guard isRetryableParticipantSharedBootstrapRecoveryError(error) else {
                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }

        return nil
    }

    private func isDeferredAcceptedShareBootstrapError(_ error: Error) -> Bool {
        guard let cloudKitError = error as? CloudKitManager.CloudKitManagerError else {
            return false
        }

        if case .sharedHouseholdFetchFailed = cloudKitError {
            return true
        }
        return false
    }

    private func isRetryableParticipantSharedBootstrapRecoveryError(_ error: Error) -> Bool {
        if CloudKitManager.isRetryableParticipantSharedZoneBootstrapError(error) {
            return true
        }

        if let ckError = error as? CKError {
            switch ckError.code {
            case .unknownItem, .zoneNotFound, .permissionFailure:
                return true
            case .partialFailure:
                if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                    return partialErrors.values.contains {
                        isRetryableParticipantSharedBootstrapRecoveryError($0)
                    }
                }
                return true
            default:
                return false
            }
        }

        if let cloudKitError = error as? CloudKitManager.CloudKitManagerError {
            switch cloudKitError {
            case .sharedHouseholdFetchFailed:
                return true
            case let .unknownError(underlying):
                return isRetryableParticipantSharedBootstrapRecoveryError(underlying)
            default:
                return false
            }
        }

        return false
    }

    private func completeSameUserRecoveryJoin(
        household: Household,
        userId: String
    ) async {
        updateCache(with: household)
        currentHousehold = household
        clearRecoveredJoinDiagnostics()
        await cloudKit.migrateMemberColorsIfNeeded(householdId: household.id)
        await refreshMemberCacheFromCloudIfNeeded(household: household, userId: userId)
        await prewarmJoinedHouseholdGraphIfNeeded(household: household, userId: userId)
    }

    private func clearRecoveredJoinDiagnostics() {
        CloudKitDiagnosticsState.shared.clear()
    }

    private func clearConflictingJoinStateBeforeTargetedJoin(
        targetHouseholdId: UUID,
        userId: String
    ) async throws {
        let scopedMemberships = try await fetchScopedActiveMemberships(userId: userId)
        let conflictingMemberships = scopedMemberships.filter { $0.member.householdId != targetHouseholdId }

        for scopedMembership in conflictingMemberships {
            try await severMembershipAssociation(scopedMembership)
            removeHouseholdFromCache(id: scopedMembership.member.householdId)
            suppressRecovery(for: scopedMembership.member.householdId)
        }

        let staleCachedHouseholdIds = fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: nil
        )
        .map(\.id)
        .filter { $0 != targetHouseholdId }

        for householdId in staleCachedHouseholdIds {
            removeHouseholdFromCache(id: householdId)
            suppressRecovery(for: householdId)
        }

        if let currentHousehold, currentHousehold.id != targetHouseholdId {
            suppressRecovery(for: currentHousehold.id)
            clearCurrentHousehold()
        }
    }

    private func fetchScopedActiveMemberships(
        userId: String,
        householdId: UUID? = nil
    ) async throws -> [ScopedMembership] {
        let memberships = try await householdRepository.fetchActiveScopedMemberships(
            userId: userId,
            householdId: householdId
        )

        let scopedMemberships = memberships.map { membership in
            ScopedMembership(
                member: membership.member,
                source: membership.scope == .ownerPrivate ? .ownerPrivate : .participantShared
            )
        }
        return deduplicatedScopedMemberships(scopedMemberships)
    }

    private func deduplicatedScopedMemberships(_ memberships: [ScopedMembership]) -> [ScopedMembership] {
        var byHouseholdId: [UUID: ScopedMembership] = [:]

        for membership in memberships {
            let householdId = membership.member.householdId
            guard let existing = byHouseholdId[householdId] else {
                byHouseholdId[householdId] = membership
                continue
            }

            if membership.member.joinedAt >= existing.member.joinedAt {
                byHouseholdId[householdId] = membership
            }
        }

        return byHouseholdId.values.sorted { lhs, rhs in
            lhs.member.joinedAt > rhs.member.joinedAt
        }
    }

    private func severMembershipAssociation(_ scopedMembership: ScopedMembership) async throws {
        let member = scopedMembership.member
        let scope: CloudKitManager.HouseholdDatabaseScope =
            scopedMembership.source == .ownerPrivate ? .ownerPrivate : .participantShared

        await cloudKit.setHouseholdScope(scope)
        _ = try await cloudKit.updateMemberState(
            memberId: member.id,
            householdId: member.householdId,
            newDisplayName: member.displayName,
            newRole: member.role,
            isActive: false,
            colorHex: member.colorHex,
            scope: scope
        )

        if scopedMembership.source == .participantShared {
            try await cloudKit.leaveSharedHousehold(householdId: member.householdId)
        }

        await cloudKit.clearAllCachedZones(for: member.householdId)
    }

    private func upsertMembership(
        householdId: UUID,
        userId: String,
        displayName: String,
        role: Member.MemberRole,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> Member {
        let normalizedKey = DisplayNameValidator.normalizedKey(displayName)
        let allMembers = try await cloudKit.fetchMembers(householdId: householdId, scope: scope)
        if allMembers.contains(where: {
            $0.isActive &&
                $0.userId != userId &&
                DisplayNameValidator.normalizedKey($0.displayName) == normalizedKey
        }) {
            throw HouseholdError.displayNameAlreadyTaken
        }

        if let existing = try await cloudKit.fetchMemberByUserId(
            userId,
            householdId: householdId,
            scope: scope
        ) {
            let resolvedRole: Member.MemberRole = existing.role == .owner ? .owner : role
            let shouldUpdate =
                existing.displayName != displayName ||
                !existing.isActive ||
                existing.role != resolvedRole

            guard shouldUpdate else { return existing }

            _ = try await cloudKit.updateMemberState(
                memberId: existing.id,
                householdId: existing.householdId,
                newDisplayName: displayName,
                newRole: resolvedRole,
                isActive: true,
                colorHex: existing.colorHex,
                scope: scope
            )
            return Member(
                id: existing.id,
                householdId: existing.householdId,
                userId: existing.userId,
                displayName: displayName,
                role: resolvedRole,
                joinedAt: existing.joinedAt,
                isActive: true,
                colorHex: existing.colorHex
            )
        }

        let member = Member(
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: role,
            colorHex: MemberColorToken.randomHex()
        )
        _ = try await cloudKit.saveMember(member, scope: scope)
        return member
    }

    private func verifyParticipantSharedMembership(
        householdId: UUID,
        userId: String,
        expectedMember: Member? = nil
    ) async throws -> Member {
        let retryDelaysNanoseconds: [UInt64] = [0, 250_000_000, 750_000_000]
        var lastError: Error?

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            await cloudKit.setHouseholdScope(.participantShared)
            let verifiedMember: Member?
            do {
                verifiedMember = try await cloudKit.fetchMemberByUserId(
                    userId,
                    householdId: householdId,
                    scope: .participantShared
                )
            } catch {
                lastError = error
                if isParticipantSharedVerificationError(error) {
                    logJoinError(
                        stage: "memberVerify.retry",
                        householdId: householdId,
                        error: error
                    )
                    continue
                }
                logJoinError(stage: "memberVerify.fetch", householdId: householdId, error: error)
                throw debugJoinFailure(
                    prefix: "Shared membership verification failed",
                    error: error
                )
            }

            if let verifiedMember, verifiedMember.isActive {
                print(
                    "DEBUG: Join verification succeeded for household \(householdId) user \(userId) in participantShared scope."
                )
                return verifiedMember
            }

            lastError = HouseholdError.memberNotFound
        }

        if expectedMember != nil,
           lastError as? HouseholdError == .memberNotFound
        {
            let message = "Shared membership verification failed: Guest member write succeeded, but the shared Member record is still not visible after save."
            logJoinError(
                stage: "memberVerify.failed",
                householdId: householdId,
                error: HouseholdError.debugJoinFailure(message)
            )
            throw HouseholdError.debugJoinFailure(message)
        }

        let resolvedError = lastError ?? HouseholdError.sharedAccessNotEstablished
        logJoinError(
            stage: "memberVerify.failed",
            householdId: householdId,
            error: resolvedError
        )
        throw debugJoinFailure(
            prefix: "Shared membership verification failed",
            error: resolvedError
        )
    }

    private func isParticipantSharedVerificationError(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            return ckError.code == .zoneNotFound ||
                ckError.code == .permissionFailure ||
                ckError.code == .unknownItem
        }
        if let managerError = error as? CloudKitManager.CloudKitManagerError,
           case let .unknownError(underlying) = managerError
        {
            return isParticipantSharedVerificationError(underlying)
        }
        return false
    }

    private func logJoinError(stage: String, householdId: UUID? = nil, error: Error) {
        let householdComponent = householdId?.uuidString ?? "unknown"
        print(
            "HouseholdJoin: stage=\(stage) householdId=\(householdComponent) error=\(rawJoinErrorDescription(error))"
        )
    }

    private func debugJoinFailure(prefix: String, error: Error) -> HouseholdError {
        HouseholdError.debugJoinFailure(
            "\(prefix): \(rawJoinErrorDescription(error))"
        )
    }

    private func rawJoinErrorDescription(_ error: Error) -> String {
        let localized = error.localizedDescription
        let reflected = String(describing: error)
        var components: [String] = []

        if !localized.isEmpty {
            components.append(localized)
        }
        if reflected != localized {
            components.append(reflected)
        }

        if let ckError = error as? CKError {
            components.append("CKError.\(ckError.code)")

            if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] {
                components.append("retryAfter=\(retryAfter)")
            }
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
               !partialErrors.isEmpty
            {
                let partialDescriptions = partialErrors
                    .map { key, value in "\(key): \(rawJoinErrorDescription(value))" }
                    .sorted()
                    .joined(separator: "; ")
                components.append("partialErrors=\(partialDescriptions)")
            }
        }

        let filtered = components.filter { !$0.isEmpty }
        return filtered.joined(separator: " | ")
    }

    private func requiredMembershipDisplayName(from rawDisplayName: String) throws -> String {
        guard let validated = try? DisplayNameValidator.validate(rawDisplayName) else {
            throw HouseholdError.displayNameRequired
        }
        return validated
    }

    private func runCreateHouseholdPostflight(household: Household, userId: String) {
        _ = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }

            await cloudKit.migrateMemberColorsIfNeeded(householdId: household.id)

            do {
                try await validateOwnerMembershipBootstrap(
                    household: household,
                    userId: userId
                )
            } catch {
                self.error = error
                print("DEBUG: Owner membership postflight validation failed: \(error)")
            }
        }
    }

    private func validateOwnerMembershipBootstrap(
        household: Household,
        userId: String
    ) async throws {
        let retryBackoffNanoseconds: [UInt64] = [0, 250_000_000, 750_000_000]
        var lastError: Error?

        for (attempt, delay) in retryBackoffNanoseconds.enumerated() {
            if delay > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            let memberStore = MemberStore(householdId: household.id, modelContext: modelContext)
            memberStore.setSyncMode(syncMode)
            memberStore.setCloudContext(
                HouseholdSyncContextFactory.make(
                    household: household,
                    currentUserId: userId
                )
            )
            await memberStore.loadMembers()

            if let error = memberStore.error {
                lastError = error
            } else if let ownerMember = memberStore.members.first(where: {
                $0.userId == userId && $0.role == .owner && $0.isActive
            }) {
                updateCache(with: ownerMember)
                return
            } else {
                lastError = HouseholdError.memberNotFound
            }

            let isLastAttempt = attempt == retryBackoffNanoseconds.count - 1
            if isLastAttempt {
                throw lastError ?? HouseholdError.memberNotFound
            }
        }
    }

    private func prewarmJoinedHouseholdGraphIfNeeded(household: Household, userId: String) async {
        guard syncMode == .cloud else { return }

        let hydratedWithinBudget = await attemptInitialJoinHydrationWithinBudget(
            household: household,
            userId: userId
        )

        if !hydratedWithinBudget || pendingJoinStateMatches(householdId: household.id, userId: userId) {
            scheduleBackgroundJoinHydrationIfNeeded(
                household: household,
                userId: userId
            )
        }
    }

    private func attemptInitialJoinHydrationWithinBudget(
        household: Household,
        userId: String
    ) async -> Bool {
        do {
            return try await withJoinHydrationTimeout(
                nanoseconds: joinHydrationConfiguration.initialHydrationBudgetNanoseconds
            ) { [self] in
                await runJoinHydrationAttemptsUntilVisibleContent(
                    household: household,
                    userId: userId,
                    retryDelaysNanoseconds: joinHydrationConfiguration.initialRetryDelaysNanoseconds,
                    publishVisibleContentNotifications: true
                )
            }
        } catch JoinHydrationTimeoutError.timedOut {
            return false
        } catch {
            self.error = error
            return false
        }
    }

    private func scheduleBackgroundJoinHydrationIfNeeded(
        household: Household,
        userId: String
    ) {
        let shouldReplaceCurrentTask =
            joinHydrationTask == nil ||
            !pendingJoinStateMatches(householdId: household.id, userId: userId)

        guard shouldReplaceCurrentTask else { return }

        joinHydrationTask?.cancel()
        joinHydrationTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                joinHydrationTask = nil
            }

            await runBackgroundJoinHydrationLoop(
                household: household,
                userId: userId,
                retryDelaysNanoseconds: joinHydrationConfiguration.backgroundRetryDelaysNanoseconds
            )
        }
    }

    private func runBackgroundJoinHydrationLoop(
        household: Household,
        userId: String,
        retryDelaysNanoseconds: [UInt64]
    ) async {
        for delay in retryDelaysNanoseconds {
            guard pendingJoinStateMatches(householdId: household.id, userId: userId) ||
                currentHousehold?.id == household.id
            else {
                return
            }

            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: delay)
            }
            guard !_Concurrency.Task.isCancelled else { return }

            let snapshot = await performJoinedHouseholdHydrationPass(
                household: household,
                userId: userId,
                publishVisibleContentNotifications: true
            )

            if snapshot.hasVisibleSharedContent, snapshot.remoteMembershipConfirmed {
                return
            }
        }
    }

    private func runJoinHydrationAttemptsUntilVisibleContent(
        household: Household,
        userId: String,
        retryDelaysNanoseconds: [UInt64],
        publishVisibleContentNotifications: Bool
    ) async -> Bool {
        var attemptIndex = 0

        while !_Concurrency.Task.isCancelled {
            let delay = retryDelay(
                for: attemptIndex,
                from: retryDelaysNanoseconds
            )
            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: delay)
            }
            guard !_Concurrency.Task.isCancelled else { return false }

            let snapshot = await performJoinedHouseholdHydrationPass(
                household: household,
                userId: userId,
                publishVisibleContentNotifications: publishVisibleContentNotifications
            )
            if snapshot.hasVisibleSharedContent {
                return true
            }

            attemptIndex += 1
        }

        return false
    }

    private func retryDelay(
        for attemptIndex: Int,
        from retryDelaysNanoseconds: [UInt64]
    ) -> UInt64 {
        guard !retryDelaysNanoseconds.isEmpty else { return 0 }
        if attemptIndex < retryDelaysNanoseconds.count {
            return retryDelaysNanoseconds[attemptIndex]
        }
        return retryDelaysNanoseconds.last ?? 0
    }

    private func performJoinedHouseholdHydrationPass(
        household: Household,
        userId: String,
        publishVisibleContentNotifications: Bool
    ) async -> JoinedHouseholdHydrationSnapshot {
        do {
            let snapshot = try await runJoinedHouseholdHydrationPass(
                household: household,
                userId: userId
            )
            applyPendingJoinHydrationSnapshot(
                snapshot,
                householdId: household.id,
                userId: userId,
                publishVisibleContentNotifications: publishVisibleContentNotifications
            )
            return snapshot
        } catch {
            self.error = error
            let snapshot = cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: false
            )
            applyPendingJoinHydrationSnapshot(
                snapshot,
                householdId: household.id,
                userId: userId,
                publishVisibleContentNotifications: false
            )
            return snapshot
        }
    }

    private func runJoinedHouseholdHydrationPass(
        household: Household,
        userId: String
    ) async throws -> JoinedHouseholdHydrationSnapshot {
        if let joinedHouseholdPrewarmOverride {
            try await joinedHouseholdPrewarmOverride(household, userId, modelContext)
            let remoteMembershipConfirmed = try await confirmRemoteMembershipPresence(
                household: household,
                userId: userId
            )
            return cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: remoteMembershipConfirmed
            )
        }

        guard syncMode == .cloud, let modelContext else {
            return cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: false
            )
        }

        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(household.id)
        let shoppingStore = ShoppingListStore(householdId: household.id, modelContext: modelContext)
        let bundleStore = ShoppingBundleStore(householdId: household.id, modelContext: modelContext)
        let backlogStore = BacklogStore(householdId: household.id, modelContext: modelContext)

        guard let syncContext = HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: userId
        ) else {
            return cachedJoinHydrationSnapshot(
                householdId: household.id,
                userId: userId,
                remoteMembershipConfirmed: false
            )
        }

        let snapshot = try await householdRepository.loadCloudSnapshot(
            for: syncContext
        )

        let mergedMembers = mergeRemoteMembersWithLocalJoinFallback(
            snapshot.members,
            householdId: household.id,
            currentUserId: userId
        )
        updateCache(with: mergedMembers)

        taskStore.syncUnifiedWorkItemsToCache(snapshot.unifiedWorkItems)
        shoppingStore.syncToCache(snapshot.shoppingItems)
        bundleStore.syncToCache(
            snapshot.shoppingBundles,
            cloudBundleIDs: Set(snapshot.shoppingBundles.map(\.id))
        )
        backlogStore.syncToCache(
            categories: snapshot.backlogCategories,
            items: snapshot.backlogItems,
            cloudCategoryIDs: Set(snapshot.backlogCategories.map(\.id)),
            cloudItemIDs: Set(snapshot.backlogItems.map(\.id))
        )

        let remoteMembershipConfirmed = snapshot.hasActiveMembership(userId: userId)

        return cachedJoinHydrationSnapshot(
            householdId: household.id,
            userId: userId,
            remoteMembershipConfirmed: remoteMembershipConfirmed
        )
    }

    private func confirmRemoteMembershipPresence(
        household: Household,
        userId: String
    ) async throws -> Bool {
        guard let syncContext = HouseholdSyncContextFactory.make(
            household: household,
            currentUserId: userId
        ) else {
            return false
        }

        return try await householdRepository.hasActiveMembership(
            userId: userId,
            in: syncContext
        )
    }

    private func cachedJoinHydrationSnapshot(
        householdId: UUID,
        userId: String,
        remoteMembershipConfirmed: Bool
    ) -> JoinedHouseholdHydrationSnapshot {
        let activeMembers = fetchCachedMembers(householdId: householdId).filter(\.isActive)

        let taskCount: Int = fetchCachedWorkItems(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete" &&
                $0.statusRaw != WorkItem.Status.idea.rawValue
        }.count

        let ideaCount: Int = fetchCachedWorkItems(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete" &&
                $0.statusRaw == WorkItem.Status.idea.rawValue
        }.count

        let categoryCount: Int = fetchCachedBacklogCategories(householdId: householdId).count
        let shoppingItemCount: Int = fetchCachedShoppingItems(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete"
        }.count
        let bundleCount: Int = fetchCachedShoppingBundles(householdId: householdId).filter {
            $0.syncStatusRaw != "pendingDelete" &&
                $0.syncStatusRaw != "awaitingDeleteEcho"
        }.count

        return JoinedHouseholdHydrationSnapshot(
            activeMemberCount: activeMembers.count,
            currentUserHasCachedMembership: activeMembers.contains(where: { $0.userId == userId }),
            remoteMembershipConfirmed: remoteMembershipConfirmed,
            taskCount: taskCount,
            ideaCount: ideaCount,
            categoryCount: categoryCount,
            shoppingItemCount: shoppingItemCount,
            bundleCount: bundleCount
        )
    }

    private func remoteCloudRefreshSnapshot(
        userId: String,
        preferredHouseholdId: UUID?
    ) -> RemoteCloudRefreshSnapshot {
        let currentHouseholdId = currentHousehold?.id
        let observedHouseholdId = currentHouseholdId ?? preferredHouseholdId
        let hydrationSnapshot = observedHouseholdId.map { householdId in
            cachedJoinHydrationSnapshot(
                householdId: householdId,
                userId: userId,
                remoteMembershipConfirmed: isValidCachedMembershipForRecoveredHousehold(
                    householdId: householdId,
                    userId: userId
                )
            )
        }

        return RemoteCloudRefreshSnapshot(
            currentHouseholdId: currentHouseholdId,
            observedHouseholdId: observedHouseholdId,
            householdName: currentHousehold?.name,
            householdIconSymbol: currentHousehold?.iconSymbol,
            hydrationSnapshot: hydrationSnapshot
        )
    }

    private func publishRemoteCloudRefreshNotifications(
        source: String,
        remoteVisibleContentDiff: RemoteVisibleContentDiff? = nil,
        direction: HouseholdSyncDirection = .unknown,
        pushReceivedAt: Date? = nil,
        cacheUpdatedAt: Date? = nil
    ) {
        let userInfo = remoteSyncNotificationUserInfo(
            source: source,
            diff: remoteVisibleContentDiff,
            direction: direction,
            pushReceivedAt: pushReceivedAt,
            cacheUpdatedAt: cacheUpdatedAt
        )
        NotificationCenter.default.post(
            name: .householdDataDidChange,
            object: source,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: .taskBoardDataDidChange,
            object: source,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: .shoppingListDataDidChange,
            object: source,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: .backlogDataDidChange,
            object: source,
            userInfo: userInfo
        )
    }

    private func remoteSyncNotificationUserInfo(
        source: String,
        diff: RemoteVisibleContentDiff?,
        direction: HouseholdSyncDirection,
        pushReceivedAt: Date?,
        cacheUpdatedAt: Date?
    ) -> [AnyHashable: Any]? {
        guard source == "remotePush" else { return nil }

        var userInfo: [AnyHashable: Any] = [
            RemoteSyncNotificationPayloadKey.batchToken: UUID().uuidString,
            RemoteSyncNotificationPayloadKey.shoppingChangedItemIDs: Array(
                diff?.changedShoppingItemIDs.map(\.uuidString) ?? []
            ),
            RemoteSyncNotificationPayloadKey.workItemChangedIDs: Array(
                diff?.changedWorkItemIDs.map(\.uuidString) ?? []
            ),
            RemoteSyncNotificationPayloadKey.backlogChangedCategoryIDs: Array(
                diff?.changedBacklogCategoryIDs.map(\.uuidString) ?? []
            ),
            RemoteSyncNotificationPayloadKey.direction: direction.rawValue,
        ]

        if let pushReceivedAt {
            userInfo[RemoteSyncNotificationPayloadKey.pushReceivedAt] = pushReceivedAt.timeIntervalSince1970
        }
        if let cacheUpdatedAt {
            userInfo[RemoteSyncNotificationPayloadKey.cacheUpdatedAt] = cacheUpdatedAt.timeIntervalSince1970
        }

        return userInfo
    }

    private func shoppingItemTitleSnapshot(householdId: UUID) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: fetchCachedShoppingItems(householdId: householdId)
                .filter { $0.syncStatusRaw != "pendingDelete" }
                .map { ($0.id, $0.title) }
        )
    }

    private func remoteVisibleContentSnapshot(householdId: UUID) -> RemoteVisibleContentSnapshot {
        func isConfirmedRemoteState(_ syncStatusRaw: String) -> Bool {
            syncStatusRaw == "synced"
        }

        let membersByID = Dictionary(
            uniqueKeysWithValues: fetchCachedMemberRecords(householdId: householdId)
                .filter { isConfirmedRemoteState($0.syncStatusRaw) }
                .map {
                    (
                        $0.id,
                        RemoteMemberState(
                            userId: $0.userId,
                            displayName: $0.displayName,
                            role: Member.MemberRole(rawValue: $0.roleRaw) ?? .member,
                            isActive: $0.isActive
                        )
                    )
                }
        )
        let shoppingItemsByID = Dictionary(
            uniqueKeysWithValues: fetchCachedShoppingItems(householdId: householdId)
                .filter { isConfirmedRemoteState($0.syncStatusRaw) }
                .map {
                    (
                        $0.id,
                        RemoteShoppingItemState(
                            title: $0.title,
                            isBought: $0.isBought,
                            boughtAt: $0.boughtAt,
                            restockCount: $0.restockCount,
                            sortOrder: $0.sortOrder,
                            updatedAt: $0.updatedAt
                        )
                    )
                }
        )
        let shoppingBundlesByID = Dictionary(
            uniqueKeysWithValues: fetchCachedShoppingBundles(householdId: householdId)
                .filter { isConfirmedRemoteState($0.syncStatusRaw) }
                .map {
                    (
                        $0.id,
                        RemoteShoppingBundleState(
                            name: $0.name,
                            updatedAt: $0.updatedAt
                        )
                    )
                }
        )
        let visibleCachedWorkItems = Array(
            WorkItemCacheStoreSupport.canonicalCachedWorkItemsByLogicalItemID(
                fetchCachedWorkItems(householdId: householdId)
                    .filter { isConfirmedRemoteState($0.syncStatusRaw) }
            ).values
        )
        let workItemsByID = Dictionary(
            uniqueKeysWithValues: visibleCachedWorkItems.map {
                (
                    $0.id,
                    RemoteWorkItemState(
                        logicalItemID: $0.logicalItemID,
                        title: $0.title,
                        status: WorkItem.Status(rawValue: $0.statusRaw) ?? .idea,
                        assigneeId: $0.assigneeId,
                        assigneeIds: $0.toWorkItem().assigneeIds,
                        completedAt: $0.completedAt,
                        completedById: $0.completedById,
                        order: $0.order,
                        updatedAt: $0.updatedAt
                    )
                )
            }
        )
        let backlogCategoriesByID = Dictionary(
            uniqueKeysWithValues: fetchCachedBacklogCategories(householdId: householdId)
                .filter { isConfirmedRemoteState($0.syncStatusRaw) }
                .map {
                    (
                        $0.id,
                        RemoteBacklogCategoryState(
                            title: $0.title,
                            sortOrder: $0.sortOrder,
                            updatedAt: $0.updatedAt
                        )
                    )
                }
        )

        return RemoteVisibleContentSnapshot(
            membersByID: membersByID,
            shoppingItemsByID: shoppingItemsByID,
            shoppingBundlesByID: shoppingBundlesByID,
            workItemsByID: workItemsByID,
            backlogCategoriesByID: backlogCategoriesByID
        )
    }

    private func resolvedCelebrationMemberName(
        userId: String,
        householdId: UUID
    ) -> String {
        fetchCachedMembers(householdId: householdId)
            .first(where: { $0.userId == userId && $0.isActive })?
            .displayName ?? "A household member"
    }

    private func sharedTaskCelebrationAlert(
        before: RemoteVisibleContentSnapshot,
        after: RemoteVisibleContentSnapshot,
        diff: RemoteVisibleContentDiff,
        currentUserId: String,
        householdId: UUID
    ) -> (title: String, body: String)? {
        let newlyCompleted = diff.changedWorkItemIDs.compactMap { id -> RemoteWorkItemState? in
            guard let previous = before.workItemsByID[id],
                  let current = after.workItemsByID[id],
                  previous.status != .done,
                  current.status == .done,
                  let completedById = current.completedById,
                  completedById != currentUserId
            else {
                return nil
            }
            return current
        }

        guard let mostRecentCompletion = newlyCompleted.max(by: { $0.updatedAt < $1.updatedAt }),
              let completedById = mostRecentCompletion.completedById
        else {
            return nil
        }

        let memberName = resolvedCelebrationMemberName(
            userId: completedById,
            householdId: householdId
        )

        if before.nextWorkItemCount > 0, after.nextWorkItemCount == 0 {
            return (
                title: "💙 \(memberName) is on fire!",
                body: "Cleared all tasks! 🏡"
            )
        }

        return (
            title: "💙 \(memberName) is on fire!",
            body: "\(mostRecentCompletion.title) — done!"
        )
    }

    private func describeRemoteCloudRefreshSnapshot(_ snapshot: RemoteCloudRefreshSnapshot) -> String {
        guard let hydrationSnapshot = snapshot.hydrationSnapshot else {
            return "current=nil observed=\(snapshot.observedHouseholdId?.uuidString ?? "none") data=empty"
        }

        return [
            "current=\(snapshot.currentHouseholdId?.uuidString ?? "none")",
            "observed=\(snapshot.observedHouseholdId?.uuidString ?? "none")",
            "name=\(snapshot.householdName ?? "none")",
            "icon=\(snapshot.householdIconSymbol ?? "none")",
            "members=\(hydrationSnapshot.activeMemberCount)",
            "currentUser=\(hydrationSnapshot.currentUserHasCachedMembership)",
            "tasks=\(hydrationSnapshot.taskCount)",
            "ideas=\(hydrationSnapshot.ideaCount)",
            "categories=\(hydrationSnapshot.categoryCount)",
            "shopping=\(hydrationSnapshot.shoppingItemCount)",
            "bundles=\(hydrationSnapshot.bundleCount)",
        ].joined(separator: " ")
    }

    private func describeBackgroundFetchResult(_ result: UIBackgroundFetchResult) -> String {
        switch result {
        case .newData:
            "newData"
        case .noData:
            "noData"
        case .failed:
            "failed"
        @unknown default:
            "unknown"
        }
    }

    private func applyPendingJoinHydrationSnapshot(
        _ snapshot: JoinedHouseholdHydrationSnapshot,
        householdId: UUID,
        userId: String,
        publishVisibleContentNotifications: Bool
    ) {
        guard pendingJoinStateMatches(householdId: householdId, userId: userId) else { return }
        guard var pendingJoinState else { return }

        pendingJoinState.hasCompletedHydrationPass = true
        if snapshot.remoteMembershipConfirmed {
            pendingJoinState.hasConfirmedRemoteMembership = true
            clearRecoveredJoinDiagnostics()
        }

        if publishVisibleContentNotifications,
           snapshot.hasVisibleSharedContent,
           !pendingJoinState.hasPublishedVisibleContentNotifications
        {
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: "local")
            NotificationCenter.default.post(name: .shoppingListDataDidChange, object: "local")
            NotificationCenter.default.post(name: .backlogDataDidChange, object: "local")
            pendingJoinState.hasPublishedVisibleContentNotifications = true
        }

        if pendingJoinState.hasCompletedHydrationPass, pendingJoinState.hasConfirmedRemoteMembership {
            self.pendingJoinState = nil
        } else {
            self.pendingJoinState = pendingJoinState
        }
    }

    private func withJoinHydrationTimeout<T>(
        nanoseconds: UInt64,
        operation: @escaping @MainActor () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: nanoseconds)
                throw JoinHydrationTimeoutError.timedOut
            }

            guard let result = try await group.next() else {
                throw JoinHydrationTimeoutError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    func resolveLeaveBehavior(for member: Member, activeMembers: [Member]) -> LeaveResolution {
        guard member.role == .owner else {
            return .deactivateMembership
        }

        let otherActiveMembers = activeMembers.filter { $0.id != member.id }
        let hasOtherActiveOwners = otherActiveMembers.contains(where: { $0.role == .owner })

        if activeMembers.count <= 1 {
            return .deleteHousehold
        }
        if !otherActiveMembers.isEmpty, !hasOtherActiveOwners {
            return .requireTransfer
        }
        return .deactivateMembership
    }

    private func isRecordMissingError(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            return ckError.code == .unknownItem
        }
        if let managerError = error as? CloudKitManager.CloudKitManagerError,
           case let .unknownError(underlying) = managerError
        {
            return isRecordMissingError(underlying)
        }
        return false
    }

    func clearCurrentHousehold() {
        joinHydrationTask?.cancel()
        joinHydrationTask = nil
        pendingJoinState = nil
        lastRemoteCloudRefreshSnapshot = nil
        currentHousehold = nil
        _ = _Concurrency.Task { [cloudKit] in
            await cloudKit.setHouseholdScope(.participantShared)
        }
    }

    func resolveMembershipDisplayNameLocally(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> String? {
        var householdIds: [UUID] = []

        if let currentHouseholdId = currentHousehold?.id {
            householdIds.append(currentHouseholdId)
        }

        if let preferredHouseholdId,
           !householdIds.contains(preferredHouseholdId)
        {
            householdIds.append(preferredHouseholdId)
        }

        for cachedHousehold in fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ) where !householdIds.contains(cachedHousehold.id) {
            householdIds.append(cachedHousehold.id)
        }

        for householdId in householdIds {
            if let member = fetchCachedMembers(householdId: householdId).first(where: {
                $0.userId == userId && $0.isActive
            }) {
                return member.displayName
            }
        }

        return nil
    }

    func isRecoverySuppressed(for householdId: UUID) -> Bool {
        let suppressions = loadSuppressedRecoveries(cleaningExpired: true)
        return suppressions[householdId.uuidString] != nil || hasPendingExitOperation(for: householdId)
    }

    func prepareForSetupResolution(key: String) {
        guard !setupResolutionState.matches(key: key)
            || setupResolutionState.resolvedHouseholdCount != nil
        else {
            return
        }
        setupResolutionState = .loading(key: key)
    }

    func completeSetupResolution(key: String, householdCount: Int) {
        setupResolutionState = .resolved(
            key: key,
            householdCount: normalizedSingleHouseholdCount(householdCount)
        )
    }

    func resetSetupResolution() {
        setupResolutionState = .idle
    }

    func cachedRecoverableHouseholdCount(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Int {
        normalizedSingleHouseholdCount(fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        ).count)
    }

    func hasTrustedLocalHouseholdContext(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) -> Bool {
        currentHousehold != nil ||
            fetchCachedHousehold(userId: userId, preferredHouseholdId: preferredHouseholdId) != nil
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedHousehold(
        userId: String,
        preferredHouseholdId: UUID?
    ) -> CachedHousehold? {
        let cachedHouseholds = fetchRecoverableCachedHouseholds(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
        guard !cachedHouseholds.isEmpty else { return nil }

        if let preferredHouseholdId,
           let preferredMatch = cachedHouseholds.first(where: { $0.id == preferredHouseholdId })
        {
            return preferredMatch
        }

        if let ownerMatch = cachedHouseholds.first(where: { $0.ownerId == userId }) {
            return ownerMatch
        }

        return cachedHouseholds.first
    }

    private func fetchCachedMemberRecords(householdId: UUID) -> [CachedMember] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.joinedAt)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached member records error: \(error)")
            return []
        }
    }

    private func fetchCachedMembers(householdId: UUID) -> [Member] {
        fetchCachedMemberRecords(householdId: householdId).map { $0.toMember() }
    }

    private func isValidCachedMembershipForRecoveredHousehold(
        householdId: UUID,
        userId: String
    ) -> Bool {
        guard syncMode == .cloud else { return true }
        return fetchCachedMembers(householdId: householdId).contains {
            $0.userId == userId && $0.isActive
        }
    }

    private func resolvedActiveMembersForExit(
        householdId: UUID,
        activeMembersSnapshot: [Member]?
    ) -> [Member] {
        let source = activeMembersSnapshot ?? fetchCachedMembers(householdId: householdId)
        return source.filter(\.isActive)
    }

    private func fetchRecoverableCachedHouseholds(
        userId _: String,
        preferredHouseholdId _: UUID?
    ) -> [CachedHousehold] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedHousehold>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            let cachedHouseholds = try context.fetch(descriptor).filter { !isRecoverySuppressed(for: $0.id) }
            if cachedHouseholds.count > 1 {
                print("DEBUG: Multiple recoverable households found locally; enforcing single-household mode.")
            }
            return cachedHouseholds
        } catch {
            print("Fetch error: \(error)")
            return []
        }
    }

    private var shouldSkipRemoteSingleHouseholdDiscoveryForCreate: Bool {
        setupResolutionState.resolvedHouseholdCount == 0
    }

    private func ensureUserCanStartSingleHouseholdLocally(userId: String) throws {
        if let household = currentHousehold,
           !isRecoverySuppressed(for: household.id)
        {
            throw HouseholdError.alreadyInHousehold
        }

        if fetchCachedHousehold(userId: userId, preferredHouseholdId: nil) != nil {
            throw HouseholdError.alreadyInHousehold
        }
    }

    private func ensureUserCanStartSingleHouseholdRemotely(userId: String) async throws {
        await replayPendingExitOperationsIfNeeded()
        await cloudKit.ensureReady()
        try await cloudKit.checkAvailability()

        let activeMemberships = try await fetchScopedActiveMemberships(userId: userId)
        if !activeMemberships.isEmpty {
            throw HouseholdError.alreadyInHousehold
        }
    }

    private func ensureUserCanStartSingleHousehold(userId: String) async throws {
        try ensureUserCanStartSingleHouseholdLocally(userId: userId)

        guard syncMode == .cloud else { return }
        try await ensureUserCanStartSingleHouseholdRemotely(userId: userId)
    }

    func hasPendingJoinProtection(for householdId: UUID?, userId: String?) -> Bool {
        guard let householdId, let userId else { return false }
        return shouldProtectPendingJoin(householdId: householdId, userId: userId)
    }

    func forceCloudSyncDebug(userId: String) async {
        guard syncMode == .cloud, let household = currentHousehold else { return }

        isLoading = true
        defer { isLoading = false }

        await refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: household.id
        )

        let refreshedHousehold = currentHousehold ?? household
        _ = await performJoinedHouseholdHydrationPass(
            household: refreshedHousehold,
            userId: userId,
            publishVisibleContentNotifications: true
        )
        publishRemoteCloudRefreshNotifications(source: "forceCloudSync")
    }

    func runRemoteSyncPass(
        userId: String?,
        preferredHouseholdId: UUID?,
        reason: HouseholdSyncReason,
        context: RemoteCloudChangeContext = .unknown
    ) async -> HouseholdSyncPassResult {
        await HouseholdRemoteSyncExecutor(dataSource: self).execute(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId,
            reason: reason,
            context: context
        )
    }

    func handleRemoteCloudChange(
        userId: String?,
        preferredHouseholdId: UUID?,
        context: RemoteCloudChangeContext = .unknown
    ) async -> UIBackgroundFetchResult {
        let result = await runRemoteSyncPass(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId,
            reason: .remotePush(context: HouseholdSyncRemoteContext(from: context)),
            context: context
        )

        if result.fetchResult == .newData {
            let contentDiff = remoteVisibleContentDiff(from: result.events)
            publishRemoteCloudRefreshNotifications(
                source: "remotePush",
                remoteVisibleContentDiff: contentDiff,
                direction: result.diagnostics.direction,
                pushReceivedAt: context.receivedAt == .distantPast ? nil : context.receivedAt,
                cacheUpdatedAt: result.diagnostics.syncFinishedAt
            )
            deliverLegacySyncPresentation(for: result.events)
        }

        return result.fetchResult
    }

    func refreshCurrentHouseholdForRemoteCloudChange(
        userId: String,
        preferredHouseholdId: UUID?
    ) async throws -> JoinedHouseholdHydrationSnapshot? {
        await refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )

        guard let household = currentHousehold else {
            return nil
        }

        let hydrationSnapshot = try await runJoinedHouseholdHydrationPass(
            household: household,
            userId: userId
        )
        applyPendingJoinHydrationSnapshot(
            hydrationSnapshot,
            householdId: household.id,
            userId: userId,
            publishVisibleContentNotifications: false
        )
        print(
            "[RemoteSync] Hydration pass finished for household \(household.id). members=\(hydrationSnapshot.activeMemberCount) tasks=\(hydrationSnapshot.taskCount) ideas=\(hydrationSnapshot.ideaCount) shopping=\(hydrationSnapshot.shoppingItemCount) bundles=\(hydrationSnapshot.bundleCount)"
        )
        return hydrationSnapshot
    }

    func processRemoteVisibleContentChangeIfNeeded(
        beforeSnapshot: RemoteCloudRefreshSnapshot,
        beforeVisibleContentSnapshot: RemoteVisibleContentSnapshot?,
        userId: String,
        context: RemoteCloudChangeContext
    ) async -> RemoteVisibleContentResolution? {
        guard let household = currentHousehold,
              beforeSnapshot.observedHouseholdId == household.id,
              let beforeVisibleContentSnapshot
        else {
            return nil
        }

        return await resolveRemoteVisibleContentChange(
            household: household,
            beforeVisibleContentSnapshot: beforeVisibleContentSnapshot,
            userId: userId,
            context: context
        )
    }

    private func resolveRemoteVisibleContentChange(
        household: Household,
        beforeVisibleContentSnapshot: RemoteVisibleContentSnapshot,
        userId: String,
        context: RemoteCloudChangeContext
    ) async -> RemoteVisibleContentResolution {
        var afterVisibleContentSnapshot = remoteVisibleContentSnapshot(householdId: household.id)
        var contentDiff = afterVisibleContentSnapshot.diff(from: beforeVisibleContentSnapshot)
        var followUpPassCount = 0

        let followUpRetryDelays = sharedFollowUpRetryDelays(
            household: household,
            userId: userId,
            context: context
        )

        guard !followUpRetryDelays.isEmpty else {
            return RemoteVisibleContentResolution(
                snapshot: afterVisibleContentSnapshot,
                diff: contentDiff,
                followUpPassCount: followUpPassCount,
                cacheUpdatedAt: Date()
            )
        }

        for delay in followUpRetryDelays {
            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: delay)
            }
            if let retryHydrationSnapshot = try? await runJoinedHouseholdHydrationPass(
                household: household,
                userId: userId
            ) {
                applyPendingJoinHydrationSnapshot(
                    retryHydrationSnapshot,
                    householdId: household.id,
                    userId: userId,
                    publishVisibleContentNotifications: false
                )
            }

            let candidateSnapshot = remoteVisibleContentSnapshot(householdId: household.id)
            let previousSnapshot = afterVisibleContentSnapshot
            afterVisibleContentSnapshot = candidateSnapshot
            contentDiff = candidateSnapshot.diff(from: beforeVisibleContentSnapshot)
            followUpPassCount += 1

            if candidateSnapshot != previousSnapshot {
                print(
                    "[RemoteSync] Shared follow-up pass \(followUpPassCount) captured additional changes for household \(household.id)."
                )
            } else {
                print(
                    "[RemoteSync] Shared follow-up pass \(followUpPassCount) found no new changes for household \(household.id)."
                )
            }
        }

        return RemoteVisibleContentResolution(
            snapshot: afterVisibleContentSnapshot,
            diff: contentDiff,
            followUpPassCount: followUpPassCount,
            cacheUpdatedAt: Date()
        )
    }

    func emptyHouseholdSyncPassResult(
        reason: HouseholdSyncReason,
        direction: HouseholdSyncDirection,
        triggerReceivedAt: Date,
        syncStartedAt: Date,
        syncFinishedAt: Date,
        fetchResult: UIBackgroundFetchResult
    ) -> HouseholdSyncPassResult {
        let diagnostics = HouseholdSyncDiagnostics(
            batchID: UUID(),
            reason: reason,
            direction: direction,
            triggerReceivedAt: triggerReceivedAt,
            syncStartedAt: syncStartedAt,
            syncFinishedAt: syncFinishedAt,
            changedDomains: [],
            changedIDsByDomain: [:],
            activeMemberCount: currentHousehold.map { fetchCachedMembers(householdId: $0.id).filter(\.isActive).count }
        )

        return HouseholdSyncPassResult(
            fetchResult: fetchResult,
            events: [],
            diagnostics: diagnostics
        )
    }

    func makeRemoteSyncBaseline(
        userId: String,
        preferredHouseholdId: UUID?,
        context: RemoteCloudChangeContext
    ) -> RemoteSyncBaseline {
        let beforeSnapshot = remoteCloudRefreshSnapshot(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
        return RemoteSyncBaseline(
            beforeSnapshot: beforeSnapshot,
            beforeVisibleContentSnapshot: beforeSnapshot.observedHouseholdId.map(remoteVisibleContentSnapshot),
            direction: remoteSyncDirection(
                household: currentHousehold,
                userId: userId,
                context: context
            )
        )
    }

    func buildRemoteSyncPassResult(
        userId: String,
        preferredHouseholdId: UUID?,
        context: RemoteSyncPassBuildContext
    ) -> HouseholdSyncPassResult {
        let afterSnapshot = remoteCloudRefreshSnapshot(
            userId: userId,
            preferredHouseholdId: preferredHouseholdId
        )
        let refreshedSnapshot = RemoteCloudRefreshSnapshot(
            currentHouseholdId: afterSnapshot.currentHouseholdId,
            observedHouseholdId: afterSnapshot.observedHouseholdId,
            householdName: afterSnapshot.householdName,
            householdIconSymbol: afterSnapshot.householdIconSymbol,
            hydrationSnapshot: context.refreshedHydrationSnapshot ?? afterSnapshot.hydrationSnapshot
        )
        let didVisibleContentChange = context.visibleContentResolution?.diff.hasAnyChange == true
        let didMetadataOrHydrationChange = lastRemoteCloudRefreshSnapshot != refreshedSnapshot
        let didChange = didVisibleContentChange || didMetadataOrHydrationChange
        lastRemoteCloudRefreshSnapshot = refreshedSnapshot

        let beforeVisibleSnapshot =
            context.baseline.beforeVisibleContentSnapshot ?? emptyRemoteVisibleContentSnapshot
        let taskDiff = context.visibleContentResolution?.snapshot.taskContentDiff(from: beforeVisibleSnapshot)
        let ideaDiff = context.visibleContentResolution?.snapshot.ideaContentDiff(from: beforeVisibleSnapshot)
        let batchID = UUID()
        let syncFinishedAt = context.visibleContentResolution?.cacheUpdatedAt ?? Date()
        let events = makeHouseholdSyncEvents(
            batchID: batchID,
            reason: context.reason,
            direction: context.baseline.direction,
            beforeSnapshot: context.baseline.beforeSnapshot,
            afterSnapshot: refreshedSnapshot,
            contentDiff: context.visibleContentResolution?.diff,
            taskDiff: taskDiff,
            ideaDiff: ideaDiff
        )
        let diagnostics = HouseholdSyncDiagnostics(
            batchID: batchID,
            reason: context.reason,
            direction: context.baseline.direction,
            triggerReceivedAt: context.triggerReceivedAt,
            syncStartedAt: context.refreshStartedAt,
            syncFinishedAt: syncFinishedAt,
            changedDomains: Set(events.flatMap(\.domains)),
            changedIDsByDomain: changedIDsByDomain(for: events),
            activeMemberCount: activeMemberCount(
                from: context.visibleContentResolution?.snapshot,
                fallbackHydrationSnapshot: refreshedSnapshot.hydrationSnapshot
            )
        )

        logRemoteSyncTelemetry(
            direction: context.baseline.direction,
            context: context.cloudContext,
            refreshStartedAt: context.refreshStartedAt,
            cacheUpdatedAt: syncFinishedAt,
            followUpPassCount: context.visibleContentResolution?.followUpPassCount ?? 0,
            didChange: didChange
        )

        let fetchResult: UIBackgroundFetchResult = didChange ? .newData : .noData
        print(
            "[RemoteSync] Background household refresh completed with result=\(describeBackgroundFetchResult(fetchResult)). after=\(describeRemoteCloudRefreshSnapshot(afterSnapshot))"
        )

        return HouseholdSyncPassResult(
            fetchResult: fetchResult,
            events: events,
            diagnostics: diagnostics
        )
    }

    private var emptyRemoteVisibleContentSnapshot: RemoteVisibleContentSnapshot {
        RemoteVisibleContentSnapshot(
            shoppingItemsByID: [:],
            shoppingBundlesByID: [:],
            workItemsByID: [:],
            backlogCategoriesByID: [:]
        )
    }

    private func makeHouseholdSyncEvents(
        batchID: UUID,
        reason: HouseholdSyncReason,
        direction: HouseholdSyncDirection,
        beforeSnapshot: RemoteCloudRefreshSnapshot,
        afterSnapshot: RemoteCloudRefreshSnapshot,
        contentDiff: RemoteVisibleContentDiff?,
        taskDiff: RemoteTaskVisibleContentDiff?,
        ideaDiff: RemoteIdeaVisibleContentDiff?
    ) -> [HouseholdSyncEvent] {
        guard let householdId = afterSnapshot.observedHouseholdId ?? beforeSnapshot.observedHouseholdId else {
            return []
        }

        let source = HouseholdSyncEventSource(reason: reason)
        let timestamp = Date()
        var events: [HouseholdSyncEvent] = []

        if let householdEvent = makeHouseholdMetadataSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot
        ) {
            events.append(householdEvent)
        }

        if let memberEvent = makeMemberSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            contentDiff: contentDiff
        ) {
            events.append(memberEvent)
        }

        events.append(
            contentsOf: makeShoppingSyncEvents(
                householdId: householdId,
                batchID: batchID,
                source: source,
                reason: reason,
                timestamp: timestamp,
                direction: direction,
                contentDiff: contentDiff
            )
        )

        if let taskEvent = makeTaskSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            taskDiff: taskDiff
        ) {
            events.append(taskEvent)
        }

        if let ideaEvent = makeIdeaSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            ideaDiff: ideaDiff
        ) {
            events.append(ideaEvent)
        }

        if let backlogEvent = makeBacklogCategorySyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            contentDiff: contentDiff
        ) {
            events.append(backlogEvent)
        }

        return events
    }

    private func makeHouseholdMetadataSyncEvent(
        householdId: UUID,
        batchID: UUID,
        source: HouseholdSyncEventSource,
        reason: HouseholdSyncReason,
        timestamp: Date,
        direction: HouseholdSyncDirection,
        beforeSnapshot: RemoteCloudRefreshSnapshot,
        afterSnapshot: RemoteCloudRefreshSnapshot
    ) -> HouseholdSyncEvent? {
        guard beforeSnapshot.householdName != afterSnapshot.householdName ||
            beforeSnapshot.householdIconSymbol != afterSnapshot.householdIconSymbol
        else {
            return nil
        }

        return HouseholdSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            kind: .householdMetadataChanged
        )
    }

    private func makeMemberSyncEvent(
        householdId: UUID,
        batchID: UUID,
        source: HouseholdSyncEventSource,
        reason: HouseholdSyncReason,
        timestamp: Date,
        direction: HouseholdSyncDirection,
        contentDiff: RemoteVisibleContentDiff?
    ) -> HouseholdSyncEvent? {
        guard let contentDiff else { return nil }
        let changedIDs = contentDiff.addedMemberIDs
            .union(contentDiff.changedMemberIDs)
            .union(contentDiff.removedMemberIDs)
        guard !changedIDs.isEmpty else { return nil }

        return HouseholdSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            kind: .membersChanged(ids: changedIDs)
        )
    }

    private func makeShoppingSyncEvents(
        householdId: UUID,
        batchID: UUID,
        source: HouseholdSyncEventSource,
        reason: HouseholdSyncReason,
        timestamp: Date,
        direction: HouseholdSyncDirection,
        contentDiff: RemoteVisibleContentDiff?
    ) -> [HouseholdSyncEvent] {
        guard let contentDiff else { return [] }
        var events: [HouseholdSyncEvent] = []

        if !contentDiff.addedShoppingItemIDs.isEmpty {
            events.append(
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchID,
                    source: source,
                    reason: reason,
                    timestamp: timestamp,
                    direction: direction,
                    kind: .shoppingAdded(
                        ids: contentDiff.addedShoppingItemIDs,
                        titles: contentDiff.addedShoppingTitles
                    )
                )
            )
        }

        let updatedBundleIDs = contentDiff.changedShoppingBundleIDs.union(contentDiff.addedShoppingBundleIDs)
        if !contentDiff.changedShoppingItemIDs.isEmpty || !updatedBundleIDs.isEmpty {
            events.append(
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchID,
                    source: source,
                    reason: reason,
                    timestamp: timestamp,
                    direction: direction,
                    kind: .shoppingUpdated(
                        itemIDs: contentDiff.changedShoppingItemIDs,
                        bundleIDs: updatedBundleIDs
                    )
                )
            )
        }

        if !contentDiff.removedShoppingItemIDs.isEmpty || !contentDiff.removedShoppingBundleIDs.isEmpty {
            events.append(
                HouseholdSyncEvent(
                    householdId: householdId,
                    batchID: batchID,
                    source: source,
                    reason: reason,
                    timestamp: timestamp,
                    direction: direction,
                    kind: .shoppingRemoved(
                        itemIDs: contentDiff.removedShoppingItemIDs,
                        bundleIDs: contentDiff.removedShoppingBundleIDs
                    )
                )
            )
        }

        return events
    }

    private func makeTaskSyncEvent(
        householdId: UUID,
        batchID: UUID,
        source: HouseholdSyncEventSource,
        reason: HouseholdSyncReason,
        timestamp: Date,
        direction: HouseholdSyncDirection,
        taskDiff: RemoteTaskVisibleContentDiff?
    ) -> HouseholdSyncEvent? {
        guard let taskDiff, taskDiff.hasAnyChange else { return nil }
        return HouseholdSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            kind: .tasksChanged(
                addedIDs: taskDiff.addedTaskIDs,
                changedIDs: taskDiff.changedTaskIDs,
                removedIDs: taskDiff.removedTaskIDs
            )
        )
    }

    private func makeIdeaSyncEvent(
        householdId: UUID,
        batchID: UUID,
        source: HouseholdSyncEventSource,
        reason: HouseholdSyncReason,
        timestamp: Date,
        direction: HouseholdSyncDirection,
        ideaDiff: RemoteIdeaVisibleContentDiff?
    ) -> HouseholdSyncEvent? {
        guard let ideaDiff, ideaDiff.hasAnyChange else { return nil }
        return HouseholdSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            kind: .ideasChanged(
                addedIDs: ideaDiff.addedIdeaIDs,
                changedIDs: ideaDiff.changedIdeaIDs,
                removedIDs: ideaDiff.removedIdeaIDs
            )
        )
    }

    private func makeBacklogCategorySyncEvent(
        householdId: UUID,
        batchID: UUID,
        source: HouseholdSyncEventSource,
        reason: HouseholdSyncReason,
        timestamp: Date,
        direction: HouseholdSyncDirection,
        contentDiff: RemoteVisibleContentDiff?
    ) -> HouseholdSyncEvent? {
        guard let contentDiff else { return nil }
        guard !contentDiff.addedBacklogCategoryIDs.isEmpty ||
            !contentDiff.changedBacklogCategoryIDs.isEmpty ||
            !contentDiff.removedBacklogCategoryIDs.isEmpty
        else {
            return nil
        }

        return HouseholdSyncEvent(
            householdId: householdId,
            batchID: batchID,
            source: source,
            reason: reason,
            timestamp: timestamp,
            direction: direction,
            kind: .backlogCategoriesChanged(
                addedIDs: contentDiff.addedBacklogCategoryIDs,
                changedIDs: contentDiff.changedBacklogCategoryIDs,
                removedIDs: contentDiff.removedBacklogCategoryIDs
            )
        )
    }

    private func changedIDsByDomain(
        for events: [HouseholdSyncEvent]
    ) -> [HouseholdSyncChangedDomain: Set<UUID>] {
        events.reduce(into: [HouseholdSyncChangedDomain: Set<UUID>]()) { partialResult, event in
            switch event.kind {
            case .householdMetadataChanged:
                partialResult[.household, default: []].insert(event.householdId)
            case let .membersChanged(ids):
                partialResult[.members, default: []].formUnion(ids)
            case let .shoppingAdded(ids, _):
                partialResult[.shopping, default: []].formUnion(ids)
            case let .shoppingUpdated(itemIDs, bundleIDs):
                partialResult[.shopping, default: []].formUnion(itemIDs)
                partialResult[.shopping, default: []].formUnion(bundleIDs)
            case let .shoppingRemoved(itemIDs, bundleIDs):
                partialResult[.shopping, default: []].formUnion(itemIDs)
                partialResult[.shopping, default: []].formUnion(bundleIDs)
            case let .tasksChanged(addedIDs, changedIDs, removedIDs):
                partialResult[.tasks, default: []].formUnion(addedIDs)
                partialResult[.tasks, default: []].formUnion(changedIDs)
                partialResult[.tasks, default: []].formUnion(removedIDs)
            case let .ideasChanged(addedIDs, changedIDs, removedIDs):
                partialResult[.ideas, default: []].formUnion(addedIDs)
                partialResult[.ideas, default: []].formUnion(changedIDs)
                partialResult[.ideas, default: []].formUnion(removedIDs)
            case let .backlogCategoriesChanged(addedIDs, changedIDs, removedIDs):
                partialResult[.backlog, default: []].formUnion(addedIDs)
                partialResult[.backlog, default: []].formUnion(changedIDs)
                partialResult[.backlog, default: []].formUnion(removedIDs)
            }
        }
    }

    private func activeMemberCount(
        from visibleContentSnapshot: RemoteVisibleContentSnapshot?,
        fallbackHydrationSnapshot: JoinedHouseholdHydrationSnapshot?
    ) -> Int? {
        if let visibleContentSnapshot {
            return visibleContentSnapshot.membersByID.values.filter(\.isActive).count
        }
        return fallbackHydrationSnapshot?.activeMemberCount
    }

    private func remoteVisibleContentDiff(
        from events: [HouseholdSyncEvent]
    ) -> RemoteVisibleContentDiff {
        var addedShoppingTitles: [String] = []
        var addedShoppingItemIDs: Set<UUID> = []
        var changedShoppingItemIDs: Set<UUID> = []
        var changedShoppingBundleIDs: Set<UUID> = []
        var removedShoppingItemIDs: Set<UUID> = []
        var removedShoppingBundleIDs: Set<UUID> = []
        var addedTaskIDs: Set<UUID> = []
        var removedTaskIDs: Set<UUID> = []
        var changedTaskIDs: Set<UUID> = []
        var addedIdeaIDs: Set<UUID> = []
        var removedIdeaIDs: Set<UUID> = []
        var changedIdeaIDs: Set<UUID> = []
        var addedBacklogCategoryIDs: Set<UUID> = []
        var removedBacklogCategoryIDs: Set<UUID> = []
        var changedBacklogCategoryIDs: Set<UUID> = []
        var changedMemberIDs: Set<UUID> = []

        for event in events {
            switch event.kind {
            case let .membersChanged(ids):
                changedMemberIDs.formUnion(ids)
            case let .shoppingAdded(ids, titles):
                addedShoppingItemIDs.formUnion(ids)
                addedShoppingTitles.append(contentsOf: titles)
            case let .shoppingUpdated(itemIDs, bundleIDs):
                changedShoppingItemIDs.formUnion(itemIDs)
                changedShoppingBundleIDs.formUnion(bundleIDs)
            case let .shoppingRemoved(itemIDs, bundleIDs):
                removedShoppingItemIDs.formUnion(itemIDs)
                removedShoppingBundleIDs.formUnion(bundleIDs)
            case let .tasksChanged(addedIDs, changedIDs, removedIDs):
                addedTaskIDs.formUnion(addedIDs)
                changedTaskIDs.formUnion(changedIDs)
                removedTaskIDs.formUnion(removedIDs)
            case let .ideasChanged(addedIDs, changedIDs, removedIDs):
                addedIdeaIDs.formUnion(addedIDs)
                changedIdeaIDs.formUnion(changedIDs)
                removedIdeaIDs.formUnion(removedIDs)
            case let .backlogCategoriesChanged(addedIDs, changedIDs, removedIDs):
                addedBacklogCategoryIDs.formUnion(addedIDs)
                changedBacklogCategoryIDs.formUnion(changedIDs)
                removedBacklogCategoryIDs.formUnion(removedIDs)
            case .householdMetadataChanged:
                break
            }
        }

        return RemoteVisibleContentDiff(
            addedMemberIDs: [],
            removedMemberIDs: [],
            changedMemberIDs: changedMemberIDs,
            addedShoppingItemIDs: addedShoppingItemIDs,
            addedShoppingTitles: addedShoppingTitles.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            },
            addedShoppingBundleIDs: [],
            addedTaskIDs: addedTaskIDs,
            addedIdeaIDs: addedIdeaIDs,
            addedBacklogCategoryIDs: addedBacklogCategoryIDs,
            removedShoppingItemIDs: removedShoppingItemIDs,
            removedShoppingBundleIDs: removedShoppingBundleIDs,
            removedTaskIDs: removedTaskIDs,
            removedIdeaIDs: removedIdeaIDs,
            removedBacklogCategoryIDs: removedBacklogCategoryIDs,
            changedShoppingItemIDs: changedShoppingItemIDs,
            changedShoppingBundleIDs: changedShoppingBundleIDs,
            changedWorkItemIDs: changedTaskIDs.union(changedIdeaIDs),
            changedTaskIDs: changedTaskIDs,
            changedIdeaIDs: changedIdeaIDs,
            changedBacklogCategoryIDs: changedBacklogCategoryIDs
        )
    }

    private func deliverLegacySyncPresentation(
        for events: [HouseholdSyncEvent]
    ) {
        let contentDiff = remoteVisibleContentDiff(from: events)
        let taskDiff = RemoteTaskVisibleContentDiff(
            addedTaskIDs: events.reduce(into: Set<UUID>()) { partialResult, event in
                if case let .tasksChanged(addedIDs, _, _) = event.kind {
                    partialResult.formUnion(addedIDs)
                }
            },
            removedTaskIDs: events.reduce(into: Set<UUID>()) { partialResult, event in
                if case let .tasksChanged(_, _, removedIDs) = event.kind {
                    partialResult.formUnion(removedIDs)
                }
            },
            changedTaskIDs: events.reduce(into: Set<UUID>()) { partialResult, event in
                if case let .tasksChanged(_, changedIDs, _) = event.kind {
                    partialResult.formUnion(changedIDs)
                }
            }
        )

        if let shoppingPresentation = shoppingRemoteSyncPresentation(for: contentDiff) {
            CloudKitSubscriptionManager.shared.publishRemoteSyncPresentation(shoppingPresentation)
        }

        if let taskPresentation = taskRemoteSyncPresentation(for: taskDiff) {
            CloudKitSubscriptionManager.shared.publishRemoteSyncPresentation(taskPresentation)
        }
    }

    private func deliverRemoteVisibleContentAlerts(
        household: Household,
        beforeVisibleContentSnapshot: RemoteVisibleContentSnapshot,
        resolvedChange: RemoteVisibleContentResolution,
        currentUserId: String
    ) async {
        let afterVisibleContentSnapshot = resolvedChange.snapshot
        let contentDiff = resolvedChange.diff
        let taskDiff = afterVisibleContentSnapshot.taskContentDiff(from: beforeVisibleContentSnapshot)

        if !contentDiff.addedShoppingTitles.isEmpty {
            await NotificationService.shared.deliverSharedShoppingItemsAddedAlert(
                itemTitles: contentDiff.addedShoppingTitles,
                householdId: household.id,
                householdName: household.name
            )
        }

        if let celebrationAlert = sharedTaskCelebrationAlert(
            before: beforeVisibleContentSnapshot,
            after: afterVisibleContentSnapshot,
            diff: contentDiff,
            currentUserId: currentUserId,
            householdId: household.id
        ) {
            await NotificationService.shared.deliverHouseholdCelebrationAlert(
                title: celebrationAlert.title,
                body: celebrationAlert.body,
                householdId: household.id
            )
        }

        if let shoppingPresentation = shoppingRemoteSyncPresentation(for: contentDiff) {
            CloudKitSubscriptionManager.shared.publishRemoteSyncPresentation(shoppingPresentation)
        }

        if let taskPresentation = taskRemoteSyncPresentation(for: taskDiff) {
            CloudKitSubscriptionManager.shared.publishRemoteSyncPresentation(taskPresentation)
        }
    }

    private func sharedFollowUpRetryDelays(
        household: Household,
        userId: String,
        context: RemoteCloudChangeContext
    ) -> [UInt64] {
        if household.ownerId == userId {
            // The owner's shared zone resides in their private database.
            // When a participant writes to the CKShare, the owner receives a notification
            // scoped to their private database. We must process private notifications as
            // shared sync triggers for the owner so they see participant updates.
            guard context.databaseScope == .private else { return [] }
            return joinHydrationConfiguration.ownerSharedFollowUpRetryDelaysNanoseconds
        } else {
            // A participant's view of the shared zone resides in their shared database.
            guard context.databaseScope == .shared else { return [] }
            return joinHydrationConfiguration.participantSharedFollowUpRetryDelaysNanoseconds
        }
    }

    private func remoteSyncDirection(
        household: Household?,
        userId: String,
        context: RemoteCloudChangeContext
    ) -> HouseholdSyncDirection {
        guard let household else { return .unknown }

        if household.ownerId == userId {
            // The owner's shared zone resides in their private database.
            guard context.databaseScope == .private else { return .unknown }
            return .participantToOwner
        } else {
            // The participant's shared zone resides in their shared database.
            guard context.databaseScope == .shared else { return .unknown }
            return .ownerToParticipant
        }
    }

    private func logRemoteSyncTelemetry(
        direction: HouseholdSyncDirection,
        context: RemoteCloudChangeContext,
        refreshStartedAt: Date,
        cacheUpdatedAt: Date,
        followUpPassCount: Int,
        didChange: Bool
    ) {
        let pushToCacheMilliseconds: Int? = if context.receivedAt == .distantPast {
            nil
        } else {
            Int(cacheUpdatedAt.timeIntervalSince(context.receivedAt) * 1000)
        }
        let refreshMilliseconds = Int(cacheUpdatedAt.timeIntervalSince(refreshStartedAt) * 1000)
        let pushToCacheLabel = pushToCacheMilliseconds.map(String.init) ?? "n/a"

        print(
            "[RemoteSync] Telemetry direction=\(direction.rawValue) pushToCacheMs=\(pushToCacheLabel) refreshMs=\(refreshMilliseconds) followUpPasses=\(followUpPassCount) didChange=\(didChange)"
        )
    }

    private func shoppingRemoteSyncPresentation(
        for diff: RemoteVisibleContentDiff
    ) -> RemoteSyncPresentation? {
        if !diff.addedShoppingTitles.isEmpty {
            return RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: diff.addedShoppingTitles.count,
                titles: diff.addedShoppingTitles
            )
        }

        let shoppingUpdateCount =
            diff.changedShoppingItemIDs.count +
            diff.changedShoppingBundleIDs.count +
            diff.removedShoppingItemCount +
            diff.removedShoppingBundleCount +
            diff.addedShoppingBundleCount

        guard shoppingUpdateCount > 0 else { return nil }
        return RemoteSyncPresentation(
            domain: .shopping,
            kind: .updates,
            changeCount: shoppingUpdateCount,
            titles: []
        )
    }

    private func taskRemoteSyncPresentation(
        for diff: RemoteTaskVisibleContentDiff
    ) -> RemoteSyncPresentation? {
        if diff.addedTaskCount > 0 {
            return RemoteSyncPresentation(
                domain: .tasks,
                kind: .additions,
                changeCount: diff.addedTaskCount,
                titles: []
            )
        }

        let taskUpdateCount = diff.changedTaskIDs.count + diff.removedTaskCount
        guard taskUpdateCount > 0 else { return nil }
        return RemoteSyncPresentation(
            domain: .tasks,
            kind: .updates,
            changeCount: taskUpdateCount,
            titles: []
        )
    }

    private func resolveRecoverableCloudHousehold(
        userId: String,
        preferredHouseholdId: UUID? = nil
    ) async throws -> Household? {
        if let preferredHouseholdId, !isRecoverySuppressed(for: preferredHouseholdId) {
            let preferredMemberships = try await fetchScopedActiveMemberships(
                userId: userId,
                householdId: preferredHouseholdId
            )
            for scopedMembership in preferredMemberships {
                if let recoveredHousehold = try await recoverableHousehold(
                    from: scopedMembership.member,
                    source: scopedMembership.source
                ) {
                    return recoveredHousehold
                }
            }

            print(
                "DEBUG: Preferred household \(preferredHouseholdId) has no active membership for user \(userId); abandoning recovery."
            )
            await invalidateRecoveredHousehold(preferredHouseholdId)
        }

        let scopedMemberships = try await fetchScopedActiveMemberships(userId: userId)
        guard !scopedMemberships.isEmpty else { return nil }

        var recoveredByHouseholdId: [UUID: Household] = [:]
        for scopedMembership in scopedMemberships {
            if let recoveredHousehold = try await recoverableHousehold(
                from: scopedMembership.member,
                source: scopedMembership.source
            ) {
                recoveredByHouseholdId[recoveredHousehold.id] = recoveredHousehold
            }
        }

        if recoveredByHouseholdId.count > 1 {
            let householdIds = recoveredByHouseholdId.keys.map(\.uuidString).sorted().joined(separator: ", ")
            print("DEBUG: Ambiguous active memberships for user \(userId); refusing automatic recovery: \(householdIds)")
            return nil
        }

        return recoveredByHouseholdId.values.first
    }

    func validateRecoveredMembershipOrAbandon(
        household: Household,
        userId: String,
        retryDelaysNanoseconds: [UInt64] = [0, 250_000_000, 750_000_000],
        fetchActiveMember: ((Household, String) async throws -> Member?)? = nil
    ) async throws -> Bool {
        guard syncMode == .cloud else { return true }

        let fetchActiveMember = fetchActiveMember ?? { [cloudKit] household, userId in
            let scope: CloudKitManager.HouseholdDatabaseScope = household.ownerId == userId
                ? .ownerPrivate
                : .participantShared
            return try await cloudKit.fetchMemberByUserId(
                userId,
                householdId: household.id,
                scope: scope
            )
        }

        for delay in retryDelaysNanoseconds {
            if delay > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: delay)
            }

            if let member = try await fetchActiveMember(household, userId), member.isActive {
                clearRecoveredJoinDiagnostics()
                if pendingJoinStateMatches(householdId: household.id, userId: userId) {
                    pendingJoinState?.hasConfirmedRemoteMembership = true
                    if pendingJoinState?.hasCompletedHydrationPass == true {
                        pendingJoinState = nil
                    }
                }
                return true
            }
        }

        if shouldProtectPendingJoin(householdId: household.id, userId: userId) {
            print(
                "DEBUG: Preserving pending-join household \(household.id) while waiting for remote membership confirmation."
            )
            scheduleBackgroundJoinHydrationIfNeeded(
                household: household,
                userId: userId
            )
            return true
        }

        print(
            "DEBUG: Abandoning recovered household \(household.id) because no active membership exists for user \(userId)."
        )
        await invalidateRecoveredHousehold(household.id)
        return false
    }

    private func recoverableHousehold(
        from membership: HouseholdScopedMembership?
    ) async throws -> Household? {
        guard let membership else {
            return nil
        }

        let source: RecoverableMembershipSource =
            membership.scope == .ownerPrivate ? .ownerPrivate : .participantShared
        return try await recoverableHousehold(
            from: membership.member,
            source: source,
            fetchHousehold: { [householdRepository] _ in
                try await householdRepository.fetchHousehold(for: membership)
            }
        )
    }

    func recoverableHousehold(
        from member: Member?,
        source: RecoverableMembershipSource,
        fetchHousehold: ((UUID) async throws -> Household)? = nil,
        onMissingHousehold: ((Member, RecoverableMembershipSource) async -> Void)? = nil
    ) async throws -> Household? {
        guard let member, !isRecoverySuppressed(for: member.householdId) else {
            return nil
        }

        let fetchHousehold = fetchHousehold ?? { [cloudKit] householdId in
            let scope: CloudKitManager.HouseholdDatabaseScope =
                source == .ownerPrivate ? .ownerPrivate : .participantShared
            return try await cloudKit.fetchHousehold(id: householdId, scope: scope)
        }

        do {
            return try await fetchHousehold(member.householdId)
        } catch {
            guard isRecordMissingError(error) else {
                throw error
            }

            print(
                "DEBUG: Ignoring stale \(source.rawValue) membership for missing household \(member.householdId)"
            )
            suppressRecovery(for: member.householdId)
            if let onMissingHousehold {
                await onMissingHousehold(member, source)
            } else {
                await cleanupStaleRecoverableMembership(member, source: source)
            }
            return nil
        }
    }

    private func invalidateRecoveredHousehold(_ householdId: UUID) async {
        suppressRecovery(for: householdId)
        removeHouseholdFromCache(id: householdId)
        if currentHousehold?.id == householdId {
            clearCurrentHousehold()
        }
        await cloudKit.clearAllCachedZones(for: householdId)
    }

    private func cleanupStaleRecoverableMembership(
        _ member: Member,
        source: RecoverableMembershipSource
    ) async {
        await cloudKit.clearAllCachedZones(for: member.householdId)

        do {
            let scope: CloudKitManager.HouseholdDatabaseScope =
                source == .ownerPrivate ? .ownerPrivate : .participantShared
            _ = try await cloudKit.updateMemberState(
                memberId: member.id,
                householdId: member.householdId,
                newDisplayName: member.displayName,
                newRole: member.role,
                isActive: false,
                colorHex: member.colorHex,
                scope: scope
            )
        } catch {
            guard !isRecordMissingError(error) else { return }
            print(
                "DEBUG: Failed to deactivate stale \(source.rawValue) membership for household \(member.householdId): \(error)"
            )
        }
    }

    private func normalizedSingleHouseholdCount(_ count: Int) -> Int {
        count > 0 ? 1 : 0
    }

    @discardableResult
    private func updateCache(with household: Household) -> Bool {
        guard let context = modelContext else { return true }

        let descriptor = FetchDescriptor<CachedHousehold>(
            predicate: #Predicate { $0.id == household.id }
        )

        do {
            let results = try context.fetch(descriptor)
            if let existing = results.first {
                existing.update(from: household)
            } else {
                context.insert(CachedHousehold(from: household))
            }
            return saveContextOrSetError(context, operation: "upsert cached household")
        } catch {
            print("Cache update error: \(error)")
            self.error = error
            return false
        }
    }

    // swiftlint:disable function_body_length
    private func removeHouseholdFromCache(id: UUID) {
        guard let context = modelContext else { return }

        let householdId = id
        let householdDescriptor = FetchDescriptor<CachedHousehold>(
            predicate: #Predicate { $0.id == householdId }
        )
        let memberDescriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let taskDescriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let shoppingDescriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let shoppingBundleDescriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let backlogCategoryDescriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let backlogItemDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let recurringChoreDescriptor = FetchDescriptor<CachedRecurringChore>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            if let cachedHousehold = try context.fetch(householdDescriptor).first {
                context.delete(cachedHousehold)
            }

            for member in try context.fetch(memberDescriptor) {
                context.delete(member)
            }
            for task in try context.fetch(taskDescriptor) {
                context.delete(task)
            }
            for item in try context.fetch(shoppingDescriptor) {
                context.delete(item)
            }
            for bundle in try context.fetch(shoppingBundleDescriptor) {
                context.delete(bundle)
            }
            for category in try context.fetch(backlogCategoryDescriptor) {
                context.delete(category)
            }
            for item in try context.fetch(backlogItemDescriptor) {
                context.delete(item)
            }
            for chore in try context.fetch(recurringChoreDescriptor) {
                context.delete(chore)
            }

            saveContextOrSetError(context, operation: "remove household cache graph")
        } catch {
            print("Cache household removal error: \(error)")
            self.error = error
        }
    }

    // swiftlint:enable function_body_length

    private func suppressRecovery(for householdId: UUID) {
        var suppressions = loadSuppressedRecoveries(cleaningExpired: true)
        suppressions[householdId.uuidString] = Date().addingTimeInterval(recoverySuppressionDuration)
        userDefaults.set(
            suppressions.mapValues(\.timeIntervalSince1970),
            forKey: DefaultsKey.suppressedHouseholdRecoveries
        )
    }

    private func loadSuppressedRecoveries(cleaningExpired: Bool) -> [String: Date] {
        let raw = userDefaults.dictionary(forKey: DefaultsKey.suppressedHouseholdRecoveries) as? [String: TimeInterval] ?? [:]
        let now = Date()
        let mapped = raw.reduce(into: [String: Date]()) { partialResult, entry in
            let date = Date(timeIntervalSince1970: entry.value)
            if !cleaningExpired || date > now {
                partialResult[entry.key] = date
            }
        }

        if cleaningExpired, mapped.count != raw.count {
            userDefaults.set(
                mapped.mapValues(\.timeIntervalSince1970),
                forKey: DefaultsKey.suppressedHouseholdRecoveries
            )
        }

        return mapped
    }

    // MARK: - Local Household Bootstrap

    private func updateCache(with member: Member) {
        guard let context = modelContext else { return }

        let memberId = member.id
        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.id == memberId }
        )

        do {
            if let cached = try context.fetch(descriptor).first {
                cached.update(from: member)
            } else {
                context.insert(CachedMember(from: member))
            }
            saveContextOrSetError(context, operation: "upsert cached household member")
        } catch {
            print("Cache update error: \(error)")
            self.error = error
        }
    }

    private func updateCache(with members: [Member]) {
        for member in members {
            updateCache(with: member)
        }
    }

    private func beginPendingJoinProtection(householdId: UUID, userId: String) {
        joinHydrationTask?.cancel()
        joinHydrationTask = nil
        pendingJoinState = PendingJoinState(
            householdId: householdId,
            userId: userId,
            startedAt: Date(),
            expiresAt: Date().addingTimeInterval(joinHydrationConfiguration.pendingJoinGraceDuration)
        )
    }

    private func pendingJoinStateMatches(householdId: UUID, userId: String) -> Bool {
        guard let pendingJoinState else { return false }
        guard pendingJoinState.householdId == householdId, pendingJoinState.userId == userId else {
            return false
        }

        if pendingJoinState.expiresAt <= Date() {
            self.pendingJoinState = nil
            return false
        }

        return true
    }

    private func shouldProtectPendingJoin(householdId: UUID, userId: String) -> Bool {
        guard pendingJoinStateMatches(householdId: householdId, userId: userId) else {
            return false
        }
        return hasActiveCachedMembership(householdId: householdId, userId: userId)
    }

    private func hasActiveCachedMembership(householdId: UUID, userId: String) -> Bool {
        fetchCachedMembers(householdId: householdId).contains {
            $0.userId == userId && $0.isActive
        }
    }

    private func refreshMemberCacheFromCloudIfNeeded(
        household: Household,
        userId: String
    ) async {
        do {
            await setCloudScope(for: household, userId: userId)
            let scope = cloudScope(for: household, userId: userId)
            let remoteMembers = try await cloudKit.fetchMembers(
                householdId: household.id,
                scope: scope
            )
            let mergedMembers = mergeRemoteMembersWithLocalJoinFallback(
                remoteMembers,
                householdId: household.id,
                currentUserId: userId
            )
            updateCache(with: mergedMembers)
        } catch {
            if !shouldProtectPendingJoin(householdId: household.id, userId: userId) {
                self.error = error
            }
        }
    }

    private func mergeRemoteMembersWithLocalJoinFallback(
        _ remoteMembers: [Member],
        householdId: UUID,
        currentUserId: String
    ) -> [Member] {
        let cachedMembers = fetchCachedMembers(householdId: householdId)
        var mergedById = Dictionary(uniqueKeysWithValues: remoteMembers.map { ($0.id, $0) })

        if let cachedCurrentUserMember = cachedMembers.first(where: {
            $0.userId == currentUserId && $0.isActive
        }),
            !mergedById.values.contains(where: { $0.userId == currentUserId && $0.isActive })
        {
            mergedById[cachedCurrentUserMember.id] = cachedCurrentUserMember
        }

        return mergedById.values.sorted { $0.joinedAt < $1.joinedAt }
    }

    private func fetchCachedWorkItems(householdId: UUID) -> [CachedWorkItem] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached work items error: \(error)")
            return []
        }
    }

    private func fetchCachedBacklogCategories(householdId: UUID) -> [CachedBacklogCategory] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedBacklogCategory>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached backlog categories error: \(error)")
            return []
        }
    }

    private func fetchCachedShoppingItems(householdId: UUID) -> [CachedShoppingItem] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached shopping items error: \(error)")
            return []
        }
    }

    private func fetchCachedShoppingBundles(householdId: UUID) -> [CachedShoppingBundle] {
        guard let context = modelContext else { return [] }

        let descriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Fetch cached shopping bundles error: \(error)")
            return []
        }
    }
}

@MainActor
extension HouseholdStore: HouseholdRemoteSyncDataSource {
    var remoteSyncMode: SyncMode {
        syncMode
    }

    func recordRemoteSyncError(_ error: Error) {
        self.error = error
    }
}

// swiftlint:enable type_body_length file_length
