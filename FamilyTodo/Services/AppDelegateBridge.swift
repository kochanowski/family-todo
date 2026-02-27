import CloudKit
import UIKit

@MainActor
final class AppDelegateBridge: NSObject, UIApplicationDelegate {
    weak var shareAcceptanceCoordinator: ShareAcceptanceCoordinator?
    private var pendingMetadata: CKShare.Metadata?

    func application(_: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        if let shareAcceptanceCoordinator {
            shareAcceptanceCoordinator.enqueue(metadata: metadata)
        } else {
            pendingMetadata = metadata
        }
    }

    func flushPendingInviteIfNeeded() {
        guard let pendingMetadata, let shareAcceptanceCoordinator else { return }
        shareAcceptanceCoordinator.enqueue(metadata: pendingMetadata)
        self.pendingMetadata = nil
    }
}
