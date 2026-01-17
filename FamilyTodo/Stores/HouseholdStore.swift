import Foundation
import SwiftData

/// Store for household management
@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var currentHousehold: Household?
    @Published private(set) var currentMember: Member?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let cloudKit = CloudKitManager.shared

    /// Check if user has a household
    var hasHousehold: Bool {
        currentHousehold != nil
    }

    // MARK: - Load Household

    /// Load household for current user
    func loadHousehold(userId: String) async {
        isLoading = true
        error = nil

        do {
            // Try to find user's membership
            if let member = try await cloudKit.fetchMemberByUserId(userId) {
                currentMember = member
                currentHousehold = try await cloudKit.fetchHousehold(id: member.householdId)
            }
        } catch {
            // No household found is OK for new users
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Create Household

    /// Create a new household with the current user as owner
    func createHousehold(name: String, userId: String, displayName: String) async throws {
        isLoading = true
        error = nil

        do {
            // Create household
            let household = Household(
                name: name,
                ownerId: userId
            )
            _ = try await cloudKit.saveHousehold(household)

            // Create owner member
            let member = Member(
                householdId: household.id,
                userId: userId,
                displayName: displayName,
                role: .owner
            )
            _ = try await cloudKit.saveMember(member)

            // Create default areas
            let defaultAreas = Area.defaults(for: household.id)
            for area in defaultAreas {
                _ = try await cloudKit.saveArea(area)
            }

            currentHousehold = household
            currentMember = member
        } catch {
            self.error = error
            throw error
        }

        isLoading = false
    }

    // MARK: - Join Household

    /// Join an existing household by invite code
    func joinHousehold(inviteCode: String, userId: String, displayName: String) async throws {
        isLoading = true
        error = nil

        do {
            // Find household by invite code (using household ID as simple invite code for MVP)
            guard let householdId = UUID(uuidString: inviteCode) else {
                throw HouseholdError.invalidInviteCode
            }

            let household = try await cloudKit.fetchHousehold(id: householdId)

            // Create member
            let member = Member(
                householdId: household.id,
                userId: userId,
                displayName: displayName,
                role: .member
            )
            _ = try await cloudKit.saveMember(member)

            currentHousehold = household
            currentMember = member
        } catch {
            self.error = error
            throw error
        }

        isLoading = false
    }

    /// Get invite code for sharing (household ID for MVP)
    var inviteCode: String? {
        currentHousehold?.id.uuidString
    }
}

enum HouseholdError: LocalizedError {
    case invalidInviteCode
    case householdNotFound

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode:
            return "Invalid invite code. Please check and try again."
        case .householdNotFound:
            return "Household not found."
        }
    }
}
