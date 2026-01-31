import CloudKit
import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared
    @StateObject private var themeStore = ThemeStore()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedTask.self,
            CachedMember.self,
            CachedShoppingItem.self,
        ])
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
                // In CI, return a minimal container
                do {
                    return try ModelContainer(
                        for: schema,
                        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                    )
                } catch {
                    fatalError("Could not create CI ModelContainer: \(error)")
                }
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
                .preferredColorScheme(themeStore.colorScheme)
                .task {
                    #if !CI
                        await userSession.checkAuthenticationStatus()
                    #endif
                }
        }
    }
}
