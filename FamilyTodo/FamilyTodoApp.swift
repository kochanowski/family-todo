import CloudKit
import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var householdStore = HouseholdStore()
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var subscriptionManager = CloudKitSubscriptionManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedTask.self,
            CachedMember.self,
            CachedShoppingItem.self,
            CachedBacklogCategory.self,
            CachedBacklogItem.self,
            CachedHousehold.self,
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
            RootView()
                .environmentObject(userSession)
                .environmentObject(themeStore)
                .environmentObject(householdStore)
                .environmentObject(onboardingState)
                .environmentObject(subscriptionManager)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(themeStore.colorScheme)
                .task {
                    householdStore.setModelContext(sharedModelContainer.mainContext)
                    householdStore.setSyncMode(userSession.syncMode)

                    // Configure for UI Testing if needed
                    UITestHelper.configure(modelContext: sharedModelContainer.mainContext)

                    #if !CI
                        await userSession.checkAuthenticationStatus()
                        // Configure subscriptions only for cloud users with household
                        // Skip for guest users (localOnly mode) to avoid CloudKit access
                        if userSession.syncMode == .cloud,
                           let userId = userSession.userId,
                           let householdId = userSession.currentHouseholdID
                        {
                            subscriptionManager.configure(userId: userId, householdId: householdId)
                        }
                    #endif
                }
        }
    }
}

// MARK: - Root View (State-based Navigation)

struct RootView: View {
    @EnvironmentObject private var onboardingState: OnboardingState

    var body: some View {
        Group {
            switch onboardingState.currentState {
            case .onboarding:
                OnboardingCarouselView()
                    .transition(.opacity)

            case .syncChoice:
                SyncSelectionView()
                    .transition(.opacity)

            case .householdSetup:
                CreateHouseholdView()
                    .transition(.opacity)

            case .mainApp:
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingState.currentState)
    }
}

/// Helper to configure the app state for UI Testing based on launch arguments
@MainActor
struct UITestHelper {
    static func configure(modelContext: ModelContext) {
        let args = ProcessInfo.processInfo.arguments

        // Only run if uiTestMode is enabled
        guard args.contains("-uiTestMode") else { return }

        // Reset Data
        if args.contains("-resetData") {
            clearAllData(context: modelContext)
        }

        // Seeding Scenarios
        if args.contains("-seedShoppingList") {
            seedShoppingList(context: modelContext)
        }

        if args.contains("-seedTasks") {
            seedTasks(context: modelContext)
        }

        if args.contains("-seedBacklog") {
            seedBacklog(context: modelContext)
        }

        // Save changes
        try? modelContext.save()
    }

    private static func clearAllData(context: ModelContext) {
        do {
            try context.delete(model: CachedShoppingItem.self)
            try context.delete(model: CachedTask.self)
            try context.delete(model: CachedBacklogItem.self)
            try context.delete(model: CachedBacklogCategory.self)
            try context.delete(model: CachedMember.self)
            try context.delete(model: CachedHousehold.self)
        } catch {
            print("Failed to clear data: \(error)")
        }
    }

    private static func seedShoppingList(context: ModelContext) {
        let items = [
            CachedShoppingItem(name: "Milk", isBought: false),
            CachedShoppingItem(name: "Bread", isBought: false),
            CachedShoppingItem(name: "Eggs", isBought: true),
        ]
        items.forEach { context.insert($0) }
    }

    private static func seedTasks(context: ModelContext) {
        let tasks = [
            CachedTask(title: "Pay bills", isCompleted: false),
            CachedTask(title: "Call mom", isCompleted: false),
            CachedTask(title: "Walk dog", isCompleted: true),
        ]
        tasks.forEach { context.insert($0) }
    }

    private static func seedBacklog(context: ModelContext) {
        let category = CachedBacklogCategory(name: "Groceries")
        context.insert(category)

        let items = [
            CachedBacklogItem(name: "Olive Oil", category: category),
            CachedBacklogItem(name: "Spices", category: category),
        ]
        items.forEach { context.insert($0) }
    }
}
