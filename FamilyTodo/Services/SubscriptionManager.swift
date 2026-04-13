import Foundation
import RevenueCat

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
    @Published var lastErrorMessage: String?

    private weak var userSession: UserSession?
    private weak var householdStore: HouseholdStore?
    private let userDefaults: UserDefaults
    private var currentRevenueCatAppUserID: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        developerPremiumOverride = userDefaults.bool(forKey: Constants.developerPremiumOverrideKey)
        super.init()
        Purchases.shared.delegate = self
        recomputePremiumState()
    }

    func connect(
        userSession: UserSession,
        householdStore: HouseholdStore
    ) async {
        self.userSession = userSession
        self.householdStore = householdStore
        syncHouseholdPremiumFromStore()
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
        do {
            currentOffering = try await Purchases.shared.offerings().current
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Unable to load subscription options."
            print("[SubscriptionManager] Offerings refresh failed: \(error)")
        }
    }

    func refreshCustomerInfo() async {
        isLoading = true
        defer { isLoading = false }
        await checkEntitlement()
        syncHouseholdPremiumFromStore()
    }

    func checkEntitlement() async {
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
        lastErrorMessage = nil

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

    func handlePurchaseCompleted(customerInfo: CustomerInfo) {
        Task { @MainActor in
            await apply(customerInfo: customerInfo)
        }
    }

    func handleRestoreCompleted(customerInfo: CustomerInfo) {
        Task { @MainActor in
            await apply(customerInfo: customerInfo)
        }
    }

    private func syncRevenueCatIdentity() async {
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
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            await apply(customerInfo: customerInfo)
        }
    }
}
