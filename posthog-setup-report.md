<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into the Dwello (HousePulse) iOS app. The integration covers the full user lifecycle — from sign-in and household setup to day-to-day task management, shopping, and premium conversion — giving you clear visibility into how households engage with your app.

## Changes summary

**Package installation**: PostHog iOS SDK (`posthog-ios`, version ≥ 3.58.0) added to `FamilyTodo.xcodeproj/project.pbxproj` via Swift Package Manager. The scheme's Run environment variables (`POSTHOG_PROJECT_TOKEN`, `POSTHOG_HOST`) are set for local development.

**Initialization**: `FamilyTodoApp.swift` initializes PostHog in `init()` using a `PostHogEnv` enum that reads from `ProcessInfo.processInfo.environment`. SDK is guarded with `#if !CI` to avoid test pollution. `captureApplicationLifecycleEvents` is enabled.

**User identification**: On iCloud sign-in, `PostHogSDK.shared.identify()` is called with the CloudKit user ID. On guest session start, the guest ID is used as the distinct ID. `PostHogSDK.shared.reset()` is called on sign-out to unlink events from the user.

## Events instrumented

| Event | Description | File |
|---|---|---|
| `user_signed_in` | User authenticates with iCloud/Apple ID | `FamilyTodo/Services/UserSession.swift` |
| `guest_session_started` | User starts a local-only guest session | `FamilyTodo/Services/UserSession.swift` |
| `user_signed_out` | User signs out or ends their session | `FamilyTodo/Services/UserSession.swift` |
| `household_created` | User creates a new household (cloud or local) | `FamilyTodo/Stores/HouseholdStore.swift` |
| `household_joined` | User joins a household via invite code | `FamilyTodo/Stores/HouseholdStore.swift` |
| `household_left` | User leaves the current household | `FamilyTodo/Stores/HouseholdStore.swift` |
| `task_created` | A new task is created and assigned | `FamilyTodo/Stores/TaskStore.swift` |
| `task_completed` | A task is marked as done | `FamilyTodo/Stores/TaskStore.swift` |
| `idea_added` | A new idea/backlog item is added | `FamilyTodo/Stores/BacklogStore.swift` |
| `idea_promoted_to_task` | A backlog idea is promoted into an active task | `FamilyTodo/Stores/BacklogStore.swift` |
| `shopping_item_added` | A new item is added to the shopping list | `FamilyTodo/Stores/ShoppingListStore.swift` |
| `shopping_list_cleared` | Checked-off shopping items are cleared | `FamilyTodo/Stores/ShoppingListStore.swift` |
| `premium_upsell_viewed` | Premium upsell sheet is shown for a feature | `FamilyTodo/Services/SubscriptionManager.swift` |
| `premium_paywall_opened` | Full RevenueCat paywall is opened | `FamilyTodo/Services/SubscriptionManager.swift` |

## Files changed

- `FamilyTodo.xcodeproj/project.pbxproj` — PostHog SPM package reference, product dependency, and build file added
- `FamilyTodo.xcodeproj/xcshareddata/xcschemes/HousePulse.xcscheme` — `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` env vars added to Run action
- `.env` — PostHog token and host recorded (gitignored)
- `FamilyTodo/FamilyTodoApp.swift` — `PostHogEnv` enum + SDK initialization
- `FamilyTodo/Services/UserSession.swift` — identify on sign-in, reset on sign-out, guest session tracking
- `FamilyTodo/Stores/HouseholdStore.swift` — household_created, household_joined, household_left
- `FamilyTodo/Stores/TaskStore.swift` — task_created, task_completed
- `FamilyTodo/Stores/BacklogStore.swift` — idea_added, idea_promoted_to_task
- `FamilyTodo/Stores/ShoppingListStore.swift` — shopping_item_added, shopping_list_cleared
- `FamilyTodo/Services/SubscriptionManager.swift` — premium_upsell_viewed, premium_paywall_opened

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics dashboard](https://eu.posthog.com/project/186243/dashboard/702052)
- [User Onboarding Funnel](https://eu.posthog.com/project/186243/insights/MJSl5l9z) — sign-in → household created conversion
- [Daily Active Users](https://eu.posthog.com/project/186243/insights/Bj7uUErh) — signed-in vs guest DAU
- [Task Completion vs Ideas Promoted](https://eu.posthog.com/project/186243/insights/y6rxQhEE) — household productivity signals
- [Premium Upsell to Paywall Conversion](https://eu.posthog.com/project/186243/insights/qPXuQ2Lb) — monetization funnel
- [Shopping Activity](https://eu.posthog.com/project/186243/insights/lOR8aXqI) — items added and lists cleared

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-swift/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
