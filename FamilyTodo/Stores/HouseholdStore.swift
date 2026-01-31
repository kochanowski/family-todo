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
    private var activeContainer: CKContainer?

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

                // Also fetch share if owner
                if fresh.ownerId == userId {
                    // We might want to fetch share metadata here if needed
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
        isLoading = true
        defer { isLoading = false }

        let newHousehold = Household(name: name, ownerId: userId)

        // 1. Save to CloudKit
        if syncMode == .cloud {
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

        // 2. Update Cache
        updateCache(with: newHousehold)
        currentHousehold = newHousehold

        return newHousehold
    }

    // MARK: - Sharing

    func createShare() async throws -> (CKShare, CKContainer) {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }

        let share = try await cloudKit.createShare(for: household)
        self.share = share
        return (share, CKContainer.default())
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
}
