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
    private var subscriptionIds: [String] = []
    private var aggregationTimer: Timer?
    private var recentLocalMutationByRecordName: [String: Date] = [:]
    private var lastLocalMutationAt: Date?

    private let aggregationWindow: TimeInterval = 60 // 60 seconds
    private let selfNoiseWindow: TimeInterval = 8

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    func configure(userId _: String, householdId: UUID) {
        _Concurrency.Task {
            await setupSubscriptions(householdId: householdId)
            await registerForPushNotifications()
        }
    }

    // MARK: - Subscriptions

    private func setupSubscriptions(householdId _: UUID) async {
        // Ensure CloudKit is ready before accessing
        await cloudKit.ensureReady()

        let container = await cloudKit.getContainer()
        let database = container.sharedCloudDatabase
        let subscriptionId = "shared-database-changes"

        // Create Database Subscription for Shared Database
        await createDatabaseSubscription(
            subscriptionId: subscriptionId,
            database: database
        )
    }

    private func createDatabaseSubscription(
        subscriptionId: String,
        database: CKDatabase
    ) async {
        do {
            // Check if subscription already exists
            _ = try await database.subscription(for: subscriptionId)
            subscriptionIds.append(subscriptionId)
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
            subscriptionIds.append(subscriptionId)
            print("✅ Created database subscription: \(subscriptionId)")
        } catch {
            print("❌ Failed to create database subscription: \(error)")
        }
    }

    // MARK: - Push Notification Registration

    private func registerForPushNotifications() async {
        #if !CI
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            } catch {
                print("❌ Push notification permission error: \(error)")
            }
        #endif
    }

    // MARK: - Handle Remote Notification

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }

        if let dbNotification = notification as? CKDatabaseNotification {
            handleDatabaseNotification(dbNotification)
        } else if let queryNotification = notification as? CKQueryNotification {
            handleQueryNotification(queryNotification)
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

    private func triggerRefresh(for recordType: String?) {
        switch recordType {
        case "ShoppingItem":
            NotificationCenter.default.post(name: .shoppingListDataDidChange, object: nil)
        case "Task", "BacklogItem", "BacklogCategory":
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)
        default:
            NotificationCenter.default.post(name: .shoppingListDataDidChange, object: nil)
            NotificationCenter.default.post(name: .taskBoardDataDidChange, object: nil)
        }
    }

    private func handleDatabaseNotification(_: CKDatabaseNotification) {
        triggerRefresh(for: nil)
        guard !isLikelySelfNoise(recordName: nil) else { return }

        pendingShoppingChanges.append("Shared Update")
        scheduleAggregatedNotification()
        showInAppBanner(for: "Shared Update")
    }

    private func handleQueryNotification(_ notification: CKQueryNotification) {
        let recordType = notification.recordType ?? "Unknown"
        let recordName = notification.recordID?.recordName
        triggerRefresh(for: recordType)
        guard !isLikelySelfNoise(recordName: recordName) else { return }

        // Add to pending notifications for aggregation
        if recordType == "ShoppingItem" {
            pendingShoppingChanges.append(recordType)
        } else if recordType == "Task" || recordType == "BacklogItem" || recordType == "BacklogCategory" {
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
        let database = container.sharedCloudDatabase

        for subscriptionId in subscriptionIds {
            do {
                try await database.deleteSubscription(withID: subscriptionId)
                print("🗑️ Removed subscription: \(subscriptionId)")
            } catch {
                print("❌ Failed to remove subscription: \(error)")
            }
        }
        subscriptionIds.removeAll()
    }
}
