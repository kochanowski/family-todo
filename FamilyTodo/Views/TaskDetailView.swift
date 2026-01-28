import SwiftData
import SwiftUI

/// View for creating and editing tasks
struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore

    let householdId: UUID
    let task: Task?
    let areas: [Area]

    @State private var title: String
    @State private var status: Task.TaskStatus
    @State private var selectedAreaId: UUID?
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var notes: String
    @State private var showingDeleteConfirmation = false

    private var isNewTask: Bool {
        task == nil
    }

    init(store: TaskStore, householdId: UUID, task: Task? = nil, areas: [Area] = []) {
        self.store = store
        self.householdId = householdId
        self.task = task
        self.areas = areas

        _title = State(initialValue: task?.title ?? "")
        _status = State(initialValue: task?.status ?? .backlog)
        _selectedAreaId = State(initialValue: task?.areaId)
        _dueDate = State(initialValue: task?.dueDate)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _notes = State(initialValue: task?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Title
                Section {
                    TextField("What needs to be done?", text: $title)
                        .font(.body)
                }

                // Status
                Section("Status") {
                    Picker("Status", selection: $status) {
                        Label("Backlog", systemImage: "tray")
                            .tag(Task.TaskStatus.backlog)
                        Label("Next", systemImage: "star")
                            .tag(Task.TaskStatus.next)
                        Label("Done", systemImage: "checkmark.circle")
                            .tag(Task.TaskStatus.done)
                    }
                    .pickerStyle(.segmented)

                    if status == .next {
                        let currentNextCount = store.nextTasks.count
                        let isEditing = task?.status == .next
                        let effectiveCount = isEditing ? currentNextCount : currentNextCount + 1

                        if effectiveCount > TaskStore.wipLimit {
                            Label(
                                "WIP limit reached (\(TaskStore.wipLimit) max)",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            .font(.caption)
                        }
                    }
                }

                // Area
                if !areas.isEmpty {
                    Section("Area") {
                        Picker("Area", selection: $selectedAreaId) {
                            Text("None").tag(nil as UUID?)
                            ForEach(areas) { area in
                                Label(area.name, systemImage: area.icon ?? "folder")
                                    .tag(area.id as UUID?)
                            }
                        }
                    }
                }

                // Due Date
                Section {
                    Toggle("Due date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { dueDate ?? Date() },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                // Delete (for existing tasks)
                if !isNewTask {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNewTask ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Delete Task",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteTask()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func saveTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let finalDueDate = hasDueDate ? dueDate : nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNotes = trimmedNotes.isEmpty ? nil : trimmedNotes

        if let existingTask = task {
            // Update existing task
            var updatedTask = existingTask
            updatedTask.title = trimmedTitle
            updatedTask.status = status
            updatedTask.areaId = selectedAreaId
            updatedTask.dueDate = finalDueDate
            updatedTask.notes = finalNotes

            if status == .done, existingTask.status != .done {
                updatedTask.completedAt = Date()
            }

            _Concurrency.Task {
                await store.updateTask(updatedTask)
            }
        } else {
            // Create new task
            _Concurrency.Task {
                await store.createTask(
                    title: trimmedTitle,
                    status: status,
                    areaId: selectedAreaId,
                    dueDate: finalDueDate,
                    notes: finalNotes
                )
            }
        }

        dismiss()
    }

    private func deleteTask() {
        guard let task else { return }
        _Concurrency.Task {
            await store.deleteTask(task)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview("New Task") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: CachedTask.self, configurations: config)
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    return TaskDetailView(
        store: TaskStore(modelContext: container.mainContext),
        householdId: UUID()
    )
}

#Preview("Edit Task") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: CachedTask.self, configurations: config)
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    let task = Task(
        householdId: UUID(),
        title: "Clean the kitchen",
        status: .next,
        dueDate: Date().addingTimeInterval(86400),
        taskType: .oneOff,
        notes: "Don't forget the oven!"
    )

    return TaskDetailView(
        store: TaskStore(modelContext: container.mainContext),
        householdId: task.householdId,
        task: task
    )
}
