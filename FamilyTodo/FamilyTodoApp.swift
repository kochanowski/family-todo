import CloudKit
import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegateBridge.self) private var appDelegate
    @StateObject private var userSession = UserSession.shared
    @StateObject private var themeStore: ThemeStore
    @StateObject private var householdStore = HouseholdStore()
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var subscriptionManager = CloudKitSubscriptionManager.shared
    @StateObject private var celebrationManager = CelebrationManager.shared
    @StateObject private var shareAcceptanceCoordinator = ShareAcceptanceCoordinator()
    @StateObject private var cloudKitDiagnostics = CloudKitDiagnosticsState.shared
    @State private var startupRecoveryMessage: String?
    @State private var startupBootstrapState: StartupBootstrapState
    @State private var startupDiagnostics: BootstrapDiagnostics?
    @State private var hasScheduledDeferredStartupTasks = false

    private let sharedModelContainer: ModelContainer?

    private static let appSchema = Schema([
        CachedTask.self,
        CachedMember.self,
        CachedShoppingItem.self,
        CachedBacklogCategory.self,
        CachedBacklogItem.self,
        CachedHousehold.self,
        CachedArea.self,
        CachedRecurringChore.self,
    ])

    init() {
        let fontRegistrationReport = FontRegistrar.registerBundledFonts()
        _themeStore = StateObject(
            wrappedValue: ThemeStore(initialFontReport: fontRegistrationReport)
        )

        #if CI
            let bootstrapResult = SwiftDataContainerFactory.bootstrap(
                schema: Self.appSchema,
                isCI: true
            )
        #else
            let bootstrapResult = SwiftDataContainerFactory.bootstrap(
                schema: Self.appSchema
            )
        #endif

        sharedModelContainer = bootstrapResult.container
        _startupRecoveryMessage = State(initialValue: bootstrapResult.diagnosticMessage)
        _startupBootstrapState = State(initialValue: bootstrapResult.bootstrapState)
        _startupDiagnostics = State(initialValue: bootstrapResult.diagnostics)
    }

    private func scheduleDeferredStartupTasks(modelContext: ModelContext) {
        guard !hasScheduledDeferredStartupTasks else { return }
        hasScheduledDeferredStartupTasks = true

        _ = _Concurrency.Task(priority: .utility) {
            #if !CI
                await userSession.checkAuthenticationStatus()
                if userSession.syncMode == .cloud,
                   let userId = userSession.userId,
                   let householdId = userSession.currentHouseholdID
                {
                    subscriptionManager.configure(userId: userId, householdId: householdId)
                }
            #endif

            await shareAcceptanceCoordinator.processPendingIfPossible(
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState
            )

            await ChoreScheduler.shared.runIfNeeded(
                householdId: userSession.currentHouseholdID,
                modelContext: modelContext,
                syncMode: userSession.syncMode
            )

            #if !CI
                let notifSettings = NotificationSettingsStore()
                NotificationService.shared.setSettingsStore(notifSettings)
                await NotificationService.shared.checkAuthorizationStatus()
                if notifSettings.isEnabled, notifSettings.dailyDigestEnabled {
                    let components = Calendar.current.dateComponents(
                        [.hour, .minute],
                        from: notifSettings.reminderTime
                    )
                    await NotificationService.shared.scheduleDailyDigest(
                        at: components.hour ?? 8,
                        minute: components.minute ?? 0
                    )
                }
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            if startupBootstrapState == .emergency || sharedModelContainer == nil {
                StartupRecoveryView(
                    message: startupRecoveryMessage
                        ?? "Wykryto krytyczny problem lokalnej bazy. Aplikacja uruchomiona w trybie awaryjnym.",
                    diagnostics: startupDiagnostics
                )
                .preferredColorScheme(themeStore.colorScheme)
            } else if let sharedModelContainer {
                RootView()
                    .environmentObject(userSession)
                    .environmentObject(themeStore)
                    .environmentObject(householdStore)
                    .environmentObject(onboardingState)
                    .environmentObject(subscriptionManager)
                    .environmentObject(celebrationManager)
                    .environmentObject(shareAcceptanceCoordinator)
                    .environmentObject(cloudKitDiagnostics)
                    .modelContainer(sharedModelContainer)
                    .preferredColorScheme(themeStore.colorScheme)
                    .overlay {
                        let toastBackground = themeStore.surfaceElevatedColor
                        let toastAppearance = ToastView.Appearance(
                            backgroundColor: toastBackground,
                            messageColor: themeStore.inkColor,
                            strokeColor: themeStore.borderLightColor.opacity(0.55),
                            shadowColor: themeStore.inkColor.opacity(0.18),
                            actionColor: themeStore.accentTabColor,
                            messageFont: themeStore.font(for: .celebrationMessage),
                            actionFont: themeStore.font(for: .buttonLabel)
                        )

                        CelebrationOverlay(
                            manager: celebrationManager,
                            messageFont: themeStore.font(for: .celebrationMessage),
                            accentPalette: themeStore.confettiAccentPalette,
                            toastAppearance: toastAppearance
                        )
                        .environmentObject(themeStore)
                    }
                    .task {
                        appDelegate.shareAcceptanceCoordinator = shareAcceptanceCoordinator
                        appDelegate.flushPendingInviteIfNeeded()
                        householdStore.setModelContext(sharedModelContainer.mainContext)
                        householdStore.setSyncMode(userSession.syncMode)

                        // Configure for UI Testing if needed
                        UITestHelper.configure(modelContext: sharedModelContainer.mainContext)

                        #if !CI
                            if userSession.syncMode == .cloud,
                               let userId = userSession.userId,
                               let householdId = userSession.currentHouseholdID
                            {
                                subscriptionManager.configure(userId: userId, householdId: householdId)
                            }
                        #endif
                        scheduleDeferredStartupTasks(modelContext: sharedModelContainer.mainContext)
                    }
                    .onOpenURL { url in
                        if url.scheme?.lowercased() == "housepulse" {
                            do {
                                let normalized = try InviteInputNormalizer.normalizeInput(url.absoluteString)
                                shareAcceptanceCoordinator.enqueue(rawInviteCode: normalized.inviteCode)
                            } catch {
                                shareAcceptanceCoordinator.lastErrorMessage = "Invalid invite link format."
                            }
                            return
                        }

                        if let host = url.host?.lowercased(),
                           host.contains("icloud.com")
                        {
                            shareAcceptanceCoordinator.enqueue(inviteURL: url)
                        }
                    }
                    .alert(
                        "Recovery Complete",
                        isPresented: Binding(
                            get: { startupRecoveryMessage != nil },
                            set: { if !$0 { startupRecoveryMessage = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) {
                            startupRecoveryMessage = nil
                        }
                    } message: {
                        Text(startupRecoveryMessage ?? "")
                    }
            }
        }
    }
}

// MARK: - Root View (State-based Navigation)

struct RootView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var shareAcceptanceCoordinator: ShareAcceptanceCoordinator

    var body: some View {
        Group {
            switch onboardingState.currentState {
            case .onboarding:
                OnboardingCarouselView()
                    .transition(.opacity)

            case .auth:
                SignInView()
                    .transition(.opacity)

            case .householdSetup:
                if userSession.hasActiveSession {
                    CreateHouseholdView()
                        .transition(.opacity)
                } else {
                    SignInView()
                        .transition(.opacity)
                }

            case .mainApp:
                if userSession.hasActiveSession {
                    ContentView()
                        .transition(.opacity)
                } else {
                    SignInView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingState.currentState)
        .onChange(of: userSession.hasActiveSession) { _, hasSession in
            if !hasSession, onboardingState.currentState != .onboarding {
                onboardingState.openAuth()
            }
        }
        .task(id: pendingProcessingKey) {
            await shareAcceptanceCoordinator.processPendingIfPossible(
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState
            )
        }
        .task(id: householdRecoveryKey) {
            await recoverHouseholdRouteIfNeeded()
        }
        .alert(
            "Invitation Error",
            isPresented: Binding(
                get: {
                    onboardingState.currentState == .mainApp
                        && shareAcceptanceCoordinator.lastErrorMessage != nil
                },
                set: { if !$0 { shareAcceptanceCoordinator.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                shareAcceptanceCoordinator.clearError()
            }
        } message: {
            Text(shareAcceptanceCoordinator.lastErrorMessage ?? "Unknown error")
        }
    }

    private var pendingProcessingKey: String {
        [
            onboardingState.currentState.rawValue,
            userSession.sessionMode.rawValue,
            userSession.userId ?? "none",
            userSession.currentHouseholdID?.uuidString ?? "none",
            userSession.hasConfirmedDisplayName ? "named" : "unnamed",
            shareAcceptanceCoordinator.pendingInviteCode ?? "none",
            shareAcceptanceCoordinator.pendingMetadata?.rootRecordID.recordName ?? "none",
        ].joined(separator: "|")
    }

    private var householdRecoveryKey: String {
        [
            onboardingState.currentState.rawValue,
            userSession.sessionMode.rawValue,
            userSession.userId ?? "none",
            userSession.currentHouseholdID?.uuidString ?? "none",
            householdStore.currentHousehold?.id.uuidString ?? "none",
        ].joined(separator: "|")
    }

    private func recoverHouseholdRouteIfNeeded() async {
        guard onboardingState.currentState == .householdSetup else { return }
        guard userSession.hasActiveSession else { return }

        if let householdId = userSession.currentHouseholdID,
           householdStore.isRecoverySuppressed(for: householdId)
        {
            userSession.clearCurrentHousehold()
        }

        if let household = householdStore.currentHousehold,
           householdStore.isRecoverySuppressed(for: household.id)
        {
            householdStore.clearCurrentHousehold()
        }

        if userSession.currentHouseholdID != nil || householdStore.currentHousehold != nil {
            onboardingState.completeHouseholdSetup(withHousehold: true)
            return
        }

        guard let userId = userSession.userId else { return }
        householdStore.setSyncMode(userSession.syncMode)
        await householdStore.loadCurrentHouseholdAndMembership(
            userId: userId,
            preferredHouseholdId: userSession.currentHouseholdID
        )

        if let household = householdStore.currentHousehold,
           !householdStore.isRecoverySuppressed(for: household.id)
        {
            userSession.setCurrentHousehold(household.id)
            onboardingState.completeHouseholdSetup(withHousehold: true)
        }
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
            clearUserDefaults()
        }

        // Check for specific scenario
        if let scenarioIndex = args.firstIndex(of: "-seedScenario"),
           scenarioIndex + 1 < args.count
        {
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
            try context.delete(model: CachedArea.self)
            try context.delete(model: CachedRecurringChore.self)
        } catch {
            print("Failed to clear data: \(error)")
        }
    }

    private static func clearUserDefaults() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }

    private static func getCurrentHouseholdId() -> UUID? {
        guard let idString = UserDefaults.standard.string(forKey: "currentHouseholdID") else {
            return nil
        }
        return UUID(uuidString: idString)
    }

    @discardableResult
    private static func seedHousehold(context: ModelContext) -> CachedHousehold {
        let household = CachedHousehold(name: "Test House", ownerId: "test-owner")
        context.insert(household)

        // Emulate user selection of this household
        UserDefaults.standard.set(household.id.uuidString, forKey: "currentHouseholdID")
        return household
    }

    private static func seedShoppingList(context: ModelContext, household: CachedHousehold? = nil) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed shopping list: no household available")
            return
        }

        let items = [
            ShoppingItem(householdId: householdId, title: "Milk", isBought: false),
            ShoppingItem(householdId: householdId, title: "Bread", isBought: false),
            ShoppingItem(householdId: householdId, title: "Eggs", isBought: true),
        ]
        for item in items {
            context.insert(CachedShoppingItem(from: item))
        }
    }

    private static func seedTasks(context: ModelContext, household: CachedHousehold? = nil) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed tasks: no household available")
            return
        }

        let tasks = [
            Task(householdId: householdId, title: "Pay bills", status: .next, taskType: .oneOff),
            Task(householdId: householdId, title: "Call mom", status: .next, taskType: .oneOff),
            Task(householdId: householdId, title: "Walk dog", status: .done, taskType: .oneOff),
        ]
        tasks.forEach { context.insert(CachedTask(from: $0)) }
    }

    private static func seedBacklog(context: ModelContext, household: CachedHousehold? = nil) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed backlog: no household available")
            return
        }

        let category = BacklogCategory(householdId: householdId, title: "Groceries")
        let cachedCategory = CachedBacklogCategory(from: category)
        context.insert(cachedCategory)

        let items = [
            BacklogItem(categoryId: category.id, householdId: householdId, title: "Olive Oil"),
            BacklogItem(categoryId: category.id, householdId: householdId, title: "Spices"),
        ]
        items.forEach { context.insert(CachedBacklogItem(from: $0)) }
    }

    private static func seedHeavyData(context: ModelContext, household: CachedHousehold) {
        let householdId = household.id

        // Shopping List - 50 items
        for i in 1 ... 50 {
            let item = ShoppingItem(householdId: householdId, title: "Item \(i)", isBought: i % 5 == 0)
            context.insert(CachedShoppingItem(from: item))
        }

        // Tasks - 50 items
        for i in 1 ... 50 {
            let status: Task.TaskStatus = (i % 3 == 0) ? .done : .next
            let task = Task(householdId: householdId, title: "Task \(i)", status: status, taskType: .oneOff)
            context.insert(CachedTask(from: task))
        }
    }
}
