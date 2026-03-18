import CloudKit
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

        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .members)

        let initialMember = Member(
            householdId: householdId,
            userId: userId,
            displayName: "Wojtek",
            role: .owner,
            colorHex: MemberColorToken.systemPink.hex
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
            colorHex: MemberColorToken.systemBlue.hex,
            currentUserId: userId
        )

        XCTAssertEqual(store.members.first?.displayName, "Wojciech")
        XCTAssertEqual(store.members.first?.colorHex, MemberColorToken.systemBlue.hex)

        let descriptor = FetchDescriptor<CachedMember>()
        let cachedMembers = try modelContainer.mainContext.fetch(descriptor)
        XCTAssertEqual(cachedMembers.first?.displayName, "Wojciech")
        XCTAssertEqual(cachedMembers.first?.colorHex, MemberColorToken.systemBlue.hex)
    }
}

// MARK: - HouseholdStore Tests

@MainActor
final class HouseholdStoreTests: XCTestCase {
    private var store: HouseholdStore!
    private var modelContainer: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainerFactory.makeInMemoryContainer(profile: .household)
        store = HouseholdStore(modelContext: modelContainer.mainContext)
        store.setModelContext(modelContainer.mainContext)
    }

    override func tearDown() async throws {
        store = nil
        modelContainer = nil
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

    func testCreateHouseholdLocalOnlyStartsEmpty() async throws {
        let container = modelContainer
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

        // ✅ Verify a brand-new household starts empty.
        let tasks = try container.mainContext.fetch(FetchDescriptor<CachedTask>())
        XCTAssertTrue(tasks.isEmpty)

        let items = try container.mainContext.fetch(FetchDescriptor<CachedShoppingItem>())
        XCTAssertTrue(items.isEmpty)

        let bundles = try container.mainContext.fetch(FetchDescriptor<CachedShoppingBundle>())
        XCTAssertTrue(bundles.isEmpty)

        let categories = try container.mainContext.fetch(FetchDescriptor<CachedBacklogCategory>())
        XCTAssertTrue(categories.isEmpty)

        let backlogItems = try container.mainContext.fetch(FetchDescriptor<CachedBacklogItem>())
        XCTAssertTrue(backlogItems.isEmpty)

        let recurring = try container.mainContext.fetch(FetchDescriptor<CachedRecurringChore>())
        XCTAssertTrue(recurring.isEmpty)
    }

    func testCreateHouseholdRejectsMissingDisplayName() async throws {
        let container = modelContainer
        store.setSyncMode(.localOnly)

        do {
            _ = try await store.createHousehold(
                name: "Local Home",
                userId: "guest-user",
                displayName: "   "
            )
            XCTFail("Expected createHousehold to reject an empty display name")
        } catch let error as HouseholdError {
            XCTAssertEqual(error, .displayNameRequired)
        }

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedHousehold>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedMember>()).isEmpty)
    }

    func testUpdateCurrentHouseholdPersistsNameAndIconLocally() async throws {
        let container = modelContainer
        let household = Household(
            name: "Original Home",
            iconSymbol: "house.fill",
            ownerId: "household-owner"
        )
        container.mainContext.insert(CachedHousehold(from: household))
        try container.mainContext.save()

        let localStore = HouseholdStore(modelContext: container.mainContext)
        localStore.setSyncMode(.localOnly)
        localStore.currentHousehold = household

        try await localStore.updateCurrentHousehold(
            name: "Updated Home",
            userId: household.ownerId,
            iconSymbol: "star.fill"
        )

        XCTAssertEqual(localStore.currentHousehold?.name, "Updated Home")
        XCTAssertEqual(localStore.currentHousehold?.iconSymbol, "star.fill")

        let cachedHouseholds = try container.mainContext.fetch(FetchDescriptor<CachedHousehold>())
        XCTAssertEqual(cachedHouseholds.count, 1)
        XCTAssertEqual(cachedHouseholds.first?.name, "Updated Home")
        XCTAssertEqual(cachedHouseholds.first?.iconSymbol, "star.fill")
    }

    func testRestoreCachedHouseholdIgnoresCloudCacheWithoutCurrentUserMembership() throws {
        let container = modelContainer
        let localStore = HouseholdStore(modelContext: container.mainContext)
        localStore.setSyncMode(.cloud)

        let household = Household(
            name: "Zombie House",
            ownerId: "owner-user"
        )
        container.mainContext.insert(CachedHousehold(from: household))

        let someoneElse = Member(
            householdId: household.id,
            userId: "other-user",
            displayName: "Other",
            role: .member
        )
        container.mainContext.insert(CachedMember(from: someoneElse))
        try container.mainContext.save()

        let restored = localStore.restoreCachedHousehold(
            userId: "missing-user",
            preferredHouseholdId: household.id
        )

        XCTAssertNil(restored)
        XCTAssertNil(localStore.currentHousehold)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedHousehold>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedMember>()).isEmpty)
    }

    func testResolveStartupHouseholdLocallyRestoresCachedHousehold() throws {
        let container = modelContainer
        let localStore = HouseholdStore(modelContext: container.mainContext)
        localStore.setSyncMode(.cloud)

        let household = Household(
            name: "Startup Home",
            ownerId: "owner-user"
        )
        let owner = Member(
            householdId: household.id,
            userId: "owner-user",
            displayName: "Owner",
            role: .owner
        )

        container.mainContext.insert(CachedHousehold(from: household))
        container.mainContext.insert(CachedMember(from: owner))
        try container.mainContext.save()

        let restored = localStore.resolveStartupHouseholdLocally(
            userId: owner.userId,
            preferredHouseholdId: household.id
        )

        XCTAssertEqual(restored?.id, household.id)
        XCTAssertEqual(localStore.currentHousehold?.id, household.id)
    }

    func testResolveStartupHouseholdLocallyReturnsNilWhenCacheIsEmpty() throws {
        let container = modelContainer
        let localStore = HouseholdStore(modelContext: container.mainContext)
        localStore.setSyncMode(.cloud)

        let restored = localStore.resolveStartupHouseholdLocally(
            userId: "owner-user",
            preferredHouseholdId: nil
        )

        XCTAssertNil(restored)
        XCTAssertNil(localStore.currentHousehold)
    }

    func testResolveMembershipDisplayNameLocallyReturnsCachedActiveMemberName() throws {
        let container = modelContainer
        let localStore = HouseholdStore(modelContext: container.mainContext)
        localStore.setSyncMode(.cloud)

        let household = Household(
            name: "Display Name Home",
            ownerId: "owner-user"
        )
        let owner = Member(
            householdId: household.id,
            userId: "owner-user",
            displayName: "Wojtek",
            role: .owner
        )

        container.mainContext.insert(CachedHousehold(from: household))
        container.mainContext.insert(CachedMember(from: owner))
        try container.mainContext.save()

        let restoredName = localStore.resolveMembershipDisplayNameLocally(
            userId: owner.userId,
            preferredHouseholdId: household.id
        )

        XCTAssertEqual(restoredName, "Wojtek")
    }

    func testValidateRecoveredMembershipOrAbandonSuppressesZombieHousehold() async throws {
        let suiteName = "HouseholdStoreTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let container = modelContainer

        let localStore = HouseholdStore(
            modelContext: container.mainContext,
            userDefaults: defaults,
            recoverySuppressionDuration: 300
        )
        localStore.setSyncMode(.cloud)

        let household = Household(
            name: "Zombie House",
            ownerId: "owner-user"
        )
        container.mainContext.insert(CachedHousehold(from: household))
        try container.mainContext.save()
        localStore.currentHousehold = household

        let isValid = try await localStore.validateRecoveredMembershipOrAbandon(
            household: household,
            userId: "missing-user",
            retryDelaysNanoseconds: [0],
            fetchActiveMember: { _, _ in nil }
        )

        XCTAssertFalse(isValid)
        XCTAssertNil(localStore.currentHousehold)
        XCTAssertTrue(localStore.isRecoverySuppressed(for: household.id))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedHousehold>()).isEmpty)
    }

    func testLeaveCurrentHouseholdLocalOnlyRemovesRecurringCacheAndSuppressesRecovery() async throws {
        let suiteName = "HouseholdStoreTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let container = modelContainer

        let localStore = HouseholdStore(
            modelContext: container.mainContext,
            userDefaults: defaults,
            recoverySuppressionDuration: 300
        )
        localStore.setSyncMode(.localOnly)

        let household = try await localStore.createHousehold(
            name: "Leave Me",
            userId: "guest-user",
            displayName: "Guest"
        )
        let recurring = RecurringChore(
            householdId: household.id,
            title: "Water plants",
            recurrenceType: .weekly,
            categoryId: UUID()
        )
        container.mainContext.insert(CachedRecurringChore(from: recurring))
        try container.mainContext.save()

        try await localStore.leaveCurrentHousehold(userId: household.ownerId)

        XCTAssertNil(localStore.currentHousehold)
        XCTAssertTrue(localStore.isRecoverySuppressed(for: household.id))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedHousehold>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CachedRecurringChore>()).isEmpty)

        await localStore.loadCurrentHouseholdAndMembership(userId: household.ownerId)
        XCTAssertNil(localStore.currentHousehold)
    }

    func testRestoreCachedHouseholdSkipsPendingExitOperations() async throws {
        let suiteName = "HouseholdStoreTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let container = modelContainer

        let localStore = HouseholdStore(
            modelContext: container.mainContext,
            userDefaults: defaults,
            recoverySuppressionDuration: 300
        )
        localStore.setSyncMode(.localOnly)

        let household = try await localStore.createHousehold(
            name: "Pending Exit",
            userId: "guest-user",
            displayName: "Guest"
        )
        localStore.clearCurrentHousehold()

        let pending = [
            HouseholdStore.PendingExitOperation(
                kind: .leaveSharedHousehold,
                householdId: household.id,
                userId: household.ownerId
            ),
        ]
        let pendingData = try JSONEncoder().encode(pending)
        defaults.set(pendingData, forKey: HouseholdStore.pendingExitOperationsDefaultsKey)

        let restored = localStore.restoreCachedHousehold(userId: household.ownerId)
        XCTAssertNil(restored)

        await localStore.loadCurrentHouseholdAndMembership(userId: household.ownerId)
        XCTAssertNil(localStore.currentHousehold)
    }

    func testRecoverableHouseholdIgnoresMissingCloudRootAndSuppressesRecovery() async throws {
        let suiteName = "HouseholdStoreTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = HouseholdStore(
            userDefaults: defaults,
            recoverySuppressionDuration: 300
        )

        let householdId = UUID()
        let member = Member(
            householdId: householdId,
            userId: "cloud-user",
            displayName: "Wojtek",
            role: .member
        )

        let resolved = try await localStore.recoverableHousehold(
            from: member,
            source: .participantShared,
            fetchHousehold: { _ in throw CKError(.unknownItem) },
            onMissingHousehold: { _, _ in }
        )

        XCTAssertNil(resolved)
        XCTAssertTrue(localStore.isRecoverySuppressed(for: householdId))
    }

    func testRecoverableHouseholdPropagatesNonMissingCloudErrors() async throws {
        let suiteName = "HouseholdStoreTests.\(#function)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated user defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let localStore = HouseholdStore(
            userDefaults: defaults,
            recoverySuppressionDuration: 300
        )

        let householdId = UUID()
        let member = Member(
            householdId: householdId,
            userId: "cloud-user",
            displayName: "Wojtek",
            role: .member
        )

        do {
            _ = try await localStore.recoverableHousehold(
                from: member,
                source: .participantShared,
                fetchHousehold: { _ in throw CKError(.permissionFailure) },
                onMissingHousehold: { _, _ in }
            )
            XCTFail("Expected permission failure to propagate")
        } catch let error as CKError {
            XCTAssertEqual(error.code, .permissionFailure)
        }

        XCTAssertFalse(localStore.isRecoverySuppressed(for: householdId))
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

final class CloudKitManagerScopeTests: XCTestCase {
    private let ownerZoneID = CKRecordZone.ID(
        zoneName: "HouseholdZone-owner",
        ownerName: CKCurrentUserDefaultName
    )
    private let legacyZoneID = CKRecordZone.ID(
        zoneName: "LegacyZone-owner",
        ownerName: CKCurrentUserDefaultName
    )
    private let defaultZoneID = CKRecordZone.default().zoneID

    func testParticipantSharedRejectsDefaultZone() {
        XCTAssertFalse(
            CloudKitManager.isZoneCompatible(
                CKRecordZone.default().zoneID,
                for: .participantShared
            )
        )
    }

    func testParticipantSharedAllowsOwnerStyleCustomZoneWhenItIsNotDefaultZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "HouseholdZone-\(UUID().uuidString)",
            ownerName: CKCurrentUserDefaultName
        )

        XCTAssertTrue(
            CloudKitManager.isZoneCompatible(
                zoneID,
                for: .participantShared
            )
        )
    }

    func testParticipantSharedAllowsSharedCustomZone() {
        let zoneID = CKRecordZone.ID(
            zoneName: "SharedZone-\(UUID().uuidString)",
            ownerName: "_otherOwner"
        )

        XCTAssertTrue(
            CloudKitManager.isZoneCompatible(
                zoneID,
                for: .participantShared
            )
        )
    }

    func testReferenceMatchPredicateUsesInOperatorForMultipleReferences() {
        let scopedReference = CKRecord.Reference(
            recordID: CKRecord.ID(
                recordName: UUID().uuidString,
                zoneID: ownerZoneID
            ),
            action: .none
        )
        let legacyReference = CKRecord.Reference(
            recordID: CKRecord.ID(
                recordName: UUID().uuidString,
                zoneID: legacyZoneID
            ),
            action: .none
        )

        let predicate = CloudKitManager.referenceMatchPredicate(
            field: "householdId",
            references: [scopedReference, legacyReference]
        )

        XCTAssertTrue(predicate.predicateFormat.contains(" IN "))
    }

    func testReferenceMatchPredicateUsesEqualityForSingleReference() {
        let scopedReference = CKRecord.Reference(
            recordID: CKRecord.ID(
                recordName: UUID().uuidString,
                zoneID: ownerZoneID
            ),
            action: .none
        )

        let predicate = CloudKitManager.referenceMatchPredicate(
            field: "householdId",
            references: [scopedReference]
        )

        XCTAssertTrue(predicate.predicateFormat.contains(" == "))
    }

    func testMergeOwnerPrivateRecordsReturnsUnionAcrossMixedZonesAndSortsByUpdatedAt() {
        let olderTask = makeTaskRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID(),
            zoneID: ownerZoneID,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerLegacyTask = makeTaskRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2") ?? UUID(),
            zoneID: legacyZoneID,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let result = CloudKitManager.mergeOwnerPrivateRecords(
            [olderTask, newerLegacyTask],
            targetZoneID: ownerZoneID,
            sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )

        XCTAssertEqual(
            result.authoritativeRecords.map(\.recordID.recordName),
            [newerLegacyTask.recordID.recordName, olderTask.recordID.recordName]
        )
        XCTAssertEqual(
            result.legacyDuplicateRecordIDs.map(\.recordName),
            [newerLegacyTask.recordID.recordName]
        )
    }

    func testMergeOwnerPrivateRecordsPrefersTargetZoneWhenFreshnessTies() {
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3") ?? UUID()
        let sharedTimestamp = Date(timeIntervalSince1970: 300)
        let targetRecord = makeTaskRecord(
            id: recordID,
            zoneID: ownerZoneID,
            updatedAt: sharedTimestamp
        )
        let legacyRecord = makeTaskRecord(
            id: recordID,
            zoneID: defaultZoneID,
            updatedAt: sharedTimestamp
        )

        let result = CloudKitManager.mergeOwnerPrivateRecords(
            [legacyRecord, targetRecord],
            targetZoneID: ownerZoneID,
            sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )

        XCTAssertEqual(result.authoritativeRecords.map(\.recordID), [targetRecord.recordID])
        XCTAssertEqual(result.legacyDuplicateRecordIDs, [legacyRecord.recordID])
    }

    func testMergeOwnerPrivateRecordsKeepsNewerLegacySourceButDoesNotDeleteTargetRecordID() {
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D4") ?? UUID()
        let targetRecord = makeTaskRecord(
            id: recordID,
            zoneID: ownerZoneID,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerLegacyRecord = makeTaskRecord(
            id: recordID,
            zoneID: legacyZoneID,
            updatedAt: Date(timeIntervalSince1970: 500)
        )

        let result = CloudKitManager.mergeOwnerPrivateRecords(
            [targetRecord, newerLegacyRecord],
            targetZoneID: ownerZoneID,
            sortDescriptors: [NSSortDescriptor(key: "updatedAt", ascending: false)]
        )

        XCTAssertEqual(result.authoritativeRecords.map(\.recordID), [newerLegacyRecord.recordID])
        XCTAssertEqual(result.legacyDuplicateRecordIDs, [newerLegacyRecord.recordID])
        XCTAssertFalse(result.legacyDuplicateRecordIDs.contains(targetRecord.recordID))
    }

    func testMergeOwnerPrivateRecordsSortsBySortOrderAscending() {
        let first = makeShoppingRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E5") ?? UUID(),
            zoneID: legacyZoneID,
            sortOrder: 1
        )
        let second = makeShoppingRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F6") ?? UUID(),
            zoneID: ownerZoneID,
            sortOrder: 2
        )

        let result = CloudKitManager.mergeOwnerPrivateRecords(
            [second, first],
            targetZoneID: ownerZoneID,
            sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)]
        )

        XCTAssertEqual(
            result.authoritativeRecords.map(\.recordID.recordName),
            [first.recordID.recordName, second.recordID.recordName]
        )
    }

    private func makeTaskRecord(id: UUID, zoneID: CKRecordZone.ID, updatedAt: Date) -> CKRecord {
        let record = CKRecord(
            recordType: "Task",
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        )
        record["updatedAt"] = updatedAt
        return record
    }

    private func makeShoppingRecord(id: UUID, zoneID: CKRecordZone.ID, sortOrder: Int) -> CKRecord {
        let record = CKRecord(
            recordType: "ShoppingItem",
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        )
        record["sortOrder"] = sortOrder as NSNumber
        return record
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
