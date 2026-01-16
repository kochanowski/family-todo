import SwiftUI

@main
struct FamilyTodoApp: App {
    @StateObject private var userSession = UserSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(userSession)
                .task {
                    // Check authentication status on app launch
                    await userSession.checkAuthenticationStatus()
                }
        }
    }
}
