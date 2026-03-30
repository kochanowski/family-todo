import Foundation

struct HouseholdCloudSnapshot {
    let members: [Member]
    let unifiedWorkItems: [WorkItem]
    let shoppingItems: [ShoppingItem]
    let shoppingBundles: [ShoppingBundle]
    let backlogCategories: [BacklogCategory]
    let backlogItems: [BacklogItem]

    func hasActiveMembership(userId: String) -> Bool {
        members.contains { $0.userId == userId && $0.isActive }
    }
}

actor HouseholdCloudSnapshotLoader {
    private let cloud: any HouseholdCloudSyncing

    init(cloud: any HouseholdCloudSyncing) {
        self.cloud = cloud
    }

    func loadSnapshot(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) async throws -> HouseholdCloudSnapshot {
        await cloud.ensureReady()

        async let fetchedMembers = cloud.fetchMembers(
            householdId: householdId,
            scope: scope
        )
        async let fetchedUnifiedWorkItems = cloud.fetchUnifiedWorkItems(
            householdId: householdId,
            scope: scope
        )
        async let fetchedShoppingItems = cloud.fetchShoppingItems(
            householdId: householdId,
            scope: scope
        )
        async let fetchedBundles = cloud.fetchShoppingBundles(
            householdId: householdId,
            scope: scope
        )
        async let fetchedCategories = cloud.fetchBacklogCategories(
            householdId: householdId,
            scope: scope
        )
        async let fetchedBacklogItems = cloud.fetchBacklogItems(
            householdId: householdId,
            scope: scope
        )

        return try await HouseholdCloudSnapshot(
            members: fetchedMembers,
            unifiedWorkItems: fetchedUnifiedWorkItems,
            shoppingItems: fetchedShoppingItems,
            shoppingBundles: fetchedBundles,
            backlogCategories: fetchedCategories,
            backlogItems: fetchedBacklogItems
        )
    }
}
