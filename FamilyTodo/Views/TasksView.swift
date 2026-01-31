import SwiftUI

/// Tasks screen - daily chores and immediate to-dos
struct TasksView: View {
    @State private var tasks: [TaskItem] = []
    @State private var newTaskTitle = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                    // Active tasks
                    if !activeTasks.isEmpty {
                        ForEach(activeTasks) { task in
                            TaskRow(task: task, onToggle: { toggleTask(task) })
                        }
                    }

                    // Completed section
                    if !completedTasks.isEmpty {
                        completedSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120) // Space for input and tab bar
            }

            Spacer()

            // Add task input
            inputRow
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
        }
        .background(backgroundColor.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tasks")
                .font(.system(size: 28, weight: .bold))

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

            ForEach(completedTasks) { task in
                TaskRow(task: task, onToggle: { toggleTask(task) })
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

    // MARK: - Data

    private var activeTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [TaskItem] {
        tasks.filter(\.isCompleted)
    }

    private func addTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Check WIP limit
        if activeTasks.count >= 3 {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            return
        }

        let task = TaskItem(
            id: UUID(),
            title: newTaskTitle.trimmingCharacters(in: .whitespaces),
            isCompleted: false,
            assignee: nil,
            dueDate: nil
        )
        tasks.append(task)
        newTaskTitle = ""

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func toggleTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Task Item (Local Model)

struct TaskItem: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var assignee: String?
    var dueDate: Date?
}

// MARK: - Task Row

struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Square checkbox
                RoundedRectangle(cornerRadius: 4)
                    .stroke(task.isCompleted ? Color.green : Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if task.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15))
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)

                    // Metadata row
                    if task.dueDate != nil || task.assignee != nil {
                        HStack(spacing: 8) {
                            if let dueDate = task.dueDate {
                                dueDateLabel(dueDate)
                            }
                            if let assignee = task.assignee {
                                assigneePill(assignee)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dueDateLabel(_ date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        Text(dateFormatter.string(from: date))
            .font(.system(size: 12))
            .foregroundStyle(isToday ? .orange : .secondary)
    }

    private func assigneePill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
            }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
}

#Preview {
    TasksView()
}
