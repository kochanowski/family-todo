# Dwello / HousePulse Monetization & Paywall Strategy

## 1. Product Philosophy
Based on `AGENTS.md` rules: "no pressure mechanics", "low-friction", "shared-first".
We use a **Freemium model with a 14-day Free Trial**.
- **No Hard Paywalls:** Do not block access to the app completely when the trial expires.
- **Graceful Downgrade:** After the trial, users revert to the Free tier. They keep their data but lose access to premium aesthetics and advanced/power-user features.
- **Contextual Paywalls:** Display the paywall when a user attempts to use a premium feature or exceed a free tier limit, rather than at random times.

## 2. Onboarding & Trial Flow
1. **Soft Paywall at Onboarding:** At the end of the initial onboarding/setup flow, present a "Soft Paywall" offering a 14-day free trial of Dwello Plus. Ensure there is a clear "Skip" or "X" button so users aren't forced to subscribe.
2. **Apple Managed Trial:** The 14-day trial is configured via App Store Connect (Introductory Offer) and RevenueCat. The app does not need custom date-math logic for this; RevenueCat's `isPremium` flag will automatically handle the trial period and expiration.

## 3. Feature Breakdown

### 🆓 Free Tier (Core Functionality)
The Free tier must be highly functional for a standard couple/pair.
- **Household Members:** Up to 2 people per household (Owner + 1 Participant).
- **Categories (Backlog/Ideas):** Maximum of 4 categories.
- **Tasks:** Unlimited tasks within those categories. (WIP limit of 3 in `.next` still applies as per AGENTS.md).
- **Shopping:** Standard shared shopping list (including "recently purchased").
- **Themes:** Standard System themes (Light, Dark).
- **Notifications:** Standard push notifications.
- **Task History:** Standard history access.

### 💎 Premium Tier (Dwello Plus)
Aesthetics, advanced organization, and scalability.
- **Household Members:** Unlimited (or >2, suitable for families/roommates).
- **Categories:** Unlimited categories in Backlog/Ideas.
- **Themes:** Premium themes (Retro, Paper).
- **Color Schemes:** Custom accent color choices.
- **Shopping:** Shopping Bundles (saved quick-add bundles).
- **Future Features:** Live Shopping Mode (v2.0), Chores Rotation (recurring tasks), "Poke" feature.

## 4. Implementation Guide for Agents

When implementing these limits in the codebase, follow these technical directives:

### 4.1 State Management
- Use `SubscriptionManager` (e.g. `premiumSubscriptionManager.isPremium` injected via `@EnvironmentObject`) to check the current tier.
- Do NOT perform manual date checking for the trial. Rely entirely on RevenueCat's `CustomerInfo` and the `SubscriptionManager`.

### 4.2 Contextual Triggers (Paywall Presentation)
- **Themes:** When a Free user clicks on a Premium theme in `SettingsView`, set `$premiumSubscriptionManager.displayPaywall = true`.
- **Categories:** In `BacklogStore` or `CategoriesManagementView`, intercept the action if `categories.count >= 4` and `!isPremium`. Show a contextual alert explaining the limit, with an "Upgrade" button that triggers `displayPaywall = true`.
- **Household Size:** Prevent generating an invite code or accepting a 3rd member if `members.count >= 2` and `!isPremium`.
- **Shopping Bundles:** Block the creation or use of `ShoppingBundle`s if `!isPremium`.

### 4.3 Graceful Downgrade Logic
When a user goes from Premium -> Free (e.g., trial expires or subscription cancelled):
- **Themes:** If the selected theme is "Retro" or "Paper", the app must safely fallback to the "System" theme upon launch. Update `ThemeStore` to validate `isPremium` on init/load.
- **Categories:** If they have 6 categories, **do not delete them**. Allow them to view and manage tasks inside all 6 categories. However, block the creation of *new* categories.
- **Members:** If they have 4 members, **do not kick anyone out**. The household continues to function. However, block inviting any *new* members until they upgrade again.

### 4.4 Soft Paywall Implementation
- Inject a step at the end of the `OnboardingView` or right after the user signs in / creates a household.
- Display the `PaywallView` from RevenueCatUI, ensuring it provides a dismiss/skip mechanism so it doesn't become a hard blocker.
