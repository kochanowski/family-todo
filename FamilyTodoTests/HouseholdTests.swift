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
        XCTAssertEqual(household.iconSymbol, "house.fill")
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
        XCTAssertTrue(MemberColorToken.isAllowed(hex: member.colorHex))
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
        XCTAssertEqual(original.colorHex, decoded.colorHex)
    }

    func testMemberColorPaletteContainsTenPastelTokens() {
        XCTAssertEqual(MemberColorToken.allCases.count, 10)
    }

    func testMemberColorDefaultIsAlwaysAllowed() {
        let memberId = UUID(uuidString: "00000000-0000-0000-0000-00000000A7B9") ?? UUID()
        let defaultHex = MemberColorToken.defaultHex(for: memberId)
        XCTAssertTrue(MemberColorToken.isAllowed(hex: defaultHex))
    }

    func testMemberDecodingFallsBackToDefaultColorWhenMissing() throws {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "householdId": householdId.uuidString,
            "userId": "legacy-user",
            "displayName": "Legacy User",
            "role": "member",
            "joinedAt": ISO8601DateFormatter().string(from: Date()),
            "isActive": true,
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Member.self, from: data)
        XCTAssertTrue(MemberColorToken.isAllowed(hex: decoded.colorHex))
    }
}

@MainActor
final class MemberStoreProfileTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var store: MemberStore!
    private let householdId = UUID()
    private let userId = "profile-user"

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([CachedMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

        let initialMember = Member(
            householdId: householdId,
            userId: userId,
            displayName: "Wojtek",
            role: .owner,
            colorHex: MemberColorToken.pastelPink.hex
        )
        modelContainer.mainContext.insert(CachedMember(from: initialMember))
        try modelContainer.mainContext.save()

        store = MemberStore(householdId: householdId, modelContext: modelContainer.mainContext)
        store.setSyncMode(.localOnly)
        await store.loadMembers()
    }

    override func tearDown() async throws {
        store = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testUpdateCurrentUserProfilePersistsDisplayNameAndColorToCache() async throws {
        try await store.updateCurrentUserProfile(
            displayName: "Wojciech",
            colorHex: MemberColorToken.pastelBlue.hex,
            currentUserId: userId
        )

        XCTAssertEqual(store.members.first?.displayName, "Wojciech")
        XCTAssertEqual(store.members.first?.colorHex, MemberColorToken.pastelBlue.hex)

        let descriptor = FetchDescriptor<CachedMember>()
        let cachedMembers = try modelContainer.mainContext.fetch(descriptor)
        XCTAssertEqual(cachedMembers.first?.displayName, "Wojciech")
        XCTAssertEqual(cachedMembers.first?.colorHex, MemberColorToken.pastelBlue.hex)
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
            CachedTask.self,
            CachedShoppingItem.self,
            CachedBacklogCategory.self,
            CachedBacklogItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        store.setModelContext(container.mainContext)
        store.setSyncMode(.localOnly)

        try await store.createHousehold(
            name: "Local Home",
            userId: "guest-user",
            displayName: "Guest"
        )

        // ✅ Verify household created
        XCTAssertNotNil(store.currentHousehold)
        XCTAssertEqual(store.currentHousehold?.name, "Local Home")

        let households = try container.mainContext.fetch(FetchDescriptor<CachedHousehold>())
        XCTAssertEqual(households.count, 1)

        // ✅ Verify 1 member (owner)
        let members = try container.mainContext.fetch(FetchDescriptor<CachedMember>())
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.displayName, "Guest")
        XCTAssertEqual(members.first?.roleRaw, "owner")

        // ✅ Verify 8 tasks (3 next, 4 backlog, 1 done)
        let tasks = try container.mainContext.fetch(FetchDescriptor<CachedTask>())
        XCTAssertEqual(tasks.count, 8)

        let nextTasks = tasks.filter { $0.statusRaw == "next" }
        XCTAssertEqual(nextTasks.count, 3, "Should respect WIP limit")

        let backlogTasks = tasks.filter { $0.statusRaw == "backlog" }
        XCTAssertEqual(backlogTasks.count, 4)

        let doneTasks = tasks.filter { $0.statusRaw == "done" }
        XCTAssertEqual(doneTasks.count, 1)

        // ✅ Verify 5 shopping items
        let items = try container.mainContext.fetch(FetchDescriptor<CachedShoppingItem>())
        XCTAssertEqual(items.count, 5)

        let boughtItems = items.filter(\.isBought)
        XCTAssertEqual(boughtItems.count, 1, "Should have one bought item")

        // ✅ Verify 2 backlog categories
        let categories = try container.mainContext.fetch(FetchDescriptor<CachedBacklogCategory>())
        XCTAssertEqual(categories.count, 2)

        let categoryTitles = Set(categories.map(\.title))
        XCTAssertTrue(categoryTitles.contains("Home Projects"))
        XCTAssertTrue(categoryTitles.contains("Weekly Routine"))

        // ✅ Verify 5 backlog items
        let backlogItems = try container.mainContext.fetch(FetchDescriptor<CachedBacklogItem>())
        XCTAssertEqual(backlogItems.count, 5)
    }

    // MARK: - HouseholdError Tests

    func testHouseholdErrorCases() {
        // Test that error cases exist
        let errors: [HouseholdError] = [
            .invalidInviteCode,
            .displayNameAlreadyTaken,
            .householdNotFound,
            .cloudSyncRequired,
            .memberNotFound,
            .cacheNotAvailable,
        ]

        XCTAssertEqual(errors.count, 6)
    }

    func testResolveLeaveBehavior_OwnerOnlyMember_DeletesHousehold() {
        let owner = Member(
            householdId: UUID(),
            userId: "owner",
            displayName: "Owner",
            role: .owner
        )

        let decision = store.resolveLeaveBehavior(for: owner, activeMembers: [owner])

        XCTAssertEqual(decision, .deleteHousehold)
    }

    func testResolveLeaveBehavior_OwnerWithMembersWithoutOtherOwner_RequiresTransfer() {
        let householdId = UUID()
        let owner = Member(
            householdId: householdId,
            userId: "owner",
            displayName: "Owner",
            role: .owner
        )
        let member = Member(
            householdId: householdId,
            userId: "member",
            displayName: "Member",
            role: .member
        )

        let decision = store.resolveLeaveBehavior(for: owner, activeMembers: [owner, member])

        XCTAssertEqual(decision, .requireTransfer)
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
