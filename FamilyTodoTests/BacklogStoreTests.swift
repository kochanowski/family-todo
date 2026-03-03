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
        let item = BacklogItem(
            categoryId: UUID(),
            householdId: householdId,
            title: "Laundry",
            assigneeId: assigneeId,
            notes: "Notes"
        )

        let cached = CachedBacklogItem(from: item)
        let restored = cached.toBacklogItem()

        XCTAssertEqual(restored.assigneeId, assigneeId)
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
}
