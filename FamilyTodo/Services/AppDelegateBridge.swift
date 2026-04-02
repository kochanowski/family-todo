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

struct RemoteCloudChangeScopeResolution: Equatable {
    let declaredScope: CKDatabase.Scope?
    let effectiveScope: CKDatabase.Scope?
    let notificationType: CKNotification.NotificationType
    let currentSyncContext: HouseholdSyncContext?
    let inferredFromSyncContext: Bool

    var currentSyncContextAvailable: Bool {
        currentSyncContext != nil
    }
}

struct AppDelegateRemotePushDiagnostic: Equatable {
    let notificationType: CKNotification.NotificationType
    let declaredScope: CKDatabase.Scope?
    let effectiveScope: CKDatabase.Scope?
    let currentSyncContextAvailable: Bool
    let inferredFromSyncContext: Bool
    let handlerInstalled: Bool
    let queuedBehindActiveRefresh: Bool
    let willInvokeRemoteCloudChangeHandler: Bool
    let syncRole: HouseholdSyncRole?
    let syncHouseholdId: UUID?
    let applicationState: UIApplication.State
    let scopeResolution: String

    var progressOperation: String {
        [
            "remotePush",
            "type=\(notificationType.rawValue)",
            "declaredScope=\(scopeLabel(declaredScope))",
            "effectiveScope=\(scopeLabel(effectiveScope))",
            "currentSyncContextAvailable=\(currentSyncContextAvailable)",
            "inferredFromSyncContext=\(inferredFromSyncContext)",
            "handlerInstalled=\(handlerInstalled)",
            "queuedBehindActiveRefresh=\(queuedBehindActiveRefresh)",
            "willInvokeHandler=\(willInvokeRemoteCloudChangeHandler)",
            "role=\(roleLabel(syncRole))",
            "householdId=\(syncHouseholdId?.uuidString ?? "nil")",
            "appState=\(applicationStateLabel(applicationState))",
            "scopeResolution=\(scopeResolution)",
        ].joined(separator: " ")
    }

    private func scopeLabel(_ scope: CKDatabase.Scope?) -> String {
        guard let scope else { return "nil" }
        return switch scope {
        case .private:
            "private"
        case .public:
            "public"
        case .shared:
            "shared"
        @unknown default:
            "unknown"
        }
    }

    private func roleLabel(_ role: HouseholdSyncRole?) -> String {
        guard let role else { return "nil" }
        return switch role {
        case .owner:
            "owner"
        case .participant:
            "participant"
        }
    }

    private func applicationStateLabel(_ state: UIApplication.State) -> String {
        switch state {
        case .active:
            "active"
        case .inactive:
            "inactive"
        case .background:
            "background"
        @unknown default:
            "unknown"
        }
    }
}

struct RemoteCloudChangeContextResolver {
    let currentSyncContextProvider: @MainActor () -> HouseholdSyncContext?

    @MainActor
    func resolveScope(
        declaredScope: CKDatabase.Scope?,
        notificationType: CKNotification.NotificationType
    ) -> RemoteCloudChangeScopeResolution {
        let currentSyncContext = currentSyncContextProvider()
        let effectiveScope: CKDatabase.Scope? = if let declaredScope {
            declaredScope
        } else if notificationType == .recordZone, let currentSyncContext {
            switch currentSyncContext.scope {
            case .ownerPrivate:
                .private
            case .participantShared:
                .shared
            }
        } else {
            nil
        }

        return RemoteCloudChangeScopeResolution(
            declaredScope: declaredScope,
            effectiveScope: effectiveScope,
            notificationType: notificationType,
            currentSyncContext: currentSyncContext,
            inferredFromSyncContext: declaredScope == nil && effectiveScope != nil
        )
    }

    @MainActor
    func resolveDatabaseScope(
        declaredScope: CKDatabase.Scope?,
        notificationType: CKNotification.NotificationType
    ) -> CKDatabase.Scope? {
        resolveScope(
            declaredScope: declaredScope,
            notificationType: notificationType
        ).effectiveScope
    }
}

@MainActor
final class AppDelegateBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var shareAcceptanceCoordinator: ShareAcceptanceCoordinator?
    var remoteCloudChangeHandler: (@MainActor (RemoteCloudChangeContext) async -> UIBackgroundFetchResult)?
    var currentSyncContextProvider: @MainActor () -> HouseholdSyncContext? = { nil }
    var remotePushDiagnosticsRecorder: @MainActor (AppDelegateRemotePushDiagnostic) -> Void = { diagnostic in
        CloudKitDiagnosticsState.shared.recordProgress(operation: diagnostic.progressOperation)
    }

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
        let resolution = remoteCloudChangeScopeResolution(for: notification)
        if resolution.effectiveScope == nil {
            CloudKitDiagnosticsState.shared.recordProgress(
                operation: "remotePush.scopeUnresolved type=\(notification.notificationType.rawValue) declaredScope=\(scopeLabel(resolution.declaredScope)) currentSyncContextAvailable=\(resolution.currentSyncContextAvailable) role=\(resolution.currentSyncContext?.role == .owner ? "owner" : resolution.currentSyncContext?.role == .participant ? "participant" : "nil")"
            )
        }
        let remotePushDiagnostic = makeRemotePushDiagnostic(
            resolution: resolution,
            handlerInstalled: remoteCloudChangeHandler != nil,
            queuedBehindActiveRefresh: activeRemoteRefreshTask != nil
        )
        remotePushDiagnosticsRecorder(remotePushDiagnostic)

        guard let remoteCloudChangeHandler else {
            print("[RemoteSync] No remote cloud change handler is installed.")
            completionHandler(.noData)
            return
        }

        let context = remoteCloudChangeContext(
            for: notification,
            resolution: resolution
        )
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
        CloudKitDiagnosticsState.shared.recordProgress(
            operation: "push.registration.succeeded tokenLength=\(tokenPreview.count)"
        )
        print(
            "[RemoteSync] Registered for remote notifications. tokenPrefix=\(tokenPreview.prefix(16)) length=\(tokenPreview.count)"
        )
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[RemoteSync] Failed to register for remote notifications: \(error.localizedDescription)")
        CloudKitDiagnosticsState.shared.recordProgress(
            operation: "push.registration.failed description=\(sanitizeProgressValue(error.localizedDescription))"
        )
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
        for notification: CKNotification,
        resolution: RemoteCloudChangeScopeResolution? = nil
    ) -> RemoteCloudChangeContext {
        let resolvedScope = resolution ?? remoteCloudChangeScopeResolution(for: notification)

        return RemoteCloudChangeContext(
            databaseScope: resolvedScope.effectiveScope,
            notificationType: notification.notificationType,
            receivedAt: Date()
        )
    }

    func makeRemotePushDiagnostic(
        resolution: RemoteCloudChangeScopeResolution,
        handlerInstalled: Bool,
        queuedBehindActiveRefresh: Bool
    ) -> AppDelegateRemotePushDiagnostic {
        let scopeResolution: String = if resolution.effectiveScope != nil {
            resolution.inferredFromSyncContext ? "inferred" : "declared"
        } else {
            "unresolved"
        }

        AppDelegateRemotePushDiagnostic(
            notificationType: resolution.notificationType,
            declaredScope: resolution.declaredScope,
            effectiveScope: resolution.effectiveScope,
            currentSyncContextAvailable: resolution.currentSyncContextAvailable,
            inferredFromSyncContext: resolution.inferredFromSyncContext,
            handlerInstalled: handlerInstalled,
            queuedBehindActiveRefresh: queuedBehindActiveRefresh,
            willInvokeRemoteCloudChangeHandler: handlerInstalled,
            syncRole: resolution.currentSyncContext?.role,
            syncHouseholdId: resolution.currentSyncContext?.householdId,
            applicationState: UIApplication.shared.applicationState,
            scopeResolution: scopeResolution
        )
    }

    private func remoteCloudChangeScopeResolution(
        for notification: CKNotification
    ) -> RemoteCloudChangeScopeResolution {
        let declaredDatabaseScope: CKDatabase.Scope? = if let databaseNotification = notification as? CKDatabaseNotification {
            databaseNotification.databaseScope
        } else {
            nil
        }

        return RemoteCloudChangeContextResolver(
            currentSyncContextProvider: currentSyncContextProvider
        ).resolveScope(
            declaredScope: declaredDatabaseScope,
            notificationType: notification.notificationType
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

    private func scopeLabel(_ scope: CKDatabase.Scope?) -> String {
        guard let scope else { return "nil" }
        return switch scope {
        case .private:
            "private"
        case .public:
            "public"
        case .shared:
            "shared"
        @unknown default:
            "unknown"
        }
    }

    private func sanitizeProgressValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}
