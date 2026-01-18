import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([CachedTask.self])
        #if CI
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        #else
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
        #endif
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
                    #if !CI
                        // Check authentication status on app launch
                        await userSession.checkAuthenticationStatus()
                    #endif
                }
        }
    }
}
