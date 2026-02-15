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
                GuidedEmptyStateView()
            }
        }
    }
}

private struct BacklogContent: View {
    @StateObject private var store: BacklogStore
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.appTabBarHeight) private var tabBarHeight
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        GeometryReader { _ in
            let listBottomInset = AppChromeMetrics.contentBottomInset(
                tabBarHeight: tabBarHeight
            )

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
                        .padding(.bottom, listBottomInset)
                } else if store.categories.isEmpty {
                    emptyState
                        .padding(.bottom, listBottomInset)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(store.categories) { category in
                                CategoryCard(
                                    category: category,
                                    items: store.items(for: category.id),
                                    onAddItem: { title in
                                        HapticManager.lightTap()
                                        _ = _Concurrency.Task { await store.addItem(to: category.id, title: title) }
                                    },
                                    onDeleteItem: { item in
                                        _ = _Concurrency.Task { await store.deleteItem(item) }
                                    },
                                    onPromoteItem: { item in
                                        _ = _Concurrency.Task { _ = await store.promoteItemToTask(item) }
                                    },
                                    onRenameCategory: { newTitle in
                                        _ = _Concurrency.Task { await store.renameCategory(category, newTitle: newTitle) }
                                    },
                                    onDeleteCategory: {
                                        _ = _Concurrency.Task { await store.deleteCategory(category) }
                                    }
                                )
                                .rowInsertAnimation()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, listBottomInset)
                    }
                    .refreshable {
                        store.setSyncMode(userSession.syncMode)
                        await store.loadData()
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            store.setSyncMode(userSession.syncMode)
            await store.loadData()
        }
        .alert("New Category", isPresented: $isAddingCategory) {
            TextField("Category Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) { newCategoryName = "" }
            Button("Create") {
                let name = newCategoryName
                newCategoryName = ""
                HapticManager.lightTap()
                _ = _Concurrency.Task { await store.addCategory(name) }
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
                    .foregroundStyle(.orange)
            }
            .accessibilityIdentifier("backlogAddCategoryButton")
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
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: BacklogCategory
    let items: [BacklogItem]
    let onAddItem: (String) -> Void
    let onDeleteItem: (BacklogItem) -> Void
    let onPromoteItem: (BacklogItem) -> Void
    let onRenameCategory: (String) -> Void
    let onDeleteCategory: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAddingItem = false
    @State private var newItemText = ""
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameCategoryText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            HStack {
                Text(category.title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        renameCategoryText = category.title
                        showRenameAlert = true
                    } label: {
                        Label("Rename Category", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        if items.isEmpty {
                            onDeleteCategory()
                        } else {
                            HapticManager.warning()
                            showDeleteConfirmation = true
                        }
                    } label: {
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
            .accessibilityIdentifier("backlogCategoryHeader_\(category.title)")

            // Items
            ForEach(items) { item in
                BacklogItemRow(item: item)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            onPromoteItem(item)
                        } label: {
                            Label("Promote", systemImage: "arrow.up.circle")
                        }
                        .tint(.blue)
                    }
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
                            .foregroundStyle(.orange)

                        Text("Add item")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backlogAddItemButton_\(category.title)")
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
        .confirmationDialog(
            "Delete \"\(category.title)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Category and \(items.count) Items", role: .destructive) {
                withAnimation(WowAnimation.easeOut) {
                    onDeleteCategory()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the category and all its items.")
        }
        .alert("Rename Category", isPresented: $showRenameAlert) {
            TextField("Category Name", text: $renameCategoryText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                onRenameCategory(renameCategoryText)
            }
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
