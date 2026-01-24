import CloudKit
import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared
    @StateObject private var householdStore = HouseholdStore()
    @StateObject private var themeStore = ThemeStore()

    /// Pending share metadata to be processed after authentication
    @State private var pendingShareMetadata: CKShare.Metadata?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CachedTask.self,
            CachedHousehold.self,
            CachedMember.self,
            CachedArea.self,
            CachedRecurringChore.self,
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
                .environmentObject(householdStore)
                .environmentObject(themeStore)
                .modelContainer(sharedModelContainer)
                .task {
                    #if !CI
                        // Check authentication status on app launch
                        await userSession.checkAuthenticationStatus()
                    #endif
                }
                .onChange(of: userSession.isAuthenticated) { _, isAuthenticated in
                    // Process pending share when user becomes authenticated
                    if isAuthenticated, let metadata = pendingShareMetadata {
                        processPendingShare(metadata)
                        pendingShareMetadata = nil
                    }
                }
        }
    }

    // MARK: - Share Acceptance

    /// Process a pending share metadata
    private func processPendingShare(_ metadata: CKShare.Metadata) {
        _Concurrency.Task {
            guard let userId = userSession.userId,
                  let displayName = userSession.displayName
            else {
                return
            }

            do {
                try await householdStore.acceptShareInvitation(
                    metadata: metadata,
                    userId: userId,
                    displayName: displayName
                )
            } catch {
                print("Failed to accept share: \(error)")
            }
        }
    }
}

// MARK: - CloudKit Sharing Support

extension FamilyTodoApp {
    /// Handle CloudKit share acceptance via scene delegate
    /// This is called when user taps a CKShare URL
    func userDidAcceptCloudKitShare(with metadata: CKShare.Metadata) {
        if userSession.isAuthenticated {
            processPendingShare(metadata)
        } else {
            // Store for later processing after authentication
            pendingShareMetadata = metadata
        }
    }
}
