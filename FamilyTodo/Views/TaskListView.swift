import SwiftData
import SwiftUI

/// Main Kanban-style task list view with three columns: Next, Backlog, Done
struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userSession: UserSession
    @StateObject private var store: TaskStore
    @StateObject private var areaStore: AreaStore
    @State private var showingAddTask = false
    @State private var selectedTask: Task?
    @State private var selectedAreaFilter: UUID?

    private let householdId: UUID

    init(householdId: UUID, modelContext: ModelContext) {
        self.householdId = householdId
        _store = StateObject(wrappedValue: TaskStore(modelContext: modelContext))
        _areaStore = StateObject(wrappedValue: AreaStore(householdId: householdId, modelContext: modelContext))
    }

    private func filteredTasks(_ tasks: [Task]) -> [Task] {
        guard let areaId = selectedAreaFilter else { return tasks }
        return tasks.filter { $0.areaId == areaId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Area filter
                    if !areaStore.areas.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(title: "All", isSelected: selectedAreaFilter == nil) {
                                    selectedAreaFilter = nil
                                }
                                ForEach(areaStore.areas) { area in
                                    FilterChip(
                                        title: area.name,
                                        icon: area.icon,
                                        isSelected: selectedAreaFilter == area.id
                                    ) {
                                        selectedAreaFilter = area.id
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Next (Now) - Limited to 3 tasks (WIP)
                    TaskColumnView(
                        title: "Next",
                        subtitle: "\(store.nextTasks.count)/\(TaskStore.wipLimit)",
                        tasks: filteredTasks(store.nextTasks),
                        areas: areaStore.areas,
                        accentColor: .orange,
                        onTap: { selectedTask = $0 },
                        onMove: { task, status in
                            _Concurrency.Task { await store.moveTask(task, to: status) }
                        }
                    )

                    // Backlog
                    TaskColumnView(
                        title: "Backlog",
                        subtitle: "\(store.backlogTasks.count) tasks",
                        tasks: filteredTasks(store.backlogTasks),
                        areas: areaStore.areas,
                        accentColor: .blue,
                        onTap: { selectedTask = $0 },
                        onMove: { task, status in
                            _Concurrency.Task { await store.moveTask(task, to: status) }
                        }
                    )

                    // Done (recent)
                    TaskColumnView(
                        title: "Done",
                        subtitle: "Recently completed",
                        tasks: filteredTasks(Array(store.doneTasks.prefix(10))),
                        areas: areaStore.areas,
                        accentColor: .green,
                        onTap: { selectedTask = $0 },
                        onMove: { task, status in
                            _Concurrency.Task { await store.moveTask(task, to: status) }
                        }
                    )
                }
                .padding(.vertical)
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
                await areaStore.loadAreas()
            }
            .sheet(isPresented: $showingAddTask) {
                TaskDetailView(store: store, householdId: householdId, areas: areaStore.areas)
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(store: store, householdId: householdId, task: task, areas: areaStore.areas)
            }
            .overlay {
                if store.isLoading, store.tasks.isEmpty {
                    ProgressView("Loading tasks...")
                }
            }
            .task {
                store.setSyncMode(userSession.syncMode)
                areaStore.setSyncMode(userSession.syncMode)
                store.setHousehold(householdId)
                await store.loadTasks()
                await areaStore.loadAreas()
            }
            .onChange(of: userSession.syncMode) { _, newMode in
                store.setSyncMode(newMode)
                areaStore.setSyncMode(newMode)
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task Column

struct TaskColumnView: View {
    let title: String
    let subtitle: String
    let tasks: [Task]
    let areas: [Area]
    let accentColor: Color
    let onTap: (Task) -> Void
    let onMove: (Task, Task.TaskStatus) -> Void

    private func areaName(for task: Task) -> String? {
        guard let areaId = task.areaId else { return nil }
        return areas.first { $0.id == areaId }?.name
    }

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
                        TaskRowView(task: task, areaName: areaName(for: task), accentColor: accentColor)
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
    let areaName: String?
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

                HStack(spacing: 8) {
                    if let areaName {
                        Text(areaName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }

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
    .environmentObject(UserSession.shared)
}
