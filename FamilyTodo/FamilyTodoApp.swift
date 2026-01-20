import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared
    @StateObject private var themeStore = ThemeStore()

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
            #if CI
                // In CI, return a minimal container - tests don't need persistence
                return try! ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            #else
                fatalError("Could not create ModelContainer: \(error)")
            #endif
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userSession)
                .environmentObject(themeStore)
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
