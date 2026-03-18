import Foundation
@testable import HousePulse
import SwiftData

enum TestCacheFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_736_000_000)

    static func timestamp(_ offset: TimeInterval = 0) -> Date {
        referenceDate.addingTimeInterval(offset)
    }

    static func household(
        id: UUID = UUID(),
        name: String = "Test Household",
        iconSymbol: String = "house.fill",
        ownerId: String = "owner-user-id",
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> Household {
        Household(
            id: id,
            name: name,
            iconSymbol: iconSymbol,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func cachedHousehold(
        from household: Household,
        colorHex: String = MemberColorToken.fallbackHex
    ) -> CachedHousehold {
        let cached = CachedHousehold(from: household)
        cached.colorHex = colorHex
        return cached
    }

    static func member(
        id: UUID = UUID(),
        householdId: UUID,
        userId: String = "member-user-id",
        displayName: String = "Alex",
        role: Member.MemberRole = .member,
        joinedAt: Date = referenceDate,
        isActive: Bool = true,
        colorHex: String? = MemberColorToken.fallbackHex
    ) -> Member {
        Member(
            id: id,
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: role,
            joinedAt: joinedAt,
            isActive: isActive,
            colorHex: colorHex
        )
    }

    static func cachedMember(
        from member: Member,
        syncStatus: String = "synced",
        lastSyncedAt: Date? = nil
    ) -> CachedMember {
        let cached = CachedMember(from: member)
        cached.syncStatusRaw = syncStatus
        cached.lastSyncedAt = resolvedLastSyncedAt(
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt
        )
        return cached
    }

    static func category(
        id: UUID = UUID(),
        householdId: UUID,
        title: String = "Ideas",
        colorHex: String = MemberColorToken.fallbackHex,
        sortOrder: Int = 0,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> BacklogCategory {
        BacklogCategory(
            id: id,
            householdId: householdId,
            title: title,
            colorHex: colorHex,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func cachedCategory(
        from category: BacklogCategory,
        syncStatus: String = "synced",
        lastSyncedAt: Date? = nil
    ) -> CachedBacklogCategory {
        let cached = CachedBacklogCategory(from: category)
        cached.syncStatusRaw = syncStatus
        cached.lastSyncedAt = resolvedLastSyncedAt(
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt
        )
        return cached
    }

    static func idea(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
        categoryId: UUID,
        householdId: UUID,
        title: String = "Idea",
        assigneeId: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> BacklogItem {
        BacklogItem(
            id: id,
            logicalItemID: logicalItemID,
            categoryId: categoryId,
            householdId: householdId,
            title: title,
            assigneeId: assigneeId,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func task(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
        householdId: UUID,
        title: String = "Task",
        status: Task.TaskStatus = .next,
        assigneeId: UUID? = UUID(),
        assigneeIds: [UUID]? = nil,
        backlogCategoryId: UUID? = nil,
        areaId: UUID? = nil,
        dueDate: Date? = nil,
        lastPokedAt: Date? = nil,
        completedAt: Date? = nil,
        completedById: String? = nil,
        taskType: Task.TaskType = .oneOff,
        recurringChoreId: UUID? = nil,
        notes: String? = nil,
        order: Int = 0,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> Task {
        let resolvedAssigneeIds = assigneeIds ?? assigneeId.map { [$0] } ?? []
        return Task(
            id: id,
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: assigneeId,
            assigneeIds: resolvedAssigneeIds,
            backlogCategoryId: backlogCategoryId,
            areaId: areaId,
            dueDate: dueDate,
            lastPokedAt: lastPokedAt,
            completedAt: completedAt,
            completedById: completedById,
            taskType: taskType,
            recurringChoreId: recurringChoreId,
            notes: notes,
            order: order,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func ideaWorkItem(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
        categoryId: UUID,
        householdId: UUID,
        title: String = "Idea",
        assigneeId: UUID? = nil,
        notes: String? = nil,
        order: Int = 0,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> WorkItem {
        WorkItem(
            id: id,
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: title,
            status: .idea,
            assigneeId: assigneeId,
            assigneeIds: assigneeId.map { [$0] } ?? [],
            categoryId: categoryId,
            notes: notes,
            order: order,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func taskWorkItem(
        id: UUID = UUID(),
        logicalItemID: UUID? = nil,
        householdId: UUID,
        title: String = "Task",
        status: WorkItem.Status = .next,
        assigneeId: UUID? = UUID(),
        assigneeIds: [UUID]? = nil,
        categoryId: UUID? = nil,
        areaId: UUID? = nil,
        dueDate: Date? = nil,
        lastPokedAt: Date? = nil,
        completedAt: Date? = nil,
        completedById: String? = nil,
        taskType: WorkItem.ItemType = .oneOff,
        recurringChoreId: UUID? = nil,
        notes: String? = nil,
        order: Int = 0,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> WorkItem {
        let resolvedAssigneeIds = assigneeIds ?? assigneeId.map { [$0] } ?? []
        return WorkItem(
            id: id,
            logicalItemID: logicalItemID,
            householdId: householdId,
            title: title,
            status: status,
            assigneeId: assigneeId,
            assigneeIds: resolvedAssigneeIds,
            categoryId: categoryId,
            areaId: areaId,
            dueDate: dueDate,
            lastPokedAt: lastPokedAt,
            completedAt: completedAt,
            completedById: completedById,
            taskType: taskType,
            recurringChoreId: recurringChoreId,
            notes: notes,
            order: order,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func cachedWorkItem(
        from item: WorkItem,
        syncStatus: String = "synced",
        lastSyncedAt: Date? = nil
    ) -> CachedWorkItem {
        let cached = CachedWorkItem(from: item)
        cached.syncStatusRaw = syncStatus
        cached.lastSyncedAt = resolvedLastSyncedAt(
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt
        )
        return cached
    }

    static func shoppingItem(
        id: UUID = UUID(),
        householdId: UUID,
        title: String = "Milk",
        quantityValue: String? = nil,
        quantityUnit: String? = nil,
        isBought: Bool = false,
        boughtAt: Date? = nil,
        restockCount: Int = 0,
        sortOrder: Int = 0,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> ShoppingItem {
        ShoppingItem(
            id: id,
            householdId: householdId,
            title: title,
            quantityValue: quantityValue,
            quantityUnit: quantityUnit,
            isBought: isBought,
            boughtAt: boughtAt,
            restockCount: restockCount,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func cachedShoppingItem(
        from item: ShoppingItem,
        syncStatus: String = "synced",
        lastSyncedAt: Date? = nil
    ) -> CachedShoppingItem {
        let cached = CachedShoppingItem(from: item)
        cached.syncStatusRaw = syncStatus
        cached.lastSyncedAt = resolvedLastSyncedAt(
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt
        )
        return cached
    }

    static func shoppingBundle(
        id: UUID = UUID(),
        householdId: UUID,
        name: String = "Weekend breakfast",
        icon: String = ShoppingBundle.creationDefaultIcon,
        items: [String] = ["Eggs", "Bread"],
        sortOrder: Int = 0,
        createdAt: Date = referenceDate,
        updatedAt: Date = referenceDate
    ) -> ShoppingBundle {
        ShoppingBundle(
            id: id,
            householdId: householdId,
            name: name,
            icon: icon,
            items: items,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func cachedShoppingBundle(
        from bundle: ShoppingBundle,
        syncStatus: String = "synced",
        lastSyncedAt: Date? = nil
    ) -> CachedShoppingBundle {
        let cached = CachedShoppingBundle(from: bundle)
        cached.syncStatusRaw = syncStatus
        cached.lastSyncedAt = resolvedLastSyncedAt(
            syncStatus: syncStatus,
            lastSyncedAt: lastSyncedAt
        )
        return cached
    }

    @discardableResult
    static func insert<Model: PersistentModel>(
        _ model: Model,
        into context: ModelContext,
        save: Bool = false
    ) throws -> Model {
        context.insert(model)
        if save {
            try context.save()
        }
        return model
    }

    static func insert<Models: Sequence>(
        _ models: Models,
        into context: ModelContext,
        save: Bool = false
    ) throws where Models.Element: PersistentModel {
        for model in models {
            context.insert(model)
        }
        if save {
            try context.save()
        }
    }

    static func save(_ context: ModelContext) throws {
        try context.save()
    }

    private static func resolvedLastSyncedAt(
        syncStatus: String,
        lastSyncedAt: Date?
    ) -> Date? {
        if let lastSyncedAt {
            return lastSyncedAt
        }

        return syncStatus == "synced" ? referenceDate : nil
    }
}
