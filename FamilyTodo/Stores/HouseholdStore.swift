import CloudKit
import Combine
import SwiftData
import SwiftUI
import UIKit

@MainActor
class HouseholdStore: ObservableObject {
    @Published var currentHousehold: Household?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var share: CKShare?

    private var modelContext: ModelContext?
    private lazy var cloudKit = CloudKitManager.shared
    private var syncMode: SyncMode = .cloud

    // Cache for sharing controller
    private var activeShare: CKShare?
    private(set) var activeContainer: CKContainer?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setSyncMode(_ mode: SyncMode) {
        syncMode = mode
    }

    // MARK: - Lifecycle

    func loadHousehold(userId: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // 1. Try to load from cache first
        if let cached = fetchCachedHousehold(userId: userId) {
            currentHousehold = cached.toHousehold()
        }

        guard syncMode == .cloud else { return }

        // 2. Load from CloudKit
        do {
            // Ensure CloudKit is ready before accessing
            await cloudKit.ensureReady()

            // In a real app with private DB + sharing, finding the "current" household
            // often involves querying for the one owned by user or shared with them.
            // For MVP/HousePulse, we check if we have one locally, otherwise we might look
            // for the one where we are a member.

            // NOTE: This logic assumes 1 household per user for simplicity in this iteration.
            // If we have a cached one, refresh it.
            if let current = currentHousehold {
                let fresh = try await cloudKit.fetchHousehold(id: current.id)
                updateCache(with: fresh)
                currentHousehold = fresh
            } else {
                // If checking cloud for the first time on this device
                print("DEBUG: Checking CloudKit for existing household membership...")
                // Try to find a member record for this user
                if let member = try await cloudKit.fetchMemberByUserId(userId) {
                    print("DEBUG: Found member membership for household: \(member.householdId)")
                    let fresh = try await cloudKit.fetchHousehold(id: member.householdId)
                    updateCache(with: fresh)
                    currentHousehold = fresh
                } else {
                    print("DEBUG: No existing membership found in cloud.")
                }
            }
        } catch {
            print("Error loading household: \(error)")
            // Don't show error to user if we have cached data
            if currentHousehold == nil {
                self.error = error
            }
        }
    }

    func createHousehold(name: String, userId: String, displayName: String) async throws -> Household {
        // CloudKit safety check
        precondition(
            syncMode == .localOnly || syncMode == .cloud,
            "Invalid sync mode for household creation"
        )

        isLoading = true
        defer { isLoading = false }

        let newHousehold = Household(name: name, ownerId: userId)

        // 1. Save to CloudKit (if cloud sync is enabled and available)
        if syncMode == .cloud {
            // Check CloudKit availability first
            try await cloudKit.checkAvailability()

            _ = try await cloudKit.saveHousehold(newHousehold)

            // Create initial member (owner)
            let owner = Member(
                householdId: newHousehold.id,
                userId: userId,
                displayName: displayName,
                role: .owner
            )
            _ = try await cloudKit.saveMember(owner)
        }

        // 2. Seed default data in local-only mode
        if syncMode == .localOnly {
            try seedDefaultData(
                householdId: newHousehold.id,
                userId: userId,
                displayName: displayName
            )
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
        let container = await cloudKit.getContainer()

        let share = try await cloudKit.createShare(for: household)
        self.share = share
        activeContainer = container
        return (share, container)
    }

    // MARK: - Join Household

    func joinHousehold(inviteCode: String, userId: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard syncMode == .cloud else {
            throw HouseholdError.cloudSyncRequired
        }

        // Accept the share using the invite code (CloudKit share URL)
        let household = try await cloudKit.acceptShare(inviteCode: inviteCode)

        // Create member record for the joining user
        let member = Member(
            householdId: household.id,
            userId: userId,
            displayName: displayName,
            role: .member
        )
        _ = try await cloudKit.saveMember(member)

        // Update local cache
        updateCache(with: household)
        currentHousehold = household
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedHousehold(userId _: String) -> CachedHousehold? {
        guard let context = modelContext else { return nil }

        // Logic: Find household where ownerId == userId OR (TODO: handle shared households)
        // For now, simple fetch
        let descriptor = FetchDescriptor<CachedHousehold>()
        do {
            return try context.fetch(descriptor).first
        } catch {
            print("Fetch error: \(error)")
            return nil
        }
    }

    private func updateCache(with household: Household) {
        guard let context = modelContext else { return }

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
            try context.save()
        } catch {
            print("Cache update error: \(error)")
        }
    }

    // MARK: - Guest Mode Data Seeding

    private func seedDefaultData(
        householdId: UUID,
        userId: String,
        displayName: String
    ) throws {
        guard let context = modelContext else {
            throw HouseholdError.cacheNotAvailable
        }

        // 1. Create owner member
        let ownerMember = Member(
            householdId: householdId,
            userId: userId,
            displayName: displayName,
            role: .owner
        )
        context.insert(CachedMember(from: ownerMember))

        // 2. Create 8 starter tasks (3 next, 4 backlog, 1 done)
        let tasks = createStarterTasks(
            householdId: householdId,
            memberId: ownerMember.id
        )
        for task in tasks {
            context.insert(CachedTask(from: task))
        }

        // 3. Create 5 shopping items
        let items = createStarterShoppingItems(householdId: householdId)
        for item in items {
            context.insert(CachedShoppingItem(from: item))
        }

        // 4. Create backlog categories and items
        let (categories, backlogItems) = createStarterBacklog(householdId: householdId)
        for category in categories {
            context.insert(CachedBacklogCategory(from: category))
        }
        for item in backlogItems {
            context.insert(CachedBacklogItem(from: item))
        }

        // Save all
        try context.save()
    }

    private func createStarterTasks(
        householdId: UUID,
        memberId: UUID
    ) -> [Task] {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let thisWeek = Calendar.current.date(byAdding: .day, value: 5, to: today) ?? today

        return [
            // Next tasks (3 - respects WIP limit)
            Task(
                householdId: householdId,
                title: "Clean kitchen counters",
                status: .next,
                assigneeId: memberId,
                assigneeIds: [memberId],
                dueDate: today,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Take out trash",
                status: .next,
                assigneeId: memberId,
                assigneeIds: [memberId],
                dueDate: today,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Water plants",
                status: .next,
                assigneeId: memberId,
                assigneeIds: [memberId],
                dueDate: thisWeek,
                taskType: .oneOff
            ),

            // Backlog tasks (4)
            Task(
                householdId: householdId,
                title: "Vacuum living room",
                status: .backlog,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Clean bathroom sink",
                status: .backlog,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Change bed sheets",
                status: .backlog,
                taskType: .oneOff
            ),
            Task(
                householdId: householdId,
                title: "Organize pantry",
                status: .backlog,
                taskType: .oneOff
            ),

            // Done task (1 - shows completion)
            Task(
                householdId: householdId,
                title: "Wipe dining table",
                status: .done,
                assigneeId: memberId,
                assigneeIds: [memberId],
                completedAt: yesterday,
                completedById: memberId.uuidString,
                taskType: .oneOff
            ),
        ]
    }

    private func createStarterShoppingItems(householdId: UUID) -> [ShoppingItem] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        return [
            ShoppingItem(
                householdId: householdId,
                title: "Milk",
                quantityValue: "2",
                quantityUnit: "L"
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Bread",
                quantityValue: "1",
                quantityUnit: "loaf"
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Dish soap",
                quantityValue: "1",
                quantityUnit: "bottle"
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Paper towels",
                quantityValue: "2",
                quantityUnit: "rolls",
                isBought: true,
                boughtAt: yesterday,
                restockCount: 1
            ),
            ShoppingItem(
                householdId: householdId,
                title: "Coffee",
                quantityValue: "200",
                quantityUnit: "g"
            ),
        ]
    }

    private func createStarterBacklog(
        householdId: UUID
    ) -> (categories: [BacklogCategory], items: [BacklogItem]) {
        let homeProjectsCategory = BacklogCategory(
            householdId: householdId,
            title: "Home Projects",
            sortOrder: 0
        )

        let routineCategory = BacklogCategory(
            householdId: householdId,
            title: "Weekly Routine",
            sortOrder: 1
        )

        let items = [
            BacklogItem(
                categoryId: homeProjectsCategory.id,
                householdId: householdId,
                title: "Paint bedroom walls",
                notes: "Need to buy paint and brushes"
            ),
            BacklogItem(
                categoryId: homeProjectsCategory.id,
                householdId: householdId,
                title: "Fix leaky faucet"
            ),
            BacklogItem(
                categoryId: homeProjectsCategory.id,
                householdId: householdId,
                title: "Install new shelves in garage"
            ),
            BacklogItem(
                categoryId: routineCategory.id,
                householdId: householdId,
                title: "Deep clean bathroom"
            ),
            BacklogItem(
                categoryId: routineCategory.id,
                householdId: householdId,
                title: "Mow the lawn"
            ),
        ]

        return ([homeProjectsCategory, routineCategory], items)
    }
}
