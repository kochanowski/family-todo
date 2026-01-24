import Foundation

struct RecurringChore: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    var recurrenceType: RecurrenceType
    var recurrenceDay: Int?
    var recurrenceDayOfMonth: Int?
    var recurrenceInterval: Int?
    var defaultAssigneeIds: [UUID]
    var areaId: UUID?
    var isActive: Bool
    var lastGeneratedDate: Date?
    var nextScheduledDate: Date?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    enum RecurrenceType: String, Codable {
        case daily
        case weekly
        case biweekly
        case monthly
        case everyNDays = "every-n-days"
        case everyNWeeks = "every-n-weeks"
        case everyNMonths = "every-n-months"
    }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        recurrenceType: RecurrenceType,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceInterval: Int? = nil,
        defaultAssigneeIds: [UUID] = [],
        areaId: UUID? = nil,
        isActive: Bool = true,
        lastGeneratedDate: Date? = nil,
        nextScheduledDate: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.householdId = householdId
        self.title = title
        self.recurrenceType = recurrenceType
        self.recurrenceDay = recurrenceDay
        self.recurrenceDayOfMonth = recurrenceDayOfMonth
        self.recurrenceInterval = recurrenceInterval
        self.defaultAssigneeIds = defaultAssigneeIds
        self.areaId = areaId
        self.isActive = isActive
        self.lastGeneratedDate = lastGeneratedDate
        self.nextScheduledDate = nextScheduledDate
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func calculateNextScheduledDate(after date: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch recurrenceType {
        case .daily:
            return nextDailyDate(calendar: calendar, date: date)

        case .weekly:
            return nextWeeklyDate(calendar: calendar, date: date)

        case .biweekly:
            return nextBiweeklyDate(calendar: calendar, fallback: date)

        case .monthly:
            return nextMonthlyDate(calendar: calendar, date: date)

        case .everyNDays:
            return nextEveryNDays(calendar: calendar, fallback: date)

        case .everyNWeeks:
            return nextEveryNWeeks(calendar: calendar, fallback: date)

        case .everyNMonths:
            return nextEveryNMonths(calendar: calendar, fallback: date)
        }
    }

    private func nextDailyDate(calendar: Calendar, date: Date) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    private func nextWeeklyDate(calendar: Calendar, date: Date) -> Date? {
        guard let weekday = recurrenceDay else { return nil }
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = weekday
        guard let thisWeek = calendar.date(from: components) else { return nil }
        if thisWeek > date {
            return thisWeek
        }
        return calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek)
    }

    private func nextBiweeklyDate(calendar: Calendar, fallback: Date) -> Date? {
        if let lastGenerated = lastGeneratedDate {
            return calendar.date(byAdding: .weekOfYear, value: 2, to: lastGenerated)
        }
        return fallback
    }

    private func nextMonthlyDate(calendar: Calendar, date: Date) -> Date? {
        guard let dayOfMonth = recurrenceDayOfMonth else { return nil }
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = dayOfMonth
        guard let thisMonth = calendar.date(from: components) else { return nil }
        if thisMonth > date {
            return thisMonth
        }
        return calendar.date(byAdding: .month, value: 1, to: thisMonth)
    }

    private func nextEveryNDays(calendar: Calendar, fallback: Date) -> Date? {
        let interval = max(recurrenceInterval ?? 1, 1)
        if let lastGenerated = lastGeneratedDate {
            return calendar.date(byAdding: .day, value: interval, to: lastGenerated)
        }
        return fallback
    }

    private func nextEveryNWeeks(calendar: Calendar, fallback: Date) -> Date? {
        let interval = max(recurrenceInterval ?? 1, 1)
        if let lastGenerated = lastGeneratedDate {
            return calendar.date(byAdding: .weekOfYear, value: interval, to: lastGenerated)
        }
        return fallback
    }

    private func nextEveryNMonths(calendar: Calendar, fallback: Date) -> Date? {
        let interval = max(recurrenceInterval ?? 1, 1)
        if let lastGenerated = lastGeneratedDate {
            return calendar.date(byAdding: .month, value: interval, to: lastGenerated)
        }
        return fallback
    }
}
