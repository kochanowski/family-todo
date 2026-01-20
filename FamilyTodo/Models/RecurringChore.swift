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
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))

        case .weekly:
            guard let weekday = recurrenceDay else { return nil }
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            components.weekday = weekday
            guard let thisWeek = calendar.date(from: components) else { return nil }
            if thisWeek > date {
                return thisWeek
            }

            return calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek)

        case .biweekly:
            let baseDate = lastGeneratedDate ?? date
            return calendar.date(byAdding: .weekOfYear, value: 2, to: baseDate)

        case .monthly:
            guard let dayOfMonth = recurrenceDayOfMonth else { return nil }
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = dayOfMonth
            guard let thisMonth = calendar.date(from: components) else { return nil }
            if thisMonth > date {
                return thisMonth
            }

            return calendar.date(byAdding: .month, value: 1, to: thisMonth)

        case .everyNDays:
            let interval = max(recurrenceInterval ?? 1, 1)
            let baseDate = lastGeneratedDate ?? date
            return calendar.date(byAdding: .day, value: interval, to: baseDate)

        case .everyNWeeks:
            let interval = max(recurrenceInterval ?? 1, 1)
            let baseDate = lastGeneratedDate ?? date
            return calendar.date(byAdding: .weekOfYear, value: interval, to: baseDate)

        case .everyNMonths:
            let interval = max(recurrenceInterval ?? 1, 1)
            let baseDate = lastGeneratedDate ?? date
            return calendar.date(byAdding: .month, value: interval, to: baseDate)
        }
    }
}
