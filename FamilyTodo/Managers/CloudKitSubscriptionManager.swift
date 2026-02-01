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

    private let container = CKContainer.default()
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

    private func setupSubscriptions(householdId: UUID) async {
        let database = container.sharedCloudDatabase

        // Shopping Item subscription
        await createSubscription(
            recordType: "ShoppingItem",
            subscriptionId: "shopping-changes-\(householdId.uuidString)",
            database: database
        )

        // Task subscription
        await createSubscription(
            recordType: "Task",
            subscriptionId: "task-changes-\(householdId.uuidString)",
            database: database
        )
    }

    private func createSubscription(
        recordType: String,
        subscriptionId: String,
        database: CKDatabase
    ) async {
        // Check if subscription already exists
        do {
            _ = try await database.subscription(for: subscriptionId)
            subscriptionIds.append(subscriptionId)
            return // Already exists
        } catch {
            // Subscription doesn't exist, create it
        }

        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionId,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            subscriptionIds.append(subscriptionId)
            print("✅ Created subscription: \(subscriptionId)")
        } catch {
            print("❌ Failed to create subscription: \(error)")
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
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = notification as? CKQueryNotification
        else {
            return
        }

        let recordType = queryNotification.recordFields?["recordType"] as? String ?? "Unknown"
        let creatorId = queryNotification.recordFields?["creatorUserId"] as? String

        // Self-notify OFF: Don't notify if we made the change
        if creatorId == currentUserId {
            return
        }

        // Add to pending notifications for aggregation
        pendingNotifications.append((recordType: recordType, timestamp: Date()))
        scheduleAggregatedNotification()

        // Show in-app banner immediately
        showInAppBanner(for: recordType)
    }

    // MARK: - In-App Banner

    private func showInAppBanner(for recordType: String) {
        if recordType == "ShoppingItem" {
            pendingShoppingChanges.append(recordType)
        } else if recordType == "Task" {
            pendingTaskChanges.append(recordType)
        }

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
        // Filter notifications within the aggregation window
        let recentNotifications = pendingNotifications.filter {
            Date().timeIntervalSince($0.timestamp) <= aggregationWindow
        }

        guard !recentNotifications.isEmpty else { return }

        let shoppingCount = recentNotifications.filter { $0.recordType == "ShoppingItem" }.count
        let taskCount = recentNotifications.filter { $0.recordType == "Task" }.count

        var message: String = if shoppingCount > 0, taskCount > 0 {
            "\(shoppingCount) shopping items and \(taskCount) tasks added"
        } else if shoppingCount > 0 {
            shoppingCount == 1 ? "New shopping item added" : "\(shoppingCount) new items added to Shopping List"
        } else {
            taskCount == 1 ? "New task added" : "\(taskCount) new tasks added"
        }

        // Send local notification (app is in background)
        sendLocalNotification(title: "FamilySync", body: message)

        pendingNotifications.removeAll()
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
