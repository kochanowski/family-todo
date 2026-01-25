import SwiftUI

struct CompletedItemsView: View {
    @ObservedObject var taskStore: TaskStore
    @Environment(\.dismiss) private var dismiss

    private var completedTasks: [Task] {
        taskStore.tasks.filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? Date.distantPast) > ($1.completedAt ?? Date.distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                if completedTasks.isEmpty {
                    ContentUnavailableView(
                        "No Completed Tasks",
                        systemImage: "checkmark.circle",
                        description: Text("Completed tasks will appear here")
                    )
                } else {
                    ForEach(completedTasks) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)

                                Text(task.title)
                                    .font(.body)

                                Spacer()
                            }

                            if let completedAt = task.completedAt {
                                Text(completedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Completed Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
    }
}
