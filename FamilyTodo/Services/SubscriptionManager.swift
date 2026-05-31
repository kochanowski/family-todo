import Foundation
import RevenueCat
import RevenueCatUI
import SwiftUI

enum PremiumFeature: Identifiable, Equatable {
    case premiumTheme
    case accentColor
    case backlogCategoryLimit
    case householdMemberLimit
    case shoppingBundles

    var id: String {
        switch self {
        case .premiumTheme:
            "premiumTheme"
        case .accentColor:
            "accentColor"
        case .backlogCategoryLimit:
            "backlogCategoryLimit"
        case .householdMemberLimit:
            "householdMemberLimit"
        case .shoppingBundles:
            "shoppingBundles"
        }
    }
}

enum UpsellContext: Identifiable, Equatable {
    case premiumTheme
    case accentColor
    case backlogCategoryLimit
    case householdMemberLimit
    case shoppingBundles

    init(feature: PremiumFeature) {
        switch feature {
        case .premiumTheme:
            self = .premiumTheme
        case .accentColor:
            self = .accentColor
        case .backlogCategoryLimit:
            self = .backlogCategoryLimit
        case .householdMemberLimit:
            self = .householdMemberLimit
        case .shoppingBundles:
            self = .shoppingBundles
        }
    }

    var id: String {
        switch self {
        case .premiumTheme:
            "premiumTheme"
        case .accentColor:
            "accentColor"
        case .backlogCategoryLimit:
            "backlogCategoryLimit"
        case .householdMemberLimit:
            "householdMemberLimit"
        case .shoppingBundles:
            "shoppingBundles"
        }
    }

    var iconName: String {
        switch self {
        case .premiumTheme:
            "sparkles"
        case .accentColor:
            "paintpalette.fill"
        case .backlogCategoryLimit:
            "folder.badge.plus"
        case .householdMemberLimit:
            "person.2.badge.plus.fill"
        case .shoppingBundles:
            "shippingbox.fill"
        }
    }

    var eyebrow: String {
        "Dwello Pro"
    }

    var title: String {
        switch self {
        case .premiumTheme:
            "Make Dwello feel like home"
        case .accentColor:
            "Personalize your accent"
        case .backlogCategoryLimit:
            "Unlimited idea categories"
        case .householdMemberLimit:
            "Invite the whole household"
        case .shoppingBundles:
            "Shop faster with bundles"
        }
    }

    var message: String {
        switch self {
        case .premiumTheme:
            "Retro and Paper themes are included with Dwello Pro, with richer typography and calmer surfaces for your shared space."
        case .accentColor:
            "Custom accent colors are a Dwello Pro feature, so every household can tune Dwello to its own style."
        case .backlogCategoryLimit:
            "Free households can create up to \(PremiumAccessPolicy.freeBacklogCategoryLimit) idea categories. Dwello Pro lets you keep planning without trimming your setup."
        case .householdMemberLimit:
            "Free households include up to \(PremiumAccessPolicy.freeHouseholdMemberLimit) members. Dwello Pro unlocks room for everyone who coordinates at home."
        case .shoppingBundles:
            "Shopping bundles are included with Dwello Pro, so repeated lists like breakfast, cleaning, and weekly staples take one tap."
        }
    }

    var primaryCTATitle: String {
        "See Dwello Pro"
    }
}

enum PremiumAccessPolicy {
    static let freeHouseholdMemberLimit = 2
    static let freeBacklogCategoryLimit = 4

    static func canUseTheme(_ theme: UnifiedTheme, isPremium: Bool) -> Bool {
        isPremium || !theme.isPremium
    }

    static func canUseAccentColor(_ tint: TabTintColor, isPremium: Bool) -> Bool {
        isPremium || tint == .defaultGreen
    }

    static func canCreateBacklogCategory(currentCount: Int, isPremium: Bool) -> Bool {
        isPremium || currentCount < freeBacklogCategoryLimit
    }

    static func canAddHouseholdMember(activeMemberCount: Int, isPremium: Bool) -> Bool {
        isPremium || activeMemberCount < freeHouseholdMemberLimit
    }

    static func canUseShoppingBundles(isPremium: Bool) -> Bool {
        isPremium
    }
}

private struct PremiumSheetsHost: ViewModifier {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var premiumSubscriptionManager: SubscriptionManager

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $premiumSubscriptionManager.displayPaywall) {
                PaywallView(displayCloseButton: true)
                    .onDisappear {
                        onboardingState.consumePostSetupPaywall()
                        _ = _Concurrency.Task {
                            await premiumSubscriptionManager.refreshCustomerInfo()
                        }
                    }
            }
            .sheet(isPresented: $premiumSubscriptionManager.displayCustomerCenter) {
                CustomerCenterView()
                    .onDisappear {
                        _ = _Concurrency.Task {
                            await premiumSubscriptionManager.refreshCustomerInfo()
                        }
                    }
            }
            .sheet(item: $premiumSubscriptionManager.activeUpsellContext) { context in
                PremiumUpsellSheet(context: context)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}

extension View {
    func premiumSheetsHost() -> some View {
        modifier(PremiumSheetsHost())
    }
}

@MainActor
enum RevenueCatRuntime {
    private(set) static var isConfigured = false

    static func configureIfNeeded(
        apiKey rawAPIKey: String,
        diagnostics: CloudKitDiagnosticsState
    ) {
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Purchases.logLevel = .debug
        Purchases.logHandler = { level, message in
            _ = _Concurrency.Task { @MainActor in
                diagnostics.recordMessage(
                    operation: "revenuecat.log.\(level)",
                    payload: message,
                    source: .revenueCat
                )
            }
        }

        guard !apiKey.isEmpty else {
            diagnostics.recordMessage(
                operation: "revenuecat.configure.skipped",
                payload: "RevenueCat API key is empty. Premium features remain unavailable.",
                source: .revenueCat,
                kind: .error
            )
            isConfigured = false
            return
        }

        #if !DEBUG
            if apiKey.hasPrefix("test_") || apiKey.hasPrefix("sk_") {
                diagnostics.recordMessage(
                    operation: "revenuecat.configure.invalidReleaseKey",
                    payload: "RevenueCat release build received an invalid API key prefix.",
                    source: .revenueCat,
                    kind: .error
                )
                isConfigured = false
                return
            }
        #endif

        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true
        diagnostics.recordMessage(
            operation: "revenuecat.configure.success",
            payload: "RevenueCat configured successfully.",
            source: .revenueCat
        )
    }
}

@MainActor
final class SubscriptionManager: NSObject, ObservableObject {
    enum Constants {
        static let entitlementID = "HousePulse Pro"
        static let developerPremiumOverrideKey = "developerPremiumOverride"
    }

    @Published private(set) var hasRevenueCatEntitlement = false
    @Published private(set) var hasHouseholdPremium = false
    @Published private(set) var isPremium = false
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var isLoading = false
    @Published private(set) var developerPremiumOverride: Bool
    @Published var displayPaywall = false
    @Published var displayCustomerCenter = false
    @Published var activeUpsellContext: UpsellContext?
    @Published var lastErrorMessage: String?

    private weak var userSession: UserSession?
    private weak var householdStore: HouseholdStore?
    private let userDefaults: UserDefaults
    private var currentRevenueCatAppUserID: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        developerPremiumOverride = userDefaults.bool(forKey: Constants.developerPremiumOverrideKey)
        super.init()
        if RevenueCatRuntime.isConfigured {
            Purchases.shared.delegate = self
        }
        recomputePremiumState()
    }

    func connect(
        userSession: UserSession,
        householdStore: HouseholdStore
    ) async {
        self.userSession = userSession
        self.householdStore = householdStore
        syncHouseholdPremiumFromStore()
        guard RevenueCatRuntime.isConfigured else { return }
        await refreshOfferings()
        await syncRevenueCatIdentity()
        await refreshCustomerInfo()
    }

    func handleSessionChange() async {
        await syncRevenueCatIdentity()
        await refreshCustomerInfo()
    }

    func handleHouseholdChange() async {
        syncHouseholdPremiumFromStore()
        await refreshCustomerInfo()
    }

    func refreshOfferings() async {
        guard RevenueCatRuntime.isConfigured else { return }
        do {
            currentOffering = try await Purchases.shared.offerings().current
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Unable to load subscription options."
            print("[SubscriptionManager] Offerings refresh failed: \(error)")
        }
    }

    func refreshCustomerInfo() async {
        guard RevenueCatRuntime.isConfigured else {
            syncHouseholdPremiumFromStore()
            return
        }
        isLoading = true
        defer { isLoading = false }
        await checkEntitlement()
        syncHouseholdPremiumFromStore()
    }

    func checkEntitlement() async {
        guard RevenueCatRuntime.isConfigured else { return }
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            if customerInfo.entitlements.all[Constants.entitlementID]?.isActive == true {
                // User has access to entitlement
            }
            await apply(customerInfo: customerInfo)
        } catch {
            lastErrorMessage = "Unable to verify subscription status."
            print("Error: \(error)")
        }
    }

    func prepareForSignOut() async {
        displayPaywall = false
        displayCustomerCenter = false
        activeUpsellContext = nil
        lastErrorMessage = nil

        guard RevenueCatRuntime.isConfigured else {
            hasRevenueCatEntitlement = false
            syncHouseholdPremiumFromStore()
            recomputePremiumState()
            return
        }

        do {
            _ = try await Purchases.shared.logOut()
            currentRevenueCatAppUserID = nil
        } catch {
            print("[SubscriptionManager] RevenueCat logOut failed: \(error)")
        }

        hasRevenueCatEntitlement = false
        syncHouseholdPremiumFromStore()
        recomputePremiumState()
    }

    func unlockDeveloperPremiumOverride() {
        userDefaults.set(true, forKey: Constants.developerPremiumOverrideKey)
        developerPremiumOverride = true
        recomputePremiumState()
    }

    func refreshDeveloperPremiumOverride() {
        developerPremiumOverride = userDefaults.bool(forKey: Constants.developerPremiumOverrideKey)
        recomputePremiumState()
    }

    func package(matching identifier: String) -> Package? {
        currentOffering?.availablePackages.first(where: { $0.identifier == identifier })
    }

    func presentUpsell(_ context: UpsellContext) {
        HapticManager.lightTap()
        activeUpsellContext = context
        AppAnalytics.capture(
            "premium_upsell_viewed",
            properties: ["feature": context.id],
            sessionMode: userSession?.sessionMode,
            syncMode: userSession?.syncMode,
            householdId: userSession?.currentHouseholdID
        )
    }

    func presentPaywallFromUpsell() {
        activeUpsellContext = nil
        displayPaywall = true
        AppAnalytics.capture(
            "premium_paywall_opened",
            properties: ["source": "upsell"],
            sessionMode: userSession?.sessionMode,
            syncMode: userSession?.syncMode,
            householdId: userSession?.currentHouseholdID
        )
    }

    func handlePurchaseCompleted(customerInfo: CustomerInfo) {
        _ = _Concurrency.Task { @MainActor in
            await apply(customerInfo: customerInfo)
        }
    }

    func handleRestoreCompleted(customerInfo: CustomerInfo) {
        _ = _Concurrency.Task { @MainActor in
            await apply(customerInfo: customerInfo)
        }
    }

    private func syncRevenueCatIdentity() async {
        guard RevenueCatRuntime.isConfigured else { return }
        guard let userSession else { return }

        let targetUserID = userSession.isAuthenticated ? userSession.userId : nil
        guard currentRevenueCatAppUserID != targetUserID else { return }

        do {
            if let targetUserID {
                _ = try await Purchases.shared.logIn(targetUserID)
                currentRevenueCatAppUserID = targetUserID
            } else {
                _ = try await Purchases.shared.logOut()
                currentRevenueCatAppUserID = nil
            }
        } catch {
            lastErrorMessage = "Unable to update subscription account state."
            print("[SubscriptionManager] RevenueCat identity sync failed: \(error)")
        }
    }

    private func syncHouseholdPremiumFromStore() {
        hasHouseholdPremium = householdStore?.currentHousehold?.isPremium ?? false
        recomputePremiumState()
    }

    private func apply(customerInfo: CustomerInfo) async {
        hasRevenueCatEntitlement = customerInfo.entitlements.all[Constants.entitlementID]?.isActive == true
        if let userSession,
           userSession.isAuthenticated,
           let appUserID = userSession.userId
        {
            currentRevenueCatAppUserID = appUserID
        }
        lastErrorMessage = nil
        await propagatePremiumToCurrentHouseholdIfNeeded()
        syncHouseholdPremiumFromStore()
        recomputePremiumState()
    }

    private func propagatePremiumToCurrentHouseholdIfNeeded() async {
        guard hasRevenueCatEntitlement,
              let userSession,
              userSession.syncMode == .cloud,
              let userId = userSession.userId,
              let householdStore,
              let household = householdStore.currentHousehold,
              !household.isPremium
        else {
            return
        }

        do {
            try await householdStore.syncCurrentHouseholdPremiumStatus(true, userId: userId)
        } catch {
            lastErrorMessage = "Subscription activated, but household premium sync failed."
            print("[SubscriptionManager] Failed to sync household premium state: \(error)")
        }
    }

    private func recomputePremiumState() {
        isPremium = developerPremiumOverride || hasRevenueCatEntitlement || hasHouseholdPremium
    }
}

extension SubscriptionManager: PurchasesDelegate {
    nonisolated func purchases(_: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        _ = _Concurrency.Task { @MainActor in
            await apply(customerInfo: customerInfo)
        }
    }
}
