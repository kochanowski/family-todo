import Foundation
import SwiftData
import SwiftUI

/// More screen - hub for settings, profile, and configuration
struct MoreView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTabBarHeight) private var tabBarHeight

    var body: some View {
        GeometryReader { _ in
            let listBottomInset = AppChromeMetrics.contentBottomInset(
                tabBarHeight: tabBarHeight
            )

            NavigationStack {
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
                                    MoreRow(icon: "folder", title: "Backlog Categories")
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
                        .padding(.bottom, listBottomInset)
                    }

                    Spacer()
                }
                .background(Color.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        HStack(spacing: 16) {
            // Avatar stack
            ZStack {
                Circle()
                    .fill(.blue)
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
        colorScheme == .dark ? Color(hex: "1C1C1E") : .white
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
        .appTabBarVisibility(false)
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
        .navigationTitle("Backlog Categories")
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
        .appTabBarVisibility(false)
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
    @EnvironmentObject private var userSession: UserSession

    @State private var newTitle = ""
    @State private var recurrenceType: RecurringChore.RecurrenceType = .weekly
    @State private var recurrenceDay = 2
    @State private var recurrenceDayOfMonth = 1
    @State private var recurrenceInterval = 1

    init(householdId: UUID, modelContext: ModelContext) {
        _store = StateObject(
            wrappedValue: RecurringChoreStore(householdId: householdId, modelContext: modelContext)
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

                Button {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    _ = _Concurrency.Task {
                        await store.addChore(
                            title: title,
                            recurrenceType: recurrenceType,
                            recurrenceInterval: recurrenceType == .custom ? recurrenceInterval : 1,
                            recurrenceDay: recurrenceType == .weekly ? recurrenceDay : nil,
                            recurrenceDayOfMonth: recurrenceType == .monthly ? recurrenceDayOfMonth : nil
                        )
                    }
                    newTitle = ""
                    recurrenceInterval = 1
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
            await store.loadChores()
        }
        .appTabBarVisibility(false)
    }

    private var weekdayOptions: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.weekdaySymbols
    }
}

struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @Environment(\.appTabBarHeight) private var tabBarHeight
    @StateObject private var notificationSettings = NotificationSettingsStore()

    var body: some View {
        List {
            // MARK: - Appearance Section

            Section {
                AppearanceSelector(selectedMode: Binding(
                    get: { themeStore.appearanceMode },
                    set: {
                        HapticManager.selection()
                        themeStore.appearanceMode = $0
                    }
                ))
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            } header: {
                Text("Appearance")
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

                Toggle(isOn: Binding(
                    get: { themeStore.suggestionsEnabled },
                    set: { themeStore.suggestionsEnabled = $0 }
                )) {
                    Label("Shopping suggestions", systemImage: "lightbulb.fill")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("settingsToggle_suggestions")
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
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: AppChromeMetrics.contentBottomInset(tabBarHeight: tabBarHeight))
        }
        .appTabBarVisibility(false)
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
                    .fill(isSelected ? Color.blue : secondaryBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("appearanceCard_\(mode.displayName)")
    }

    private var secondaryBackground: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.93)
    }
}

#Preview {
    MoreView()
        .environmentObject(ThemeStore())
}
