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
            clearUserDefaults()
        }
        
        // Check for specific scenario
        if let scenarioIndex = args.firstIndex(of: "-seedScenario"),
           scenarioIndex + 1 < args.count {
            let scenario = args[scenarioIndex + 1]
            applyScenario(scenario, context: modelContext)
        }
        
        // Legacy/Granular Seeding Flags
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
    
    private static func applyScenario(_ scenario: String, context: ModelContext) {
        switch scenario {
        case "guest_no_household":
            // Data cleared by -resetData, ensure no household created
            break
            
        case "household_basic":
            let household = seedHousehold(context: context)
            seedShoppingList(context: context, household: household)
            seedTasks(context: context, household: household)
            seedBacklog(context: context, household: household)
            
        case "heavy_data":
            let household = seedHousehold(context: context)
            seedHeavyData(context: context, household: household)
            
        default:
            print("Unknown seeding scenario: \(scenario)")
        }
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
    
    private static func clearUserDefaults() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }
    
    @discardableResult
    private static func seedHousehold(context: ModelContext) -> CachedHousehold {
        let household = CachedHousehold(name: "Test House", joinCode: "123456")
        context.insert(household)
        
        // Emulate user selection of this household
        UserDefaults.standard.set(household.id.uuidString, forKey: "currentHouseholdID")
        return household
    }
    
    private static func seedShoppingList(context: ModelContext, household: CachedHousehold? = nil) {
        let items = [
            CachedShoppingItem(name: "Milk", isBought: false),
            CachedShoppingItem(name: "Bread", isBought: false),
            CachedShoppingItem(name: "Eggs", isBought: true)
        ]
        items.forEach { 
            /* if items have household relation, set it here. Assuming they don't for now based on cached models or if they do, we'd need to update logic. */
            context.insert($0) 
        }
    }
    
    private static func seedTasks(context: ModelContext, household: CachedHousehold? = nil) {
        let tasks = [
            CachedTask(title: "Pay bills", isCompleted: false),
            CachedTask(title: "Call mom", isCompleted: false),
            CachedTask(title: "Walk dog", isCompleted: true)
        ]
        tasks.forEach { context.insert($0) }
    }
    
    private static func seedBacklog(context: ModelContext, household: CachedHousehold? = nil) {
        let category = CachedBacklogCategory(name: "Groceries")
        context.insert(category)
        
        let items = [
            CachedBacklogItem(name: "Olive Oil", category: category),
            CachedBacklogItem(name: "Spices", category: category)
        ]
        items.forEach { context.insert($0) }
    }
    
    private static func seedHeavyData(context: ModelContext, household: CachedHousehold) {
        // Shopping List - 50 items
        for i in 1...50 {
            context.insert(CachedShoppingItem(name: "Item \(i)", isBought: i % 5 == 0))
        }
        
        // Tasks - 50 items
        for i in 1...50 {
            context.insert(CachedTask(title: "Task \(i)", isCompleted: i % 3 == 0))
        }
    }
}
