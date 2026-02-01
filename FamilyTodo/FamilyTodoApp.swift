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
                    #if !CI
                        await userSession.checkAuthenticationStatus()
                        // Configure subscriptions if user has household
                        if let userId = userSession.userId,
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
