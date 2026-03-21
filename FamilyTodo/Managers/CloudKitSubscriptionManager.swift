import CloudKit
import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Manages CloudKit subscriptions for real-time change notifications
@MainActor
final class CloudKitSubscriptionManager: ObservableObject {
    static let shared = CloudKitSubscriptionManager()

    // MARK: - Published State

    @Published var pendingShoppingChanges: [String] = []
    @Published var pendingTaskChanges: [String] = []
    @Published var showNewItemsBanner = false
    @Published var newItemsCount = 0

    // MARK: - Private State

    /// Use CloudKitManager for consistent container access
    private let cloudKit = CloudKitManager.shared
    private var databaseSubscriptionIds: Set<String> = []
    private var householdZoneSubscriptionIds: Set<String> = []
    private var configuredUserId: String?
    private var configuredHouseholdId: UUID?
    private var configuredScope: CloudKitManager.HouseholdDatabaseScope?
    private var aggregationTimer: Timer?
    private var recentLocalMutationByRecordName: [String: Date] = [:]
    private var lastLocalMutationAt: Date?

    private let aggregationWindow: TimeInterval = 60 // 60 seconds
    private let selfNoiseWindow: TimeInterval = 8

    // MARK: - Initialization

    init() {}

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
            // Check if subscription already exists
            _ = try await database.subscription(for: subscriptionId)
            databaseSubscriptionIds.insert(subscriptionId)
            return // Already exists
        } catch {
            // Subscription doesn't exist, proceed to create
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionId)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            databaseSubscriptionIds.insert(subscriptionId)
            print("✅ Created database subscription: \(subscriptionId)")
        } catch {
            print("❌ Failed to create database subscription: \(error)")
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
            _ = try await database.subscription(for: subscriptionId)
            householdZoneSubscriptionIds.insert(subscriptionId)
            return
        } catch {
            // Subscription doesn't exist yet.
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
            householdZoneSubscriptionIds.insert(subscriptionId)
            print("✅ Created zone subscription: \(subscriptionId) for zone \(zoneID.zoneName)")
        } catch {
            print("❌ Failed to create zone subscription: \(subscriptionId) error=\(error)")
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
                print("❌ Failed to remove subscription: \(subscriptionId) error=\(error)")
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
        guard let scope else { return [] }
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

    private func triggerRefreshForAllDomains(source: String) {
        NotificationCenter.default.post(name: .shoppingListDataDidChange, object: source)
        NotificationCenter.default.post(name: .taskBoardDataDidChange, object: source)
        NotificationCenter.default.post(name: .backlogDataDidChange, object: source)
        NotificationCenter.default.post(name: .householdDataDidChange, object: source)
    }

    private func triggerRefresh(for recordType: String?, source: String) {
        switch recordType {
        case "ShoppingItem", "ShoppingBundle":
            NotificationCenter.default.post(name: .shoppingListDataDidChange, object: source)
        case "WorkItem":
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: source)
            NotificationCenter.default.post(name: .backlogDataDidChange, object: source)
        case "Task":
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: source)
        case "BacklogItem":
            NotificationCenter.default.post(name: .backlogDataDidChange, object: source)
        case "BacklogCategory":
            NotificationCenter.default.post(name: .backlogDataDidChange, object: source)
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: source)
        case "Household", "Member":
            NotificationCenter.default.post(name: .householdDataDidChange, object: source)
        default:
            return
        }
    }

    private func handleDatabaseNotification(_: CKDatabaseNotification) {
        guard !isLikelySelfNoise(recordName: nil) else {
            print("[CloudKitSubscription] Dropping database notification as likely self-noise.")
            return
        }
        triggerRefreshForAllDomains(source: "remote")

        pendingShoppingChanges.append("Shared Update")
        scheduleAggregatedNotification()
        showInAppBanner(for: "Shared Update")
    }

    private func handleRecordZoneNotification(_: CKRecordZoneNotification) {
        guard !isLikelySelfNoise(recordName: nil) else {
            print("[CloudKitSubscription] Dropping record-zone notification as likely self-noise.")
            return
        }
        triggerRefreshForAllDomains(source: "remote")

        pendingShoppingChanges.append("Zone Update")
        scheduleAggregatedNotification()
        showInAppBanner(for: "Zone Update")
    }

    private func handleQueryNotification(_ notification: CKQueryNotification) {
        let recordType = (notification.recordFields?["recordType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recordName = notification.recordID?.recordName
        guard !isLikelySelfNoise(recordName: recordName) else {
            print("[CloudKitSubscription] Dropping query notification as likely self-noise for recordName=\(recordName ?? "unknown").")
            return
        }
        triggerRefresh(for: recordType, source: "remote")

        guard let recordType, !recordType.isEmpty, recordType != "Unknown" else {
            return
        }

        if recordType == "Household" || recordType == "Member" {
            return
        }

        // Add to pending notifications for aggregation
        if recordType == "ShoppingItem" || recordType == "ShoppingBundle" {
            pendingShoppingChanges.append(recordType)
        } else if recordType == "Task" || recordType == "BacklogItem" || recordType == "BacklogCategory" || recordType == "WorkItem" {
            pendingTaskChanges.append(recordType)
        } else {
            pendingTaskChanges.append(recordType)
        }

        scheduleAggregatedNotification()
        showInAppBanner(for: recordType)
    }

    // MARK: - In-App Banner

    private func showInAppBanner(for _: String) {
        // Update banner state
        newItemsCount = pendingShoppingChanges.count + pendingTaskChanges.count
        if newItemsCount > 0 {
            HapticManager.selection()
            withAnimation(WowAnimation.spring) {
                showNewItemsBanner = true
            }
        }
    }

    func dismissBanner() {
        withAnimation(WowAnimation.easeOut) {
            showNewItemsBanner = false
        }
        pendingShoppingChanges.removeAll()
        pendingTaskChanges.removeAll()
        newItemsCount = 0
    }

    // MARK: - Aggregation

    private func scheduleAggregatedNotification() {
        aggregationTimer?.invalidate()
        guard UIApplication.shared.applicationState != .active else { return }
        aggregationTimer = Timer.scheduledTimer(withTimeInterval: aggregationWindow, repeats: false) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.sendAggregatedNotification()
            }
        }
    }

    private func sendAggregatedNotification() {
        // Simple aggregation since we might not have details from Shared DB
        let count = pendingShoppingChanges.count + pendingTaskChanges.count
        guard count > 0 else { return }

        let message = count == 1 ? "New shared item added" : "\(count) new shared items added"

        // Send local notification (app is in background)
        sendLocalNotification(title: "FamilySync", body: message)

        pendingShoppingChanges.removeAll()
        pendingTaskChanges.removeAll()
        newItemsCount = 0
    }

    private func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
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
    }
}
