@testable import HousePulse
import SwiftData
import XCTest

final class HouseholdTests: XCTestCase {
    // MARK: - Initialization Tests

    func testHouseholdInitialization() {
        let household = Household(
            name: "Smith Family",
            ownerId: "user123"
        )

        XCTAssertEqual(household.name, "Smith Family")
        XCTAssertEqual(household.ownerId, "user123")
        XCTAssertTrue(household.members.isEmpty)
        XCTAssertTrue(household.areas.isEmpty)
    }

    func testHouseholdWithMembers() {
        let householdId = UUID()
        let member = Member(
            householdId: householdId,
            userId: "user1",
            displayName: "John",
            role: .owner
        )

        var household = Household(
            id: householdId,
            name: "Test Family",
            ownerId: "user1"
        )
        household.members = [member]

        XCTAssertEqual(household.members.count, 1)
        XCTAssertEqual(household.members.first?.displayName, "John")
    }

    func testHouseholdWithAreas() {
        let householdId = UUID()
        let areas = Area.defaults(for: householdId)

        var household = Household(
            id: householdId,
            name: "Test Family",
            ownerId: "user1"
        )
        household.areas = areas

        XCTAssertEqual(household.areas.count, 6)
    }

    // MARK: - Codable Tests

    func testHouseholdEncodingDecoding() throws {
        let original = Household(
            name: "Codable Family",
            ownerId: "user456"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Household.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.ownerId, decoded.ownerId)
    }
}

// MARK: - Member Tests

final class MemberTests: XCTestCase {
    private let householdId = UUID()

    // MARK: - Initialization Tests

    func testMemberInitialization() {
        let member = Member(
            householdId: householdId,
            userId: "apple-user-id",
            displayName: "John Doe",
            role: .owner
        )

        XCTAssertEqual(member.householdId, householdId)
        XCTAssertEqual(member.userId, "apple-user-id")
        XCTAssertEqual(member.displayName, "John Doe")
        XCTAssertEqual(member.role, .owner)
        XCTAssertTrue(member.isActive)
    }

    func testMemberAsRegularMember() {
        let member = Member(
            householdId: householdId,
            userId: "user2",
            displayName: "Jane Doe",
            role: .member,
            isActive: true
        )

        XCTAssertEqual(member.role, .member)
    }

    func testMemberRoleRawValues() {
        XCTAssertEqual(Member.MemberRole.owner.rawValue, "owner")
        XCTAssertEqual(Member.MemberRole.member.rawValue, "member")
    }

    func testInactiveMember() {
        let member = Member(
            householdId: householdId,
            userId: "user3",
            displayName: "Inactive User",
            role: .member,
            isActive: false
        )

        XCTAssertFalse(member.isActive)
    }

    // MARK: - Codable Tests

    func testMemberEncodingDecoding() throws {
        let original = Member(
            householdId: householdId,
            userId: "test-user",
            displayName: "Test User",
            role: .member
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Member.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.userId, decoded.userId)
        XCTAssertEqual(original.displayName, decoded.displayName)
        XCTAssertEqual(original.role, decoded.role)
    }
}

// MARK: - HouseholdStore Tests

@MainActor
final class HouseholdStoreTests: XCTestCase {
    private var store: HouseholdStore!

    override func setUp() async throws {
        try await super.setUp()
        store = HouseholdStore()
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Computed Properties

    func testCurrentHousehold_WhenNil_IsNil() {
        XCTAssertNil(store.currentHousehold)
    }

    func testInitialState() {
        XCTAssertNil(store.currentHousehold)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.error)
    }

    func testCreateHouseholdLocalOnlySeedsCache() async throws {
        let schema = Schema([
            CachedHousehold.self,
            CachedMember.self,
            CachedArea.self,
            CachedTask.self,
            CachedRecurringChore.self,
            CachedShoppingItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        store.setModelContext(container.mainContext)
        store.setSyncMode(.localOnly)

        try await store.createHousehold(name: "Local Home", userId: "guest-user", displayName: "Guest")

        XCTAssertNotNil(store.currentHousehold)
        XCTAssertEqual(store.currentHousehold?.name, "Local Home")
        XCTAssertEqual(store.currentHousehold?.ownerId, "guest-user")

        // Verify household is cached
        let households = try container.mainContext.fetch(FetchDescriptor<CachedHousehold>())
        XCTAssertEqual(households.count, 1)
        XCTAssertEqual(households.first?.name, "Local Home")

        // Note: Current implementation doesn't seed default data (members, areas, tasks, etc.)
        // This functionality will be added in future iterations when onboarding flow is implemented
    }

    // MARK: - HouseholdError Tests

    func testHouseholdErrorCases() {
        // Test that error cases exist
        let errors: [HouseholdError] = [
            .invalidInviteCode,
            .householdNotFound,
            .cloudSyncRequired,
            .memberNotFound,
        ]

        XCTAssertEqual(errors.count, 4)
    }
}

// MARK: - Invite Code Validation Tests

final class InviteCodeValidationTests: XCTestCase {
    func testValidUUIDString() {
        let validCode = UUID().uuidString

        let uuid = UUID(uuidString: validCode)

        XCTAssertNotNil(uuid)
    }

    func testInvalidInviteCode_NotUUID() {
        let invalidCode = "not-a-uuid"

        let uuid = UUID(uuidString: invalidCode)

        XCTAssertNil(uuid)
    }

    func testInvalidInviteCode_Empty() {
        let emptyCode = ""

        let uuid = UUID(uuidString: emptyCode)

        XCTAssertNil(uuid)
    }

    func testInvalidInviteCode_TooShort() {
        let shortCode = "12345"

        let uuid = UUID(uuidString: shortCode)

        XCTAssertNil(uuid)
    }
}
