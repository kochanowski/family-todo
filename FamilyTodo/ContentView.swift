import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if userSession.isAuthenticated {
                MainTabView()
            } else {
                SignInView()
            }
        }
    }
}

/// Main application view shown after authentication
struct MainTabView: View {
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.modelContext) private var modelContext

    /// For MVP: use a stable household ID derived from user ID
    /// TODO: Replace with proper household management (create/join flow)
    private var householdId: UUID {
        // Create deterministic UUID from user ID for consistent household
        if let userId = userSession.user?.id {
            let namespace = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
            return UUID(uuidString: UUID5.generate(namespace: namespace, name: userId).uuidString) ?? UUID()
        }
        return UUID()
    }

    var body: some View {
        TabView {
            TaskListView(householdId: householdId, modelContext: modelContext)
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

/// Settings view with sign out option
struct SettingsView: View {
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        NavigationStack {
            List {
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

/// UUID5 generation for deterministic UUIDs
enum UUID5 {
    static func generate(namespace: UUID, name: String) -> UUID {
        var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = Array(name.utf8)
        namespaceBytes.append(contentsOf: nameBytes)

        // Simple hash-based UUID (not cryptographic, but deterministic)
        var hash: UInt64 = 5381
        for byte in namespaceBytes {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }

        var uuid = UUID().uuid
        withUnsafeMutableBytes(of: &uuid) { ptr in
            ptr.storeBytes(of: hash.bigEndian, as: UInt64.self)
        }

        return UUID(uuid: uuid)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CachedTask.self, configurations: config)

    return ContentView()
        .environmentObject(UserSession.shared)
        .modelContainer(container)
}
