import Combine
import Foundation
import SwiftData

enum AppNotificationCategory {
    static let taskReminder = "TASK_REMINDER"
    static let dailyDigest = "DAILY_DIGEST"
    static let sharedActivity = "SHARED_ACTIVITY"
    static let sharedShoppingUpdate = "SHARED_SHOPPING_UPDATE"
    static let celebration = "CELEBRATION"

    static let foregroundSuppressedCollaborationCategories: Set<String> = [
        sharedActivity,
        sharedShoppingUpdate,
        celebration,
    ]
}

enum PassiveSharedActivityDomain: String, Equatable, Hashable {
    case shopping
    case tasks
    case ideas
}

struct PassiveSharedActivityAlertDescriptor: Equatable {
    let householdId: UUID
    let householdName: String?
    let domain: PassiveSharedActivityDomain
    let changeCount: Int
    let shoppingTitles: [String]
    let preservesShoppingTitles: Bool

    init(
        householdId: UUID,
        householdName: String?,
        domain: PassiveSharedActivityDomain,
        changeCount: Int,
        shoppingTitles: [String] = [],
        preservesShoppingTitles: Bool = false
    ) {
        self.householdId = householdId
        self.householdName = householdName
        self.domain = domain
        self.changeCount = changeCount
        self.shoppingTitles = shoppingTitles
        self.preservesShoppingTitles = preservesShoppingTitles
    }
}

struct PassiveSharedActivityAlertBatch: Equatable {
    let householdId: UUID
    let householdName: String?
    let domain: PassiveSharedActivityDomain
    let changeCount: Int
    let shoppingTitles: [String]
    let preservesShoppingTitles: Bool
}

struct PassiveSharedActivityAlertAccumulator {
    private struct PendingKey: Hashable {
        let householdId: UUID
        let domain: PassiveSharedActivityDomain
    }

    private struct PendingBatch {
        var householdName: String?
        var changeCount: Int
        var shoppingTitles: Set<String>
        var preservesShoppingTitles: Bool
        var flushAt: Date
    }

    let window: TimeInterval
    private var pendingByKey: [PendingKey: PendingBatch] = [:]

    init(window: TimeInterval = 8) {
        self.window = window
    }

    var nextFlushAt: Date? {
        pendingByKey.values.map(\.flushAt).min()
    }

    mutating func record(
        _ descriptor: PassiveSharedActivityAlertDescriptor,
        at: Date
    ) -> [PassiveSharedActivityAlertBatch] {
        let readyBatches = flushReady(at: at)
        guard descriptor.changeCount > 0 else { return readyBatches }

        let key = PendingKey(
            householdId: descriptor.householdId,
            domain: descriptor.domain
        )
        let filteredTitles = Set(descriptor.shoppingTitles.filter { !$0.isEmpty })

        if var existing = pendingByKey[key], at < existing.flushAt {
            existing.householdName = descriptor.householdName ?? existing.householdName
            existing.changeCount += descriptor.changeCount

            if descriptor.domain == .shopping,
               existing.preservesShoppingTitles,
               descriptor.preservesShoppingTitles
            {
                existing.shoppingTitles.formUnion(filteredTitles)
            } else {
                existing.preservesShoppingTitles = false
                existing.shoppingTitles.removeAll()
            }

            pendingByKey[key] = existing
        } else {
            pendingByKey[key] = PendingBatch(
                householdName: descriptor.householdName,
                changeCount: descriptor.changeCount,
                shoppingTitles: descriptor.domain == .shopping && descriptor.preservesShoppingTitles
                    ? filteredTitles : [],
                preservesShoppingTitles: descriptor.domain == .shopping && descriptor.preservesShoppingTitles,
                flushAt: at.addingTimeInterval(window)
            )
        }

        return readyBatches
    }

    mutating func flushReady(at: Date) -> [PassiveSharedActivityAlertBatch] {
        let readyKeys = pendingByKey.compactMap { key, pending in
            pending.flushAt <= at ? key : nil
        }

        let readyBatches = readyKeys.compactMap { key -> PassiveSharedActivityAlertBatch? in
            guard let pending = pendingByKey.removeValue(forKey: key) else { return nil }
            return PassiveSharedActivityAlertBatch(
                householdId: key.householdId,
                householdName: pending.householdName,
                domain: key.domain,
                changeCount: pending.changeCount,
                shoppingTitles: pending.shoppingTitles.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                },
                preservesShoppingTitles: pending.preservesShoppingTitles
            )
        }

        return readyBatches.sorted { lhs, rhs in
            if lhs.householdId == rhs.householdId {
                return lhs.domain.rawValue < rhs.domain.rawValue
            }
            return lhs.householdId.uuidString < rhs.householdId.uuidString
        }
    }
}

struct SharedShoppingNotificationBatch: Equatable {
    let householdId: UUID
    let householdName: String?
    let itemTitles: [String]

    var count: Int {
        itemTitles.count
    }
}

struct SharedShoppingNotificationAccumulator {
    private struct PendingBatch {
        var householdName: String?
        var itemTitles: Set<String>
        var flushAt: Date
    }

    let window: TimeInterval
    private var pendingByHouseholdId: [UUID: PendingBatch] = [:]

    init(window: TimeInterval = 3) {
        self.window = window
    }

    var nextFlushAt: Date? {
        pendingByHouseholdId.values.map(\.flushAt).min()
    }

    mutating func record(
        householdId: UUID,
        householdName: String?,
        itemTitles: [String],
        at: Date
    ) -> SharedShoppingNotificationBatch? {
        let readyBatch = flushReady(at: at).first
        let deduplicatedTitles = Set(itemTitles.filter { !$0.isEmpty })
        guard !deduplicatedTitles.isEmpty else { return readyBatch }

        if var existing = pendingByHouseholdId[householdId], at < existing.flushAt {
            existing.itemTitles.formUnion(deduplicatedTitles)
            existing.householdName = householdName ?? existing.householdName
            pendingByHouseholdId[householdId] = existing
        } else {
            pendingByHouseholdId[householdId] = PendingBatch(
                householdName: householdName,
                itemTitles: deduplicatedTitles,
                flushAt: at.addingTimeInterval(window)
            )
        }

        return readyBatch
    }

    mutating func flushReady(at: Date) -> [SharedShoppingNotificationBatch] {
        let readyHouseholdIDs = pendingByHouseholdId.compactMap { householdId, pending in
            pending.flushAt <= at ? householdId : nil
        }

        let readyBatches = readyHouseholdIDs.compactMap { householdId -> SharedShoppingNotificationBatch? in
            guard let pending = pendingByHouseholdId.removeValue(forKey: householdId) else {
                return nil
            }
            return SharedShoppingNotificationBatch(
                householdId: householdId,
                householdName: pending.householdName,
                itemTitles: pending.itemTitles.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
            )
        }

        return readyBatches.sorted { lhs, rhs in
            lhs.householdId.uuidString < rhs.householdId.uuidString
        }
    }
}

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
        private var passiveSharedActivityAlertAccumulator = PassiveSharedActivityAlertAccumulator(window: 8)
        private var passiveSharedActivityFlushTask: _Concurrency.Task<Void, Never>?

        private init() {}

        func setSettingsStore(_ store: NotificationSettingsStore) {
            settingsStore = store
            recordNotificationProgress(
                "notification.settings.bound hasStore=true notificationsEnabled=\(store.isEnabled) sharedActivityEnabled=\(store.sharedActivityEnabled) soundEnabled=\(store.soundEnabled)"
            )
        }

        // MARK: - Authorization

        func requestAuthorization() async {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                isAuthorized = granted
                recordNotificationProgress(
                    "notification.authorization.requested result=\(granted ? "granted" : "denied")"
                )
            } catch {
                isAuthorized = false
                recordNotificationProgress(
                    "notification.authorization.requestFailed description=\(sanitizeNotificationValue(error.localizedDescription))"
                )
            }
        }

        func requestCollaborationAuthorizationIfNeeded() async {
            let settings = await center.notificationSettings()
            recordNotificationProgress(
                "notification.authorization.checked status=\(authorizationStatusLabel(settings.authorizationStatus)) source=collaborationRequest"
            )
            switch settings.authorizationStatus {
            case .notDetermined:
                await requestAuthorization()
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .denied:
                isAuthorized = false
            @unknown default:
                isAuthorized = false
            }
        }

        func checkAuthorizationStatus() async {
            let settings = await center.notificationSettings()
            isAuthorized = settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral
            recordNotificationProgress(
                "notification.authorization.checked status=\(authorizationStatusLabel(settings.authorizationStatus)) source=refresh isAuthorized=\(isAuthorized)"
            )
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
            content.categoryIdentifier = AppNotificationCategory.taskReminder

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
            content.categoryIdentifier = AppNotificationCategory.dailyDigest

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

        private func schedulePassiveSharedActivityFlushIfNeeded() {
            passiveSharedActivityFlushTask?.cancel()

            guard let nextFlushAt = passiveSharedActivityAlertAccumulator.nextFlushAt else {
                passiveSharedActivityFlushTask = nil
                recordNotificationProgress(
                    "notification.sharedActivity.flushIdle reason=noPendingBatches"
                )
                return
            }

            let delay = max(0, nextFlushAt.timeIntervalSinceNow)
            recordNotificationProgress(
                "notification.sharedActivity.flushScheduled delayMs=\(Int(delay * 1000))"
            )
            passiveSharedActivityFlushTask = _Concurrency.Task { @MainActor [weak self] in
                guard delay > 0 else {
                    await self?.flushPassiveSharedActivityAlertBatches(at: Date())
                    return
                }

                try? await _Concurrency.Task.sleep(
                    nanoseconds: UInt64(delay * 1_000_000_000)
                )
                guard !_Concurrency.Task.isCancelled else { return }
                await self?.flushPassiveSharedActivityAlertBatches(at: Date())
            }
        }

        private func flushPassiveSharedActivityAlertBatches(at now: Date) async {
            let readyBatches = passiveSharedActivityAlertAccumulator.flushReady(at: now)
            recordNotificationProgress(
                "notification.sharedActivity.flushStarted readyBatchCount=\(readyBatches.count)"
            )
            for batch in readyBatches {
                await deliverPassiveSharedActivityBatch(batch)
            }
            schedulePassiveSharedActivityFlushIfNeeded()
        }

        private func deliverPassiveSharedActivityBatch(
            _ batch: PassiveSharedActivityAlertBatch
        ) async {
            let content = UNMutableNotificationContent()
            let resolvedTitle: String = if let householdName = batch.householdName, !householdName.isEmpty {
                householdName
            } else {
                "HousePulse"
            }
            content.title = resolvedTitle
            content.body = passiveSharedActivityBody(for: batch)
            content.sound = soundEnabled() ? .default : nil
            content.threadIdentifier = "shared-activity-\(batch.householdId.uuidString)-\(batch.domain.rawValue)"
            content.categoryIdentifier = AppNotificationCategory.sharedActivity

            let request = UNNotificationRequest(
                identifier: "shared-activity-\(batch.householdId.uuidString)-\(batch.domain.rawValue)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                recordNotificationProgress(
                    "notification.sharedActivity.delivered householdId=\(batch.householdId.uuidString) domain=\(batch.domain.rawValue) changeCount=\(batch.changeCount) preservesShoppingTitles=\(batch.preservesShoppingTitles) threadIdentifier=\(request.content.threadIdentifier)"
                )
            } catch {
                // Passive collaboration alerts are optional and should not break sync.
                recordNotificationProgress(
                    "notification.sharedActivity.deliveryFailed householdId=\(batch.householdId.uuidString) domain=\(batch.domain.rawValue) description=\(sanitizeNotificationValue(error.localizedDescription))"
                )
                CloudKitDiagnosticsState.shared.record(
                    error: error,
                    operation: "notification.sharedActivity.delivery"
                )
            }
        }

        private func passiveSharedActivityBody(
            for batch: PassiveSharedActivityAlertBatch
        ) -> String {
            switch batch.domain {
            case .shopping:
                if batch.preservesShoppingTitles,
                   batch.changeCount == 1,
                   let title = batch.shoppingTitles.first
                {
                    return "\(title) was added to the shopping list."
                }

                if batch.preservesShoppingTitles {
                    return "\(batch.changeCount) items were added to the shopping list."
                }

                return batch.changeCount == 1
                    ? "1 shopping change."
                    : "\(batch.changeCount) shopping changes."
            case .tasks:
                return batch.changeCount == 1
                    ? "1 task change."
                    : "\(batch.changeCount) task changes."
            case .ideas:
                return batch.changeCount == 1
                    ? "1 idea change."
                    : "\(batch.changeCount) idea changes."
            }
        }

        private func notificationsEnabled() -> Bool {
            (settingsStore?.isEnabled ?? true)
        }

        private func passiveSharedActivityEnabled() -> Bool {
            settingsStore?.sharedActivityEnabled ?? true
        }

        private func soundEnabled() -> Bool {
            settingsStore?.soundEnabled ?? true
        }

        private func deliverImmediateAlert(
            title: String,
            body: String,
            identifier: String,
            threadIdentifier: String,
            categoryIdentifier: String
        ) async -> Bool {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = soundEnabled() ? .default : nil
            content.threadIdentifier = threadIdentifier
            content.categoryIdentifier = categoryIdentifier

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                return true
            } catch {
                // Collaboration alerts are optional.
                CloudKitDiagnosticsState.shared.record(
                    error: error,
                    operation: "notification.immediateAlert.delivery"
                )
                return false
            }
        }

        func deliverSharedShoppingItemsAddedAlert(
            itemTitles: [String],
            householdId: UUID,
            householdName: String?
        ) async {
            await deliverPassiveSharedActivityAlert(
                PassiveSharedActivityAlertDescriptor(
                    householdId: householdId,
                    householdName: householdName,
                    domain: .shopping,
                    changeCount: itemTitles.count,
                    shoppingTitles: itemTitles,
                    preservesShoppingTitles: true
                )
            )
        }

        func deliverPassiveSharedActivityAlert(
            _ descriptor: PassiveSharedActivityAlertDescriptor
        ) async {
            await checkAuthorizationStatus()
            let notificationsEnabled = notificationsEnabled()
            let sharedActivityEnabled = passiveSharedActivityEnabled()
            let applicationState = UIApplication.shared.applicationState
            let isSuppressedInForeground = CloudKitSubscriptionManager.shared
                .shouldSuppressPassiveSharedActivityAlert(applicationState: applicationState)

            recordNotificationProgress(
                "notification.sharedActivity.candidate householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) changeCount=\(descriptor.changeCount) titleCount=\(descriptor.shoppingTitles.count) preservesShoppingTitles=\(descriptor.preservesShoppingTitles) isAuthorized=\(isAuthorized) notificationsEnabled=\(notificationsEnabled) sharedActivityEnabled=\(sharedActivityEnabled) appState=\(applicationStateLabel(applicationState)) foregroundSuppressed=\(isSuppressedInForeground)"
            )

            guard isAuthorized else {
                recordNotificationProgress(
                    "notification.sharedActivity.suppressed householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) reason=unauthorized"
                )
                return
            }
            guard notificationsEnabled else {
                recordNotificationProgress(
                    "notification.sharedActivity.suppressed householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) reason=notificationsDisabled"
                )
                return
            }
            guard sharedActivityEnabled else {
                recordNotificationProgress(
                    "notification.sharedActivity.suppressed householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) reason=sharedActivityDisabled"
                )
                return
            }
            guard !isSuppressedInForeground else {
                recordNotificationProgress(
                    "notification.sharedActivity.suppressed householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) reason=foregroundActive"
                )
                return
            }

            let readyBatches = passiveSharedActivityAlertAccumulator.record(
                descriptor,
                at: Date()
            )
            let nextFlushDelayMilliseconds = passiveSharedActivityAlertAccumulator.nextFlushAt
                .map { max(0, Int($0.timeIntervalSinceNow * 1000)) } ?? -1
            recordNotificationProgress(
                "notification.sharedActivity.queued householdId=\(descriptor.householdId.uuidString) domain=\(descriptor.domain.rawValue) readyBatchCount=\(readyBatches.count) nextFlushDelayMs=\(nextFlushDelayMilliseconds)"
            )
            for readyBatch in readyBatches {
                await deliverPassiveSharedActivityBatch(readyBatch)
            }
            schedulePassiveSharedActivityFlushIfNeeded()
        }

        func deliverHouseholdCelebrationAlert(
            title: String,
            body: String,
            householdId: UUID
        ) async {
            await checkAuthorizationStatus()
            let notificationsEnabled = notificationsEnabled()
            let applicationState = UIApplication.shared.applicationState
            let isSuppressedInForeground = CloudKitSubscriptionManager.shared
                .shouldSuppressHouseholdCelebrationAlert(applicationState: applicationState)

            recordNotificationProgress(
                "notification.celebration.candidate householdId=\(householdId.uuidString) isAuthorized=\(isAuthorized) notificationsEnabled=\(notificationsEnabled) appState=\(applicationStateLabel(applicationState)) foregroundSuppressed=\(isSuppressedInForeground)"
            )

            guard isAuthorized else {
                recordNotificationProgress(
                    "notification.celebration.suppressed householdId=\(householdId.uuidString) reason=unauthorized"
                )
                return
            }
            guard notificationsEnabled else {
                recordNotificationProgress(
                    "notification.celebration.suppressed householdId=\(householdId.uuidString) reason=notificationsDisabled"
                )
                return
            }
            guard !isSuppressedInForeground else {
                recordNotificationProgress(
                    "notification.celebration.suppressed householdId=\(householdId.uuidString) reason=foregroundActive"
                )
                return
            }

            let delivered = await deliverImmediateAlert(
                title: title,
                body: body,
                identifier: "celebration-\(householdId.uuidString)-\(UUID().uuidString)",
                threadIdentifier: "celebration-\(householdId.uuidString)",
                categoryIdentifier: AppNotificationCategory.celebration
            )
            recordNotificationProgress(
                delivered
                    ? "notification.celebration.delivered householdId=\(householdId.uuidString)"
                    : "notification.celebration.deliveryFailed householdId=\(householdId.uuidString)"
            )
        }

        private func recordNotificationProgress(_ operation: String) {
            CloudKitDiagnosticsState.shared.recordProgress(operation: operation)
        }

        private func authorizationStatusLabel(
            _ status: UNAuthorizationStatus
        ) -> String {
            switch status {
            case .notDetermined:
                "notDetermined"
            case .denied:
                "denied"
            case .authorized:
                "authorized"
            case .provisional:
                "provisional"
            case .ephemeral:
                "ephemeral"
            @unknown default:
                "unknown"
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

        private func sanitizeNotificationValue(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\n", with: "_")
                .replacingOccurrences(of: " ", with: "_")
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

        func requestCollaborationAuthorizationIfNeeded() async {
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

        func deliverSharedShoppingItemsAddedAlert(
            itemTitles _: [String],
            householdId _: UUID,
            householdName _: String?
        ) async {}

        func deliverPassiveSharedActivityAlert(
            _: PassiveSharedActivityAlertDescriptor
        ) async {}

        func deliverHouseholdCelebrationAlert(
            title _: String,
            body _: String,
            householdId _: UUID
        ) async {}
    }
#endif
