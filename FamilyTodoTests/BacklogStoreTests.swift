@testable import HousePulse
import SwiftData
import XCTest

@MainActor
final class BacklogStoreTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var store: BacklogStore!
    private let householdId = UUID()

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            CachedBacklogItem.self,
            CachedBacklogCategory.self,
            CachedTask.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

        store = BacklogStore(householdId: householdId, modelContext: modelContainer.mainContext)
        store.setSyncMode(.localOnly)
    }

    override func tearDown() async throws {
        store = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testCachedBacklogItemRoundTripPreservesAssignee() {
        let assigneeId = UUID()
        let logicalItemID = UUID()
        let item = BacklogItem(
            logicalItemID: logicalItemID,
            categoryId: UUID(),
            householdId: householdId,
            title: "Laundry",
            assigneeId: assigneeId,
            notes: "Notes"
        )

        let cached = CachedBacklogItem(from: item)
        let restored = cached.toBacklogItem()

        XCTAssertEqual(restored.assigneeId, assigneeId)
        XCTAssertEqual(restored.logicalItemID, logicalItemID)
        XCTAssertEqual(restored.title, "Laundry")
    }

    func testPromoteUsesBacklogAssigneeWhenNoOverrideProvided() async throws {
        let categoryId = UUID()
        let assigneeId = UUID()
        await store.addItem(to: categoryId, title: "Vacuum living room", assigneeId: assigneeId)

        guard let backlogItem = store.items(for: categoryId).first else {
            XCTFail("Expected backlog item")
            return
        }

        let result = await store.promoteItemToTask(backlogItem, assigneeId: nil)

        switch result {
        case .success:
            break
        default:
            XCTFail("Expected promotion success, got \(result)")
            return
        }

        XCTAssertTrue(store.items(for: categoryId).isEmpty)

        let taskDescriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.title == "Vacuum living room" }
        )
        let cachedTasks = try modelContainer.mainContext.fetch(taskDescriptor)
        XCTAssertEqual(cachedTasks.count, 1)
        XCTAssertEqual(cachedTasks.first?.assigneeId, assigneeId)
        XCTAssertEqual(cachedTasks.first?.statusRaw, Task.TaskStatus.next.rawValue)

        let hydratedTaskStore = TaskStore(modelContext: modelContainer.mainContext)
        hydratedTaskStore.setHousehold(householdId)
        hydratedTaskStore.setSyncMode(.localOnly)
        await hydratedTaskStore.loadTasksForDisplay()

        XCTAssertEqual(hydratedTaskStore.tasks.count, 1)
        XCTAssertEqual(hydratedTaskStore.tasks.first?.title, "Vacuum living room")
    }

    func testPromoteReusesExistingTaskWithSameLogicalItemID() async throws {
        let category = BacklogCategory(
            householdId: householdId,
            title: "Projects",
            sortOrder: 0
        )
        modelContainer.mainContext.insert(CachedBacklogCategory(from: category))

        let logicalItemID = UUID()
        let backlogItem = BacklogItem(
            id: UUID(),
            logicalItemID: logicalItemID,
            categoryId: category.id,
            householdId: householdId,
            title: "Promote once",
            assigneeId: UUID()
        )
        let existingTask = Task(
            id: UUID(),
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: "Promote once",
            status: .next,
            assigneeId: backlogItem.assigneeId,
            taskType: .oneOff
        )

        modelContainer.mainContext.insert(CachedBacklogItem(from: backlogItem))
        modelContainer.mainContext.insert(CachedTask(from: existingTask))
        try modelContainer.mainContext.save()

        store.setSyncMode(.localOnly)
        await store.loadDataForDisplay()

        let result = await store.promoteItemToTask(backlogItem, assigneeId: backlogItem.assigneeId)

        switch result {
        case let .success(createdTaskId):
            XCTAssertEqual(createdTaskId, existingTask.id)
        default:
            XCTFail("Expected promotion success, got \(result)")
            return
        }

        XCTAssertTrue(store.items(for: category.id).isEmpty)

        let taskDescriptor = FetchDescriptor<CachedTask>(
            predicate: #Predicate { $0.householdId == householdId }
        )
        let cachedTasks = try modelContainer.mainContext.fetch(taskDescriptor)
        XCTAssertEqual(
            cachedTasks.filter { ($0.logicalItemID ?? $0.id) == logicalItemID }.count,
            1
        )
        XCTAssertEqual(cachedTasks.first?.id, existingTask.id)
    }

    func testDeleteItemInCloudModeReplacesVisibleCacheRowWithPendingDeleteTombstone() async throws {
        let categoryId = UUID()
        await store.addItem(to: categoryId, title: "Promoted idea")

        guard let item = store.items(for: categoryId).first else {
            XCTFail("Expected backlog item")
            return
        }

        store.setSyncMode(.cloud)
        let didDelete = await store.deleteItem(item)

        XCTAssertTrue(didDelete)
        XCTAssertTrue(store.items(for: categoryId).isEmpty)

        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == item.id }
        )
        let cachedItems = try modelContainer.mainContext.fetch(descriptor)
        XCTAssertEqual(cachedItems.count, 1)
        XCTAssertEqual(cachedItems.first?.syncStatusRaw, "pendingDelete")
    }

    func testUpdateItemUpsertsCacheWhenCachedRowMissing() async throws {
        let categoryId = UUID()
        let assigneeId = UUID()
        await store.addItem(to: categoryId, title: "Assign me")

        guard let createdItem = store.items(for: categoryId).first else {
            XCTFail("Expected backlog item")
            return
        }

        let cachedDescriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == createdItem.id }
        )
        if let cachedItem = try modelContainer.mainContext.fetch(cachedDescriptor).first {
            modelContainer.mainContext.delete(cachedItem)
            try modelContainer.mainContext.save()
        }

        await store.updateItem(
            createdItem,
            title: createdItem.title,
            notes: createdItem.notes,
            assigneeId: assigneeId
        )

        let reloadedCached = try modelContainer.mainContext.fetch(cachedDescriptor).first
        XCTAssertNotNil(reloadedCached)
        XCTAssertEqual(reloadedCached?.assigneeId, assigneeId)
    }

    func testSyncToCacheSkipsCloudRecordWhenItemIsPendingDelete() throws {
        let categoryId = UUID()
        let itemId = UUID()
        let localCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let localUpdatedAt = localCreatedAt.addingTimeInterval(5)
        let cloudUpdatedAt = localUpdatedAt.addingTimeInterval(120)

        let category = BacklogCategory(
            id: categoryId,
            householdId: householdId,
            title: "Home",
            sortOrder: 0,
            createdAt: localCreatedAt,
            updatedAt: localUpdatedAt
        )
        let cachedCategory = CachedBacklogCategory(from: category)
        modelContainer.mainContext.insert(cachedCategory)

        let localItem = BacklogItem(
            id: itemId,
            categoryId: categoryId,
            householdId: householdId,
            title: "Local tombstone title",
            createdAt: localCreatedAt,
            updatedAt: localUpdatedAt
        )
        let tombstone = CachedBacklogItem(from: localItem)
        tombstone.syncStatusRaw = "pendingDelete"
        tombstone.lastSyncedAt = nil
        modelContainer.mainContext.insert(tombstone)
        try modelContainer.mainContext.save()

        let staleCloudItem = BacklogItem(
            id: itemId,
            categoryId: categoryId,
            householdId: householdId,
            title: "Stale cloud title",
            createdAt: localCreatedAt,
            updatedAt: cloudUpdatedAt
        )

        store.syncToCache(
            categories: [category],
            items: [staleCloudItem],
            cloudCategoryIDs: [categoryId],
            cloudItemIDs: [itemId]
        )

        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == itemId }
        )
        let cachedItems = try modelContainer.mainContext.fetch(descriptor)
        XCTAssertEqual(cachedItems.count, 1)
        XCTAssertEqual(cachedItems.first?.syncStatusRaw, "pendingDelete")
        XCTAssertEqual(cachedItems.first?.title, "Local tombstone title")
    }

    func testSyncToCacheDoesNotAcceptSemanticStaleBacklogEcho() throws {
        let category = BacklogCategory(
            householdId: householdId,
            title: "Home",
            sortOrder: 0
        )
        modelContainer.mainContext.insert(CachedBacklogCategory(from: category))

        let localUpdatedAt = Date(timeIntervalSince1970: 1_736_910_000)
        let localItem = BacklogItem(
            id: UUID(),
            categoryId: category.id,
            householdId: householdId,
            title: "Moved locally",
            assigneeId: UUID(),
            notes: "local notes",
            updatedAt: localUpdatedAt
        )
        let cached = CachedBacklogItem(from: localItem)
        cached.syncStatusRaw = "awaitingCloudEcho"
        cached.lastSyncedAt = Date()
        modelContainer.mainContext.insert(cached)
        try modelContainer.mainContext.save()

        let staleCloudItem = BacklogItem(
            id: localItem.id,
            categoryId: category.id,
            householdId: householdId,
            title: localItem.title,
            assigneeId: localItem.assigneeId,
            notes: "stale notes",
            updatedAt: localUpdatedAt.addingTimeInterval(30)
        )

        store.syncToCache(
            categories: [category],
            items: [staleCloudItem],
            cloudCategoryIDs: [category.id],
            cloudItemIDs: [localItem.id]
        )

        let descriptor = FetchDescriptor<CachedBacklogItem>(
            predicate: #Predicate { $0.id == localItem.id }
        )
        guard let persisted = try modelContainer.mainContext.fetch(descriptor).first else {
            XCTFail("Expected cached backlog item after sync")
            return
        }

        XCTAssertEqual(persisted.notes, "local notes")
        XCTAssertEqual(persisted.syncStatusRaw, "awaitingCloudEcho")
    }

    func testDeleteCategoryIsBlockedWhenIdeasStillExist() async {
        await store.addCategory("Projects")

        guard let category = store.categories.first else {
            XCTFail("Expected category")
            return
        }

        await store.addItem(to: category.id, title: "Paint hallway")

        let result = await store.deleteCategory(category)

        XCTAssertEqual(result, .blocked(.ideas(count: 1)))
        XCTAssertEqual(store.categories.count, 1)
    }

    func testDeleteCategoryIsBlockedWhenTaskStillLinksToCategory() async throws {
        await store.addCategory("Errands")

        guard let category = store.categories.first else {
            XCTFail("Expected category")
            return
        }

        let task = Task(
            householdId: householdId,
            title: "Pick up parcel",
            status: .done,
            backlogCategoryId: category.id,
            taskType: .oneOff
        )
        modelContainer.mainContext.insert(CachedTask(from: task))
        try modelContainer.mainContext.save()

        let result = await store.deleteCategory(category)

        XCTAssertEqual(result, .blocked(.tasks(count: 1)))
        XCTAssertEqual(store.categories.count, 1)
        XCTAssertEqual(
            store.categoryDeletionBlockReason(for: category.id),
            .tasks(count: 1)
        )
    }

    func testInitHydratesCategoriesAndItemsFromCacheBeforeLoad() throws {
        let category = BacklogCategory(
            householdId: householdId,
            title: "Home"
        )
        let item = BacklogItem(
            categoryId: category.id,
            householdId: householdId,
            title: "Water plants"
        )
        modelContainer.mainContext.insert(CachedBacklogCategory(from: category))
        modelContainer.mainContext.insert(CachedBacklogItem(from: item))
        try modelContainer.mainContext.save()

        let hydratedStore = BacklogStore(
            householdId: householdId,
            modelContext: modelContainer.mainContext
        )

        XCTAssertTrue(hydratedStore.hasHydratedLocalSnapshot)
        XCTAssertEqual(hydratedStore.categories.count, 1)
        XCTAssertEqual(hydratedStore.categories.first?.title, "Home")
        XCTAssertEqual(hydratedStore.items(for: category.id).count, 1)
        XCTAssertEqual(hydratedStore.items(for: category.id).first?.title, "Water plants")
    }

    func testLoadDataForDisplayRehydratesWhenSnapshotMarkedStale() async throws {
        let originalCategory = BacklogCategory(
            householdId: householdId,
            title: "Original"
        )
        let originalItem = BacklogItem(
            categoryId: originalCategory.id,
            householdId: householdId,
            title: "Original idea"
        )
        modelContainer.mainContext.insert(CachedBacklogCategory(from: originalCategory))
        modelContainer.mainContext.insert(CachedBacklogItem(from: originalItem))
        try modelContainer.mainContext.save()

        await store.loadDataForDisplay()
        XCTAssertEqual(store.categories.map(\.title), ["Original"])

        let replacementCategory = BacklogCategory(
            householdId: householdId,
            title: "Updated",
            sortOrder: 0
        )
        let replacementItem = BacklogItem(
            categoryId: replacementCategory.id,
            householdId: householdId,
            title: "Updated idea"
        )

        let categoryDescriptor = FetchDescriptor<CachedBacklogCategory>()
        let itemDescriptor = FetchDescriptor<CachedBacklogItem>()
        for cachedCategory in try modelContainer.mainContext.fetch(categoryDescriptor) {
            modelContainer.mainContext.delete(cachedCategory)
        }
        for cachedItem in try modelContainer.mainContext.fetch(itemDescriptor) {
            modelContainer.mainContext.delete(cachedItem)
        }
        modelContainer.mainContext.insert(CachedBacklogCategory(from: replacementCategory))
        modelContainer.mainContext.insert(CachedBacklogItem(from: replacementItem))
        try modelContainer.mainContext.save()

        store.markLocalSnapshotStale()
        await store.loadDataForDisplay()

        XCTAssertEqual(store.categories.map(\.title), ["Updated"])
        XCTAssertEqual(store.items(for: replacementCategory.id).map(\.title), ["Updated idea"])
    }
}
