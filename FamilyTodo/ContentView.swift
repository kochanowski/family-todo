import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        MainAppView()
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
    @State private var tabBarController: UITabBarController?

    var body: some View {
        legacyTabView
            .background(
                TabBarControllerAccessor { controller in
                    guard tabBarController !== controller else { return }
                    tabBarController = controller
                    applyTabBarAppearance()
                }
            )
            .background(AppBackgroundView())
            .onAppear {
                applyTabBarAppearance()
            }
            .onChange(of: themeStore.unifiedTheme) { _, _ in
                applyTabBarAppearance()
            }
            .onChange(of: themeStore.tabTintColor) { _, _ in
                applyTabBarAppearance()
            }
            .onChange(of: themeStore.retroFontScale) { _, _ in
                applyTabBarAppearance()
            }
            .onChange(of: activeTab) { _, _ in
                applyTabBarAppearance()
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
    }

    private func bootstrapHouseholdIfNeeded() async {
        guard !hasBootstrappedHousehold else { return }
        hasBootstrappedHousehold = true

        if let household = householdStore.currentHousehold {
            if userSession.currentHouseholdID != household.id {
                userSession.setCurrentHousehold(household.id)
            }
            return
        }

        guard let userId = userSession.userId else { return }

        householdStore.setSyncMode(userSession.syncMode)

        if let restoredHousehold = householdStore.restoreCachedHousehold(
            userId: userId,
            preferredHouseholdId: userSession.currentHouseholdID
        ) {
            if userSession.currentHouseholdID != restoredHousehold.id {
                userSession.setCurrentHousehold(restoredHousehold.id)
            }
            _ = _Concurrency.Task {
                await householdStore.refreshCurrentHouseholdAndMembershipFromCloud(
                    userId: userId,
                    preferredHouseholdId: userSession.currentHouseholdID
                )
            }
            return
        }

        await householdStore.loadCurrentHouseholdAndMembership(
            userId: userId,
            preferredHouseholdId: userSession.currentHouseholdID
        )
        if let household = householdStore.currentHousehold,
           userSession.currentHouseholdID != household.id
        {
            userSession.setCurrentHousehold(household.id)
        }
    }

    private func applyTabBarAppearance() {
        TabBarTypographyManager.apply(
            themeStore: themeStore,
            tabBarController: tabBarController,
            selectedIndex: AppTab.allCases.firstIndex(of: activeTab)
        )
    }
}

private struct TabBarControllerAccessor: UIViewControllerRepresentable {
    let onResolve: (UITabBarController) -> Void

    func makeUIViewController(context _: Context) -> TabBarControllerReaderViewController {
        let viewController = TabBarControllerReaderViewController()
        viewController.onResolve = onResolve
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: TabBarControllerReaderViewController,
        context _: Context
    ) {
        uiViewController.onResolve = onResolve
        uiViewController.resolveTabBarControllerIfNeeded()
    }
}

private final class TabBarControllerReaderViewController: UIViewController {
    var onResolve: ((UITabBarController) -> Void)?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resolveTabBarControllerIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveTabBarControllerIfNeeded()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        resolveTabBarControllerIfNeeded()
    }

    func resolveTabBarControllerIfNeeded() {
        guard let tabBarController = resolvedTabBarController else { return }
        onResolve?(tabBarController)
    }

    private var resolvedTabBarController: UITabBarController? {
        if let tabBarController {
            return tabBarController
        }

        var currentParent: UIViewController? = parent
        while let candidate = currentParent {
            if let tabBarController = candidate as? UITabBarController {
                return tabBarController
            }
            currentParent = candidate.parent
        }

        return nil
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
