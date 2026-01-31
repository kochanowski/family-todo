import CloudKit
import Combine
import SwiftData
import SwiftUI

@MainActor
class MemberStore: ObservableObject {
    @Published var members: [Member] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var modelContext: ModelContext?
    private lazy var cloudKit = CloudKitManager.shared
    private let householdId: UUID?
    private var syncMode: SyncMode = .cloud

    init(householdId: UUID?, modelContext: ModelContext? = nil) {
        self.householdId = householdId
        self.modelContext = modelContext
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func setSyncMode(_ mode: SyncMode) {
        self.syncMode = mode
    }

    // MARK: - Data Loading

    func loadMembers() async {
        guard let householdId = householdId else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // 1. Load from cache
        members = fetchCachedMembers(householdId: householdId)

        guard syncMode == .cloud else { return }

        // 2. Load from CloudKit
        do {
            let fetchedMembers = try await cloudKit.fetchMembers(householdId: householdId)
            
            // Update cache
            updateCache(with: fetchedMembers, for: householdId)
            
            // Update UI
            self.members = fetchedMembers
        } catch {
            print("Error loading members: \(error)")
            self.error = error
        }
    }

    // MARK: - Operations

    func updateMember(id: UUID, displayName: String, currentUserId: String?) async throws {
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        var member = members[index]
        
        // Optimistic Update
        let oldName = member.displayName
        member.displayName = displayName
        members[index] = member
        
        // Update Cache
        updateCachedMember(member)
        
        if syncMode == .cloud {
            do {
                _ = try await cloudKit.saveMember(member)
            } catch {
                // Revert
                member.displayName = oldName
                members[index] = member
                updateCachedMember(member)
                throw error
            }
        }
    }

    func updateRole(id: UUID, newRole: Member.MemberRole, currentUserId: String?) async throws {
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        var member = members[index]
        
        let oldRole = member.role
        
        // TODO: Validate only owner can change roles (should be enforced by UI/CloudKit rules)
        
        // Optimistic
        // Since 'role' is let in Member struct (immutable), we need to create a new Member
        let updatedMember = Member(
            id: member.id,
            householdId: member.householdId,
            userId: member.userId,
            displayName: member.displayName,
            role: newRole,
            joinedAt: member.joinedAt,
            isActive: member.isActive
        )
        
        members[index] = updatedMember
        updateCachedMember(updatedMember)
        
        if syncMode == .cloud {
            do {
                _ = try await cloudKit.saveMember(updatedMember)
            } catch {
                members[index] = member // revert
                updateCachedMember(member)
                throw error
            }
        }
    }

    func deleteMember(id: UUID, currentUserId: String?) async throws {
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        let member = members[index]
        
        // Optimistic
        members.remove(at: index)
        deleteCachedMember(id: id)
        
        if syncMode == .cloud {
            do {
                try await cloudKit.deleteMember(id: id)
            } catch {
                // Revert
                members.insert(member, at: index)
                updateCachedMember(member)
                throw error
            }
        }
    }

    // MARK: - SwiftData Helpers

    private func fetchCachedMembers(householdId: UUID) -> [Member] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.householdId == householdId },
            sortBy: [SortDescriptor(\.joinedAt)]
        )
        
        do {
            return try context.fetch(descriptor).map { $0.toMember() }
        } catch {
            print("Cache fetch error: \(error)")
            return []
        }
    }

    private func updateCache(with members: [Member], for householdId: UUID) {
        guard let context = modelContext else { return }
        
        // Simple strategy: Delete all for household and regarding (inefficient but safe for now)
        // Better: diffing. For now, let's just update existing and add new.
        
        for member in members {
            updateCachedMember(member)
        }
        
        // TODO: Handle deletions (members in cache but not in fetch)
    }

    private func updateCachedMember(_ member: Member) {
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
            try context.save()
        } catch {
             print("Cache save error: \(error)")
        }
    }
    
    private func deleteCachedMember(id: UUID) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<CachedMember>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            if let cached = try context.fetch(descriptor).first {
                context.delete(cached)
                try context.save()
            }
        } catch {
            print("Cache delete error: \(error)")
        }
    }
}
