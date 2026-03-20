import CloudKit
import UIKit

@MainActor
final class AppDelegateBridge: NSObject, UIApplicationDelegate {
    weak var shareAcceptanceCoordinator: ShareAcceptanceCoordinator?
    var remoteCloudChangeHandler: (@MainActor () async -> UIBackgroundFetchResult)?
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
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }

        print("[RemoteSync] AppDelegate received CloudKit push of type \(notificationTypeLabel(notification)).")
        CloudKitSubscriptionManager.shared.handleRemoteNotification(userInfo: userInfo)

        guard let remoteCloudChangeHandler else {
            print("[RemoteSync] No remote cloud change handler is installed.")
            completionHandler(.noData)
            return
        }

        _ = _Concurrency.Task { @MainActor in
            let result = await remoteCloudChangeHandler()
            print("[RemoteSync] AppDelegate completed background push refresh with result \(backgroundFetchResultLabel(result)).")
            completionHandler(result)
        }
    }

    func flushPendingInviteIfNeeded() {
        guard let pendingMetadata, let shareAcceptanceCoordinator else { return }
        shareAcceptanceCoordinator.enqueue(metadata: pendingMetadata)
        self.pendingMetadata = nil
    }

    private func notificationTypeLabel(_ notification: CKNotification) -> String {
        switch notification.notificationType {
        case .database:
            "database"
        case .query:
            "query"
        case .readNotification:
            "read"
        case .recordZone:
            "recordZone"
        @unknown default:
            "unknown"
        }
    }

    private func backgroundFetchResultLabel(_ result: UIBackgroundFetchResult) -> String {
        switch result {
        case .newData:
            "newData"
        case .noData:
            "noData"
        case .failed:
            "failed"
        @unknown default:
            "unknown"
        }
    }
}
