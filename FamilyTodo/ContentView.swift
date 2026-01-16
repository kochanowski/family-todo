import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        Group {
            if userSession.isAuthenticated {
                // Main app view (placeholder for now)
                MainTabView()
            } else {
                // Authentication required
                SignInView()
            }
        }
    }
}

/// Main application view shown after authentication
/// This is a placeholder - will be replaced with TaskListView, etc.
struct MainTabView: View {
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Welcome to Family To-Do!")
                    .font(.title)
                    .fontWeight(.semibold)

                if let user = userSession.user {
                    VStack(spacing: 8) {
                        Text("Signed in as:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let displayName = user.displayName {
                            Text(displayName)
                                .font(.headline)
                        } else {
                            Text("User ID: \(user.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }

                Text("Main UI will be implemented next")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Sign Out") {
                    userSession.signOut()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("My Tasks")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(UserSession.shared)
}
