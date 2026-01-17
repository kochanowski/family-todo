import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([CachedTask.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userSession)
                .modelContainer(sharedModelContainer)
                .task {
                    // Check authentication status on app launch
                    await userSession.checkAuthenticationStatus()
                }
        }
    }
}
