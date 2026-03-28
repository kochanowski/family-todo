import CloudKit
@testable import HousePulse
import XCTest

final class CloudKitManagerJoinBootstrapTests: XCTestCase {
    func testParticipantSharedIgnoresCachedMetadataZoneWithDefaultOwnerSeed() {
        let zoneID = CKRecordZone.ID(
            zoneName: "HouseholdZone-\(UUID().uuidString)",
            ownerName: "__defaultOwner__"
        )

        XCTAssertTrue(
            CloudKitManager.shouldIgnoreCachedParticipantSharedZone(zoneID)
        )
    }

    func testParticipantSharedRetainsVerifiedSharedZoneFromOtherOwner() {
        let zoneID = CKRecordZone.ID(
            zoneName: "HouseholdZone-\(UUID().uuidString)",
            ownerName: "_otherOwner"
        )

        XCTAssertFalse(
            CloudKitManager.shouldIgnoreCachedParticipantSharedZone(zoneID)
        )
    }

    func testParticipantSharedTreatsSharedDatabaseInvalidArgumentsAsRetryableBootstrapError() {
        let error = CKError(
            .invalidArguments,
            userInfo: [
                NSLocalizedDescriptionKey: "Only shared zones can be accessed in the shared DB",
            ]
        )

        XCTAssertTrue(
            CloudKitManager.isRetryableParticipantSharedZoneBootstrapError(error)
        )
    }

    func testParticipantSharedDoesNotTreatGenericInvalidArgumentsAsRetryableBootstrapError() {
        let error = CKError(
            .invalidArguments,
            userInfo: [
                NSLocalizedDescriptionKey: "Bad request",
            ]
        )

        XCTAssertFalse(
            CloudKitManager.isRetryableParticipantSharedZoneBootstrapError(error)
        )
    }
}
