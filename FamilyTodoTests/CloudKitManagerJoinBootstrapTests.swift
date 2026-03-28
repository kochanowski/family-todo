import CloudKit
@testable import HousePulse
import XCTest

final class CloudKitManagerJoinBootstrapTests: XCTestCase {
    func testCreateShareDefersInteractiveSharedGraphRepairToBackground() {
        XCTAssertFalse(CloudKitManager.createShareBlocksOnInteractiveRepair)
    }

    func testAcceptedRootFetchRetryWindowIsLongEnoughForSharePropagation() {
        let totalDelay = CloudKitManager.acceptedRootFetchBackoffDelaysNanoseconds.reduce(0, +)

        XCTAssertGreaterThanOrEqual(
            totalDelay,
            12_000_000_000,
            "Participant join bootstrap should tolerate multi-second CloudKit propagation after share acceptance."
        )
        XCTAssertGreaterThanOrEqual(
            CloudKitManager.acceptedRootFetchBackoffDelaysNanoseconds.count,
            5
        )
    }

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
