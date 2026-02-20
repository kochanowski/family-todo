import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var userSession: UserSession

    var body: some View {
        Group {
            if userSession.hasActiveSession {
                MainAppView()
            } else {
                SignInView()
            }
        }
    }
}

/// Main app shell using native TabView.
/// iOS 26+ gets system Liquid Glass tab transitions automatically.
struct MainAppView: View {
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var activeTab: AppTab = .shopping
    @State private var hasBootstrappedHousehold = false

    var body: some View {
        legacyTabView
            .background(AppBackgroundView())
            .onAppear {
                TabBarTypographyManager.apply(themeStore: themeStore)
            }
            .onChange(of: themeStore.unifiedTheme) { _, _ in
                TabBarTypographyManager.apply(themeStore: themeStore)
            }
            .onChange(of: themeStore.tabTintColor) { _, _ in
                TabBarTypographyManager.apply(themeStore: themeStore)
            }
            .onChange(of: themeStore.retroFontScale) { _, _ in
                TabBarTypographyManager.apply(themeStore: themeStore)
            }
            .task {
                await bootstrapHouseholdIfNeeded()
            }
    }

    private var legacyTabView: some View {
        TabView(selection: $activeTab) {
            NavigationStack {
                ShoppingListView()
            }
            .tabItem {
                Label(AppTab.shopping.title, systemImage: AppTab.shopping.icon)
            }
            .tag(AppTab.shopping)

            NavigationStack {
                TasksView(selectedTab: $activeTab)
            }
            .tabItem {
                Label(AppTab.tasks.title, systemImage: AppTab.tasks.icon)
            }
            .tag(AppTab.tasks)

            NavigationStack {
                BacklogView()
            }
            .tabItem {
                Label(AppTab.backlog.title, systemImage: AppTab.backlog.icon)
            }
            .tag(AppTab.backlog)

            NavigationStack {
                MoreView()
            }
            .tabItem {
                Label(AppTab.more.title, systemImage: AppTab.more.icon)
            }
            .tag(AppTab.more)
        }
        .tint(themeStore.resolvedTabTint)
    }

    private func bootstrapHouseholdIfNeeded() async {
        guard !hasBootstrappedHousehold else { return }
        hasBootstrappedHousehold = true

        guard userSession.currentHouseholdID == nil, let userId = userSession.userId else { return }

        await householdStore.loadCurrentHouseholdAndMembership(userId: userId)
        if let household = householdStore.currentHousehold {
            userSession.setCurrentHousehold(household.id)
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}

#Preview {
    MainAppView()
}
