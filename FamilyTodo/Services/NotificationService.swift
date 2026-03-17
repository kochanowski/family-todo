import Combine
import Foundation
import SwiftData

struct DailyDigestPlan: Equatable {
    let fireDate: Date
    let dueCount: Int

    var title: String {
        "Tasks Due Today"
    }

    var body: String {
        if dueCount == 1 {
            return "You have 1 task due today."
        }
        return "You have \(dueCount) tasks due today."
    }
}

enum NotificationSchedulePlanner {
    static func taskReminderDate(
        for dueDate: Date,
        defaultReminderTime: Date,
        calendar: Calendar = .current
    ) -> Date? {
        if Task.dueDateHasExplicitTime(dueDate, calendar: calendar) {
            return dueDate
        }
        return Task.date(
            byApplyingTimeFrom: defaultReminderTime,
            to: dueDate,
            calendar: calendar
        )
    }

    static func dailyDigestPlan(
        tasks: [Task],
        now: Date = Date(),
        reminderTime: Date,
        calendar: Calendar = .current
    ) -> DailyDigestPlan? {
        guard let fireDate = nextDigestFireDate(after: now, reminderTime: reminderTime, calendar: calendar) else {
            return nil
        }

        let dueCount = tasks.reduce(into: 0) { count, task in
            guard task.status != .done,
                  let dueDate = task.dueDate,
                  calendar.isDate(dueDate, inSameDayAs: fireDate)
            else {
                return
            }
            count += 1
        }

        guard dueCount > 0 else { return nil }
        return DailyDigestPlan(fireDate: fireDate, dueCount: dueCount)
    }

    static func nextDigestFireDate(
        after now: Date,
        reminderTime: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let todayAtReminder = Task.date(
            byApplyingTimeFrom: reminderTime,
            to: now,
            calendar: calendar
        ) else {
            return nil
        }

        if todayAtReminder > now {
            return todayAtReminder
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return nil
        }

        return Task.date(
            byApplyingTimeFrom: reminderTime,
            to: tomorrow,
            calendar: calendar
        )
    }
}

#if !targetEnvironment(simulator) && !CI
    import UserNotifications
#endif

#if !targetEnvironment(simulator) && !CI
    /// Service for managing local notifications
    @MainActor
    final class NotificationService: ObservableObject {
        static let shared = NotificationService()

        @Published private(set) var isAuthorized = false

        private let center = UNUserNotificationCenter.current()
        private var settingsStore: NotificationSettingsStore?

        private init() {}

        func setSettingsStore(_ store: NotificationSettingsStore) {
            settingsStore = store
        }

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
            guard let settingsStore,
                  isAuthorized,
                  settingsStore.isEnabled,
                  settingsStore.taskRemindersEnabled,
                  task.status != .done,
                  let dueDate = task.dueDate,
                  let reminderDate = NotificationSchedulePlanner.taskReminderDate(
                      for: dueDate,
                      defaultReminderTime: settingsStore.reminderTime
                  )
            else { return }

            await removeTaskReminder(for: task)

            guard reminderDate > Date() else { return }

            let content = UNMutableNotificationContent()
            content.title = "Task Reminder"
            content.body = task.title
            content.sound = settingsStore.soundEnabled ? .default : nil
            content.categoryIdentifier = "TASK_REMINDER"

            let dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminderDate
            )

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

        /// Remove all task reminders (pending and already delivered).
        func removeAllTaskReminders() {
            _ = _Concurrency.Task {
                let taskRequestIDs = await pendingTaskReminderRequestIDs()
                center.removePendingNotificationRequests(withIdentifiers: taskRequestIDs)
                center.removeDeliveredNotifications(withIdentifiers: taskRequestIDs)
            }
        }

        private func taskNotificationId(_ task: Task) -> String {
            "task-\(task.id.uuidString)"
        }

        // MARK: - Daily Digest

        func scheduleDailyDigest(at hour: Int = 8, minute: Int = 0) async {
            guard let settingsStore else { return }
            settingsStore.reminderTime = Calendar.current.date(
                from: DateComponents(hour: hour, minute: minute)
            ) ?? settingsStore.reminderTime
        }

        /// Cancel daily digest
        func cancelDailyDigest() {
            center.removePendingNotificationRequests(withIdentifiers: ["daily-digest"])
        }

        /// Remove all delivered notifications from the notification center.
        func removeAllDeliveredNotifications() {
            center.removeAllDeliveredNotifications()
        }

        func refreshScheduledNotifications(
            householdId: UUID?,
            modelContext: ModelContext
        ) async {
            await refreshTaskReminders(householdId: householdId, modelContext: modelContext)
            await refreshDailyDigest(householdId: householdId, modelContext: modelContext)
        }

        func refreshDailyDigest(
            householdId: UUID?,
            modelContext: ModelContext
        ) async {
            cancelDailyDigest()

            guard let settingsStore,
                  isAuthorized,
                  settingsStore.isEnabled,
                  settingsStore.dailyDigestEnabled,
                  let householdId
            else {
                return
            }

            let tasks = cachedTasks(
                householdId: householdId,
                modelContext: modelContext
            )

            guard let plan = NotificationSchedulePlanner.dailyDigestPlan(
                tasks: tasks,
                reminderTime: settingsStore.reminderTime
            ) else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = settingsStore.soundEnabled ? .default : nil
            content.categoryIdentifier = "DAILY_DIGEST"

            let dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: plan.fireDate
            )

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
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

        private func refreshTaskReminders(
            householdId: UUID?,
            modelContext: ModelContext
        ) async {
            let taskRequestIDs = await pendingTaskReminderRequestIDs()
            center.removePendingNotificationRequests(withIdentifiers: taskRequestIDs)

            guard let settingsStore,
                  isAuthorized,
                  settingsStore.isEnabled,
                  settingsStore.taskRemindersEnabled,
                  let householdId
            else {
                return
            }

            let tasks = cachedTasks(
                householdId: householdId,
                modelContext: modelContext
            )

            for task in tasks where task.status != .done && task.dueDate != nil {
                await scheduleTaskReminder(for: task)
            }
        }

        private func cachedTasks(
            householdId: UUID,
            modelContext: ModelContext
        ) -> [Task] {
            let workItemDescriptor = FetchDescriptor<CachedWorkItem>(
                predicate: #Predicate { $0.householdId == householdId }
            )

            if let cachedWorkItems = try? modelContext.fetch(workItemDescriptor),
               !cachedWorkItems.isEmpty
            {
                return cachedWorkItems
                    .filter { $0.syncStatusRaw != SyncStatus.pendingDelete.rawValue }
                    .compactMap { $0.toWorkItem().asTask() }
            }

            let descriptor = FetchDescriptor<CachedTask>(
                predicate: #Predicate { $0.householdId == householdId }
            )

            guard let cachedTasks = try? modelContext.fetch(descriptor) else {
                return []
            }

            return cachedTasks
                .filter { $0.syncStatusRaw != SyncStatus.pendingDelete.rawValue }
                .map { $0.toTask() }
        }

        private func pendingTaskReminderRequestIDs() async -> [String] {
            let pendingRequests = await center.pendingNotificationRequests()
            return pendingRequests
                .map(\.identifier)
                .filter { $0.hasPrefix("task-") }
        }
    }
#else
    @MainActor
    final class NotificationService: ObservableObject {
        static let shared = NotificationService()

        @Published private(set) var isAuthorized = false

        private init() {}

        func setSettingsStore(_: NotificationSettingsStore) {}

        func requestAuthorization() async {
            isAuthorized = false
        }

        func checkAuthorizationStatus() async {
            isAuthorized = false
        }

        func scheduleTaskReminder(for _: Task) async {}

        func removeTaskReminder(for _: Task) async {}

        func removeAllTaskReminders() {}

        func removeAllDeliveredNotifications() {}

        func scheduleDailyDigest(at _: Int = 8, minute _: Int = 0) async {}

        func cancelDailyDigest() {}

        func refreshScheduledNotifications(
            householdId _: UUID?,
            modelContext _: ModelContext
        ) async {}

        func refreshDailyDigest(
            householdId _: UUID?,
            modelContext _: ModelContext
        ) async {}
    }
#endif
