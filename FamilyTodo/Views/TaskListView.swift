import SwiftData
import SwiftUI

/// Main Kanban-style task list view with three columns: Next, Backlog, Done
struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store: TaskStore
    @State private var showingAddTask = false
    @State private var selectedTask: Task?

    private let householdId: UUID

    init(householdId: UUID, modelContext: ModelContext) {
        self.householdId = householdId
        _store = StateObject(wrappedValue: TaskStore(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Next (Now) - Limited to 3 tasks (WIP)
                    TaskColumnView(
                        title: "Next",
                        subtitle: "\(store.nextTasks.count)/\(TaskStore.wipLimit)",
                        tasks: store.nextTasks,
                        accentColor: .orange,
                        onTap: { selectedTask = $0 },
                        onMove: { task, status in
                            Task { await store.moveTask(task, to: status) }
                        }
                    )

                    // Backlog
                    TaskColumnView(
                        title: "Backlog",
                        subtitle: "\(store.backlogTasks.count) tasks",
                        tasks: store.backlogTasks,
                        accentColor: .blue,
                        onTap: { selectedTask = $0 },
                        onMove: { task, status in
                            Task { await store.moveTask(task, to: status) }
                        }
                    )

                    // Done (recent)
                    TaskColumnView(
                        title: "Done",
                        subtitle: "Recently completed",
                        tasks: Array(store.doneTasks.prefix(10)),
                        accentColor: .green,
                        onTap: { selectedTask = $0 },
                        onMove: { task, status in
                            Task { await store.moveTask(task, to: status) }
                        }
                    )
                }
                .padding()
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await store.loadTasks()
            }
            .sheet(isPresented: $showingAddTask) {
                TaskDetailView(store: store, householdId: householdId)
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(store: store, householdId: householdId, task: task)
            }
            .overlay {
                if store.isLoading, store.tasks.isEmpty {
                    ProgressView("Loading tasks...")
                }
            }
            .task {
                store.setHousehold(householdId)
                await store.loadTasks()
            }
        }
    }
}

// MARK: - Task Column

struct TaskColumnView: View {
    let title: String
    let subtitle: String
    let tasks: [Task]
    let accentColor: Color
    let onTap: (Task) -> Void
    let onMove: (Task, Task.TaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(accentColor)

                Spacer()

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Tasks
            if tasks.isEmpty {
                Text("No tasks")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TaskRowView(task: task, accentColor: accentColor)
                            .onTapGesture { onTap(task) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                swipeActions(for: task)
                            }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func swipeActions(for task: Task) -> some View {
        switch task.status {
        case .backlog:
            Button {
                onMove(task, .next)
            } label: {
                Label("Next", systemImage: "arrow.right")
            }
            .tint(.orange)

        case .next:
            Button {
                onMove(task, .done)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.green)

        case .done:
            Button {
                onMove(task, .backlog)
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: Task
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(accentColor.opacity(0.2))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)

                if let dueDate = task.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(dueDate, style: .date)
                            .font(.caption)
                    }
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CachedTask.self, configurations: config)

    return TaskListView(
        householdId: UUID(),
        modelContext: container.mainContext
    )
}
