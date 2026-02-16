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
    private enum PromotionBanner: Equatable {
        case assigneeRequired
        case wipLimitReached(current: Int, limit: Int)
        case failed(String)

        var text: String {
            switch self {
            case .assigneeRequired:
                "Assign this item before moving it to Tasks/NEXT."
            case let .wipLimitReached(current, limit):
                "WIP limit reached (\(current)/\(limit)). Complete one active task first."
            case let .failed(message):
                message
            }
        }
    }

    @StateObject private var store: BacklogStore
    @StateObject private var memberStore: MemberStore
    @EnvironmentObject private var userSession: UserSession

    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var activeBanner: PromotionBanner?
    @State private var pendingPromotionItem: BacklogItem?
    @State private var selectedAssigneeIdForPromotion: UUID?
    @State private var pendingAssignmentItem: BacklogItem?
    @State private var selectedAssigneeIdForAssignment: UUID?
    @State private var editingItem: BacklogItem?

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
        _memberStore = StateObject(wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        let listBottomInset: CGFloat = 16

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, activeBanner == nil ? 12 : 8)

            if let activeBanner {
                BacklogStatusBanner(text: activeBanner.text)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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
                                assigneeNameFor: { assigneeId in
                                    assigneeName(for: assigneeId)
                                },
                                onAddItem: { title in
                                    HapticManager.lightTap()
                                    _ = _Concurrency.Task { await store.addItem(to: category.id, title: title) }
                                },
                                onDeleteItem: { item in
                                    _ = _Concurrency.Task { await store.deleteItem(item) }
                                },
                                onEditItem: { item in
                                    editingItem = item
                                },
                                onAssignItem: { item in
                                    pendingAssignmentItem = item
                                    selectedAssigneeIdForAssignment = item.assigneeId ?? currentMember?.id
                                },
                                onPromoteItem: { item in
                                    promoteItem(item)
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
                    memberStore.setSyncMode(userSession.syncMode)
                    await store.loadData()
                    await memberStore.loadMembers()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            store.setSyncMode(userSession.syncMode)
            memberStore.setSyncMode(userSession.syncMode)
            await store.loadData()
            await memberStore.loadMembers()
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
        .sheet(isPresented: Binding(
            get: { pendingPromotionItem != nil },
            set: { isPresented in
                if !isPresented {
                    pendingPromotionItem = nil
                    selectedAssigneeIdForPromotion = nil
                }
            }
        )) {
            if let pendingPromotionItem {
                BacklogAssigneePickerSheet(
                    title: "Assign before start",
                    actionTitle: "Promote",
                    members: activeMembers,
                    allowUnassigned: false,
                    selectedAssigneeId: $selectedAssigneeIdForPromotion,
                    onCancel: {
                        self.pendingPromotionItem = nil
                        selectedAssigneeIdForPromotion = nil
                    },
                    onConfirm: {
                        guard let assigneeId = selectedAssigneeIdForPromotion else { return }
                        let item = pendingPromotionItem
                        self.pendingPromotionItem = nil
                        selectedAssigneeIdForPromotion = nil
                        completePromotion(of: item, assigneeId: assigneeId)
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingAssignmentItem != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAssignmentItem = nil
                    selectedAssigneeIdForAssignment = nil
                }
            }
        )) {
            BacklogAssigneePickerSheet(
                title: "Assign owner",
                actionTitle: "Save",
                members: activeMembers,
                allowUnassigned: true,
                selectedAssigneeId: $selectedAssigneeIdForAssignment,
                onCancel: {
                    pendingAssignmentItem = nil
                    selectedAssigneeIdForAssignment = nil
                },
                onConfirm: {
                    guard let item = pendingAssignmentItem else { return }
                    let selectedAssignee = selectedAssigneeIdForAssignment
                    pendingAssignmentItem = nil
                    selectedAssigneeIdForAssignment = nil
                    _ = _Concurrency.Task {
                        await store.updateItem(
                            item,
                            title: item.title,
                            notes: item.notes,
                            assigneeId: selectedAssignee
                        )
                    }
                }
            )
        }
        .sheet(item: $editingItem) { item in
            BacklogItemEditSheet(
                item: item,
                members: activeMembers,
                onSave: { title, notes, assigneeId in
                    _ = _Concurrency.Task {
                        await store.updateItem(
                            item,
                            title: title,
                            notes: notes,
                            assigneeId: assigneeId
                        )
                    }
                },
                onDelete: {
                    _ = _Concurrency.Task {
                        await store.deleteItem(item)
                    }
                }
            )
        }
    }

    private var activeMembers: [Member] {
        memberStore.members
            .filter(\.isActive)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var currentMember: Member? {
        guard let userId = userSession.userId else { return nil }
        return activeMembers.first { $0.userId == userId }
    }

    private func assigneeName(for assigneeId: UUID?) -> String? {
        guard let assigneeId else { return nil }
        return activeMembers.first(where: { $0.id == assigneeId })?.displayName
    }

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

    private func promoteItem(_ item: BacklogItem) {
        guard !activeMembers.isEmpty else {
            showBanner(.assigneeRequired)
            return
        }

        if let assignedId = item.assigneeId {
            completePromotion(of: item, assigneeId: assignedId)
            return
        }

        if activeMembers.count == 1, let assigneeId = activeMembers.first?.id {
            completePromotion(of: item, assigneeId: assigneeId)
            return
        }

        pendingPromotionItem = item
        selectedAssigneeIdForPromotion = currentMember?.id
    }

    private func completePromotion(of item: BacklogItem, assigneeId: UUID) {
        _ = _Concurrency.Task {
            let result = await store.promoteItemToTask(item, assigneeId: assigneeId)
            handlePromotionResult(result)
        }
    }

    private func handlePromotionResult(_ result: BacklogStore.PromotionResult) {
        switch result {
        case .success:
            activeBanner = nil
            HapticManager.success()
        case .assigneeRequired:
            HapticManager.warning()
            showBanner(.assigneeRequired)
        case let .wipLimitReached(current, limit):
            HapticManager.warning()
            showBanner(.wipLimitReached(current: current, limit: limit))
        case let .failed(message):
            HapticManager.warning()
            showBanner(.failed(message))
        }
    }

    private func showBanner(_ banner: PromotionBanner) {
        withAnimation(WowAnimation.spring) {
            activeBanner = banner
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            if activeBanner == banner {
                withAnimation(WowAnimation.easeOut) {
                    activeBanner = nil
                }
            }
        }
    }
}

private struct BacklogStatusBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.orange.opacity(0.12))
        }
    }
}

private struct BacklogAssigneePickerSheet: View {
    let title: String
    let actionTitle: String
    let members: [Member]
    let allowUnassigned: Bool
    @Binding var selectedAssigneeId: UUID?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if allowUnassigned {
                    Button {
                        selectedAssigneeId = nil
                    } label: {
                        HStack {
                            Text("Unassigned")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedAssigneeId == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(members) { member in
                    Button {
                        selectedAssigneeId = member.id
                    } label: {
                        HStack {
                            Text(member.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedAssigneeId == member.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(actionTitle) {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                    .disabled(!allowUnassigned && selectedAssigneeId == nil)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: BacklogCategory
    let items: [BacklogItem]
    let assigneeNameFor: (UUID?) -> String?
    let onAddItem: (String) -> Void
    let onDeleteItem: (BacklogItem) -> Void
    let onEditItem: (BacklogItem) -> Void
    let onAssignItem: (BacklogItem) -> Void
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

            ForEach(items) { item in
                BacklogItemRow(
                    item: item,
                    assigneeName: assigneeNameFor(item.assigneeId),
                    onTap: { onEditItem(item) },
                    onEdit: { onEditItem(item) },
                    onAssign: { onAssignItem(item) },
                    onPromote: { onPromoteItem(item) },
                    onDelete: { onDeleteItem(item) }
                )
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

            if isAddingItem {
                HStack(spacing: 10) {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 20, height: 20)

                    TextField("Add item", text: $newItemText)
                        .font(.system(size: 15))
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
                .padding(.vertical, 10)
            } else {
                Button {
                    isAddingItem = true
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .stroke(Color.orange.opacity(0.55), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.orange)
                            }

                        Text("Add item")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.orange)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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
    let assigneeName: String?
    let onTap: () -> Void
    let onEdit: () -> Void
    let onAssign: () -> Void
    let onPromote: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15))
                    .strikethrough(false)

                if let assigneeName {
                    Text(assigneeName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                }
            }

            Spacer()

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button {
                    onAssign()
                } label: {
                    Label("Assign", systemImage: "person.crop.circle.badge.plus")
                }

                Button {
                    onPromote()
                } label: {
                    Label("Promote", systemImage: "arrow.up.circle")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

private struct BacklogItemEditSheet: View {
    let item: BacklogItem
    let members: [Member]
    let onSave: (String, String?, UUID?) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var assigneeId: UUID?
    @State private var showDeleteConfirmation = false

    init(
        item: BacklogItem,
        members: [Member],
        onSave: @escaping (String, String?, UUID?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.members = members
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes ?? "")
        _assigneeId = State(initialValue: item.assigneeId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Title", text: $title)
                }

                Section("Assignee") {
                    Picker("Who", selection: $assigneeId) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section {
                    Button("Delete Item", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Backlog Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        commit()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Delete this item?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func commit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmedTitle, trimmedNotes.isEmpty ? nil : trimmedNotes, assigneeId)
        dismiss()
    }
}

#Preview {
    BacklogView()
        .environmentObject(UserSession.shared)
}
