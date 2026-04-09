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
                    TabBarDiagnosticsMonitor.shared.attach(to: controller, selectedTab: activeTab)
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
                TabBarDiagnosticsMonitor.shared.recordSnapshot(
                    event: "tabbar.mainAppView.appeared",
                    extra: ["hasResolvedController": "\(tabBarController != nil)"]
                )
                TabBarDiagnosticsMonitor.shared.updateSelectedTab(activeTab)
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
                TabBarDiagnosticsMonitor.shared.updateSelectedTab(activeTab)
                TabBarDiagnosticsMonitor.shared.recordSnapshot(
                    event: "tabbar.selection.changed",
                    extra: ["activeTab": activeTab.rawValue]
                )
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

private struct TabBarControllerAccessor: UIViewRepresentable {
    let onResolve: (UITabBarController) -> Void

    func makeUIView(context _: Context) -> TabBarControllerProbeView {
        let view = TabBarControllerProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: TabBarControllerProbeView, context _: Context) {
        uiView.onResolve = onResolve
        uiView.resolveTabBarControllerIfNeeded(reason: "updateUIView")
    }
}

private final class TabBarControllerProbeView: UIView {
    var onResolve: ((UITabBarController) -> Void)?
    private weak var lastResolvedController: UITabBarController?
    private var hasLoggedMissingResolution = false
    private var hasScheduledAsyncRetry = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        alpha = 0.001
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolveTabBarControllerIfNeeded(reason: "didMoveToSuperview")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveTabBarControllerIfNeeded(reason: "didMoveToWindow")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveTabBarControllerIfNeeded(reason: "layoutSubviews")
    }

    func resolveTabBarControllerIfNeeded(reason: String) {
        guard let resolution = resolvedTabBarController else {
            if !hasLoggedMissingResolution {
                hasLoggedMissingResolution = true
                CloudKitDiagnosticsState.shared.recordTabBarEvent(
                    operation: "tabbar.accessor.resolve.missed",
                    payload: [
                        "view=\(String(describing: type(of: self)))",
                        "reason=\(reason)",
                        "superview=\(superview.map { String(describing: type(of: $0)) } ?? "nil")",
                        "window=\(window.map { String(describing: type(of: $0)) } ?? "nil")",
                        "windowRoot=\(window?.rootViewController.map { String(describing: type(of: $0)) } ?? "nil")",
                        "responderChain=\(responderChainDescription())",
                    ].joined(separator: "\n")
                )
            }
            scheduleAsyncRetryIfNeeded()
            return
        }

        hasLoggedMissingResolution = false
        if lastResolvedController !== resolution.controller {
            lastResolvedController = resolution.controller
            CloudKitDiagnosticsState.shared.recordTabBarEvent(
                operation: "tabbar.accessor.resolved",
                payload: [
                    "view=\(String(describing: type(of: self)))",
                    "reason=\(reason)",
                    "strategy=\(resolution.strategy)",
                    "tabBarController=\(String(describing: type(of: resolution.controller)))",
                    "selectedIndex=\(resolution.controller.selectedIndex)",
                    "responderChain=\(responderChainDescription())",
                ].joined(separator: "\n")
            )
        }
        onResolve?(resolution.controller)
    }

    private var resolvedTabBarController: (controller: UITabBarController, strategy: String)? {
        if let tabBarController = responderChainTabBarController {
            return (tabBarController, "responderChain")
        }

        if let rootViewController = window?.rootViewController,
           let tabBarController = findTabBarController(in: rootViewController)
        {
            return (tabBarController, "windowRoot")
        }

        return nil
    }

    private var responderChainTabBarController: UITabBarController? {
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if let tabBarController = currentResponder as? UITabBarController {
                return tabBarController
            }

            if let viewController = currentResponder as? UIViewController {
                if let tabBarController = viewController as? UITabBarController {
                    return tabBarController
                }

                var parent = viewController.parent
                while let currentParent = parent {
                    if let tabBarController = currentParent as? UITabBarController {
                        return tabBarController
                    }
                    parent = currentParent.parent
                }
            }

            responder = currentResponder.next
        }

        return nil
    }

    private func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }

        for child in viewController.children {
            if let tabBarController = findTabBarController(in: child) {
                return tabBarController
            }
        }

        if let presentedViewController = viewController.presentedViewController,
           let tabBarController = findTabBarController(in: presentedViewController)
        {
            return tabBarController
        }

        return nil
    }

    private func responderChainDescription() -> String {
        var responders: [String] = []
        var responder: UIResponder? = self
        var remainingBudget = 16

        while let currentResponder = responder, remainingBudget > 0 {
            responders.append(String(describing: type(of: currentResponder)))
            responder = currentResponder.next
            remainingBudget -= 1
        }

        if responder != nil {
            responders.append("...")
        }

        return responders.joined(separator: " -> ")
    }

    private func scheduleAsyncRetryIfNeeded() {
        guard !hasScheduledAsyncRetry else { return }
        hasScheduledAsyncRetry = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            hasScheduledAsyncRetry = false
            resolveTabBarControllerIfNeeded(reason: "asyncRetry")
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
