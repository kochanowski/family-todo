import CloudKit
@testable import HousePulse
import SwiftData
import UIKit
import XCTest

@MainActor
final class HouseholdRemoteSyncTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var suiteName: String?
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .household)
        let isolatedDefaults = TestModelContainerFactory.makeUserDefaults(
            suitePrefix: "HouseholdRemoteSyncTests"
        )
        suiteName = isolatedDefaults.suiteName
        defaults = isolatedDefaults.defaults
    }

    override func tearDown() async throws {
        TestModelContainerFactory.clearUserDefaults(suiteName: suiteName, defaults: defaults)
        modelContainer = nil
        suiteName = nil
        defaults = nil
        try await super.tearDown()
    }

    private func makeStore(
        cloud: FakeHouseholdCloud,
        joinHydrationConfiguration: HouseholdStore.JoinHydrationConfiguration = .default
    ) -> HouseholdStore {
        HouseholdStore(
            modelContext: modelContainer.mainContext,
            cloudKit: cloud,
            userDefaults: defaults,
            recoverySuppressionDuration: 300,
            joinHydrationConfiguration: joinHydrationConfiguration
        )
    }

    private func makeStore(
        cloud: FakeHouseholdCloud,
        joinedHouseholdPrewarmOverride: @escaping (Household, String, ModelContext?) async throws -> Void,
        joinHydrationConfiguration: HouseholdStore.JoinHydrationConfiguration = .default
    ) -> HouseholdStore {
        HouseholdStore(
            modelContext: modelContainer.mainContext,
            cloudKit: cloud,
            joinedHouseholdPrewarmOverride: joinedHouseholdPrewarmOverride,
            userDefaults: defaults,
            recoverySuppressionDuration: 300,
            joinHydrationConfiguration: joinHydrationConfiguration
        )
    }

    private func cachedMembers(for householdId: UUID) throws -> [CachedMember] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedWorkItems(for householdId: UUID) throws -> [CachedWorkItem] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedWorkItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedShoppingItems(for householdId: UUID) throws -> [CachedShoppingItem] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedShoppingBundles(for householdId: UUID) throws -> [CachedShoppingBundle] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedShoppingBundle>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    private func cachedBacklogCategories(for householdId: UUID) throws -> [CachedBacklogCategory] {
        try modelContainer.mainContext.fetch(
            FetchDescriptor<CachedBacklogCategory>(
                predicate: #Predicate { $0.householdId == householdId }
            )
        )
    }

    func testHandleRemoteCloudChangeRefreshesSharedCachesAndReturnsNewData() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let category = TestCacheFixtures.category(householdId: household.id, title: "Planning")
        let task = TestCacheFixtures.task(
            householdId: household.id,
            title: "Take out trash",
            backlogCategoryId: category.id
        )
        let idea = TestCacheFixtures.idea(
            categoryId: category.id,
            householdId: household.id,
            title: "Plan spring cleaning"
        )
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )
        let bundle = TestCacheFixtures.shoppingBundle(
            householdId: household.id,
            name: "Weekly staples"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [task],
            shoppingItems: [shoppingItem],
            shoppingBundles: [bundle],
            backlogItems: [idea],
            backlogCategories: [category],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let householdExpectation = expectation(
            forNotification: .householdDataDidChange,
            object: nil,
            handler: nil
        )
        let shoppingExpectation = expectation(
            forNotification: .shoppingListDataDidChange,
            object: nil,
            handler: nil
        )

        let result = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )

        await fulfillment(of: [householdExpectation, shoppingExpectation], timeout: 1.0)

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(try cachedMembers(for: household.id).count, 1)
        XCTAssertEqual(try cachedWorkItems(for: household.id).count, 2)
        XCTAssertEqual(try cachedShoppingItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedShoppingBundles(for: household.id).count, 1)
        XCTAssertEqual(try cachedBacklogCategories(for: household.id).count, 1)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(operations.contains {
            $0.name == "fetchUnifiedWorkItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchShoppingItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchBacklogItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
    }

    func testHandleRemoteCloudChangeReturnsNoDataWhenCachesAreAlreadyCurrent() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let task = TestCacheFixtures.task(
            householdId: household.id,
            title: "Take out trash"
        )
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [task],
            shoppingItems: [shoppingItem],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let firstResult = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )
        let secondResult = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )

        XCTAssertEqual(firstResult, .newData)
        XCTAssertEqual(secondResult, .noData)
    }

    func testHandleRemoteCloudChangeReturnsNewDataWhenHouseholdMetadataChanges() async throws {
        let userId = "joined-user"
        let localHousehold = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let refreshedHousehold = Household(
            id: localHousehold.id,
            name: "Nowy Dom",
            iconSymbol: "building.2.fill",
            ownerId: localHousehold.ownerId,
            createdAt: localHousehold.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2000)
        )
        let membership = TestCacheFixtures.member(
            householdId: localHousehold.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )

        let cloud = FakeHouseholdCloud(
            households: [refreshedHousehold],
            participantMembers: [membership],
            acceptedSharedHouseholdIDs: [localHousehold.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = localHousehold

        modelContainer.mainContext.insert(CachedHousehold(from: localHousehold))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let householdExpectation = expectation(
            forNotification: .householdDataDidChange,
            object: nil,
            handler: nil
        )

        let result = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: localHousehold.id
        )

        await fulfillment(of: [householdExpectation], timeout: 1.0)

        XCTAssertEqual(result, .newData)
        XCTAssertEqual(store.currentHousehold?.name, "Nowy Dom")
        XCTAssertEqual(store.currentHousehold?.iconSymbol, "building.2.fill")
    }

    func testForceCloudSyncDebugPublishesStoreNotificationsAndRefreshesParticipantSharedCaches() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let category = TestCacheFixtures.category(householdId: household.id, title: "Planning")
        let task = TestCacheFixtures.task(
            householdId: household.id,
            title: "Take out trash",
            backlogCategoryId: category.id
        )
        let shoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [task],
            shoppingItems: [shoppingItem],
            backlogCategories: [category],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        try modelContainer.mainContext.save()

        let householdExpectation = expectation(forNotification: .householdDataDidChange, object: nil)
        let shoppingExpectation = expectation(forNotification: .shoppingListDataDidChange, object: nil)
        let taskExpectation = expectation(forNotification: .taskBoardDataDidChange, object: nil)
        let backlogExpectation = expectation(forNotification: .backlogDataDidChange, object: nil)

        await store.forceCloudSyncDebug(userId: userId)

        await fulfillment(
            of: [
                householdExpectation,
                shoppingExpectation,
                taskExpectation,
                backlogExpectation,
            ],
            timeout: 1.0
        )

        XCTAssertEqual(try cachedMembers(for: household.id).count, 1)
        XCTAssertEqual(try cachedWorkItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedShoppingItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedBacklogCategories(for: household.id).count, 1)

        let operations = await cloud.operationEventsSnapshot()
        XCTAssertTrue(operations.contains {
            $0.name == "fetchMembers" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchUnifiedWorkItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchShoppingItems" && $0.scope == .participantShared && $0.householdId == household.id
        })
        XCTAssertTrue(operations.contains {
            $0.name == "fetchBacklogCategories" && $0.scope == .participantShared && $0.householdId == household.id
        })
    }

    func testRemoteVisibleContentDiffCountsRealInsertedRecords() {
        let existingTaskID = UUID()
        let addedTaskID = UUID()
        let existingShoppingID = UUID()
        let addedShoppingID = UUID()

        let before = RemoteVisibleContentSnapshot(
            shoppingTitlesByID: [existingShoppingID: "Milk"],
            shoppingBundleIDs: [UUID()],
            workItemIDs: [existingTaskID],
            backlogCategoryIDs: [UUID()]
        )

        let after = RemoteVisibleContentSnapshot(
            shoppingTitlesByID: [
                existingShoppingID: "Milk",
                addedShoppingID: "Bread",
            ],
            shoppingBundleIDs: before.shoppingBundleIDs.union([UUID()]),
            workItemIDs: before.workItemIDs.union([addedTaskID]),
            backlogCategoryIDs: before.backlogCategoryIDs.union([UUID()])
        )

        let diff = after.diff(from: before)

        XCTAssertEqual(diff.addedShoppingTitles, ["Bread"])
        XCTAssertEqual(diff.addedShoppingBundleCount, 1)
        XCTAssertEqual(diff.addedWorkItemCount, 1)
        XCTAssertEqual(diff.addedBacklogCategoryCount, 1)
        XCTAssertEqual(diff.totalAddedCount, 4)
    }

    func testHandleRemoteCloudChangeReturnsNewDataForFieldOnlyShoppingToggle() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let itemID = UUID()
        let localShoppingItem = ShoppingItem(
            id: itemID,
            householdId: household.id,
            title: "Milk",
            isBought: false,
            sortOrder: 0,
            updatedAt: Date(timeIntervalSince1970: 1_736_900_000)
        )
        let remoteShoppingItem = ShoppingItem(
            id: itemID,
            householdId: household.id,
            title: "Milk",
            isBought: true,
            boughtAt: Date(timeIntervalSince1970: 1_736_900_030),
            sortOrder: 0,
            updatedAt: Date(timeIntervalSince1970: 1_736_900_030)
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            shoppingItems: [remoteShoppingItem],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        modelContainer.mainContext.insert(CachedShoppingItem(from: localShoppingItem))
        try modelContainer.mainContext.save()

        let shoppingExpectation = expectation(
            forNotification: .shoppingListDataDidChange,
            object: nil,
            handler: nil
        )

        let result = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )

        await fulfillment(of: [shoppingExpectation], timeout: 1.0)

        XCTAssertEqual(result, .newData)

        let cachedItems = try cachedShoppingItems(for: household.id)
        XCTAssertEqual(cachedItems.count, 1)
        XCTAssertEqual(cachedItems.first?.isBought, true)
    }

    func testHandleRemoteCloudChangeReturnsNewDataForFieldOnlyTaskUpdate() async throws {
        let userId = "joined-user"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: "owner-1")
        let membership = TestCacheFixtures.member(
            householdId: household.id,
            userId: userId,
            displayName: "Taylor",
            role: .member
        )
        let taskID = UUID()
        let taskLogicalID = UUID()
        let assigneeID = UUID()
        let localTask = Task(
            id: taskID,
            logicalItemID: taskLogicalID,
            householdId: household.id,
            title: "Take out trash",
            status: .next,
            assigneeId: assigneeID,
            taskType: .oneOff,
            updatedAt: Date(timeIntervalSince1970: 1_736_900_000)
        )
        let remoteTask = Task(
            id: taskID,
            logicalItemID: taskLogicalID,
            householdId: household.id,
            title: "Take out trash",
            status: .done,
            assigneeId: assigneeID,
            completedAt: Date(timeIntervalSince1970: 1_736_900_060),
            completedById: "user-1",
            taskType: .oneOff,
            updatedAt: Date(timeIntervalSince1970: 1_736_900_060)
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            participantMembers: [membership],
            tasks: [remoteTask],
            acceptedSharedHouseholdIDs: [household.id]
        )

        let store = makeStore(cloud: cloud)
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: membership))
        modelContainer.mainContext.insert(TestCacheFixtures.cachedWorkItem(from: WorkItem(task: localTask)))
        try modelContainer.mainContext.save()

        let taskExpectation = expectation(
            forNotification: .taskBoardDataDidChange,
            object: nil,
            handler: nil
        )

        let result = await store.handleRemoteCloudChange(
            userId: userId,
            preferredHouseholdId: household.id
        )

        await fulfillment(of: [taskExpectation], timeout: 1.0)

        XCTAssertEqual(result, .newData)

        let cachedItems = try cachedWorkItems(for: household.id)
        XCTAssertEqual(cachedItems.count, 1)
        XCTAssertEqual(cachedItems.first?.statusRaw, WorkItem.Status.done.rawValue)
        XCTAssertEqual(cachedItems.first?.completedById, "user-1")
    }

    func testOwnerSharedRemoteChangeKeepsHydratingUntilDelayedTaskArrives() async throws {
        final class Counter {
            var value = 0
            func increment() -> Int {
                value += 1
                return value
            }
        }

        let ownerUserId = "owner-1"
        let household = TestCacheFixtures.household(name: "Domownicy", ownerId: ownerUserId)
        let ownerMember = TestCacheFixtures.member(
            householdId: household.id,
            userId: ownerUserId,
            displayName: "Wojtek",
            role: .owner
        )
        let delayedTask = TestCacheFixtures.task(
            householdId: household.id,
            title: "Take out trash"
        )
        let immediateShoppingItem = TestCacheFixtures.shoppingItem(
            householdId: household.id,
            title: "Milk"
        )

        let cloud = FakeHouseholdCloud(
            households: [household],
            ownerMembers: [ownerMember]
        )
        let hydrationPassCount = Counter()
        let joinHydrationConfiguration = HouseholdStore.JoinHydrationConfiguration(
            initialHydrationBudgetNanoseconds: 5_000_000_000,
            initialRetryDelaysNanoseconds: [0],
            backgroundRetryDelaysNanoseconds: [],
            pendingJoinGraceDuration: 30,
            ownerSharedFollowUpRetryDelaysNanoseconds: [0]
        )

        let store = makeStore(
            cloud: cloud,
            joinedHouseholdPrewarmOverride: { _, _, context in
                guard let context else { return }
                let pass = hydrationPassCount.increment()

                if pass == 1 {
                    context.insert(CachedShoppingItem(from: immediateShoppingItem))
                } else {
                    context.insert(TestCacheFixtures.cachedWorkItem(from: WorkItem(task: delayedTask)))
                }
                try context.save()
            },
            joinHydrationConfiguration: joinHydrationConfiguration
        )
        store.setSyncMode(.cloud)
        store.currentHousehold = household

        modelContainer.mainContext.insert(CachedHousehold(from: household))
        modelContainer.mainContext.insert(CachedMember(from: ownerMember))
        try modelContainer.mainContext.save()

        let result = await store.handleRemoteCloudChange(
            userId: ownerUserId,
            preferredHouseholdId: household.id,
            context: RemoteCloudChangeContext(
                databaseScope: .shared,
                notificationType: .database,
                receivedAt: Date()
            )
        )

        XCTAssertEqual(result, .newData)
        XCTAssertGreaterThanOrEqual(hydrationPassCount.value, 2)
        XCTAssertEqual(try cachedShoppingItems(for: household.id).count, 1)
        XCTAssertEqual(try cachedWorkItems(for: household.id).count, 1)
    }
}

final class CloudKitSubscriptionManagerTests: XCTestCase {
    @MainActor
    private func makeManager() -> CloudKitSubscriptionManager {
        let manager = CloudKitSubscriptionManager()
        manager.resetTransientPresentationState()
        return manager
    }

    @MainActor
    func testParticipantSharedSkipsZoneSubscriptions() {
        XCTAssertFalse(
            CloudKitSubscriptionManager.shouldCreateZoneSubscription(for: .participantShared)
        )
        XCTAssertTrue(
            CloudKitSubscriptionManager.shouldCreateZoneSubscription(for: .ownerPrivate)
        )
    }

    func testCloudKitSchemaKeepsHouseholdMemberRecordIndexesAndInviteTokenRoles() throws {
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cloudkit")
            .appendingPathComponent("schema")
            .appendingPathComponent("housepulse-schema.json")
        let data = try Data(contentsOf: schemaURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let schema = try XCTUnwrap(object as? [String: Any])
        let recordTypes = try XCTUnwrap(schema["recordTypes"] as? [[String: Any]])

        let household = try XCTUnwrap(recordTypes.first { $0["name"] as? String == "Household" })
        let householdIndexes = try XCTUnwrap(household["indexes"] as? [String: Any])
        XCTAssertTrue(((householdIndexes["query"] as? [String]) ?? []).contains("___recordID"))

        let member = try XCTUnwrap(recordTypes.first { $0["name"] as? String == "Member" })
        let memberIndexes = try XCTUnwrap(member["indexes"] as? [String: Any])
        XCTAssertTrue(((memberIndexes["query"] as? [String]) ?? []).contains("___recordID"))

        let securityRoles = try XCTUnwrap(schema["securityRoles"] as? [[String: Any]])
        let inviteRolePermissions = securityRoles.flatMap { role -> [String] in
            let roleName = role["name"] as? String ?? ""
            let recordPermissions = (role["recordTypePermissions"] as? [[String: Any]]) ?? []
            return recordPermissions.compactMap { permission -> [String]? in
                guard permission["recordType"] as? String == "InviteToken" else { return nil }
                let actions = [
                    (permission["create"] as? Bool == true) ? "create" : nil,
                    (permission["read"] as? Bool == true) ? "read" : nil,
                    (permission["write"] as? Bool == true) ? "write" : nil,
                ].compactMap { $0 }
                return actions.map { "\(roleName):\($0)" }
            }.flatMap { $0 }
        }

        XCTAssertTrue(inviteRolePermissions.contains("_world:read"))
        XCTAssertTrue(inviteRolePermissions.contains("_icloud:create"))
        XCTAssertTrue(inviteRolePermissions.contains("_icloud:read"))
        XCTAssertTrue(inviteRolePermissions.contains("_creator:read"))
        XCTAssertTrue(inviteRolePermissions.contains("_creator:write"))
    }

    @MainActor
    func testShoppingAdditionOnShoppingTabPublishesInlineFeedbackWithoutBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.shopping)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 3,
                titles: ["Milk", "Bread", "Eggs"]
            ),
            applicationState: .active
        )

        XCTAssertEqual(manager.shoppingInlineFeedback?.text, "3 items added")
        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 0)
    }

    @MainActor
    func testShoppingAdditionOffShoppingTabShowsBannerWithoutInlineFeedback() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 2)
        XCTAssertNil(manager.shoppingInlineFeedback)
        XCTAssertNil(manager.tasksInlineFeedback)
    }

    @MainActor
    func testTaskUpdateOnTasksTabPublishesInlineFeedbackWithoutBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .tasks,
                kind: .updates,
                changeCount: 1,
                titles: []
            ),
            applicationState: .active
        )

        XCTAssertEqual(manager.tasksInlineFeedback?.text, "Tasks updated")
        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertNil(manager.shoppingInlineFeedback)
    }

    @MainActor
    func testTaskAdditionOffTasksTabDoesNotShowGlobalBannerOrInlineFeedback() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.shopping)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .tasks,
                kind: .additions,
                changeCount: 1,
                titles: ["Take out trash"]
            ),
            applicationState: .active
        )

        XCTAssertFalse(manager.showNewItemsBanner)
        XCTAssertNil(manager.tasksInlineFeedback)
        XCTAssertNil(manager.shoppingInlineFeedback)
    }

    @MainActor
    func testSharedShoppingAlertsAreSuppressedOnlyWhenShoppingTabIsVisible() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }

        manager.updateActiveTab(.shopping)
        XCTAssertTrue(manager.shouldSuppressSharedShoppingAlert(applicationState: .active))

        manager.updateActiveTab(.tasks)
        XCTAssertFalse(manager.shouldSuppressSharedShoppingAlert(applicationState: .active))
        XCTAssertFalse(manager.shouldSuppressSharedShoppingAlert(applicationState: .background))
    }

    @MainActor
    func testCelebrationAlertsAreSuppressedOnlyWhenTasksTabIsVisible() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }

        manager.updateActiveTab(.tasks)
        XCTAssertTrue(manager.shouldSuppressHouseholdCelebrationAlert(applicationState: .active))

        manager.updateActiveTab(.shopping)
        XCTAssertFalse(manager.shouldSuppressHouseholdCelebrationAlert(applicationState: .active))
        XCTAssertFalse(manager.shouldSuppressHouseholdCelebrationAlert(applicationState: .background))
    }

    @MainActor
    func testShoppingAdditionOffShoppingTabAccumulatesExistingBannerCount() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )
        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 3,
                titles: ["Eggs", "Butter", "Cheese"]
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 5)
    }

    @MainActor
    func testTaskPresentationDoesNotClearExistingShoppingBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.more)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )
        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .tasks,
                kind: .updates,
                changeCount: 1,
                titles: []
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 2)
    }

    @MainActor
    func testShoppingUpdatesOffShoppingTabDoNotClearExistingBanner() {
        let manager = makeManager()
        defer { manager.resetTransientPresentationState() }
        manager.updateActiveTab(.tasks)

        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .additions,
                changeCount: 2,
                titles: ["Milk", "Bread"]
            ),
            applicationState: .active
        )
        manager.publishRemoteSyncPresentation(
            RemoteSyncPresentation(
                domain: .shopping,
                kind: .updates,
                changeCount: 1,
                titles: []
            ),
            applicationState: .active
        )

        XCTAssertTrue(manager.showNewItemsBanner)
        XCTAssertEqual(manager.newItemsCount, 2)
    }
}

final class SharedShoppingNotificationAccumulatorTests: XCTestCase {
    func testAccumulatorBatchesTitlesIntoSingleAlert() {
        let householdId = UUID()
        let start = Date(timeIntervalSince1970: 1_736_950_000)
        var accumulator = SharedShoppingNotificationAccumulator(window: 3)

        XCTAssertNil(
            accumulator.record(
                householdId: householdId,
                householdName: "Dom",
                itemTitles: ["Milk"],
                at: start
            )
        )
        XCTAssertNil(
            accumulator.record(
                householdId: householdId,
                householdName: "Dom",
                itemTitles: ["Bread", "Eggs"],
                at: start.addingTimeInterval(1)
            )
        )

        let batch = accumulator.flushReady(at: start.addingTimeInterval(3.1))

        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.householdId, householdId)
        XCTAssertEqual(batch.first?.householdName, "Dom")
        XCTAssertEqual(batch.first?.itemTitles, ["Bread", "Eggs", "Milk"])
    }

    func testAccumulatorSeparatesBatchesOutsideWindow() {
        let householdId = UUID()
        let start = Date(timeIntervalSince1970: 1_736_950_000)
        var accumulator = SharedShoppingNotificationAccumulator(window: 3)

        XCTAssertNil(
            accumulator.record(
                householdId: householdId,
                householdName: nil,
                itemTitles: ["Milk"],
                at: start
            )
        )

        let firstBatch = accumulator.record(
            householdId: householdId,
            householdName: nil,
            itemTitles: ["Bread"],
            at: start.addingTimeInterval(4)
        )

        XCTAssertEqual(firstBatch?.count, 1)
        XCTAssertEqual(firstBatch?.itemTitles, ["Milk"])

        let trailingBatch = accumulator.flushReady(at: start.addingTimeInterval(8))
        XCTAssertEqual(trailingBatch.count, 1)
        XCTAssertEqual(trailingBatch.first?.itemTitles, ["Bread"])
    }
}

final class RemoteSyncAnimationSupportTests: XCTestCase {
    private func makeWorkItemState(
        title: String = "Item",
        status: WorkItem.Status,
        updatedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> RemoteWorkItemState {
        RemoteWorkItemState(
            logicalItemID: UUID(),
            title: title,
            status: status,
            assigneeId: nil,
            assigneeIds: [],
            completedAt: nil,
            completedById: nil,
            order: 0,
            updatedAt: updatedAt
        )
    }

    func testVisibleDeltaMarksInsertedRemovedAndUpdatedIDs() {
        let insertedID = UUID()
        let updatedID = UUID()
        let removedID = UUID()

        let delta = RemoteSyncVisibleDeltaResolver.resolve(
            beforeLocations: [
                updatedID: 0,
                removedID: 0,
            ],
            afterLocations: [
                insertedID: 0,
                updatedID: 0,
            ],
            changedIDs: [updatedID]
        )

        XCTAssertEqual(delta.insertedIDs, [insertedID])
        XCTAssertEqual(delta.updatedIDs, [updatedID])
        XCTAssertEqual(delta.removedIDs, [removedID])
        XCTAssertEqual(delta.highlightedIDs, [insertedID, updatedID])
    }

    func testVisibleDeltaTreatsLocationChangesAsRemovalAndInsertion() {
        let movedID = UUID()
        let oldCategoryID = UUID()
        let newCategoryID = UUID()

        let delta = RemoteSyncVisibleDeltaResolver.resolve(
            beforeLocations: [movedID: oldCategoryID],
            afterLocations: [movedID: newCategoryID],
            changedIDs: [movedID]
        )

        XCTAssertEqual(delta.insertedIDs, [movedID])
        XCTAssertEqual(delta.updatedIDs, [])
        XCTAssertEqual(delta.removedIDs, [movedID])
        XCTAssertEqual(delta.highlightedIDs, [movedID])
    }

    func testVisibleDeltaDoesNotHighlightUnchangedSharedIDs() {
        let unchangedID = UUID()
        let delta = RemoteSyncVisibleDeltaResolver.resolve(
            beforeLocations: [unchangedID: 0],
            afterLocations: [unchangedID: 0],
            changedIDs: []
        )

        XCTAssertEqual(delta.insertedIDs, [])
        XCTAssertEqual(delta.updatedIDs, [])
        XCTAssertEqual(delta.removedIDs, [])
        XCTAssertEqual(delta.highlightedIDs, [])
    }

    func testRemoteSyncNotificationPayloadReadsUUIDSetsFromUserInfo() throws {
        let batchToken = UUID()
        let shoppingID = UUID()
        let workItemID = UUID()
        let categoryID = UUID()
        let pushReceivedAt = Date(timeIntervalSince1970: 1_736_990_000)
        let cacheUpdatedAt = Date(timeIntervalSince1970: 1_736_990_001)
        let notification = Notification(
            name: .shoppingListDataDidChange,
            object: "remotePush",
            userInfo: [
                RemoteSyncNotificationPayloadKey.batchToken: batchToken.uuidString,
                RemoteSyncNotificationPayloadKey.shoppingChangedItemIDs: [shoppingID.uuidString],
                RemoteSyncNotificationPayloadKey.workItemChangedIDs: [workItemID.uuidString],
                RemoteSyncNotificationPayloadKey.backlogChangedCategoryIDs: [categoryID.uuidString],
                RemoteSyncNotificationPayloadKey.direction: "participant_to_owner",
                RemoteSyncNotificationPayloadKey.pushReceivedAt: pushReceivedAt.timeIntervalSince1970,
                RemoteSyncNotificationPayloadKey.cacheUpdatedAt: cacheUpdatedAt.timeIntervalSince1970,
            ]
        )

        let payload = try XCTUnwrap(notification.remoteSyncAnimationPayload)
        XCTAssertEqual(payload.batchToken, batchToken)
        XCTAssertEqual(payload.shoppingChangedItemIDs, [shoppingID])
        XCTAssertEqual(payload.workItemChangedIDs, [workItemID])
        XCTAssertEqual(payload.backlogChangedCategoryIDs, [categoryID])
        XCTAssertEqual(payload.direction, "participant_to_owner")
        XCTAssertEqual(payload.pushReceivedAt, pushReceivedAt)
        XCTAssertEqual(payload.cacheUpdatedAt, cacheUpdatedAt)
    }

    @MainActor
    func testRemoteVisibleRefreshTaskRunsPrimaryAndDependentRefreshBeforeResolvingDelta() async {
        let insertedID = UUID()
        let updatedID = UUID()
        var callOrder: [String] = []
        var visibleLocations: [UUID: Int] = [updatedID: 0]

        let refreshTask = RemoteVisibleRefreshTask(
            changedIDs: [updatedID, insertedID],
            captureVisibleLocations: {
                callOrder.append("capture")
                return visibleLocations
            },
            rehydratePrimaryStore: {
                callOrder.append("primary")
            },
            refreshDependentStores: {
                callOrder.append("dependents")
                visibleLocations[insertedID] = 0
            }
        )

        let delta = await refreshTask.run()

        XCTAssertEqual(callOrder, ["capture", "primary", "dependents", "capture"])
        XCTAssertEqual(delta.insertedIDs, [insertedID])
        XCTAssertEqual(delta.updatedIDs, [updatedID])
        XCTAssertEqual(delta.removedIDs, [])
    }

    @MainActor
    func testRemoteVisibleRefreshTaskAllowsNoopDependentRefresh() async {
        let updatedID = UUID()
        var callOrder: [String] = []
        let refreshTask = RemoteVisibleRefreshTask(
            changedIDs: [updatedID],
            captureVisibleLocations: {
                callOrder.append("capture")
                return [updatedID: 0]
            },
            rehydratePrimaryStore: {
                callOrder.append("primary")
            }
        )

        let delta = await refreshTask.run()

        XCTAssertEqual(callOrder, ["capture", "primary", "capture"])
        XCTAssertEqual(delta.insertedIDs, [])
        XCTAssertEqual(delta.updatedIDs, [updatedID])
        XCTAssertEqual(delta.removedIDs, [])
    }

    func testTaskContentDiffIgnoresIdeaOnlyChanges() {
        let ideaID = UUID()
        let before = RemoteVisibleContentSnapshot(
            shoppingItemsByID: [:],
            shoppingBundlesByID: [:],
            workItemsByID: [
                ideaID: makeWorkItemState(title: "Plan trip", status: .idea),
            ],
            backlogCategoriesByID: [:]
        )
        let after = RemoteVisibleContentSnapshot(
            shoppingItemsByID: [:],
            shoppingBundlesByID: [:],
            workItemsByID: [
                ideaID: makeWorkItemState(
                    title: "Plan summer trip",
                    status: .idea,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
            ],
            backlogCategoriesByID: [:]
        )

        let diff = after.taskContentDiff(from: before)
        XCTAssertEqual(diff.addedTaskCount, 0)
        XCTAssertEqual(diff.removedTaskCount, 0)
        XCTAssertEqual(diff.changedTaskIDs, [])
        XCTAssertFalse(diff.hasAnyChange)
    }

    func testTaskContentDiffTreatsIdeaPromotionAsTaskAddition() {
        let sharedID = UUID()
        let before = RemoteVisibleContentSnapshot(
            shoppingItemsByID: [:],
            shoppingBundlesByID: [:],
            workItemsByID: [
                sharedID: makeWorkItemState(title: "Plan trip", status: .idea),
            ],
            backlogCategoriesByID: [:]
        )
        let after = RemoteVisibleContentSnapshot(
            shoppingItemsByID: [:],
            shoppingBundlesByID: [:],
            workItemsByID: [
                sharedID: makeWorkItemState(
                    title: "Book flights",
                    status: .next,
                    updatedAt: Date(timeIntervalSince1970: 2)
                ),
            ],
            backlogCategoriesByID: [:]
        )

        let diff = after.taskContentDiff(from: before)
        XCTAssertEqual(diff.addedTaskCount, 1)
        XCTAssertEqual(diff.removedTaskCount, 0)
        XCTAssertEqual(diff.changedTaskIDs, [])
        XCTAssertTrue(diff.hasAnyChange)
    }
}
