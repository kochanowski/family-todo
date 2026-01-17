import Foundation

/// Store for recurring chore management
@MainActor
final class RecurringChoreStore: ObservableObject {
    @Published private(set) var chores: [RecurringChore] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let cloudKit = CloudKitManager.shared
    private let householdId: UUID?

    init(householdId: UUID?) {
        self.householdId = householdId
    }

    var activeChores: [RecurringChore] {
        chores.filter(\.isActive)
    }

    // MARK: - Load Chores

    func loadChores() async {
        guard let householdId else { return }

        isLoading = true
        error = nil

        do {
            chores = try await cloudKit.fetchRecurringChores(householdId: householdId)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Create Chore

    func createChore(
        title: String,
        recurrenceType: RecurringChore.RecurrenceType,
        recurrenceDay: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        areaId: UUID? = nil,
        notes: String? = nil
    ) async {
        guard let householdId else { return }

        var chore = RecurringChore(
            householdId: householdId,
            title: title,
            recurrenceType: recurrenceType,
            recurrenceDay: recurrenceDay,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            areaId: areaId,
            notes: notes
        )
        chore.nextScheduledDate = chore.calculateNextScheduledDate()

        // Optimistic update
        chores.append(chore)

        do {
            _ = try await cloudKit.saveRecurringChore(chore)
        } catch {
            chores.removeAll { $0.id == chore.id }
            self.error = error
        }
    }

    // MARK: - Update Chore

    func updateChore(_ chore: RecurringChore) async {
        var updatedChore = chore
        updatedChore.updatedAt = Date()

        // Optimistic update
        if let index = chores.firstIndex(where: { $0.id == chore.id }) {
            chores[index] = updatedChore
        }

        do {
            _ = try await cloudKit.saveRecurringChore(updatedChore)
        } catch {
            self.error = error
            await loadChores()
        }
    }

    // MARK: - Toggle Active

    func toggleActive(_ chore: RecurringChore) async {
        var updatedChore = chore
        updatedChore.isActive.toggle()
        await updateChore(updatedChore)
    }

    // MARK: - Delete Chore

    func deleteChore(_ chore: RecurringChore) async {
        chores.removeAll { $0.id == chore.id }

        do {
            try await cloudKit.deleteRecurringChore(id: chore.id)
        } catch {
            self.error = error
            await loadChores()
        }
    }

    // MARK: - Generate Task from Chore

    func generateTask(from chore: RecurringChore, taskStore: TaskStore) async {
        guard let householdId else { return }

        // Create task from chore
        await taskStore.createTask(
            title: chore.title,
            status: .backlog,
            assigneeId: chore.defaultAssigneeId,
            areaId: chore.areaId,
            dueDate: chore.nextScheduledDate,
            notes: chore.notes
        )

        // Update chore with new dates
        var updatedChore = chore
        updatedChore.lastGeneratedDate = Date()
        updatedChore.nextScheduledDate = updatedChore.calculateNextScheduledDate()
        await updateChore(updatedChore)
    }
}
