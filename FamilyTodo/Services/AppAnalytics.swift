import Foundation
import PostHog

enum AppAnalytics {
    static func identifyUser(_ userId: String, sessionMode: SessionMode, displayName: String? = nil, hasConfirmedDisplayName: Bool? = nil) {
        var properties: [String: Any] = [
            "session_mode": sessionMode.analyticsValue,
        ]
        if let displayName {
            properties["display_name"] = displayName
        }
        if let hasConfirmedDisplayName {
            properties["has_confirmed_display_name"] = hasConfirmedDisplayName
        }

        PostHogSDK.shared.identify(userId, userProperties: properties)
    }

    static func capture(_ event: String, properties: [String: Any] = [:], sessionMode: SessionMode? = nil, syncMode: SyncMode? = nil, householdId: UUID? = nil) {
        PostHogSDK.shared.capture(
            event,
            properties: enrichedProperties(
                properties,
                sessionMode: sessionMode,
                syncMode: syncMode,
                householdId: householdId
            )
        )
    }

    static func screenViewed(_ screen: AppScreen, sessionMode: SessionMode, syncMode: SyncMode, householdId: UUID?) {
        let properties = enrichedProperties(
            [
                "$screen_name": screen.rawValue,
                "screen_name": screen.rawValue,
                "screen_area": screen.area,
            ],
            sessionMode: sessionMode,
            syncMode: syncMode,
            householdId: householdId
        )

        PostHogSDK.shared.capture("$screen", properties: properties)
        PostHogSDK.shared.capture("app_screen_viewed", properties: properties)
    }

    static func onboardingStarted(sessionMode: SessionMode) {
        capture("onboarding_started", sessionMode: sessionMode)
        captureActivationMilestone("onboarding_started", sessionMode: sessionMode)
    }

    static func activationMilestone(_ milestone: ActivationMilestone, sessionMode: SessionMode? = nil, syncMode: SyncMode? = nil, householdId: UUID? = nil, properties: [String: Any] = [:]) {
        captureActivationMilestone(
            milestone.rawValue,
            sessionMode: sessionMode,
            syncMode: syncMode,
            householdId: householdId,
            properties: properties
        )
    }

    static func firstValueCompleted(source: FirstValueSource, syncMode: SyncMode, householdId: UUID?) {
        guard markOnce(key: "first_value_completed") else { return }
        let properties: [String: Any] = ["source": source.rawValue]
        capture(
            "first_value_completed",
            properties: properties,
            syncMode: syncMode,
            householdId: householdId
        )
        captureActivationMilestone(
            "first_value_completed",
            syncMode: syncMode,
            householdId: householdId,
            properties: properties
        )
    }

    private static func captureActivationMilestone(_ milestone: String, sessionMode: SessionMode? = nil, syncMode: SyncMode? = nil, householdId: UUID? = nil, properties: [String: Any] = [:]) {
        var milestoneProperties = properties
        milestoneProperties["milestone"] = milestone
        capture(
            "activation_milestone_completed",
            properties: milestoneProperties,
            sessionMode: sessionMode,
            syncMode: syncMode,
            householdId: householdId
        )
    }

    private static func enrichedProperties(_ properties: [String: Any], sessionMode: SessionMode?, syncMode: SyncMode?, householdId: UUID?) -> [String: Any] {
        var enriched = properties
        if let sessionMode {
            enriched["session_mode"] = sessionMode.analyticsValue
        }
        if let syncMode {
            enriched["sync_mode"] = syncMode.analyticsValue
        }
        if let householdId {
            enriched["household_id"] = householdId.uuidString
            enriched["has_household"] = true
        } else {
            enriched["has_household"] = false
        }
        return enriched
    }

    private static func markOnce(key: String) -> Bool {
        let defaultsKey = "analytics.\(key).tracked"
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return false }
        UserDefaults.standard.set(true, forKey: defaultsKey)
        return true
    }
}

struct RootAnalyticsTracker {
    private var lastScreen: AppScreen?

    mutating func track(state: LaunchState, sessionMode: SessionMode, syncMode: SyncMode, householdId: UUID?) {
        guard let screen = rootScreen(for: state) else { return }
        guard lastScreen != screen else { return }

        lastScreen = screen
        AppAnalytics.screenViewed(
            screen,
            sessionMode: sessionMode,
            syncMode: syncMode,
            householdId: householdId
        )

        if screen == .onboarding {
            AppAnalytics.onboardingStarted(sessionMode: sessionMode)
        }
    }

    private func rootScreen(for state: LaunchState) -> AppScreen? {
        switch state {
        case .onboarding:
            .onboarding
        case .auth:
            .signIn
        case .householdSetup:
            .householdSetup
        case .mainApp:
            nil
        }
    }
}

enum AppScreen: String {
    case onboarding = "Onboarding"
    case signIn = "Sign In"
    case householdSetup = "Household Setup"
    case shopping = "Shopping"
    case tasks = "Tasks"
    case ideas = "Ideas"
    case more = "More"

    var area: String {
        switch self {
        case .onboarding, .signIn, .householdSetup:
            "onboarding"
        case .shopping, .tasks, .ideas:
            "core"
        case .more:
            "settings"
        }
    }
}

enum ActivationMilestone: String {
    case signedIn = "signed_in"
    case householdCreated = "household_created"
    case householdJoined = "household_joined"
    case shoppingItemAdded = "shopping_item_added"
    case taskCreated = "task_created"
    case ideaAdded = "idea_added"
}

enum FirstValueSource: String {
    case shoppingItem = "shopping_item"
    case task
    case idea
}

extension SessionMode {
    var analyticsValue: String {
        switch self {
        case .signedOut:
            "signed_out"
        case .guest:
            "guest"
        case .signedIn:
            "icloud"
        }
    }
}

extension SyncMode {
    var analyticsValue: String {
        switch self {
        case .localOnly:
            "local"
        case .cloud:
            "cloud"
        }
    }
}

extension AppTab {
    var analyticsScreen: AppScreen {
        switch self {
        case .shopping:
            .shopping
        case .tasks:
            .tasks
        case .backlog:
            .ideas
        case .more:
            .more
        }
    }
}
