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

    private lazy var container = CKContainer.default()
    private var subscriptionIds: [String] = []
    private var aggregationTimer: Timer?
    private var pendingNotifications: [(recordType: String, timestamp: Date)] = []
    private var currentUserId: String?

    private let aggregationWindow: TimeInterval = 60 // 60 seconds

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    func configure(userId: String, householdId: UUID) {
        currentUserId = userId

        _Concurrency.Task {
            await setupSubscriptions(householdId: householdId)
            await registerForPushNotifications()
        }
    }

    // MARK: - Subscriptions

    private func setupSubscriptions(householdId _: UUID) async {
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

    private func handleDatabaseNotification(_: CKDatabaseNotification) {
        // Shared database changed.
        // For WOW polish, we'll assume it's relevant and show a generic banner.
        pendingShoppingChanges.append("Shared Update")
        scheduleAggregatedNotification()
        showInAppBanner(for: "Shared Update")
    }

    private func handleQueryNotification(_ notification: CKQueryNotification) {
        let recordType = notification.recordFields?["recordType"] as? String ?? "Unknown"
        let creatorId = notification.recordFields?["creatorUserId"] as? String

        // Self-notify OFF: Don't notify if we made the change
        if creatorId == currentUserId {
            return
        }

        // Add to pending notifications for aggregation
        if recordType == "ShoppingItem" {
            pendingShoppingChanges.append(recordType)
        } else if recordType == "Task" {
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
