import Foundation
import SwiftData
import SwiftUI
import UIKit

/// More screen - hub for settings, profile, and configuration
struct MoreView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Menu items
            ScrollView {
                VStack(spacing: 16) {
                    // Profile card
                    NavigationLink {
                        ProfileView()
                    } label: {
                        ProfileCard()
                    }
                    .buttonStyle(.plain)

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
        HStack {
            Text("More")
                .font(.system(size: 28, weight: .bold))

            Spacer()
        }
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        HStack(spacing: 16) {
            // Avatar stack
            ZStack {
                Circle()
                    .fill(themeStore.accentColor)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(userSession.displayName?.prefix(1) ?? "U"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                // .offset(x: -10) // TODO: Multi-avatar logic
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(userSession.displayName ?? "User")
                    .font(.system(size: 17, weight: .semibold))

                Text(householdStore.currentHousehold?.name ?? "No Household")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        }
    }

    private var cardBackground: Color {
        themeStore.surfaceColor
    }
}

// MARK: - More Row Component

/// Standardized row for More menu items to ensure consistent icon sizing and styling.
struct MoreRow: View {
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
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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

struct ProfileView: View {
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession
    @State private var editedHouseholdName = ""
    @State private var showRenameHousehold = false
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var actionErrorMessage: String?

    var body: some View {
        List {
            Section("Household") {
                if let household = householdStore.currentHousehold {
                    LabeledContent("Name", value: household.name)
                } else {
                    Text("No Household Selected")
                }
            }

            Section("Members") {
                if let household = householdStore.currentHousehold {
                    NavigationLink {
                        MemberManagementView(householdId: household.id)
                    } label: {
                        Text("Manage Members")
                    }
                } else {
                    Text("Select a household first")
                }
            }

            Section("Household Actions") {
                Button("Rename Household") {
                    editedHouseholdName = householdStore.currentHousehold?.name ?? ""
                    showRenameHousehold = true
                }
                .disabled(householdStore.currentHousehold == nil)

                Button("Leave Household", role: .destructive) {
                    showLeaveConfirmation = true
                }
                .disabled(householdStore.currentHousehold == nil || userSession.userId == nil)

                if householdStore.currentHousehold?.ownerId == userSession.userId {
                    Button("Delete Household", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Household", isPresented: $showRenameHousehold) {
            TextField("Household name", text: $editedHouseholdName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                renameHousehold()
            }
        }
        .confirmationDialog("Leave household?", isPresented: $showLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                leaveHousehold()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access until invited again.")
        }
        .confirmationDialog("Delete household permanently?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteHousehold()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action removes members and shared data.")
        }
        .alert("Action failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "Unknown error")
        }
    }

    private func renameHousehold() {
        _ = _Concurrency.Task {
            do {
                try await householdStore.renameCurrentHousehold(editedHouseholdName)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func leaveHousehold() {
        guard let userId = userSession.userId else { return }
        _ = _Concurrency.Task {
            do {
                try await householdStore.leaveCurrentHousehold(userId: userId)
                userSession.clearCurrentHousehold()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteHousehold() {
        guard let userId = userSession.userId else { return }
        _ = _Concurrency.Task {
            do {
                try await householdStore.deleteCurrentHousehold(requestedBy: userId)
                userSession.clearCurrentHousehold()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}

struct MemberRow: View {
    let name: String
    let initials: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

            Text(name)
                .font(.system(size: 16))

            Spacer()
        }
    }
}

struct CategoriesManagementView: View {
    @StateObject private var store: BacklogStore
    @EnvironmentObject private var userSession: UserSession
    @State private var newCategoryName = ""
    @State private var renamingCategory: BacklogCategory?
    @State private var renamingTitle = ""

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext))
    }

    var body: some View {
        List {
            ForEach(store.categories) { category in
                HStack {
                    Text(category.title)
                    Spacer()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        _ = _Concurrency.Task {
                            await store.deleteCategory(category)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        renamingCategory = category
                        renamingTitle = category.title
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
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
                HStack {
                    TextField("New category", text: $newCategoryName)
                        .onSubmit {
                            addCategory()
                        }

                    Button {
                        addCategory()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
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
        .alert("Rename Category", isPresented: Binding(
            get: { renamingCategory != nil },
            set: { if !$0 { renamingCategory = nil } }
        )) {
            TextField("Category name", text: $renamingTitle)
            Button("Cancel", role: .cancel) {
                renamingCategory = nil
            }
            Button("Save") {
                guard let category = renamingCategory else { return }
                _ = _Concurrency.Task {
                    await store.renameCategory(category, newTitle: renamingTitle)
                }
                renamingCategory = nil
            }
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = _Concurrency.Task {
            await store.addCategory(trimmed)
        }
        newCategoryName = ""
    }
}

struct RepetitiveTasksView: View {
    @StateObject private var store: RecurringChoreStore
    @StateObject private var backlogStore: BacklogStore
    @EnvironmentObject private var userSession: UserSession

    @State private var newTitle = ""
    @State private var recurrenceType: RecurringChore.RecurrenceType = .weekly
    @State private var recurrenceDay = 2
    @State private var recurrenceDayOfMonth = 1
    @State private var recurrenceInterval = 1
    @State private var selectedCategoryId: UUID?

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(
            wrappedValue: RecurringChoreStore(householdId: householdId, modelContext: modelContext)
        )
        _backlogStore = StateObject(
            wrappedValue: BacklogStore(householdId: householdId, modelContext: modelContext)
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
                                    .font(.system(size: 16, weight: .medium))
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            if let categoryId = chore.categoryId,
                               let category = backlogStore.categories.first(where: { $0.id == categoryId })
                            {
                                Text(category.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(category.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(category.color.opacity(0.12)))
                            }
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

            Section("Add repetitive task") {
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

                Button {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    _ = _Concurrency.Task {
                        await store.addChore(
                            title: title,
                            recurrenceType: recurrenceType,
                            recurrenceInterval: recurrenceType == .custom ? recurrenceInterval : 1,
                            recurrenceDay: recurrenceType == .weekly ? recurrenceDay : nil,
                            recurrenceDayOfMonth: recurrenceType == .monthly ? recurrenceDayOfMonth : nil,
                            categoryId: selectedCategoryId
                        )
                    }
                    newTitle = ""
                    recurrenceInterval = 1
                    selectedCategoryId = nil
                } label: {
                    Label("Add repetitive task", systemImage: "plus.circle.fill")
                }
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Repetitive Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.setSyncMode(userSession.syncMode)
            backlogStore.setSyncMode(userSession.syncMode)
            await store.loadChores()
            await backlogStore.loadData()
        }
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
                                .font(.system(size: 15))
                                .strikethrough(true)
                                .foregroundStyle(.secondary)

                            if let notes = task.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }

                            if let completedAt = task.completedAt {
                                Text(completedAt, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
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
        .confirmationDialog(
            "Task History Cleanup",
            isPresented: Binding(
                get: { pendingCleanup != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCleanup = nil
                    }
                }
            )
        ) {
            Button("Clear All", role: .destructive) {
                runCleanupAction(.clearAll)
            }
            Button("Keep Last 7 Days") {
                runCleanupAction(.keepLast7Days)
            }
            Button("Keep Last 30 Days") {
                runCleanupAction(.keepLast30Days)
            }
            Button("Cancel", role: .cancel) {
                pendingCleanup = nil
            }
        } message: {
            switch pendingCleanup {
            case .clearAll:
                Text("This permanently removes all items from Task History.")
            case .keepLast7Days:
                Text("This removes history older than 7 days.")
            case .keepLast30Days:
                Text("This removes history older than 30 days.")
            case .none:
                Text("")
            }
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
}

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @StateObject private var notificationSettings = NotificationSettingsStore()
    @AppStorage("recommendedWipLimit") private var recommendedWipLimit = TaskStore.defaultRecommendedWipLimit

    var body: some View {
        List {
            // MARK: - Theme + Appearance Section

            Section {
                ThemePresetSelector(selectedPreset: Binding(
                    get: { themeStore.preset },
                    set: {
                        HapticManager.selection()
                        themeStore.preset = $0
                    }
                ))
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)

                if themeStore.preset == .system {
                    AppearanceSelector(selectedMode: Binding(
                        get: { themeStore.appearanceMode },
                        set: {
                            HapticManager.selection()
                            themeStore.appearanceMode = $0
                        }
                    ))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("Appearance")
            }

            // MARK: - Tab Color Section

            Section {
                HStack(spacing: 16) {
                    ForEach(TabTintColor.allCases) { tint in
                        Button {
                            HapticManager.selection()
                            themeStore.tabTintColor = tint
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(tint.color ?? .accentColor)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                themeStore.tabTintColor == tint ? Color.primary : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                    .overlay(
                                        Image(systemName: tint.iconName)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    )
                                Text(tint.displayName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        themeStore.tabTintColor == tint ? .primary : .secondary
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Tab bar color")
            }

            // MARK: - Toggles Section

            Section {
                Toggle(isOn: Binding(
                    get: { themeStore.celebrationsEnabled },
                    set: { themeStore.celebrationsEnabled = $0 }
                )) {
                    Label("Celebrations", systemImage: "party.popper.fill")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("settingsToggle_celebrations")
            }

            Section("Tasks") {
                HStack {
                    Label("Recommended task limit", systemImage: "target")
                        .foregroundStyle(.primary)

                    Spacer()

                    Stepper(value: $recommendedWipLimit, in: 1 ... 7) {
                        Text("\(recommendedWipLimit)")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(width: 130)
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationSettings.isEnabled)
                    .onChange(of: notificationSettings.isEnabled) { _, enabled in
                        if enabled {
                            _ = _Concurrency.Task {
                                await NotificationService.shared.requestAuthorization()
                            }
                        }
                    }

                Toggle("Task reminders", isOn: $notificationSettings.taskRemindersEnabled)
                    .disabled(!notificationSettings.isEnabled)

                Toggle("Daily digest", isOn: $notificationSettings.dailyDigestEnabled)
                    .disabled(!notificationSettings.isEnabled)

                if notificationSettings.dailyDigestEnabled {
                    DatePicker(
                        "Digest time",
                        selection: Binding(
                            get: { notificationSettings.reminderTime },
                            set: { notificationSettings.reminderTime = $0 }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .disabled(!notificationSettings.isEnabled)
                }

                Toggle("Notification sound", isOn: $notificationSettings.soundEnabled)
                    .disabled(!notificationSettings.isEnabled)
            }

            // MARK: - Sign Out

            Section {
                Button(role: .destructive) {
                    signOut()
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            NotificationService.shared.setSettingsStore(notificationSettings)
            await NotificationService.shared.checkAuthorizationStatus()
            await syncDailyDigest()
        }
        .onChange(of: notificationSettings.dailyDigestEnabled) { _, _ in
            _ = _Concurrency.Task {
                await syncDailyDigest()
            }
        }
        .onChange(of: notificationSettings.reminderTime) { _, _ in
            _ = _Concurrency.Task {
                await syncDailyDigest()
            }
        }
    }

    private func signOut() {
        _Concurrency.Task {
            await subscriptionManager.removeSubscriptions()
            householdStore.clearCurrentHousehold()
            userSession.clearCurrentHousehold()
            userSession.signOut()
        }
    }

    private func syncDailyDigest() async {
        if notificationSettings.isEnabled, notificationSettings.dailyDigestEnabled {
            let components = Calendar.current.dateComponents([.hour, .minute], from: notificationSettings.reminderTime)
            await NotificationService.shared.scheduleDailyDigest(
                at: components.hour ?? 8,
                minute: components.minute ?? 0
            )
        } else {
            NotificationService.shared.cancelDailyDigest()
        }
    }
}

// MARK: - Appearance Card Selector

private struct AppearanceSelector: View {
    @Binding var selectedMode: AppearanceMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppearanceMode.allCases) { mode in
                AppearanceCard(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    colorScheme: colorScheme
                ) {
                    selectedMode = mode
                }
            }
        }
    }
}

private struct AppearanceCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 24, weight: .medium))

                Text(mode.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? themeStore.accentColor : secondaryBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("appearanceCard_\(mode.displayName)")
    }

    private var secondaryBackground: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.93)
    }
}

private struct ThemePresetSelector: View {
    @Binding var selectedPreset: ThemePreset

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ThemePreset.allCases) { preset in
                    ThemePresetCard(
                        preset: preset,
                        isSelected: selectedPreset == preset
                    ) {
                        selectedPreset = preset
                    }
                }
            }
        }
    }
}

private struct ThemePresetCard: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: preset.palette.theme(for: .todo).gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 40)
                    .overlay(
                        Image(systemName: preset.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(preset.palette.theme(for: .todo).accentColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(preset.displayName)
                    .font(labelFont)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var labelFont: Font {
        if let fontName = preset.uiFontName, UIFont(name: fontName, size: 11) != nil {
            return .custom(fontName, size: 11)
        }
        if let fontName = preset.fontName, UIFont(name: fontName, size: 11) != nil {
            return .custom(fontName, size: 11)
        }
        return .system(size: 11, weight: isSelected ? .bold : .regular)
    }
}

#Preview {
    MoreView()
        .environmentObject(ThemeStore())
}
