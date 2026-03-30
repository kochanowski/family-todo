@testable import HousePulse
import XCTest

final class CloudKitManagerOwnerQueryTests: XCTestCase {
    func testOwnerPrivateUsesZoneBoundQueryForCollaborativeHouseholdGraphRecordTypes() {
        XCTAssertTrue(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "Member"))
        XCTAssertTrue(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "WorkItem"))
        XCTAssertTrue(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "ShoppingItem"))
        XCTAssertTrue(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "ShoppingBundle"))
        XCTAssertTrue(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "BacklogCategory"))
        XCTAssertTrue(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "BacklogItem"))
    }

    func testOwnerPrivateKeepsExhaustiveQueryFallbackForNonCollaborativeRecordTypes() {
        XCTAssertFalse(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "InviteToken"))
        XCTAssertFalse(CloudKitManager.shouldUseOwnerZoneBoundQuery(recordType: "Household"))
    }
}
