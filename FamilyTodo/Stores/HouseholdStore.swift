import CloudKit
import Foundation
import SwiftData

/// Store for household management
@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var currentHousehold: Household?
    @Published private(set) var currentMember: Member?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private lazy var cloudKit = CloudKitManager.shared

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

            // Seed starter tasks
            let starterTasks = [
                Task(
                    householdId: household.id,
                    title: "Fix the faucet",
                    status: .next,
                    assigneeId: member.id,
                    assigneeIds: [member.id],
                    taskType: .oneOff
                ),
                Task(
                    householdId: household.id,
                    title: "Take down the Christmas tree",
                    status: .next,
                    assigneeId: member.id,
                    assigneeIds: [member.id],
                    taskType: .oneOff
                ),
            ]
            for task in starterTasks {
                _ = try await cloudKit.saveTask(task)
            }

            // Seed shopping list
            let starterItems = [
                ShoppingItem(householdId: household.id, title: "Milk"),
                ShoppingItem(householdId: household.id, title: "Bread"),
                ShoppingItem(householdId: household.id, title: "Sugar"),
            ]
            for item in starterItems {
                _ = try await cloudKit.saveShoppingItem(item)
            }

            // Seed recurring chores
            let starterChores = [
                RecurringChore(
                    householdId: household.id,
                    title: "Water the plants",
                    recurrenceType: .everyNWeeks,
                    recurrenceInterval: 2,
                    defaultAssigneeIds: [member.id]
                ),
                RecurringChore(
                    householdId: household.id,
                    title: "Replace towels",
                    recurrenceType: .everyNWeeks,
                    recurrenceInterval: 3,
                    defaultAssigneeIds: [member.id]
                ),
                RecurringChore(
                    householdId: household.id,
                    title: "Check purifier filters",
                    recurrenceType: .everyNWeeks,
                    recurrenceInterval: 2,
                    defaultAssigneeIds: [member.id]
                ),
            ]
            for var chore in starterChores {
                chore.nextScheduledDate = chore.calculateNextScheduledDate()
                _ = try await cloudKit.saveRecurringChore(chore)
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

    /// Get invite code for sharing (household ID for MVP fallback)
    var inviteCode: String? {
        currentHousehold?.id.uuidString
    }

    // MARK: - CKShare Sharing

    /// Get share URL for inviting members
    func getShareURL() async throws -> URL? {
        guard let household = currentHousehold else { return nil }
        return try await cloudKit.getShareURL(for: household.id)
    }

    /// Create a CKShare for the current household
    func createShare() async throws -> CKShare {
        guard let household = currentHousehold else {
            throw HouseholdError.householdNotFound
        }
        return try await cloudKit.createShare(for: household)
    }

    /// Accept a share invitation and join the household
    func acceptShareInvitation(
        metadata: CKShare.Metadata,
        userId: String,
        displayName: String
    ) async throws {
        isLoading = true
        error = nil

        do {
            // Accept the CloudKit share
            try await cloudKit.acceptShare(metadata: metadata)

            // Fetch the shared household
            guard let householdId = UUID(uuidString: metadata.rootRecordID.recordName) else {
                throw HouseholdError.invalidShare
            }

            let household = try await cloudKit.fetchHousehold(id: householdId)

            // Check if member already exists
            let existingMember = try await cloudKit.fetchMemberByUserId(userId)
            if existingMember != nil {
                // Already a member, just load the household
                currentHousehold = household
                currentMember = existingMember
            } else {
                // Create new member record
                let member = Member(
                    householdId: household.id,
                    userId: userId,
                    displayName: displayName,
                    role: .member
                )
                _ = try await cloudKit.saveMember(member)

                currentHousehold = household
                currentMember = member
            }
        } catch {
            self.error = error
            throw error
        }

        isLoading = false
    }
}

enum HouseholdError: LocalizedError {
    case invalidInviteCode
    case householdNotFound
    case invalidShare

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode:
            "Invalid invite code. Please check and try again."
        case .householdNotFound:
            "Household not found."
        case .invalidShare:
            "Invalid share invitation. The link may be expired or invalid."
        }
    }
}
