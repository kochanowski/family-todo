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
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var syncCoordinator: HouseholdSyncCoordinator
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager
    @Query(sort: \CachedMember.joinedAt) private var cachedMembers: [CachedMember]

    @State private var activeTab: AppTab = .shopping
    @State private var hasBootstrappedHousehold = false
    @State private var tabBarController: UITabBarController?
    @State private var hasPrimedActiveMemberBaseline = false
    @State private var knownActiveMemberIDs = Set<UUID>()
    @State private var activeJoinToastMessage: String?
    @State private var joinToastDismissTask: _Concurrency.Task<Void, Never>?

    var body: some View {
        legacyTabView
            .background(
                TabBarControllerAccessor { controller in
                    if tabBarController !== controller {
                        tabBarController = controller
                    }
                    reconcileTabBarAppearance(using: controller)
                }
            )
            .background(AppBackgroundView())
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    if let activeJoinToastMessage {
                        ToastView(message: activeJoinToastMessage)
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(2)
                    }

                    if subscriptionManager.showNewItemsBanner {
                        NewItemsBanner(
                            count: subscriptionManager.newItemsCount,
                            onTap: {
                                activeTab = .shopping
                                subscriptionManager.dismissBanner()
                            },
                            onDismiss: {
                                subscriptionManager.dismissBanner()
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .padding(.top, 12)
            }
            .onAppear {
                reconcileTabBarAppearance()
                primeActiveMemberBaseline()
                subscriptionManager.updateActiveTab(activeTab)
            }
            .onChange(of: themeStore.unifiedTheme) { _, _ in
                reconcileTabBarAppearance()
            }
            .onChange(of: themeStore.tabTintColor) { _, _ in
                reconcileTabBarAppearance()
            }
            .onChange(of: themeStore.retroFontScale) { _, _ in
                reconcileTabBarAppearance()
            }
            .onChange(of: activeTab) { _, _ in
                reconcileTabBarAppearance()
                subscriptionManager.updateActiveTab(activeTab)
            }
            .onChange(of: userSession.currentHouseholdID) { _, _ in
                primeActiveMemberBaseline()
            }
            .onChange(of: householdStore.currentHousehold?.id) { _, _ in
                primeActiveMemberBaseline()
            }
            .onChange(of: activeMemberSnapshot) { oldValue, newValue in
                handleActiveMemberSnapshotChange(from: oldValue, to: newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .tabBarAppearanceRefreshRequested)) { _ in
                refreshTabBarAppearanceForHouseholdChromeChange()
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: activeJoinToastMessage)
            .task {
                await bootstrapHouseholdIfNeeded()
            }
    }

    private var legacyTabView: some View {
        TabView(selection: $activeTab) {
            NavigationStack {
                ShoppingListView(selectedTab: $activeTab)
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
                BacklogView(selectedTab: $activeTab)
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

    private var activeMemberSnapshot: ActiveMemberSnapshot {
        let householdId = userSession.currentHouseholdID ?? householdStore.currentHousehold?.id
        let activeMembers = cachedMembers
            .filter { cachedMember in
                guard let householdId else { return false }
                return cachedMember.householdId == householdId && cachedMember.isActive
            }
            .map {
                ActiveMemberSnapshot.Entry(
                    id: $0.id,
                    userId: $0.userId,
                    displayName: $0.displayName
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        return ActiveMemberSnapshot(
            householdId: householdId,
            currentUserId: userSession.userId,
            members: activeMembers
        )
    }

    private func bootstrapHouseholdIfNeeded() async {
        guard !hasBootstrappedHousehold else { return }
        hasBootstrappedHousehold = true

        if let household = householdStore.currentHousehold {
            if userSession.currentHouseholdID != household.id {
                userSession.setCurrentHousehold(household.id)
            }
            refreshCurrentHouseholdInBackgroundIfNeeded(
                userId: userSession.userId,
                preferredHouseholdId: household.id
            )
            return
        }

        let startupUserId = userSession.userId ?? (userSession.isGuest ? "local-guest" : nil)
        guard let startupUserId else { return }

        householdStore.setSyncMode(userSession.syncMode)

        if let restoredHousehold = householdStore.resolveStartupHouseholdLocally(
            userId: startupUserId,
            preferredHouseholdId: userSession.currentHouseholdID
        ) {
            if userSession.currentHouseholdID != restoredHousehold.id {
                userSession.setCurrentHousehold(restoredHousehold.id)
            }
            refreshCurrentHouseholdInBackgroundIfNeeded(
                userId: userSession.userId,
                preferredHouseholdId: restoredHousehold.id
            )
            return
        }

        if handleSuppressedHouseholdRecoveryIfNeeded() {
            return
        }

        guard userSession.syncMode == .cloud else { return }
        if onboardingState.currentState == .mainApp {
            householdStore.resetSetupResolution()
            onboardingState.openHouseholdSetup()
        }
    }

    private func refreshCurrentHouseholdInBackgroundIfNeeded(
        userId: String?,
        preferredHouseholdId: UUID?
    ) {
        guard userSession.syncMode == .cloud, let userId else { return }

        _ = _Concurrency.Task {
            await householdStore.refreshCurrentHouseholdAndMembershipFromCloud(
                userId: userId,
                preferredHouseholdId: preferredHouseholdId
            )
            await MainActor.run {
                handleSuppressedHouseholdRecoveryIfNeeded()
            }
        }
    }

    private func reconcileTabBarAppearance(using controller: UITabBarController? = nil) {
        TabBarTypographyManager.reconcile(
            themeStore: themeStore,
            tabBarController: controller ?? tabBarController,
            selectedIndex: AppTab.allCases.firstIndex(of: activeTab)
        )
    }

    private func refreshTabBarAppearanceForHouseholdChromeChange() {
        reconcileTabBarAppearance()
        DispatchQueue.main.async {
            reconcileTabBarAppearance()
        }
        // A defensive reapply keeps the selected tab tinted even if UIKit settles later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            reconcileTabBarAppearance()
        }
    }

    @discardableResult
    private func handleSuppressedHouseholdRecoveryIfNeeded() -> Bool {
        guard let householdId = userSession.currentHouseholdID,
              householdStore.isRecoverySuppressed(for: householdId)
        else {
            return false
        }

        if householdStore.hasPendingJoinProtection(for: householdId, userId: userSession.userId) {
            return false
        }

        householdStore.clearCurrentHousehold()
        userSession.clearCurrentHousehold()
        householdStore.resetSetupResolution()
        onboardingState.openHouseholdSetup()
        return true
    }

    private func primeActiveMemberBaseline() {
        let snapshot = activeMemberSnapshot
        hasPrimedActiveMemberBaseline = !snapshot.members.isEmpty || snapshot.householdId == nil
        knownActiveMemberIDs = Set(snapshot.members.map(\.id))
        dismissJoinToastIfNeeded()
    }

    private func handleActiveMemberSnapshotChange(
        from oldValue: ActiveMemberSnapshot,
        to newValue: ActiveMemberSnapshot
    ) {
        guard oldValue != newValue else { return }

        if !hasPrimedActiveMemberBaseline || oldValue.householdId != newValue.householdId {
            knownActiveMemberIDs = Set(newValue.members.map(\.id))
            hasPrimedActiveMemberBaseline = true
            return
        }

        let knownIds = knownActiveMemberIDs
        knownActiveMemberIDs = Set(newValue.members.map(\.id))

        if householdStore.hasPendingJoinProtection(
            for: newValue.householdId,
            userId: newValue.currentUserId
        ) || syncCoordinator.latestBatch?.classification == .bootstrap {
            dismissJoinToastIfNeeded()
            return
        }

        let newlyJoinedMembers = newValue.members.filter { member in
            !knownIds.contains(member.id) && member.userId != newValue.currentUserId
        }

        guard !newlyJoinedMembers.isEmpty else { return }
        presentJoinToast(for: newlyJoinedMembers)
    }

    private func presentJoinToast(for members: [ActiveMemberSnapshot.Entry]) {
        let message = if members.count == 1 {
            "\(members[0].displayName) joined the household!"
        } else {
            "\(members.count) people joined the household!"
        }

        joinToastDismissTask?.cancel()
        activeJoinToastMessage = message

        joinToastDismissTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(nanoseconds: 2_500_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            activeJoinToastMessage = nil
            joinToastDismissTask = nil
        }
    }

    private func dismissJoinToastIfNeeded() {
        joinToastDismissTask?.cancel()
        joinToastDismissTask = nil
        activeJoinToastMessage = nil
    }
}

private struct ActiveMemberSnapshot: Equatable {
    struct Entry: Equatable, Hashable {
        let id: UUID
        let userId: String
        let displayName: String
    }

    let householdId: UUID?
    let currentUserId: String?
    let members: [Entry]
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
