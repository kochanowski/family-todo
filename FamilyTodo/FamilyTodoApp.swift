import CloudKit
import SwiftData
import SwiftUI

@main
struct FamilyTodoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegateBridge.self) private var appDelegate
    @StateObject private var userSession = UserSession.shared
    @StateObject private var themeStore: ThemeStore
    @StateObject private var householdStore: HouseholdStore
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
        CachedWorkItem.self,
        CachedTask.self,
        CachedMember.self,
        CachedShoppingItem.self,
        CachedShoppingBundle.self,
        CachedBacklogCategory.self,
        CachedBacklogItem.self,
        CachedHousehold.self,
        CachedArea.self,
        CachedRecurringChore.self,
    ])

    init() {
        let launchArguments = ProcessInfo.processInfo.arguments
        UITestHelper.prepareForLaunch(arguments: launchArguments)

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
        _householdStore = StateObject(
            wrappedValue: HouseholdStore(modelContext: bootstrapResult.container?.mainContext)
        )
        _startupRecoveryMessage = State(initialValue: bootstrapResult.diagnosticMessage)
        _startupBootstrapState = State(initialValue: bootstrapResult.bootstrapState)
        _startupDiagnostics = State(initialValue: bootstrapResult.diagnostics)
        AppTips.configureIfNeeded(launchArguments: launchArguments)
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

            #if !CI
                let notifSettings = NotificationSettingsStore()
                NotificationService.shared.setSettingsStore(notifSettings)
                await NotificationService.shared.checkAuthorizationStatus()
                await NotificationService.shared.refreshScheduledNotifications(
                    householdId: userSession.currentHouseholdID,
                    modelContext: modelContext
                )
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            AppChromeContainer(themeStore: themeStore) {
                Group {
                    if startupBootstrapState == .recoveryRequired ||
                        startupBootstrapState == .emergency ||
                        sharedModelContainer == nil
                    {
                        StartupRecoveryView(
                            message: startupRecoveryMessage
                                ?? "Wykryto krytyczny problem lokalnej bazy. Aplikacja uruchomiona w trybie awaryjnym.",
                            diagnostics: startupDiagnostics
                        )
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
                            .overlay {
                                if onboardingState.currentState == .mainApp {
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
                            }
                            .task {
                                appDelegate.shareAcceptanceCoordinator = shareAcceptanceCoordinator
                                appDelegate.flushPendingInviteIfNeeded()
                                WorkItemCacheMigrator.migrateIfNeeded(
                                    context: sharedModelContainer.mainContext
                                )
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
    }
}

private struct AppChromeContainer<Content: View>: View {
    @ObservedObject var themeStore: ThemeStore
    @ViewBuilder let content: Content

    var body: some View {
        content
            .tint(themeStore.resolvedTabTint)
            .preferredColorScheme(themeStore.colorScheme)
    }
}

// MARK: - Root View (State-based Navigation)

struct RootView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var userSession: UserSession
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var shareAcceptanceCoordinator: ShareAcceptanceCoordinator
    @EnvironmentObject private var subscriptionManager: CloudKitSubscriptionManager

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
                    if userSession.needsDisplayNamePrompt {
                        SignInView()
                            .transition(.opacity)
                    } else if shouldShowHouseholdSetupLoader {
                        HouseholdSetupLoadingView()
                            .transition(.opacity)
                    } else {
                        CreateHouseholdView()
                            .transition(.opacity)
                    }
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
                householdStore.resetSetupResolution()
                onboardingState.openAuth()
            }
        }
        .onChange(of: onboardingState.currentState) { _, newState in
            if newState == .householdSetup {
                householdStore.prepareForSetupResolution(key: householdSetupResolutionKey)
            } else {
                householdStore.resetSetupResolution()
            }
        }
        .onChange(of: householdSetupResolutionKey) { _, newKey in
            guard onboardingState.currentState == .householdSetup else { return }
            guard userSession.hasActiveSession else { return }
            householdStore.prepareForSetupResolution(key: newKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .householdDataDidChange)) { _ in
            _ = _Concurrency.Task {
                await handleHouseholdDataDidChange()
            }
        }
        .task(id: pendingProcessingKey) {
            await shareAcceptanceCoordinator.processPendingIfPossible(
                userSession: userSession,
                householdStore: householdStore,
                onboardingState: onboardingState
            )
        }
        .task(id: tipContextKey) {
            guard onboardingState.currentState == .mainApp else { return }
            AppTips.syncContextIfNeeded(
                sessionMode: userSession.sessionMode,
                userId: userSession.userId,
                householdId: userSession.currentHouseholdID
            )
        }
        .task(id: subscriptionConfigurationKey) {
            configureSubscriptionsIfNeeded()
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
            householdStore.isModelContextReady ? "contextReady" : "contextMissing",
            shareAcceptanceCoordinator.pendingInviteCode ?? "noPendingInvite",
            shareAcceptanceCoordinator.pendingMetadata?.rootRecordID.recordName ?? "noPendingMetadata",
            shareAcceptanceCoordinator.isProcessing ? "processingShare" : "idleShare",
        ].joined(separator: "|")
    }

    private var tipContextKey: String {
        [
            onboardingState.currentState.rawValue,
            userSession.sessionMode.rawValue,
            userSession.userId ?? "none",
            userSession.currentHouseholdID?.uuidString ?? "none",
        ].joined(separator: "|")
    }

    private var subscriptionConfigurationKey: String {
        [
            onboardingState.currentState.rawValue,
            userSession.syncMode == .cloud ? "cloud" : "local",
            userSession.userId ?? "none",
            userSession.currentHouseholdID?.uuidString ?? "none",
        ].joined(separator: "|")
    }

    private var householdSetupResolutionKey: String {
        [
            onboardingState.currentState.rawValue,
            userSession.sessionMode.rawValue,
            userSession.userId ?? "none",
            userSession.currentHouseholdID?.uuidString ?? "none",
        ].joined(separator: "|")
    }

    private var hasPendingShareAcceptance: Bool {
        shareAcceptanceCoordinator.pendingInviteCode != nil ||
            shareAcceptanceCoordinator.pendingMetadata != nil ||
            shareAcceptanceCoordinator.isProcessing
    }

    private func recoverHouseholdRouteIfNeeded() async {
        guard onboardingState.currentState == .householdSetup else { return }
        guard userSession.hasActiveSession else { return }
        guard householdStore.isModelContextReady else { return }

        let resolutionKey = householdSetupResolutionKey
        householdStore.prepareForSetupResolution(key: resolutionKey)

        _ = clearSuppressedCurrentHouseholdSelectionIfNeeded(routeToSetup: false)

        if let household = householdStore.currentHousehold {
            completeRecoveredHouseholdRoute(with: household, resolutionKey: resolutionKey)
            return
        }

        householdStore.setSyncMode(userSession.syncMode)

        if userSession.syncMode == SyncMode.localOnly {
            if let cachedHousehold = householdStore.resolveStartupHouseholdLocally(
                userId: "local-guest",
                preferredHouseholdId: userSession.currentHouseholdID
            ) {
                completeRecoveredHouseholdRoute(with: cachedHousehold, resolutionKey: resolutionKey)
                return
            }

            householdStore.completeSetupResolution(
                key: resolutionKey,
                householdCount: householdStore.cachedRecoverableHouseholdCount(
                    userId: "local-guest",
                    preferredHouseholdId: userSession.currentHouseholdID
                )
            )
            return
        }

        guard let userId = userSession.userId else {
            householdStore.completeSetupResolution(key: resolutionKey, householdCount: 0)
            return
        }

        guard !hasPendingShareAcceptance else {
            return
        }

        if let cachedHousehold = householdStore.resolveStartupHouseholdLocally(
            userId: userId,
            preferredHouseholdId: userSession.currentHouseholdID
        ) {
            completeRecoveredHouseholdRoute(with: cachedHousehold, resolutionKey: resolutionKey)
            return
        }

        _ = clearSuppressedCurrentHouseholdSelectionIfNeeded(routeToSetup: false)

        if let household = householdStore.currentHousehold,
           !householdStore.isRecoverySuppressed(for: household.id)
        {
            completeRecoveredHouseholdRoute(with: household, resolutionKey: resolutionKey)
            return
        }

        householdStore.completeSetupResolution(
            key: resolutionKey,
            householdCount: householdStore.cachedRecoverableHouseholdCount(
                userId: userId,
                preferredHouseholdId: userSession.currentHouseholdID
            )
        )
    }

    private func completeRecoveredHouseholdRoute(with household: Household, resolutionKey: String) {
        householdStore.completeSetupResolution(key: resolutionKey, householdCount: 1)
        if userSession.currentHouseholdID != household.id {
            userSession.setCurrentHousehold(household.id)
        }
        onboardingState.completeHouseholdSetup(withHousehold: true)
    }

    private func handleHouseholdDataDidChange() async {
        guard onboardingState.currentState == .mainApp else { return }
        guard userSession.syncMode == .cloud else { return }
        guard let userId = userSession.userId else { return }
        guard userSession.currentHouseholdID != nil else { return }

        await householdStore.refreshCurrentHouseholdAndMembershipFromCloud(
            userId: userId,
            preferredHouseholdId: userSession.currentHouseholdID
        )

        _ = clearSuppressedCurrentHouseholdSelectionIfNeeded(routeToSetup: true)
    }

    private func configureSubscriptionsIfNeeded() {
        guard onboardingState.currentState == .mainApp else { return }
        guard userSession.syncMode == .cloud else { return }
        guard let userId = userSession.userId,
              let householdId = userSession.currentHouseholdID
        else {
            return
        }

        subscriptionManager.configure(userId: userId, householdId: householdId)
    }

    private var shouldShowCreateHouseholdView: Bool {
        guard onboardingState.currentState == .householdSetup else { return false }
        guard userSession.hasActiveSession else { return false }

        switch householdStore.setupResolutionState {
        case let .resolved(key, householdCount):
            return key == householdSetupResolutionKey && householdCount == 0
        case .idle, .loading:
            return false
        }
    }

    private var shouldShowHouseholdSetupLoader: Bool {
        guard onboardingState.currentState == .householdSetup else { return false }
        guard userSession.hasActiveSession else { return false }
        guard !shouldShowCreateHouseholdView else { return false }

        if !householdStore.isModelContextReady || hasPendingShareAcceptance {
            return true
        }

        switch householdStore.setupResolutionState {
        case let .loading(key):
            return key == householdSetupResolutionKey
        case .idle:
            return true
        case .resolved:
            return false
        }
    }

    @discardableResult
    private func clearSuppressedCurrentHouseholdSelectionIfNeeded(routeToSetup: Bool) -> Bool {
        var didClear = false

        if let householdId = userSession.currentHouseholdID,
           householdStore.isRecoverySuppressed(for: householdId)
        {
            userSession.clearCurrentHousehold()
            didClear = true
        }

        if let household = householdStore.currentHousehold,
           householdStore.isRecoverySuppressed(for: household.id)
        {
            householdStore.clearCurrentHousehold()
            didClear = true
        }

        if didClear, routeToSetup {
            householdStore.resetSetupResolution()
            onboardingState.openHouseholdSetup()
        }

        return didClear
    }
}

private struct HouseholdSetupLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)

            Text("Loading household...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
enum LocalAppReset {
    static func clearAllData(context: ModelContext) {
        do {
            try context.delete(model: CachedShoppingItem.self)
            try context.delete(model: CachedShoppingBundle.self)
            try context.delete(model: CachedWorkItem.self)
            try context.delete(model: CachedTask.self)
            try context.delete(model: CachedBacklogItem.self)
            try context.delete(model: CachedBacklogCategory.self)
            try context.delete(model: CachedMember.self)
            try context.delete(model: CachedHousehold.self)
            try context.delete(model: CachedArea.self)
            try context.delete(model: CachedRecurringChore.self)
            try context.save()
        } catch {
            print("Failed to clear data: \(error)")
        }
    }

    static func clearUserDefaults(_ userDefaults: UserDefaults = .standard) {
        let keys = Array(userDefaults.dictionaryRepresentation().keys)
        keys.forEach { userDefaults.removeObject(forKey: $0) }
        if let domain = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: domain)
        }
        userDefaults.synchronize()
    }

    static func performHardReset(
        modelContext: ModelContext,
        userSession: UserSession,
        householdStore: HouseholdStore,
        onboardingState: OnboardingState,
        subscriptionManager: CloudKitSubscriptionManager,
        shareAcceptanceCoordinator: ShareAcceptanceCoordinator,
        celebrationManager: CelebrationManager,
        resetReason: StoreResetReason = .hardResetApp,
        userDefaults: UserDefaults = .standard
    ) async {
        // Local-only fresh-start reset. Remote CloudKit cleanup is exposed as a separate
        // destructive debug action so startup/onboarding is never blocked by network work.
        await subscriptionManager.removeSubscriptions()
        await CloudKitManager.shared.resetAvailabilityCache()
        if userSession.syncMode == .cloud, let userId = userSession.userId {
            await householdStore.hardResetCloudHousehold(userId: userId)
        }
        NotificationService.shared.cancelDailyDigest()
        NotificationService.shared.removeAllDeliveredNotifications()
        NotificationService.shared.removeAllTaskReminders()

        clearAllData(context: modelContext)
        clearUserDefaults(userDefaults)
        SwiftDataContainerFactory.requestStoreReset(reason: resetReason, userDefaults)
        shareAcceptanceCoordinator.resetForDevelopment()
        celebrationManager.resetForDevelopment()
        AppTips.resetForHardReset(userDefaults: userDefaults)

        householdStore.clearCurrentHousehold()
        householdStore.resetSetupResolution()
        userSession.clearCurrentHousehold()

        userSession.signOut()
        onboardingState.resetOnboarding()
    }
}

/// Helper to configure the app state for UI Testing based on launch arguments
@MainActor
struct UITestHelper {
    static func prepareForLaunch(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("-uiTestMode") else { return }
        applyThemeOverride(arguments: arguments)
        AppTips.resetDatastoreForTestingIfNeeded(launchArguments: arguments)
    }

    static func configure(modelContext: ModelContext) {
        let args = ProcessInfo.processInfo.arguments

        // Only run if uiTestMode is enabled
        guard args.contains("-uiTestMode") else { return }

        // Reset Data
        if args.contains("-resetData") {
            LocalAppReset.clearAllData(context: modelContext)
            LocalAppReset.clearUserDefaults()
        }

        applyThemeOverride(arguments: args)

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

        case "household_empty":
            _ = seedHousehold(context: context)

        case "household_empty_seen_tutorials":
            _ = seedHousehold(context: context)
            markTutorialsSeen()

        case "shopping_single_item":
            let household = seedHousehold(context: context)
            seedShoppingSingleActiveItem(context: context, household: household)

        case "ideas_single_category":
            let household = seedHousehold(context: context)
            seedSingleBacklogCategory(context: context, household: household)

        case "ideas_unassigned":
            let household = seedHousehold(context: context)
            seedUnassignedBacklog(context: context, household: household)

        case "contextual_onboarding":
            let household = seedHousehold(context: context)
            seedShoppingList(context: context, household: household)
            seedShoppingBundles(context: context, household: household)
            seedTasks(context: context, household: household)
            seedPromotableBacklog(context: context, household: household)

        case "heavy_data":
            let household = seedHousehold(context: context)
            seedHeavyData(context: context, household: household)

        default:
            print("Unknown seeding scenario: \(scenario)")
        }
    }

    private static func applyThemeOverride(arguments: [String]) {
        guard let themeIndex = arguments.firstIndex(of: "-themeOverride"),
              themeIndex + 1 < arguments.count
        else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(FontSizeScale.regular.rawValue, forKey: "paperFontScale")
        defaults.set(FontSizeScale.regular.rawValue, forKey: "retroFontScale")
        defaults.set(FontSizeScale.regular.rawValue, forKey: "systemFontScale")

        switch arguments[themeIndex + 1].lowercased() {
        case "retro", "retrodark", "retro-dark":
            defaults.set(ThemePreset.retroDark.rawValue, forKey: "themePreset")
        case "retrolight", "retro-light":
            defaults.set(ThemePreset.retroLight.rawValue, forKey: "themePreset")
        case "paper":
            defaults.set(ThemePreset.paper.rawValue, forKey: "themePreset")
        case "light":
            defaults.set(ThemePreset.system.rawValue, forKey: "themePreset")
            defaults.set(AppearanceMode.light.rawValue, forKey: "appearanceMode")
        case "dark":
            defaults.set(ThemePreset.system.rawValue, forKey: "themePreset")
            defaults.set(AppearanceMode.dark.rawValue, forKey: "appearanceMode")
        default:
            defaults.set(ThemePreset.system.rawValue, forKey: "themePreset")
            defaults.set(AppearanceMode.system.rawValue, forKey: "appearanceMode")
        }
    }

    private static func markTutorialsSeen() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasSeenShoppingTutorial")
        defaults.set(true, forKey: "hasSeenTasksTutorial")
        defaults.set(true, forKey: "hasSeenIdeasTutorial")
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

    private static func seedShoppingBundles(context: ModelContext, household: CachedHousehold? = nil) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed shopping bundles: no household available")
            return
        }

        let bundle = ShoppingBundle(
            householdId: householdId,
            name: "Weekend Reset",
            icon: "sparkles",
            items: ["Dish soap", "Paper towels", "Coffee beans"]
        )
        context.insert(CachedShoppingBundle(from: bundle))
    }

    private static func seedShoppingSingleActiveItem(
        context: ModelContext,
        household: CachedHousehold? = nil
    ) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed single shopping item: no household available")
            return
        }

        let item = ShoppingItem(householdId: householdId, title: "Coffee", isBought: false)
        context.insert(CachedShoppingItem(from: item))
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
        tasks.map(WorkItem.init(task:)).forEach { context.insert(CachedWorkItem(from: $0)) }
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
        items.map(WorkItem.init(idea:)).forEach { context.insert(CachedWorkItem(from: $0)) }
        items.forEach { context.insert(CachedBacklogItem(from: $0)) }
    }

    private static func seedPromotableBacklog(
        context: ModelContext,
        household: CachedHousehold? = nil
    ) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed promotable backlog: no household available")
            return
        }

        let category = BacklogCategory(householdId: householdId, title: "Projects")
        let cachedCategory = CachedBacklogCategory(from: category)
        context.insert(cachedCategory)

        let assignedIdea = BacklogItem(
            categoryId: category.id,
            householdId: householdId,
            title: "Paint guest room",
            assigneeId: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")
        )
        context.insert(CachedWorkItem(from: WorkItem(idea: assignedIdea)))
        context.insert(CachedBacklogItem(from: assignedIdea))
    }

    private static func seedSingleBacklogCategory(
        context: ModelContext,
        household: CachedHousehold? = nil
    ) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed single backlog category: no household available")
            return
        }

        let category = BacklogCategory(householdId: householdId, title: "Projects")
        context.insert(CachedBacklogCategory(from: category))
    }

    private static func seedUnassignedBacklog(
        context: ModelContext,
        household: CachedHousehold? = nil
    ) {
        guard let householdId = household?.id ?? getCurrentHouseholdId() else {
            print("Cannot seed unassigned backlog: no household available")
            return
        }

        let category = BacklogCategory(householdId: householdId, title: "Projects")
        context.insert(CachedBacklogCategory(from: category))

        let idea = BacklogItem(
            categoryId: category.id,
            householdId: householdId,
            title: "Replace hallway lamp"
        )
        context.insert(CachedWorkItem(from: WorkItem(idea: idea)))
        context.insert(CachedBacklogItem(from: idea))
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
            context.insert(CachedWorkItem(from: WorkItem(task: task)))
            context.insert(CachedTask(from: task))
        }
    }
}
