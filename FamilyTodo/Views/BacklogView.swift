import SwiftData
import SwiftUI

/// Backlog screen - long-term storage for ideas and projects, organized by categories
struct BacklogView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                BacklogContent(householdId: householdId, modelContext: modelContext)
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

private struct BacklogContent: View {
    @StateObject private var store: BacklogStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Content
            if store.isLoading, store.categories.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.categories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(store.categories) { category in
                            CategoryCard(
                                category: category,
                                items: store.items(for: category.id),
                                onAddItem: { title in
                                    Task { await store.addItem(to: category.id, title: title) }
                                },
                                onDeleteItem: { item in
                                    Task { await store.deleteItem(item) }
                                },
                                onDeleteCategory: {
                                    Task { await store.deleteCategory(category) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    await store.loadData()
                }
            }

            Spacer()
        }
        .background(backgroundColor.ignoresSafeArea())
        .task {
            await store.loadData()
        }
        .alert("New Category", isPresented: $isAddingCategory) {
            TextField("Category Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) { newCategoryName = "" }
            Button("Create") {
                let name = newCategoryName
                newCategoryName = ""
                Task { await store.addCategory(name) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Backlog")
                .font(.system(size: 28, weight: .bold))

            Spacer()

            Button {
                isAddingCategory = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Categories", systemImage: "archivebox")
        } description: {
            Text("Create a category to start organizing your backlog items.")
        } actions: {
            Button("Create Category") {
                isAddingCategory = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(hex: "F9F9F9")
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: BacklogCategory
    let items: [BacklogItem]
    let onAddItem: (String) -> Void
    let onDeleteItem: (BacklogItem) -> Void
    let onDeleteCategory: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAddingItem = false
    @State private var newItemText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            HStack {
                Text(category.title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button(role: .destructive, action: onDeleteCategory) {
                        Label("Delete Category", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Items
            ForEach(items) { item in
                BacklogItemRow(item: item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDeleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                Divider()
                    .padding(.leading, 16)
            }

            // Add item row
            if isAddingItem {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)

                    TextField("New item", text: $newItemText)
                        .onSubmit {
                            submitItem()
                        }
                        .submitLabel(.done)
                        .autocorrectionDisabled()

                    Button {
                        isAddingItem = false
                        newItemText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Button {
                    isAddingItem = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)

                        Text("Add item")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
    }

    private func submitItem() {
        guard !newItemText.isEmpty else {
            isAddingItem = false
            return
        }
        onAddItem(newItemText)
        newItemText = ""
        isAddingItem = false
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Backlog Item Row

struct BacklogItemRow: View {
    let item: BacklogItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(item.title)
                .font(.system(size: 15))
                .strikethrough(false) // Ready for future completion status

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    BacklogView()
        .environmentObject(UserSession.shared)
}
