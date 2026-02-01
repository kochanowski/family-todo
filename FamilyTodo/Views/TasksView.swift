import SwiftData
import SwiftUI

/// Tasks screen - daily chores and immediate to-dos
struct TasksView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                TasksContent(householdId: householdId, modelContext: modelContext)
            } else {
                ContentUnavailableView(
                    "No Household Selected",
                    systemImage: "house.slash",
                    description: Text("Please select or create a household in the More tab.")
                )
            }
        }
    }
}

private struct TasksContent: View {
    @StateObject private var store: TaskStore
    @State private var newTaskTitle = ""
    @State private var taskBeingCompleted: UUID?
    @State private var showAllCompleteAnimation = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var userSession: UserSession

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: TaskStore(modelContext: modelContext))
        _store.wrappedValue.setHousehold(householdId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Focus rule banner
            focusRuleBanner
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Tasks list
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Active tasks (Next)
                    if !store.nextTasks.isEmpty {
                        ForEach(store.nextTasks) { task in
                            if taskBeingCompleted != task.id {
                                TaskRow(task: task, onToggle: { toggleTask(task) })
                                    .rowInsertAnimation()
                                    .accessibilityIdentifier("taskRow_\(task.title)")
                            }
                        }
                    }

                    // Completed section
                    if !store.doneTasks.isEmpty {
                        completedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120) // Space for input and tab bar
            }
            .refreshable {
                store.setSyncMode(userSession.syncMode)
                await store.loadTasks()
            }

            Spacer()

            // Add task input
            inputRow
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
        }
        .background(backgroundColor.ignoresSafeArea())
        .task {
            store.setSyncMode(userSession.syncMode)
            await store.loadTasks()
        }
        .onChange(of: store.error as? TaskStoreError) { _, error in
            if let error {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                // In a real app we might show a toast here
                print("Task Error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 28, weight: .bold))

            // All complete indicator
            if store.nextTasks.isEmpty, !store.doneTasks.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                    .scaleEffect(showAllCompleteAnimation ? 1.2 : 1.0)
                    .animation(WowAnimation.spring, value: showAllCompleteAnimation)
            }

            Spacer()
        }
    }

    // MARK: - Focus Rule Banner

    private var focusRuleBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 18))
                .foregroundStyle(.blue)

            Text("Focus on max 3 active tasks")
                .font(.system(size: 14))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.blue.opacity(0.1))
        }
    }

    // MARK: - Completed Section

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMPLETED")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 24)
                .padding(.bottom, 8)

            ForEach(store.doneTasks) { task in
                TaskRow(task: task, onToggle: { toggleTask(task) })
                    .rowInsertAnimation()
                    .accessibilityIdentifier("taskRowCompleted_\(task.title)")
            }
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: 22, height: 22)

            TextField("Add task", text: $newTaskTitle)
                .font(.system(size: 15))
                .focused($isInputFocused)
                .accessibilityIdentifier("taskInputField")
                .onSubmit {
                    addTask()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
    }

    // MARK: - Data Actions

    private func addTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)

        // Optimistic check for WIP limit
        if !store.canMoveToNext(assigneeId: nil) { // Assuming unassigned or current user
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }

        _Concurrency.Task {
            await store.createTask(title: title, status: .next)
        }

        newTaskTitle = ""
        HapticManager.lightTap()
    }

    private func toggleTask(_ task: Task) {
        let newStatus: Task.TaskStatus = task.status == .done ? .next : .done

        if newStatus == .next, !store.canMoveToNext(assigneeId: task.assigneeId) {
            HapticManager.warning()
            return
        }

        // Check if this completes all tasks
        let willCompleteAll = newStatus == .done && store.nextTasks.count == 1

        if newStatus == .done {
            // Animate completion
            HapticManager.lightTap()
            withAnimation(WowAnimation.easeOut) {
                taskBeingCompleted = task.id
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _Concurrency.Task {
                    await store.moveTask(task, to: newStatus)
                    taskBeingCompleted = nil

                    if willCompleteAll {
                        // Celebrate!
                        HapticManager.success()
                        showAllCompleteAnimation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAllCompleteAnimation = false
                        }
                    } else {
                        HapticManager.mediumTap()
                    }
                }
            }
        } else {
            // Un-completing: no special animation
            _Concurrency.Task {
                await store.moveTask(task, to: newStatus)
            }
            HapticManager.lightTap()
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: Task
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Square checkbox
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isCompleted ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted)

                    // Metadata row
                    if task.dueDate != nil {
                        HStack(spacing: 8) {
                            if let dueDate = task.dueDate {
                                dueDateLabel(dueDate)
                            }
                            // Assignee support coming later with MemberStore
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var isCompleted: Bool {
        task.status == .done
    }

    @ViewBuilder
    private func dueDateLabel(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        Text(dateFormatter.string(from: date))
            .font(.system(size: 12))
            .foregroundStyle(isToday ? .orange : .secondary)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
}

#Preview {
    TasksView()
        .environmentObject(UserSession.shared)
}
