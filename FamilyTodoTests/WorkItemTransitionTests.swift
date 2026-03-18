@testable import HousePulse
import SwiftData
import XCTest

@MainActor
final class WorkItemTransitionTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private let householdId = UUID()
    private let assigneeId = UUID()

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .appCache)
    }

    override func tearDown() async throws {
        modelContainer = nil
        try await super.tearDown()
    }

    func testPromotionResurrectionGuardKeepsPromotedItemOutOfIdeasAfterStaleCloudIdeaEcho() async throws {
        let category = TestCacheFixtures.category(householdId: householdId, title: "Ideas")
        let idea = TestCacheFixtures.idea(
            categoryId: category.id,
            householdId: householdId,
            title: "Promote me",
            assigneeId: assigneeId
        )

        try TestCacheFixtures.insert(
            CachedBacklogCategory(from: category),
            into: modelContainer.mainContext,
            save: true
        )
        try TestCacheFixtures.insert(
            TestCacheFixtures.cachedWorkItem(from: WorkItem(idea: idea)),
            into: modelContainer.mainContext,
            save: true
        )

        let backlogStore = makeBacklogStore()
        let taskStore = makeTaskStore()
        await backlogStore.loadDataForDisplay()
        await taskStore.loadTasksForDisplay()

        let promotedTaskId: UUID
        switch backlogStore.promoteItemToTask(idea, assigneeId: assigneeId) {
        case let .success(createdTaskId):
            promotedTaskId = createdTaskId
        default:
            XCTFail("Expected local promotion to succeed")
            return
        }

        taskStore.rehydrateVisibleSnapshotFromCache()

        XCTAssertFalse(backlogStore.items(for: category.id).contains(where: { $0.logicalItemID == idea.logicalItemID }))
        XCTAssertEqual(taskStore.tasks.filter { $0.logicalItemID == idea.logicalItemID }.count, 1)

        try markWorkItemAwaitingCloudEcho(id: promotedTaskId)

        let staleIdea = BacklogItem(
            id: idea.id,
            logicalItemID: idea.logicalItemID,
            categoryId: category.id,
            householdId: householdId,
            title: "Stale cloud idea",
            assigneeId: assigneeId,
            notes: "old server state",
            createdAt: idea.createdAt,
            updatedAt: idea.updatedAt.addingTimeInterval(120)
        )

        backlogStore.syncToCache(
            categories: [category],
            items: [staleIdea],
            cloudCategoryIDs: [category.id],
            cloudItemIDs: [idea.id]
        )
        backlogStore.rehydrateVisibleSnapshotFromCache()
        taskStore.rehydrateVisibleSnapshotFromCache()

        XCTAssertFalse(backlogStore.items(for: category.id).contains(where: { $0.logicalItemID == idea.logicalItemID }))
        let visibleTasks = taskStore.tasks.filter { $0.logicalItemID == idea.logicalItemID }
        XCTAssertEqual(visibleTasks.count, 1)
        XCTAssertEqual(visibleTasks.first?.status, .next)
        XCTAssertEqual(try fetchCachedWorkItems(logicalItemID: idea.logicalItemID).count, 1)
    }

    func testDemotionResurrectionGuardKeepsDemotedItemOutOfTasksAfterStaleCloudTaskEcho() async throws {
        let category = TestCacheFixtures.category(householdId: householdId, title: "Ideas")
        let originalDueDate = TestCacheFixtures.timestamp(600)
        let task = TestCacheFixtures.task(
            householdId: householdId,
            title: "Move me back",
            status: .next,
            assigneeId: assigneeId,
            areaId: UUID(),
            dueDate: originalDueDate,
            lastPokedAt: TestCacheFixtures.timestamp(300)
        )

        try TestCacheFixtures.insert(
            CachedBacklogCategory(from: category),
            into: modelContainer.mainContext,
            save: true
        )
        try TestCacheFixtures.insert(
            TestCacheFixtures.cachedWorkItem(from: WorkItem(task: task)),
            into: modelContainer.mainContext,
            save: true
        )

        let backlogStore = makeBacklogStore()
        let taskStore = makeTaskStore()
        await backlogStore.loadDataForDisplay()
        await taskStore.loadTasksForDisplay()

        let moveResult = taskStore.moveTaskToIdeas(task, destinationCategoryId: category.id)
        XCTAssertEqual(moveResult, .success(categoryId: category.id))

        backlogStore.rehydrateVisibleSnapshotFromCache()

        XCTAssertTrue(taskStore.tasks.filter { $0.logicalItemID == task.logicalItemID }.isEmpty)
        XCTAssertEqual(backlogStore.items(for: category.id).filter { $0.logicalItemID == task.logicalItemID }.count, 1)

        let demotedRow = try XCTUnwrap(fetchCachedWorkItem(id: task.id))
        XCTAssertEqual(demotedRow.statusRaw, WorkItem.Status.idea.rawValue)
        XCTAssertEqual(demotedRow.categoryId, category.id)
        XCTAssertNil(demotedRow.dueDate)
        XCTAssertNil(demotedRow.completedAt)
        XCTAssertNil(demotedRow.areaId)

        try markWorkItemAwaitingCloudEcho(id: task.id)

        let staleTask = Task(
            id: task.id,
            logicalItemID: task.logicalItemID,
            householdId: householdId,
            title: "Stale cloud task",
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            areaId: UUID(),
            dueDate: originalDueDate.addingTimeInterval(300),
            taskType: .oneOff,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt.addingTimeInterval(180)
        )

        taskStore.syncToCache([staleTask], cloudTaskIDs: [task.id])
        taskStore.rehydrateVisibleSnapshotFromCache()
        backlogStore.rehydrateVisibleSnapshotFromCache()

        XCTAssertTrue(taskStore.tasks.filter { $0.logicalItemID == task.logicalItemID }.isEmpty)
        XCTAssertEqual(backlogStore.items(for: category.id).filter { $0.logicalItemID == task.logicalItemID }.count, 1)
        XCTAssertEqual(try fetchCachedWorkItems(logicalItemID: task.logicalItemID).count, 1)
    }

    func testCompletionResurrectionGuardKeepsLocallyCompletedTaskDoneAfterStaleCloudEcho() async throws {
        let task = TestCacheFixtures.task(
            householdId: householdId,
            title: "Finish me",
            status: .next,
            assigneeId: assigneeId,
            updatedAt: TestCacheFixtures.timestamp(60)
        )
        try TestCacheFixtures.insert(
            TestCacheFixtures.cachedWorkItem(from: WorkItem(task: task)),
            into: modelContainer.mainContext,
            save: true
        )

        let taskStore = makeTaskStore()
        await taskStore.loadTasksForDisplay()

        let result = await taskStore.toggleTaskCompletion(task)
        XCTAssertEqual(result, .ok)

        guard let completedTask = taskStore.doneTasks.first(where: { $0.id == task.id }) else {
            XCTFail("Expected task to be completed locally")
            return
        }

        XCTAssertNil(taskStore.nextTasks.first(where: { $0.id == task.id }))
        XCTAssertNotNil(completedTask.completedAt)

        try markWorkItemAwaitingCloudEcho(id: task.id)

        let staleTask = Task(
            id: task.id,
            logicalItemID: task.logicalItemID,
            householdId: householdId,
            title: task.title,
            status: .next,
            assigneeId: assigneeId,
            assigneeIds: [assigneeId],
            taskType: .oneOff,
            createdAt: task.createdAt,
            updatedAt: completedTask.updatedAt.addingTimeInterval(180)
        )

        taskStore.syncToCache([staleTask], cloudTaskIDs: [task.id])
        taskStore.rehydrateVisibleSnapshotFromCache()

        XCTAssertNil(taskStore.nextTasks.first(where: { $0.id == task.id }))
        XCTAssertEqual(taskStore.doneTasks.filter { $0.id == task.id }.count, 1)

        let persisted = try XCTUnwrap(fetchCachedWorkItem(id: task.id))
        XCTAssertEqual(persisted.statusRaw, WorkItem.Status.done.rawValue)
        XCTAssertNotNil(persisted.completedAt)
    }

    func testBundleDeleteEchoGuardKeepsDeletedBundleHiddenUntilCloudAbsenceIsConfirmed() async throws {
        let bundle = TestCacheFixtures.shoppingBundle(
            householdId: householdId,
            name: "Weekend breakfast",
            items: ["Eggs", "Bread"]
        )
        try TestCacheFixtures.insert(
            TestCacheFixtures.cachedShoppingBundle(from: bundle),
            into: modelContainer.mainContext,
            save: true
        )

        var bundleStore = makeBundleStore()
        await bundleStore.loadBundlesForDisplay()
        XCTAssertEqual(bundleStore.bundles.map(\.id), [bundle.id])

        let cachedDescriptor = FetchDescriptor<CachedShoppingBundle>(
            predicate: #Predicate { $0.id == bundle.id }
        )

        guard let cachedBundle = try modelContainer.mainContext.fetch(cachedDescriptor).first else {
            XCTFail("Expected cached bundle to exist")
            return
        }

        cachedBundle.syncStatusRaw = "pendingDelete"
        cachedBundle.lastSyncedAt = nil
        try modelContainer.mainContext.save()

        bundleStore = makeBundleStore()
        await bundleStore.loadBundlesForDisplay()
        XCTAssertTrue(bundleStore.bundles.isEmpty)

        var snapshot = try bundleStore.pendingSyncSnapshot(
            from: modelContainer.mainContext.fetch(FetchDescriptor<CachedShoppingBundle>())
        )
        XCTAssertTrue(bundleStore.mergeCloudSnapshot([bundle], with: snapshot).isEmpty)

        cachedBundle.syncStatusRaw = "awaitingDeleteEcho"
        cachedBundle.lastSyncedAt = Date()
        try modelContainer.mainContext.save()

        bundleStore = makeBundleStore()
        await bundleStore.loadBundlesForDisplay()
        XCTAssertTrue(bundleStore.bundles.isEmpty)

        snapshot = try bundleStore.pendingSyncSnapshot(
            from: modelContainer.mainContext.fetch(FetchDescriptor<CachedShoppingBundle>())
        )
        XCTAssertTrue(bundleStore.mergeCloudSnapshot([bundle], with: snapshot).isEmpty)
    }

    func testPromoteThenDemoteSameLogicalItemReappearsInIdeas() async throws {
        let category = TestCacheFixtures.category(householdId: householdId, title: "Ideas")
        let idea = TestCacheFixtures.idea(
            categoryId: category.id,
            householdId: householdId,
            title: "Promote then demote me",
            assigneeId: assigneeId
        )

        try TestCacheFixtures.insert(
            CachedBacklogCategory(from: category),
            into: modelContainer.mainContext,
            save: true
        )
        try TestCacheFixtures.insert(
            TestCacheFixtures.cachedWorkItem(from: WorkItem(idea: idea)),
            into: modelContainer.mainContext,
            save: true
        )

        let backlogStore = makeBacklogStore()
        let taskStore = makeTaskStore()
        await backlogStore.loadDataForDisplay()
        await taskStore.loadTasksForDisplay()

        switch backlogStore.promoteItemToTask(idea, assigneeId: assigneeId) {
        case .success:
            break
        default:
            XCTFail("Expected local promotion to succeed")
            return
        }

        taskStore.rehydrateVisibleSnapshotFromCache()

        XCTAssertFalse(backlogStore.items(for: category.id).contains(where: { $0.logicalItemID == idea.logicalItemID }))
        XCTAssertEqual(taskStore.tasks.filter { $0.logicalItemID == idea.logicalItemID }.count, 1)

        guard let promotedTask = taskStore.tasks.first(where: { $0.logicalItemID == idea.logicalItemID }) else {
            XCTFail("Expected promoted task to be visible in taskStore")
            return
        }

        let demoteResult = taskStore.moveTaskToIdeas(promotedTask, destinationCategoryId: category.id)
        XCTAssertEqual(demoteResult, .success(categoryId: category.id))

        backlogStore.rehydrateVisibleSnapshotFromCache()

        let reappearedIdeas = backlogStore.items(for: category.id).filter { $0.logicalItemID == idea.logicalItemID }
        XCTAssertEqual(reappearedIdeas.count, 1)
        XCTAssertTrue(taskStore.tasks.filter { $0.logicalItemID == idea.logicalItemID }.isEmpty)
    }

    private func makeTaskStore() -> TaskStore {
        let taskStore = TaskStore(modelContext: modelContainer.mainContext)
        taskStore.setHousehold(householdId)
        taskStore.setSyncMode(SyncMode.localOnly)
        return taskStore
    }

    private func makeBacklogStore() -> BacklogStore {
        let backlogStore = BacklogStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        backlogStore.setSyncMode(SyncMode.localOnly)
        return backlogStore
    }

    private func makeBundleStore() -> ShoppingBundleStore {
        let bundleStore = ShoppingBundleStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )
        bundleStore.setSyncMode(SyncMode.localOnly)
        return bundleStore
    }

    private func markWorkItemAwaitingCloudEcho(id: UUID) throws {
        guard let cached = try fetchCachedWorkItem(id: id) else {
            XCTFail("Expected cached work item for id \(id)")
            return
        }
        cached.syncStatusRaw = WorkItemCacheStoreSupport.awaitingCloudEcho
        cached.lastSyncedAt = Date()
        try modelContainer.mainContext.save()
    }

    private func fetchCachedWorkItem(id: UUID) throws -> CachedWorkItem? {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContainer.mainContext.fetch(descriptor).first
    }

    private func fetchCachedWorkItems(logicalItemID: UUID) throws -> [CachedWorkItem] {
        let descriptor = FetchDescriptor<CachedWorkItem>(
            predicate: #Predicate { $0.logicalItemID == logicalItemID }
        )
        return try modelContainer.mainContext.fetch(descriptor)
    }
}
