import Foundation

struct RecurringChore: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    let recurrenceType: RecurrenceType
    var recurrenceDay: Int?
    var recurrenceDayOfMonth: Int?
    var defaultAssigneeId: UUID?
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
    }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        title: String,
        recurrenceType: RecurrenceType,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        defaultAssigneeId: UUID? = nil,
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
        self.defaultAssigneeId = defaultAssigneeId
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
            guard let last = lastGeneratedDate else { return date }
            return calendar.date(byAdding: .day, value: 14, to: last)

        case .monthly:
            guard let dayOfMonth = recurrenceDayOfMonth else { return nil }
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = dayOfMonth
            guard let thisMonth = calendar.date(from: components) else { return nil }
            if thisMonth > date {
                return thisMonth
            }

            return calendar.date(byAdding: .month, value: 1, to: thisMonth)
        }
    }
}
