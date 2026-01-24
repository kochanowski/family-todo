import Foundation
import SwiftData

/// Store for household members
@MainActor
final class MemberStore: ObservableObject {
    @Published private(set) var members: [Member] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var modelContext: ModelContext?

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
    }

    /// Set model context for offline caching
    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func loadMembers() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        // 1. Load from cache first (instant UI)
        loadFromCache()

        // 2. Sync with CloudKit in background
        do {
            let fetchedMembers = try await cloudKit.fetchMembers(householdId: householdId)
            members = fetchedMembers
            members.sort {
                if $0.role != $1.role {
                    return $0.role == .owner
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            // 3. Update cache
            syncToCache(fetchedMembers)
        } catch {
            // Keep cached data on error
            self.error = error
        }

        isLoading = false
    }

    private func loadFromCache() {
        guard let context = modelContext, let householdId else { return }

        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId }
        )

        if let cachedMembers = try? context.fetch(descriptor) {
            members = cachedMembers.map { $0.toMember() }
            members.sort {
                if $0.role != $1.role {
                    return $0.role == .owner
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private func syncToCache(_ members: [Member]) {
        guard let context = modelContext else { return }

        for member in members {
            let descriptor = FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.id == member.id }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.update(from: member)
            } else {
                let cached = CachedMember(from: member)
                context.insert(cached)
            }
        }

        try? context.save()
    }

    // MARK: - Member Management

    /// Update member display name
    func updateMember(id: UUID, displayName: String, currentUserId _: String?) async throws {
        guard !displayName.isEmpty else {
            throw MemberStoreError.invalidDisplayName
        }

        // Fetch current member
        guard var member = members.first(where: { $0.id == id }) else {
            throw MemberStoreError.memberNotFound
        }

        // Update display name
        member = Member(
            id: member.id,
            householdId: member.householdId,
            userId: member.userId,
            displayName: displayName,
            role: member.role,
            joinedAt: member.joinedAt,
            isActive: member.isActive
        )

        // Optimistic UI update
        if let index = members.firstIndex(where: { $0.id == id }) {
            members[index] = member
        }

        // Save to cache with pending status
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.id == id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: member)
                cached.syncStatusRaw = "pendingUpload"
                try? context.save()
            }
        }

        // Save to CloudKit
        do {
            _ = try await cloudKit.saveMember(member)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedMember>(
                    predicate: #Predicate { $0.id == id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    try? context.save()
                }
            }
        } catch {
            // Keep in cache with pending status
            throw error
        }
    }

    /// Delete member with validations
    func deleteMember(id: UUID, currentUserId: String?) async throws {
        guard let member = members.first(where: { $0.id == id }) else {
            throw MemberStoreError.memberNotFound
        }

        // Validation: Cannot delete yourself if you're owner
        if let currentUserId, member.userId == currentUserId, member.role == .owner {
            throw MemberStoreError.cannotDeleteSelfAsOwner
        }

        // Validation: Must have at least one owner remaining
        let remainingOwners = members.filter { $0.role == .owner && $0.id != id }
        if remainingOwners.isEmpty {
            throw MemberStoreError.cannotDeleteLastOwner
        }

        // Optimistic UI update
        members.removeAll(where: { $0.id == id })

        // Mark as pending delete in cache
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.id == id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.syncStatusRaw = "pendingDelete"
                try? context.save()
            }
        }

        // Delete from CloudKit
        do {
            try await cloudKit.deleteMember(id: id)

            // Remove from cache
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedMember>(
                    predicate: #Predicate { $0.id == id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    context.delete(cached)
                    try? context.save()
                }
            }
        } catch {
            // Restore member in UI on failure
            if !members.contains(where: { $0.id == id }) {
                members.append(member)
                members.sort {
                    if $0.role != $1.role {
                        return $0.role == .owner
                    }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            }
            throw error
        }
    }

    /// Update member role with validations
    func updateRole(id: UUID, newRole: Member.MemberRole, currentUserId: String?) async throws {
        guard let member = members.first(where: { $0.id == id }) else {
            throw MemberStoreError.memberNotFound
        }

        // Validation: Only owner can change roles
        guard let currentUserId,
              let currentUser = members.first(where: { $0.userId == currentUserId }),
              currentUser.role == .owner
        else {
            throw MemberStoreError.insufficientPermissions
        }

        // Validation: Cannot remove owner role from yourself
        if member.userId == currentUserId, member.role == .owner, newRole == .member {
            throw MemberStoreError.cannotDemoteSelf
        }

        // Validation: Must have at least one owner remaining
        if member.role == .owner, newRole == .member {
            let remainingOwners = members.filter { $0.role == .owner && $0.id != id }
            if remainingOwners.isEmpty {
                throw MemberStoreError.cannotRemoveLastOwner
            }
        }

        // Update member
        let updatedMember = Member(
            id: member.id,
            householdId: member.householdId,
            userId: member.userId,
            displayName: member.displayName,
            role: newRole,
            joinedAt: member.joinedAt,
            isActive: member.isActive
        )

        // Optimistic UI update
        if let index = members.firstIndex(where: { $0.id == id }) {
            members[index] = updatedMember
        }

        // Save to cache with pending status
        if let context = modelContext {
            let descriptor = FetchDescriptor<CachedMember>(
                predicate: #Predicate { $0.id == id }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.update(from: updatedMember)
                cached.syncStatusRaw = "pendingUpload"
                try? context.save()
            }
        }

        // Save to CloudKit
        do {
            _ = try await cloudKit.saveMember(updatedMember)

            // Mark as synced
            if let context = modelContext {
                let descriptor = FetchDescriptor<CachedMember>(
                    predicate: #Predicate { $0.id == id }
                )
                if let cached = try? context.fetch(descriptor).first {
                    cached.syncStatusRaw = "synced"
                    cached.lastSyncedAt = Date()
                    try? context.save()
                }
            }
        } catch {
            // Keep in cache with pending status
            throw error
        }
    }
}

// MARK: - Errors

enum MemberStoreError: LocalizedError {
    case memberNotFound
    case invalidDisplayName
    case cannotDeleteSelfAsOwner
    case cannotDeleteLastOwner
    case insufficientPermissions
    case cannotDemoteSelf
    case cannotRemoveLastOwner

    var errorDescription: String? {
        switch self {
        case .memberNotFound:
            "Member not found"
        case .invalidDisplayName:
            "Display name cannot be empty"
        case .cannotDeleteSelfAsOwner:
            "You cannot remove yourself as the owner. Transfer ownership first."
        case .cannotDeleteLastOwner:
            "Cannot remove the last owner. At least one owner must remain."
        case .insufficientPermissions:
            "Only owners can change member roles"
        case .cannotDemoteSelf:
            "You cannot remove your own owner role. Have another owner change your role."
        case .cannotRemoveLastOwner:
            "Cannot remove owner role. At least one owner must remain."
        }
    }
}
