import SwiftUI

/// View for managing recurring chores
struct RecurringChoresView: View {
    @ObservedObject var householdStore: HouseholdStore
    @StateObject private var choreStore: RecurringChoreStore
    @State private var showingAddChore = false
    @State private var selectedChore: RecurringChore?

    init(householdStore: HouseholdStore) {
        self.householdStore = householdStore
        _choreStore = StateObject(wrappedValue: RecurringChoreStore(householdId: householdStore.currentHousehold?.id))
    }

    var body: some View {
        NavigationStack {
            List {
                if !choreStore.activeChores.isEmpty {
                    Section("Active") {
                        ForEach(choreStore.activeChores) { chore in
                            ChoreRowView(chore: chore)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedChore = chore }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        _Concurrency.Task { await choreStore.deleteChore(chore) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        _Concurrency.Task { await choreStore.toggleActive(chore) }
                                    } label: {
                                        Label("Pause", systemImage: "pause")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                }

                let inactiveChores = choreStore.chores.filter { !$0.isActive }
                if !inactiveChores.isEmpty {
                    Section("Paused") {
                        ForEach(inactiveChores) { chore in
                            ChoreRowView(chore: chore)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedChore = chore }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        _Concurrency.Task { await choreStore.deleteChore(chore) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        _Concurrency.Task { await choreStore.toggleActive(chore) }
                                    } label: {
                                        Label("Resume", systemImage: "play")
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                }

                if choreStore.chores.isEmpty, !choreStore.isLoading {
                    ContentUnavailableView(
                        "No Recurring Chores",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        description: Text("Add chores that repeat on a schedule")
                    )
                }
            }
            .navigationTitle("Recurring")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddChore = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await choreStore.loadChores()
            }
            .sheet(isPresented: $showingAddChore) {
                RecurringChoreDetailView(choreStore: choreStore)
            }
            .sheet(item: $selectedChore) { chore in
                RecurringChoreDetailView(choreStore: choreStore, chore: chore)
            }
            .overlay {
                if choreStore.isLoading, choreStore.chores.isEmpty {
                    ProgressView("Loading...")
                }
            }
            .task {
                await choreStore.loadChores()
            }
        }
    }
}

// MARK: - Chore Row

struct ChoreRowView: View {
    let chore: RecurringChore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recurrenceIcon)
                .font(.title3)
                .foregroundStyle(chore.isActive ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title)
                    .font(.body)
                    .foregroundStyle(chore.isActive ? .primary : .secondary)

                Text(recurrenceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let nextDate = chore.nextScheduledDate, chore.isActive {
                Text(nextDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var recurrenceIcon: String {
        switch chore.recurrenceType {
        case .daily:
            "sun.max"
        case .weekly:
            "calendar.badge.clock"
        case .biweekly:
            "calendar"
        case .monthly:
            "calendar.circle"
        case .everyNDays:
            "clock"
        case .everyNWeeks:
            "calendar.badge.clock"
        case .everyNMonths:
            "calendar.circle"
        }
    }

    private var recurrenceDescription: String {
        switch chore.recurrenceType {
        case .daily:
            return "Every day"
        case .weekly:
            if let day = chore.recurrenceDay {
                let formatter = DateFormatter()
                let weekday = formatter.weekdaySymbols[day - 1]
                return "Every \(weekday)"
            }
            return "Weekly"
        case .biweekly:
            return "Every 2 weeks"
        case .monthly:
            if let day = chore.recurrenceDayOfMonth {
                return "Monthly on day \(day)"
            }
            return "Monthly"
        case .everyNDays:
            let interval = chore.recurrenceInterval ?? 1
            return "Every \(interval) day\(interval == 1 ? "" : "s")"
        case .everyNWeeks:
            let interval = chore.recurrenceInterval ?? 1
            return "Every \(interval) week\(interval == 1 ? "" : "s")"
        case .everyNMonths:
            let interval = chore.recurrenceInterval ?? 1
            return "Every \(interval) month\(interval == 1 ? "" : "s")"
        }
    }
}

// MARK: - Chore Detail View

struct RecurringChoreDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var choreStore: RecurringChoreStore

    let chore: RecurringChore?

    @State private var title: String
    @State private var recurrenceType: RecurringChore.RecurrenceType
    @State private var weekday: Int
    @State private var dayOfMonth: Int
    @State private var recurrenceInterval: Int
    @State private var notes: String

    private var isNewChore: Bool { chore == nil }

    init(choreStore: RecurringChoreStore, chore: RecurringChore? = nil) {
        self.choreStore = choreStore
        self.chore = chore
        _title = State(initialValue: chore?.title ?? "")
        _recurrenceType = State(initialValue: chore?.recurrenceType ?? .weekly)
        _weekday = State(initialValue: chore?.recurrenceDay ?? 2) // Monday
        _dayOfMonth = State(initialValue: chore?.recurrenceDayOfMonth ?? 1)
        _recurrenceInterval = State(initialValue: chore?.recurrenceInterval ?? 2)
        _notes = State(initialValue: chore?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chore name", text: $title)
                }

                Section("Repeat") {
                    Picker("Frequency", selection: $recurrenceType) {
                        Text("Daily").tag(RecurringChore.RecurrenceType.daily)
                        Text("Weekly").tag(RecurringChore.RecurrenceType.weekly)
                        Text("Every 2 weeks").tag(RecurringChore.RecurrenceType.biweekly)
                        Text("Monthly").tag(RecurringChore.RecurrenceType.monthly)
                        Text("Every N days").tag(RecurringChore.RecurrenceType.everyNDays)
                        Text("Every N weeks").tag(RecurringChore.RecurrenceType.everyNWeeks)
                        Text("Every N months").tag(RecurringChore.RecurrenceType.everyNMonths)
                    }

                    if recurrenceType == .weekly || recurrenceType == .biweekly {
                        Picker("Day", selection: $weekday) {
                            ForEach(1 ... 7, id: \.self) { day in
                                Text(weekdayName(day)).tag(day)
                            }
                        }
                    }

                    if recurrenceType == .monthly {
                        Picker("Day of month", selection: $dayOfMonth) {
                            ForEach(1 ... 28, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                    }

                    if recurrenceType == .everyNDays {
                        Stepper("Every \(recurrenceInterval) day\(recurrenceInterval == 1 ? "" : "s")", value: $recurrenceInterval, in: 1 ... 30)
                    }

                    if recurrenceType == .everyNWeeks {
                        Stepper("Every \(recurrenceInterval) week\(recurrenceInterval == 1 ? "" : "s")", value: $recurrenceInterval, in: 1 ... 12)
                    }

                    if recurrenceType == .everyNMonths {
                        Stepper("Every \(recurrenceInterval) month\(recurrenceInterval == 1 ? "" : "s")", value: $recurrenceInterval, in: 1 ... 12)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }
            }
            .navigationTitle(isNewChore ? "New Recurring Chore" : "Edit Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChore() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func weekdayName(_ day: Int) -> String {
        let formatter = DateFormatter()
        return formatter.weekdaySymbols[day - 1]
    }

    private func saveChore() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        let usesInterval = recurrenceType == .everyNDays || recurrenceType == .everyNWeeks || recurrenceType == .everyNMonths
        let intervalValue = usesInterval ? recurrenceInterval : nil
        let recurrenceDayValue = (recurrenceType == .weekly || recurrenceType == .biweekly) ? weekday : nil
        let recurrenceDayOfMonthValue = recurrenceType == .monthly ? dayOfMonth : nil

        _Concurrency.Task {
            if let existingChore = chore {
                var updated = existingChore
                updated.title = trimmedTitle
                updated.recurrenceType = recurrenceType
                updated.recurrenceDay = recurrenceDayValue
                updated.recurrenceDayOfMonth = recurrenceDayOfMonthValue
                updated.recurrenceInterval = intervalValue
                updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
                await choreStore.updateChore(updated)
            } else {
                await choreStore.createChore(
                    title: trimmedTitle,
                    recurrenceType: recurrenceType,
                    recurrenceDay: recurrenceDayValue,
                    recurrenceDayOfMonth: recurrenceDayOfMonthValue,
                    recurrenceInterval: intervalValue,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
            }
            dismiss()
        }
    }
}

#Preview {
    RecurringChoresView(householdStore: HouseholdStore())
}
