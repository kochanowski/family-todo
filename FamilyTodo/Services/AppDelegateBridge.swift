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

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        CloudKitSubscriptionManager.shared.handleRemoteNotification(userInfo: userInfo)
        completionHandler(.newData)
    }

    func flushPendingInviteIfNeeded() {
        guard let pendingMetadata, let shareAcceptanceCoordinator else { return }
        shareAcceptanceCoordinator.enqueue(metadata: pendingMetadata)
        self.pendingMetadata = nil
    }
}
