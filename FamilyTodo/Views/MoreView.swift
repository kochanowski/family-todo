import Foundation
import SwiftData
import SwiftUI
import UIKit

/// More screen - hub for settings, profile, and configuration
struct MoreView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, AppChromeMetrics.screenHorizontalInset)
                .padding(.top, AppChromeMetrics.screenHeaderTopPadding)
                .padding(.bottom, AppChromeMetrics.screenHeaderBottomPadding)

            // Menu items
            ScrollView {
                VStack(spacing: 16) {
                    // Household hero card
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HouseholdHeroCard()
                    }
                    .buttonStyle(.plain)

                    if userSession.isGuest {
                        GuestUpgradeBanner {
                            userSession.endGuestSession()
                            onboardingState.openAuth()
                        }
                    }

                    // Settings group
                    VStack(spacing: 0) {
                        NavigationLink {
                            if let householdId = userSession.currentHouseholdID {
                                CategoriesManagementView(householdId: householdId, modelContext: modelContext)
                            } else {
                                GuidedEmptyStateView()
                            }
                        } label: {
                            MoreRow(icon: "folder", title: "Idea Categories")
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 52)

                        NavigationLink {
                            if let householdId = userSession.currentHouseholdID {
                                RepetitiveTasksView(householdId: householdId, modelContext: modelContext)
                            } else {
                                GuidedEmptyStateView()
                            }
                        } label: {
                            MoreRow(icon: "repeat", title: "Repetitive Tasks")
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 52)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            MoreRow(icon: "gear", title: "Settings")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Settings")
                    }
                    .tint(.primary)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(cardBackground)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("More")
                .font(themeStore.font(for: .screenHeader))
                .foregroundStyle(themeStore.contentPrimaryColor)

            Spacer()
        }
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }
}

// MARK: - Household Hero

struct HouseholdHeroCard: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @Query(sort: \CachedMember.joinedAt) private var cachedMembers: [CachedMember]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: householdStore.currentHousehold?.iconSymbol ?? "house.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(householdColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(householdStore.currentHousehold?.name ?? "Domownicy")
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)
                    .lineLimit(1)

                Text(membersLine)
                    .font(themeStore.font(for: .bodySmall))
                    .foregroundStyle(themeStore.contentSecondaryColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
        .contentShape(Rectangle())
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }

    private var householdColor: Color {
        themeStore.accentTabColor
    }

    private var membersLine: String {
        guard let householdId = householdStore.currentHousehold?.id else {
            return userSession.displayName ?? "Tap to configure household"
        }

        let names = cachedMembers
            .filter { $0.householdId == householdId && $0.isActive }
            .map(\.displayName)
            .sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }

        guard !names.isEmpty else {
            return userSession.displayName ?? "No members yet"
        }

        let previewNames = names.prefix(3)
        let preview = previewNames.joined(separator: ", ")
        let remaining = names.count - previewNames.count
        return remaining > 0 ? "\(preview) +\(remaining)" : preview
    }
}

struct GuestUpgradeBanner: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unlock syncing & sharing")
                .font(themeStore.font(for: .inlineTitle))
                .foregroundStyle(themeStore.contentPrimaryColor)

            Text("Sign in with Apple to join households, invite members, and keep devices in sync.")
                .font(themeStore.font(for: .bodySmall))
                .foregroundStyle(themeStore.contentSecondaryColor)

            Button("Sign in with Apple", action: onUpgrade)
                .font(themeStore.font(for: .buttonLabel))
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeStore.surfaceColor)
        )
    }
}

// MARK: - More Row Component

/// Standardized row for More menu items to ensure consistent icon sizing and styling.
struct MoreRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(themeStore.font(for: .inlineTitle))
                    .foregroundStyle(themeStore.contentPrimaryColor)

                if let subtitle {
                    Text(subtitle)
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(themeStore.contentSecondaryColor)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Sub-screens

struct CategoriesManagementView: View {
    @StateObject private var store: BacklogStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var selectedCategory: BacklogCategory?
    @State private var isAddingCategory = false
    @State private var newCategoryColorHex = MemberColorToken.randomHex()

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        List {
            ForEach(store.categories) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 10, height: 10)
                        Text(category.title)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        _ = _Concurrency.Task {
                            await store.deleteCategory(category)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                var reordered = store.categories
                reordered.move(fromOffsets: source, toOffset: destination)
                let orderedIds = reordered.map(\.id)
                _ = _Concurrency.Task {
                    await store.reorderCategories(orderedIds: orderedIds)
                }
            }

            Section {
                Button {
                    newCategoryColorHex = MemberColorToken.randomHex()
                    isAddingCategory = true
                } label: {
                    Label("New category", systemImage: "plus.circle")
                }
            }
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .navigationTitle("Idea Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .task {
            store.setSyncMode(userSession.syncMode)
            await store.loadData()
        }
        .sheet(item: $selectedCategory) { category in
            CategoryEditorSheet(
                title: "Edit Category",
                initialName: category.title,
                initialColorHex: category.colorHex,
                primaryTitle: "Save",
                onCancel: {},
                onSubmit: { name, colorHex in
                    _ = _Concurrency.Task {
                        await store.updateCategory(
                            category,
                            newTitle: name,
                            newColorHex: colorHex
                        )
                    }
                }
            )
        }
        .sheet(isPresented: $isAddingCategory) {
            CategoryEditorSheet(
                title: "New Category",
                initialName: "",
                initialColorHex: newCategoryColorHex,
                primaryTitle: "Create",
                onCancel: {
                    newCategoryColorHex = MemberColorToken.randomHex()
                },
                onSubmit: { name, colorHex in
                    newCategoryColorHex = MemberColorToken.randomHex()
                    _ = _Concurrency.Task {
                        await store.addCategory(name, colorHex: colorHex)
                    }
                }
            )
        }
    }
}

struct RepetitiveTasksView: View {
    @StateObject private var store: RecurringChoreStore
    @StateObject private var backlogStore: BacklogStore
    @StateObject private var memberStore: MemberStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var editingChoreId: UUID?
    @State private var newTitle = ""
    @State private var recurrenceType: RecurringChore.RecurrenceType = .weekly
    @State private var recurrenceDay = 2
    @State private var recurrenceDayOfMonth = 1
    @State private var recurrenceInterval = 1
    @State private var selectedCategoryId: UUID?
    @State private var selectedAssigneeIds = Set<UUID>()
    @State private var rotationEnabled = false

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(
            wrappedValue: RecurringChoreStore(householdId: householdId, modelContext: modelContext)
        )
        _backlogStore = StateObject(
            wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext)
        )
        _memberStore = StateObject(
            wrappedValue: MemberStore(householdId: householdId, modelContext: modelContext)
        )
    }

    var body: some View {
        List {
            Section("Active recurring tasks") {
                if store.chores.isEmpty {
                    Text("No repetitive tasks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.chores) { chore in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(chore.title)
                                    .font(themeStore.font(for: .inlineTitle))

                                if chore.rotationEnabled, chore.normalizedAssigneeIDs.count > 1 {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(themeStore.font(for: .chip))
                                        .foregroundStyle(themeStore.accentTabColor)
                                }

                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { chore.isActive },
                                    set: { newValue in
                                        var updated = chore
                                        updated.isActive = newValue
                                        _ = _Concurrency.Task {
                                            await store.updateChore(updated)
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }

                            Text(chore.recurrenceType.rawValue.capitalized)
                                .font(themeStore.font(for: .chip))
                                .foregroundStyle(.secondary)

                            let assigneeNames = assigneeNames(for: chore)
                            if !assigneeNames.isEmpty {
                                Text(assigneeNames.joined(separator: " • "))
                                    .font(themeStore.font(for: .chip))
                                    .foregroundStyle(.secondary)
                            }

                            if let categoryId = chore.categoryId,
                               let category = backlogStore.categories.first(where: { $0.id == categoryId })
                            {
                                Text(category.title)
                                    .font(themeStore.font(for: .chip))
                                    .foregroundStyle(category.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(category.color.opacity(0.12)))
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                startEditing(chore)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                _ = _Concurrency.Task {
                                    await store.deleteChore(chore)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section(editingChoreId == nil ? "Add repetitive task" : "Edit repetitive task") {
                TextField("Task title", text: $newTitle)
                Picker("Frequency", selection: $recurrenceType) {
                    ForEach(RecurringChore.RecurrenceType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }

                switch recurrenceType {
                case .daily:
                    EmptyView()
                case .weekly:
                    Picker("Day of week", selection: $recurrenceDay) {
                        ForEach(Array(weekdayOptions.enumerated()), id: \.offset) { offset, day in
                            Text(day).tag(offset + 1)
                        }
                    }
                case .monthly:
                    Stepper(value: $recurrenceDayOfMonth, in: 1 ... 28) {
                        Text("Day of month: \(recurrenceDayOfMonth)")
                    }
                case .custom:
                    Stepper(value: $recurrenceInterval, in: 1 ... 365) {
                        Text("Every \(recurrenceInterval) day\(recurrenceInterval == 1 ? "" : "s")")
                    }
                }

                Picker("Category", selection: $selectedCategoryId) {
                    Text("None").tag(UUID?.none)
                    ForEach(backlogStore.categories) { category in
                        Text(category.title).tag(UUID?.some(category.id))
                    }
                }

                Text("Assigned To")
                    .font(themeStore.font(for: .sectionHeader))
                    .foregroundStyle(themeStore.contentSecondaryColor)

                if activeMembers.isEmpty {
                    Text("No members available.")
                        .font(themeStore.font(for: .bodySmall))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMembers) { member in
                        Button {
                            toggleAssignee(member.id)
                        } label: {
                            HStack {
                                Text(member.displayName)
                                    .font(themeStore.font(for: .inlineTitle))
                                Spacer()
                                if selectedAssigneeIds.contains(member.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(themeStore.accentTabColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Toggle("Rotate between assignees", isOn: $rotationEnabled)
                    .disabled(selectedAssigneeIds.count < 2)

                Button {
                    submitComposer()
                } label: {
                    Label(
                        editingChoreId == nil ? "Add repetitive task" : "Save changes",
                        systemImage: editingChoreId == nil ? "plus.circle.fill" : "checkmark.circle.fill"
                    )
                }
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if editingChoreId != nil {
                    Button("Cancel Editing", role: .cancel) {
                        resetComposer()
                    }
                }
            }
        }
        .onChange(of: selectedAssigneeIds) { _, newValue in
            if newValue.count < 2 {
                rotationEnabled = false
            }
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .navigationTitle("Repetitive Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.setSyncMode(userSession.syncMode)
            backlogStore.setSyncMode(userSession.syncMode)
            memberStore.setSyncMode(userSession.syncMode)
            await store.loadChores()
            await backlogStore.loadData()
            await memberStore.loadMembers()
        }
    }

    private var activeMembers: [Member] {
        memberStore.members
            .filter(\.isActive)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func assigneeNames(for chore: RecurringChore) -> [String] {
        chore.normalizedAssigneeIDs.compactMap { id in
            activeMembers.first(where: { $0.id == id })?.displayName
        }
    }

    private func toggleAssignee(_ memberId: UUID) {
        if selectedAssigneeIds.contains(memberId) {
            selectedAssigneeIds.remove(memberId)
        } else {
            selectedAssigneeIds.insert(memberId)
        }
    }

    private func startEditing(_ chore: RecurringChore) {
        editingChoreId = chore.id
        newTitle = chore.title
        recurrenceType = chore.recurrenceType
        recurrenceDay = chore.recurrenceDay ?? 2
        recurrenceDayOfMonth = chore.recurrenceDayOfMonth ?? 1
        recurrenceInterval = max(chore.recurrenceInterval ?? 1, 1)
        selectedCategoryId = chore.categoryId
        selectedAssigneeIds = Set(chore.normalizedAssigneeIDs)
        rotationEnabled = chore.rotationEnabled && chore.normalizedAssigneeIDs.count > 1
    }

    private func submitComposer() {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let orderedAssigneeIds = activeMembers.compactMap { member in
            selectedAssigneeIds.contains(member.id) ? member.id : nil
        }
        let resolvedRotationEnabled = rotationEnabled && orderedAssigneeIds.count > 1

        _ = _Concurrency.Task {
            if let editingChoreId,
               let existing = store.chores.first(where: { $0.id == editingChoreId })
            {
                var updated = existing
                updated.title = trimmedTitle
                updated.recurrenceType = recurrenceType
                updated.recurrenceDay = recurrenceType == .weekly ? recurrenceDay : nil
                updated.recurrenceDayOfMonth = recurrenceType == .monthly ? recurrenceDayOfMonth : nil
                updated.recurrenceInterval = recurrenceType == .custom ? recurrenceInterval : 1
                updated.defaultAssigneeIds = orderedAssigneeIds
                updated.assigneeIds = orderedAssigneeIds
                updated.rotationEnabled = resolvedRotationEnabled
                updated.nextAssigneeIndex = {
                    guard !orderedAssigneeIds.isEmpty else { return 0 }
                    return min(max(updated.nextAssigneeIndex, 0), orderedAssigneeIds.count - 1)
                }()
                updated.categoryId = selectedCategoryId
                let scheduleAnchor = updated.lastGeneratedDate ?? Date()
                updated.nextScheduledDate = ChoreScheduler.nextScheduledDate(for: updated, from: scheduleAnchor)
                updated.updatedAt = Date()
                await store.updateChore(updated)
            } else {
                await store.addChore(
                    title: trimmedTitle,
                    recurrenceType: recurrenceType,
                    recurrenceInterval: recurrenceType == .custom ? recurrenceInterval : 1,
                    recurrenceDay: recurrenceType == .weekly ? recurrenceDay : nil,
                    recurrenceDayOfMonth: recurrenceType == .monthly ? recurrenceDayOfMonth : nil,
                    defaultAssigneeIds: orderedAssigneeIds,
                    rotationEnabled: resolvedRotationEnabled,
                    categoryId: selectedCategoryId
                )
            }
            await MainActor.run {
                resetComposer()
            }
        }
    }

    private func resetComposer() {
        editingChoreId = nil
        newTitle = ""
        recurrenceType = .weekly
        recurrenceDay = 2
        recurrenceDayOfMonth = 1
        recurrenceInterval = 1
        selectedCategoryId = nil
        selectedAssigneeIds = []
        rotationEnabled = false
    }

    private var weekdayOptions: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.weekdaySymbols
    }
}

struct CompletedTasksView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let householdId = userSession.currentHouseholdID {
                CompletedTasksContent(householdId: householdId, modelContext: modelContext)
            } else {
                ContentUnavailableView {
                    Label("No Household", systemImage: "house")
                } description: {
                    Text("Join or create a household to see task history.")
                }
            }
        }
    }
}

private struct CompletedTasksContent: View {
    private enum CleanupAction: String, Identifiable {
        case clearAll
        case keepLast7Days
        case keepLast30Days

        var id: String {
            rawValue
        }
    }

    @StateObject private var store: TaskStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var pendingCleanup: CleanupAction?

    init(householdId: UUID, modelContext: ModelContext) {
        let taskStore = TaskStore(modelContext: modelContext)
        taskStore.setHousehold(householdId)
        _store = StateObject(wrappedValue: taskStore)
    }

    var body: some View {
        Group {
            if store.archivedDoneTasks.isEmpty {
                ContentUnavailableView {
                    Label("No Task History", systemImage: "checkmark.circle")
                } description: {
                    Text("Completed tasks older than 24h appear here.")
                }
            } else {
                List {
                    ForEach(store.archivedDoneTasks) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(themeStore.font(for: .listRowTitle))
                                .strikethrough(true)
                                .foregroundStyle(.secondary)

                            if let notes = task.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(themeStore.font(for: .bodySmall))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }

                            if let completedAt = task.completedAt {
                                Text(completedAt, style: .relative)
                                    .font(themeStore.font(for: .chip))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .environment(\.font, themeStore.font(for: .inlineTitle))
        .navigationTitle("Task History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.archivedDoneTasks.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            pendingCleanup = .clearAll
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }

                        Button {
                            pendingCleanup = .keepLast7Days
                        } label: {
                            Label("Keep Last 7 Days", systemImage: "calendar")
                        }

                        Button {
                            pendingCleanup = .keepLast30Days
                        } label: {
                            Label("Keep Last 30 Days", systemImage: "calendar.badge.clock")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                    }
                }
            }
        }
        .sheet(item: $pendingCleanup) { action in
            AppConfirmationSheet(
                title: "Task History Cleanup",
                message: cleanupMessage(for: action),
                primaryTitle: cleanupPrimaryTitle(for: action),
                primaryStyle: action == .clearAll ? .destructive : .accent,
                onPrimary: {
                    runCleanupAction(action)
                }
            )
        }
        .task {
            store.setSyncMode(userSession.syncMode)
            await store.loadTasks()
        }
    }

    private func runCleanupAction(_ action: CleanupAction) {
        pendingCleanup = nil
        _ = _Concurrency.Task {
            switch action {
            case .clearAll:
                await store.clearArchivedTasks(keepingDays: nil)
            case .keepLast7Days:
                await store.clearArchivedTasks(keepingDays: 7)
            case .keepLast30Days:
                await store.clearArchivedTasks(keepingDays: 30)
            }
        }
    }

    private func cleanupPrimaryTitle(for action: CleanupAction) -> String {
        switch action {
        case .clearAll:
            "Clear All"
        case .keepLast7Days:
            "Keep Last 7 Days"
        case .keepLast30Days:
            "Keep Last 30 Days"
        }
    }

    private func cleanupMessage(for action: CleanupAction) -> String {
        switch action {
        case .clearAll:
            "This permanently removes all items from Task History."
        case .keepLast7Days:
            "This removes history older than 7 days."
        case .keepLast30Days:
            "This removes history older than 30 days."
        }
    }
}

#Preview {
    MoreView()
        .environmentObject(UserSession.shared)
        .environmentObject(HouseholdStore())
        .environmentObject(OnboardingState())
        .environmentObject(ThemeStore())
}
