import Foundation
import UserNotifications

/// Service for managing local notifications
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Task Notifications

    /// Schedule a reminder for a task with due date
    func scheduleTaskReminder(for task: Task) async {
        guard isAuthorized, let dueDate = task.dueDate else { return }

        // Remove existing notification for this task
        await removeTaskReminder(for: task)

        // Don't schedule if already past
        guard dueDate > Date() else { return }

        // Schedule reminder for morning of due date (9 AM)
        let content = UNMutableNotificationContent()
        content.title = "Task Due Today"
        content.body = task.title
        content.sound = .default
        content.categoryIdentifier = "TASK_REMINDER"

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: taskNotificationId(task),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            // Silently fail - notifications are optional
        }
    }

    /// Remove scheduled reminder for a task
    func removeTaskReminder(for task: Task) async {
        center.removePendingNotificationRequests(withIdentifiers: [taskNotificationId(task)])
    }

    /// Remove all task reminders
    func removeAllTaskReminders() {
        center.removeAllPendingNotificationRequests()
    }

    private func taskNotificationId(_ task: Task) -> String {
        "task-\(task.id.uuidString)"
    }

    // MARK: - Daily Digest

    /// Schedule daily digest notification (configurable time)
    func scheduleDailyDigest(at hour: Int = 8, minute: Int = 0) async {
        guard isAuthorized else { return }

        // Remove existing daily digest
        center.removePendingNotificationRequests(withIdentifiers: ["daily-digest"])

        let content = UNMutableNotificationContent()
        content.title = "Good morning!"
        content.body = "Check your tasks for today"
        content.sound = .default
        content.categoryIdentifier = "DAILY_DIGEST"

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-digest",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            // Silently fail
        }
    }

    /// Cancel daily digest
    func cancelDailyDigest() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-digest"])
    }
}
