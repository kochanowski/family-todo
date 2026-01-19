import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if userSession.isAuthenticated {
                AuthenticatedView()
            } else {
                SignInView()
            }
        }
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
                CardsPagerView(householdStore: householdStore)
            } else {
                OnboardingView(
                    householdStore: householdStore,
                    userId: userSession.user?.id ?? "",
                    displayName: userSession.user?.displayName ?? "User"
                )
            }
        }
        .task {
            if let userId = userSession.user?.id {
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
    @ObservedObject var householdStore: HouseholdStore

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

                Section {
                    Button("Sign Out", role: .destructive) {
                        userSession.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CachedTask.self, configurations: config)

    return ContentView()
        .environmentObject(UserSession.shared)
        .modelContainer(container)
}
