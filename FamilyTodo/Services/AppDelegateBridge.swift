import CloudKit
import UIKit
import UserNotifications

struct RemoteCloudChangeContext: Equatable {
    let databaseScope: CKDatabase.Scope?
    let notificationType: CKNotification.NotificationType
    let receivedAt: Date

    static let unknown = RemoteCloudChangeContext(
        databaseScope: nil,
        notificationType: .readNotification,
        receivedAt: Date.distantPast
    )

    func merged(with newer: RemoteCloudChangeContext) -> RemoteCloudChangeContext {
        let preferredScope: CKDatabase.Scope? = if databaseScope == .shared || newer.databaseScope == .shared {
            .shared
        } else if databaseScope == .private || newer.databaseScope == .private {
            .private
        } else {
            newer.databaseScope ?? databaseScope
        }

        return RemoteCloudChangeContext(
            databaseScope: preferredScope,
            notificationType: newer.notificationType,
            receivedAt: max(receivedAt, newer.receivedAt)
        )
    }
}

struct RemoteCloudChangeContextResolver {
    let currentSyncContextProvider: @MainActor () -> HouseholdSyncContext?

    @MainActor
    func resolveDatabaseScope(
        declaredScope: CKDatabase.Scope?,
        notificationType: CKNotification.NotificationType
    ) -> CKDatabase.Scope? {
        if let declaredScope {
            return declaredScope
        }

        guard notificationType == .recordZone,
              let syncContext = currentSyncContextProvider()
        else {
            return nil
        }

        switch syncContext.scope {
        case .ownerPrivate:
            return .private
        case .participantShared:
            return .shared
        }
    }
}

@MainActor
final class AppDelegateBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var shareAcceptanceCoordinator: ShareAcceptanceCoordinator?
    var remoteCloudChangeHandler: (@MainActor (RemoteCloudChangeContext) async -> UIBackgroundFetchResult)?
    var currentSyncContextProvider: @MainActor () -> HouseholdSyncContext? = { nil }
    private var pendingMetadata: CKShare.Metadata?
    private var activeRemoteRefreshTask: _Concurrency.Task<UIBackgroundFetchResult, Never>?
    private var pendingRemoteRefreshContext: RemoteCloudChangeContext?

    func installNotificationCenterDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

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

        let context = remoteCloudChangeContext(for: notification)
        pendingRemoteRefreshContext = pendingRemoteRefreshContext?.merged(with: context) ?? context

        if let activeRemoteRefreshTask {
            _ = _Concurrency.Task { @MainActor in
                let result = await activeRemoteRefreshTask.value
                completionHandler(result)
            }
            return
        }

        let refreshTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return UIBackgroundFetchResult.noData }

            var aggregateResult: UIBackgroundFetchResult = .noData

            while let nextContext = pendingRemoteRefreshContext {
                pendingRemoteRefreshContext = nil
                let result = await remoteCloudChangeHandler(nextContext)
                aggregateResult = mergedBackgroundFetchResult(
                    aggregateResult,
                    with: result
                )
            }

            activeRemoteRefreshTask = nil
            return aggregateResult
        }
        activeRemoteRefreshTask = refreshTask

        _ = _Concurrency.Task { @MainActor in
            let result = await refreshTask.value
            print("[RemoteSync] AppDelegate completed background push refresh with result \(backgroundFetchResultLabel(result)).")
            completionHandler(result)
        }
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenPreview = deviceToken.map { String(format: "%02x", $0) }.joined()
        print(
            "[RemoteSync] Registered for remote notifications. tokenPrefix=\(tokenPreview.prefix(16)) length=\(tokenPreview.count)"
        )
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[RemoteSync] Failed to register for remote notifications: \(error.localizedDescription)")
        CloudKitDiagnosticsState.shared.record(
            error: error,
            operation: "registerForRemoteNotifications"
        )
    }

    func flushPendingInviteIfNeeded() {
        guard let pendingMetadata, let shareAcceptanceCoordinator else { return }
        shareAcceptanceCoordinator.enqueue(metadata: pendingMetadata)
        self.pendingMetadata = nil
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.sound != nil {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.banner, .list])
        }
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

    private func remoteCloudChangeContext(
        for notification: CKNotification
    ) -> RemoteCloudChangeContext {
        let declaredDatabaseScope: CKDatabase.Scope? = if let databaseNotification = notification as? CKDatabaseNotification {
            databaseNotification.databaseScope
        } else {
            nil
        }
        let databaseScope = RemoteCloudChangeContextResolver(
            currentSyncContextProvider: currentSyncContextProvider
        ).resolveDatabaseScope(
            declaredScope: declaredDatabaseScope,
            notificationType: notification.notificationType
        )

        return RemoteCloudChangeContext(
            databaseScope: databaseScope,
            notificationType: notification.notificationType,
            receivedAt: Date()
        )
    }

    private func mergedBackgroundFetchResult(
        _ lhs: UIBackgroundFetchResult,
        with rhs: UIBackgroundFetchResult
    ) -> UIBackgroundFetchResult {
        if lhs == .failed || rhs == .failed {
            return .failed
        }
        if lhs == .newData || rhs == .newData {
            return .newData
        }
        return .noData
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
