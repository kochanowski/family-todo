import CloudKit
import Combine
import Foundation
import SwiftUI
import UIKit

enum RemoteSyncPresentationDomain: Equatable {
    case shopping
    case tasks
}

enum RemoteSyncPresentationKind: Equatable {
    case additions
    case updates
}

struct RemoteSyncPresentation: Equatable {
    let domain: RemoteSyncPresentationDomain
    let kind: RemoteSyncPresentationKind
    let changeCount: Int
    let titles: [String]
}

struct InlineRemoteSyncFeedback: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Manages CloudKit subscriptions for real-time change notifications
@MainActor
final class CloudKitSubscriptionManager: ObservableObject {
    static let shared = CloudKitSubscriptionManager()

    // MARK: - Published State

    @Published var pendingShoppingChanges: [String] = []
    @Published var pendingTaskChanges: [String] = []
    @Published var showNewItemsBanner = false
    @Published var newItemsCount = 0
    @Published private(set) var activeTab: AppTab = .shopping
    @Published private(set) var shoppingInlineFeedback: InlineRemoteSyncFeedback?
    @Published private(set) var tasksInlineFeedback: InlineRemoteSyncFeedback?

    // MARK: - Private State

    /// Use CloudKitManager for consistent container access
    private let cloudKit = CloudKitManager.shared
    private var databaseSubscriptionIds: Set<String> = []
    private var householdZoneSubscriptionIds: Set<String> = []
    private var configuredUserId: String?
    private var configuredHouseholdId: UUID?
    private var configuredScope: CloudKitManager.HouseholdDatabaseScope?
    private var recentLocalMutationByRecordName: [String: Date] = [:]
    private var lastLocalMutationAt: Date?
    private var shoppingInlineDismissTask: _Concurrency.Task<Void, Never>?
    private var tasksInlineDismissTask: _Concurrency.Task<Void, Never>?

    private let selfNoiseWindow: TimeInterval = 8
    private let inlineFeedbackDurationNanoseconds: UInt64 = 2_500_000_000

    // MARK: - Initialization

    init() {}

    static func shouldCreateZoneSubscription(
        for scope: CloudKitManager.HouseholdDatabaseScope
    ) -> Bool {
        scope == .ownerPrivate
    }

    // MARK: - Setup

    func configure(
        userId: String,
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) {
        let configurationChanged =
            configuredUserId != userId ||
            configuredHouseholdId != householdId ||
            configuredScope != scope
        guard configurationChanged else { return }

        configuredUserId = userId
        configuredHouseholdId = householdId
        configuredScope = scope
        resetTransientPresentationState()

        _Concurrency.Task {
            await setupSubscriptions(householdId: householdId, scope: scope)
            await registerForRemoteNotifications()
        }
    }

    // MARK: - Subscriptions

    private func setupSubscriptions(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) async {
        // Ensure CloudKit is ready before accessing
        await cloudKit.ensureReady()

        let container = await cloudKit.getContainer()
        let sharedDatabase = container.sharedCloudDatabase
        let privateDatabase = container.privateCloudDatabase

        await createDatabaseSubscription(
            subscriptionId: "shared-database-changes",
            database: sharedDatabase
        )
        await createDatabaseSubscription(
            subscriptionId: "private-database-changes",
            database: privateDatabase
        )

        await syncHouseholdZoneSubscriptions(
            householdId: householdId,
            scope: scope,
            sharedDatabase: sharedDatabase,
            privateDatabase: privateDatabase
        )
    }

    private func createDatabaseSubscription(
        subscriptionId: String,
        database: CKDatabase
    ) async {
        do {
            let existingSubscription = try await database.subscription(for: subscriptionId)
            databaseSubscriptionIds.insert(subscriptionId)
            print(
                "[CloudKitSubscription] Reusing database subscription id=\(subscriptionId) type=\(type(of: existingSubscription))"
            )
            return
        } catch {
            print("[CloudKitSubscription] Database subscription lookup missed for id=\(subscriptionId): \(error.localizedDescription)")
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionId)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            let confirmedSubscription = try await database.subscription(for: subscriptionId)
            databaseSubscriptionIds.insert(subscriptionId)
            print(
                "✅ Created database subscription id=\(subscriptionId) confirmedType=\(type(of: confirmedSubscription))"
            )
        } catch {
            reportSubscriptionFailure(
                error,
                context: "createDatabaseSubscription.\(subscriptionId)"
            )
        }
    }

    private func syncHouseholdZoneSubscriptions(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?,
        sharedDatabase: CKDatabase,
        privateDatabase: CKDatabase
    ) async {
        let requiredSubscriptionIds = Set(zoneSubscriptionIDs(for: householdId, scope: scope))
        let obsoleteSubscriptionIds = householdZoneSubscriptionIds.subtracting(requiredSubscriptionIds)

        for subscriptionId in obsoleteSubscriptionIds {
            await deleteSubscriptionIfPresent(
                subscriptionId: subscriptionId,
                databases: [sharedDatabase, privateDatabase]
            )
            householdZoneSubscriptionIds.remove(subscriptionId)
        }

        guard let scope,
              Self.shouldCreateZoneSubscription(for: scope),
              let zoneID = try? await cloudKit.resolveSubscriptionZone(
                  householdId: householdId,
                  scope: scope
              )
        else {
            return
        }

        let database: CKDatabase = switch scope {
        case .ownerPrivate:
            privateDatabase
        case .participantShared:
            sharedDatabase
        }

        let subscriptionId = zoneSubscriptionID(
            householdId: householdId,
            scope: scope
        )
        await createZoneSubscription(
            subscriptionId: subscriptionId,
            database: database,
            zoneID: zoneID
        )
    }

    private func createZoneSubscription(
        subscriptionId: String,
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async {
        do {
            let existingSubscription = try await database.subscription(for: subscriptionId)
            householdZoneSubscriptionIds.insert(subscriptionId)
            print(
                "[CloudKitSubscription] Reusing zone subscription id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName) type=\(type(of: existingSubscription))"
            )
            return
        } catch {
            print(
                "[CloudKitSubscription] Zone subscription lookup missed for id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName): \(error.localizedDescription)"
            )
        }

        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionId
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            let confirmedSubscription = try await database.subscription(for: subscriptionId)
            householdZoneSubscriptionIds.insert(subscriptionId)
            print(
                "✅ Created zone subscription id=\(subscriptionId) zone=\(zoneID.zoneName)|\(zoneID.ownerName) confirmedType=\(type(of: confirmedSubscription))"
            )
        } catch {
            reportSubscriptionFailure(
                error,
                context: "createZoneSubscription.\(subscriptionId).\(zoneID.zoneName)"
            )
        }
    }

    private func deleteSubscriptionIfPresent(
        subscriptionId: String,
        databases: [CKDatabase]
    ) async {
        for database in databases {
            do {
                try await database.deleteSubscription(withID: subscriptionId)
                print("🗑️ Removed subscription: \(subscriptionId)")
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue
            } catch {
                reportSubscriptionFailure(
                    error,
                    context: "deleteSubscriptionIfPresent.\(subscriptionId)"
                )
            }
        }
    }

    private func zoneSubscriptionID(
        householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope
    ) -> String {
        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        return "household-zone-\(scopeName)-\(householdId.uuidString)"
    }

    private func zoneSubscriptionIDs(
        for householdId: UUID,
        scope: CloudKitManager.HouseholdDatabaseScope?
    ) -> [String] {
        guard let scope, Self.shouldCreateZoneSubscription(for: scope) else { return [] }
        return [zoneSubscriptionID(householdId: householdId, scope: scope)]
    }

    // MARK: - Push Notification Registration

    private func registerForRemoteNotifications() async {
        #if !CI
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        #endif
    }

    // MARK: - Handle Remote Notification

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            print("[CloudKitSubscription] Ignoring remote notification because it was not recognized as CloudKit.")
            return
        }

        if let dbNotification = notification as? CKDatabaseNotification {
            print("[CloudKitSubscription] Received database notification.")
            handleDatabaseNotification(dbNotification)
        } else if let zoneNotification = notification as? CKRecordZoneNotification {
            print("[CloudKitSubscription] Received record-zone notification.")
            handleRecordZoneNotification(zoneNotification)
        } else if let queryNotification = notification as? CKQueryNotification {
            let recordType = (queryNotification.recordFields?["recordType"] as? String) ?? "unknown"
            print("[CloudKitSubscription] Received query notification for recordType=\(recordType).")
            handleQueryNotification(queryNotification)
        } else {
            print("[CloudKitSubscription] Received CloudKit notification of unsupported type \(notification.notificationType.rawValue).")
        }
    }

    func registerLocalMutation(recordName: String?) {
        let now = Date()
        lastLocalMutationAt = now
        if let recordName {
            recentLocalMutationByRecordName[recordName] = now
        }
        pruneLocalMutationNoiseWindow(relativeTo: now)
    }

    private func pruneLocalMutationNoiseWindow(relativeTo now: Date) {
        recentLocalMutationByRecordName = recentLocalMutationByRecordName.filter { _, timestamp in
            now.timeIntervalSince(timestamp) <= selfNoiseWindow
        }
        if let lastLocalMutationAt, now.timeIntervalSince(lastLocalMutationAt) > selfNoiseWindow {
            self.lastLocalMutationAt = nil
        }
    }

    private func isLikelySelfNoise(recordName: String?) -> Bool {
        let now = Date()
        pruneLocalMutationNoiseWindow(relativeTo: now)

        if let recordName,
           let timestamp = recentLocalMutationByRecordName[recordName],
           now.timeIntervalSince(timestamp) <= selfNoiseWindow
        {
            return true
        }

        if let lastLocalMutationAt,
           now.timeIntervalSince(lastLocalMutationAt) <= selfNoiseWindow
        {
            return true
        }
        return false
    }

    private func handleDatabaseNotification(_: CKDatabaseNotification) {
        guard !isLikelySelfNoise(recordName: nil) else {
            print("[CloudKitSubscription] Dropping database notification as likely self-noise.")
            return
        }
        print(
            "[CloudKitSubscription] Database notification accepted. Waiting for hydrated refresh summary."
        )
    }

    private func handleRecordZoneNotification(_: CKRecordZoneNotification) {
        guard !isLikelySelfNoise(recordName: nil) else {
            print("[CloudKitSubscription] Dropping record-zone notification as likely self-noise.")
            return
        }
        print(
            "[CloudKitSubscription] Record-zone notification accepted. Waiting for hydrated refresh summary."
        )
    }

    private func handleQueryNotification(_ notification: CKQueryNotification) {
        let recordType = (notification.recordFields?["recordType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recordName = notification.recordID?.recordName
        guard !isLikelySelfNoise(recordName: recordName) else {
            print("[CloudKitSubscription] Dropping query notification as likely self-noise for recordName=\(recordName ?? "unknown").")
            return
        }

        guard let recordType, !recordType.isEmpty, recordType != "Unknown" else {
            return
        }

        if recordType == "Household" || recordType == "Member" {
            return
        }
        print(
            "[CloudKitSubscription] Query notification accepted for recordType=\(recordType). Waiting for hydrated refresh summary."
        )
    }

    // MARK: - Presentation State

    func updateActiveTab(_ tab: AppTab) {
        activeTab = tab
        if tab == .shopping {
            dismissBanner()
        }
    }

    func publishRemoteSyncPresentation(
        _ presentation: RemoteSyncPresentation,
        applicationState: UIApplication.State = UIApplication.shared.applicationState
    ) {
        guard applicationState == .active else { return }

        switch presentation.domain {
        case .shopping:
            publishShoppingPresentation(presentation)
        case .tasks:
            publishTasksPresentation(presentation)
        }
    }

    func shouldSuppressSharedShoppingAlert(
        applicationState: UIApplication.State = UIApplication.shared.applicationState
    ) -> Bool {
        applicationState == .active
    }

    func shouldSuppressHouseholdCelebrationAlert(
        applicationState: UIApplication.State = UIApplication.shared.applicationState
    ) -> Bool {
        applicationState == .active && activeTab == .tasks
    }

    func dismissBanner() {
        withAnimation(WowAnimation.easeOut) {
            showNewItemsBanner = false
        }
        pendingShoppingChanges.removeAll()
        pendingTaskChanges.removeAll()
        newItemsCount = 0
    }

    func resetTransientPresentationState() {
        dismissBanner()
        shoppingInlineDismissTask?.cancel()
        shoppingInlineDismissTask = nil
        shoppingInlineFeedback = nil
        tasksInlineDismissTask?.cancel()
        tasksInlineDismissTask = nil
        tasksInlineFeedback = nil
    }

    private func publishShoppingPresentation(_ presentation: RemoteSyncPresentation) {
        switch presentation.kind {
        case .additions:
            guard presentation.changeCount > 0 else { return }
            if activeTab == .shopping {
                publishInlineFeedback(
                    text: shoppingInlineText(for: presentation),
                    domain: .shopping
                )
                dismissBanner()
            } else {
                pendingShoppingChanges.removeAll()
                pendingTaskChanges.removeAll()
                newItemsCount = presentation.changeCount
                HapticManager.selection()
                withAnimation(WowAnimation.spring) {
                    showNewItemsBanner = true
                }
            }
        case .updates:
            dismissBanner()
            guard activeTab == .shopping else { return }
            publishInlineFeedback(
                text: shoppingInlineText(for: presentation),
                domain: .shopping
            )
        }
    }

    private func publishTasksPresentation(_ presentation: RemoteSyncPresentation) {
        dismissBanner()
        guard activeTab == .tasks else { return }
        publishInlineFeedback(
            text: tasksInlineText(for: presentation),
            domain: .tasks
        )
    }

    private func publishInlineFeedback(
        text: String,
        domain: RemoteSyncPresentationDomain
    ) {
        let feedback = InlineRemoteSyncFeedback(text: text)

        switch domain {
        case .shopping:
            shoppingInlineDismissTask?.cancel()
            withAnimation(WowAnimation.spring) {
                shoppingInlineFeedback = feedback
            }
            shoppingInlineDismissTask = scheduleInlineDismiss(for: domain, feedbackId: feedback.id)
        case .tasks:
            tasksInlineDismissTask?.cancel()
            withAnimation(WowAnimation.spring) {
                tasksInlineFeedback = feedback
            }
            tasksInlineDismissTask = scheduleInlineDismiss(for: domain, feedbackId: feedback.id)
        }
    }

    private func scheduleInlineDismiss(
        for domain: RemoteSyncPresentationDomain,
        feedbackId: UUID
    ) -> _Concurrency.Task<Void, Never> {
        _Concurrency.Task { @MainActor [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: inlineFeedbackDurationNanoseconds)
            guard !_Concurrency.Task.isCancelled, let self else { return }

            switch domain {
            case .shopping:
                guard shoppingInlineFeedback?.id == feedbackId else { return }
                withAnimation(WowAnimation.easeOut) {
                    shoppingInlineFeedback = nil
                }
                shoppingInlineDismissTask = nil
            case .tasks:
                guard tasksInlineFeedback?.id == feedbackId else { return }
                withAnimation(WowAnimation.easeOut) {
                    tasksInlineFeedback = nil
                }
                tasksInlineDismissTask = nil
            }
        }
    }

    private func shoppingInlineText(for presentation: RemoteSyncPresentation) -> String {
        switch presentation.kind {
        case .additions:
            presentation.changeCount == 1
                ? "1 item added"
                : "\(presentation.changeCount) items added"
        case .updates:
            "Shopping updated"
        }
    }

    private func tasksInlineText(for presentation: RemoteSyncPresentation) -> String {
        switch presentation.kind {
        case .additions:
            presentation.changeCount == 1
                ? "1 task added"
                : "\(presentation.changeCount) tasks added"
        case .updates:
            "Tasks updated"
        }
    }

    private func reportSubscriptionFailure(_ error: Error, context: String) {
        print("[CloudKitSubscription] \(context) failed: \(error.localizedDescription)")
        CloudKitDiagnosticsState.shared.record(error: error, operation: context)
    }

    // MARK: - Cleanup

    func removeSubscriptions() async {
        let container = await cloudKit.getContainer()
        let databases = [
            container.sharedCloudDatabase,
            container.privateCloudDatabase,
        ]

        for subscriptionId in databaseSubscriptionIds.union(householdZoneSubscriptionIds) {
            await deleteSubscriptionIfPresent(subscriptionId: subscriptionId, databases: databases)
        }
        databaseSubscriptionIds.removeAll()
        householdZoneSubscriptionIds.removeAll()
        configuredUserId = nil
        configuredHouseholdId = nil
        configuredScope = nil
        resetTransientPresentationState()
    }
}
