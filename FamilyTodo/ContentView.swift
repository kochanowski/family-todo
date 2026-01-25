import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if userSession.hasActiveSession {
                AuthenticatedView()
            } else {
                SignInView()
            }
        }
        .ignoresSafeArea(.all, edges: .all)
    }
}

/// View shown after authentication - handles household loading
struct AuthenticatedView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @StateObject private var householdStore = HouseholdStore()

    var body: some View {
        Group {
            if householdStore.isLoading {
                ProgressView("Loading...")
            } else if householdStore.hasHousehold {
                if let householdId = householdStore.currentHousehold?.id {
                    CardsPagerView(
                        householdStore: householdStore, householdId: householdId,
                        modelContext: modelContext
                    )
                }
            } else {
                OnboardingView(
                    householdStore: householdStore,
                    userId: userSession.userId ?? "",
                    displayName: userSession.displayName ?? "User",
                    isCloudSyncEnabled: userSession.syncMode == .cloud
                )
            }
        }
        .task(id: userSession.sessionMode) {
            householdStore.setModelContext(modelContext)
            householdStore.setSyncMode(userSession.syncMode)

            if let userId = userSession.userId {
                await householdStore.loadHousehold(userId: userId)
            }
        }
    }
}

/// Main application view with tasks, areas, recurring chores, and settings
struct MainTabView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var householdStore: HouseholdStore

    var body: some View {
        TabView {
            if let householdId = householdStore.currentHousehold?.id {
                TaskListView(householdId: householdId, modelContext: modelContext)
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }

                RecurringChoresView(householdStore: householdStore)
                    .tabItem {
                        Label("Recurring", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }

                AreasView(householdStore: householdStore)
                    .tabItem {
                        Label("Areas", systemImage: "square.grid.2x2")
                    }
            }

            SettingsView(householdStore: householdStore)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

/// Settings view with household info and sign out
struct SettingsView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var notificationSettingsStore: NotificationSettingsStore
    @EnvironmentObject private var shoppingListSettingsStore: ShoppingListSettingsStore
    @ObservedObject var householdStore: HouseholdStore

    private func requestNotificationPermission() async {
        await NotificationService.shared.requestAuthorization()
    }

    var body: some View {
        NavigationStack {
            List {
                // Household section
                if let household = householdStore.currentHousehold {
                    Section("Household") {
                        LabeledContent("Name", value: household.name)

                        if let inviteCode = householdStore.inviteCode {
                            HStack {
                                Text("Invite Code")
                                Spacer()
                                Text(inviteCode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Button {
                                    UIPasteboard.general.string = inviteCode
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                // Account section
                if let user = userSession.user {
                    Section("Account") {
                        if let displayName = user.displayName {
                            LabeledContent("Name", value: displayName)
                        }
                        if let email = user.email {
                            LabeledContent("Email", value: email)
                        }
                    }
                }

                Section("Appearance") {
                    Picker(
                        "Theme",
                        selection: Binding(
                            get: { themeStore.preset },
                            set: { themeStore.preset = $0 }
                        )
                    ) {
                        ForEach(ThemePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notifications") {
                    Toggle("Task Reminders", isOn: $notificationSettingsStore.taskRemindersEnabled)
                        .onChange(of: notificationSettingsStore.taskRemindersEnabled) {
                            _, enabled in
                            if enabled {
                                _Concurrency.Task {
                                    await requestNotificationPermission()
                                }
                            } else {
                                NotificationService.shared.removeAllTaskReminders()
                            }
                        }

                    Toggle("Daily Digest", isOn: $notificationSettingsStore.dailyDigestEnabled)
                        .onChange(of: notificationSettingsStore.dailyDigestEnabled) { _, enabled in
                            if enabled {
                                _Concurrency.Task {
                                    await requestNotificationPermission()
                                    if NotificationService.shared.isAuthorized {
                                        await NotificationService.shared.scheduleDailyDigest(
                                            at: notificationSettingsStore.dailyDigestHour,
                                            minute: notificationSettingsStore.dailyDigestMinute
                                        )
                                    }
                                }
                            } else {
                                NotificationService.shared.cancelDailyDigest()
                            }
                        }

                    if notificationSettingsStore.dailyDigestEnabled {
                        DatePicker(
                            "Digest Time",
                            selection: Binding(
                                get: {
                                    Calendar.current.date(
                                        bySettingHour: notificationSettingsStore.dailyDigestHour,
                                        minute: notificationSettingsStore.dailyDigestMinute,
                                        second: 0,
                                        of: Date()
                                    ) ?? Date()
                                },
                                set: { newDate in
                                    let components = Calendar.current.dateComponents(
                                        [.hour, .minute], from: newDate
                                    )
                                    notificationSettingsStore.dailyDigestHour = components.hour ?? 8
                                    notificationSettingsStore.dailyDigestMinute =
                                        components.minute ?? 0

                                    // Reschedule with new time
                                    _Concurrency.Task {
                                        await NotificationService.shared.scheduleDailyDigest(
                                            at: notificationSettingsStore.dailyDigestHour,
                                            minute: notificationSettingsStore.dailyDigestMinute
                                        )
                                    }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Toggle("Celebrations", isOn: $notificationSettingsStore.celebrationsEnabled)

                    Toggle("Sound", isOn: $notificationSettingsStore.soundEnabled)
                }

                Section("Shopping List") {
                    Stepper(
                        "Suggestions: \(shoppingListSettingsStore.suggestionLimit)",
                        value: $shoppingListSettingsStore.suggestionLimit,
                        in: ShoppingListSettingsStore.suggestionLimitRange
                    )
                }

                // Permission status info
                if !NotificationService.shared.isAuthorized {
                    Section {
                        HStack {
                            Image(systemName: "bell.slash")
                                .foregroundStyle(.orange)
                            Text("Notifications are disabled. Enable in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                Section {
                    if userSession.isGuest {
                        Button("Sign In with Apple") {
                            userSession.signIn()
                        }

                        Button("Exit Guest Mode", role: .destructive) {
                            userSession.endGuestSession()
                        }
                    } else {
                        Button("Sign Out", role: .destructive) {
                            userSession.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: CachedTask.self, configurations: config)
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    return ContentView()
        .environmentObject(UserSession.shared)
        .environmentObject(ThemeStore())
        .environmentObject(NotificationSettingsStore())
        .environmentObject(ShoppingListSettingsStore())
        .modelContainer(container)
}
