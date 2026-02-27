Act as an expert iOS Developer and Software Architect. We need to build the core navigation, onboarding, and authentication flow for our household management app. 

Please implement this complete flow using modern SwiftUI, clean MVVM architecture, and a central App State router. Use placeholders for complex backend logic (like actual database sync or camera AVFoundation setup), but the UI, navigation, and state transitions must be fully functional.

### The App Routing Flow
The root `App` struct should use an `AppState` enum or similar routing logic to manage these states:
1. `onboarding` (First launch only)
2. `auth` (Sign in or Guest choice)
3. `householdSetup` (Create or Join)
4. `mainApp` (The actual app tabs)

---

### Part 1: Premium Onboarding Carousel (State: `onboarding`)
Show this ONLY on the first app launch (use `@AppStorage("hasSeenOnboarding")`).
- Use a `TabView` with `.tabViewStyle(.page)`.
- **Slide 1:** Title: "Smart Shopping", Subtitle: "Shared lists, instant restock, and live notifications when someone adds an item.", Icon: `cart.fill`
- **Slide 2:** Title: "Clear Your Mind", Subtitle: "Turn loose ideas into actionable tasks. Keep your household organized without the stress.", Icon: `lightbulb.fill`
- **Slide 3:** Title: "Make It Yours", Subtitle: "Personalize your experience with beautiful themes, from elegant Dark mode to nostalgic Retro.", Icon: `paintpalette.fill`
- **Slide 4:** Title: "Better Together", Subtitle: "Invite your family, sync instantly, and share the mental load of household management.", Icon: `person.2.fill`
- **UI:** Large SF Symbol placeholder at the top, Title, Subtitle. A "Skip" button at the top trailing. A primary bottom button ("Next" for 1-3, "Get Started" for 4). "Get Started" or "Skip" transitions the state to `auth`.

---

### Part 2: Authentication & Guest Mode (State: `auth`)
We use a "Deferred Onboarding" approach.
- **UI:** A beautiful welcome screen with two main buttons:
  1. **"Sign in with Apple"** (Primary button). On success, sets `isAuthenticated = true` and transitions to `householdSetup`.
  2. **"Try without an account"** (Secondary/Ghost button). Sets user as a Guest and transitions directly to `mainApp`.
- **Guest Upgrade:** Inside the `mainApp` (e.g., in the "More" tab), add a prominent banner: "Unlock syncing & sharing. Sign in with Apple." Clicking this triggers the Apple Sign-In flow, and upon success, takes the user to `householdSetup`.

---

### Part 3: Household Setup (State: `householdSetup`)
Shown immediately after a successful Apple Sign-In if the user doesn't belong to a Household yet.
- **UI:** A screen asking "Let's set up your space" with two large, distinct cards/buttons:
  1. **[+] Create a Household:** Prompts for a name, creates it, and transitions to `mainApp`.
  2. **[🤝] Join a Household:** Navigates to the Join Screen.

### Part 4: The "Join Household" Screen
This screen must support 3 methods of joining. Build the UI layout for all three:
1. **QR Code (Top Half):** A camera viewfinder placeholder (e.g., a rounded rectangle with a camera icon and corner brackets) with the text "Scan QR Code".
2. **Invite Code (Bottom Half):** A `TextField` for entering a short alphanumeric code (e.g., 6 chars), with a "Join" button next to it.
3. **Universal Link (Background):** Add an `.onOpenURL { url in ... }` modifier to handle deep links (e.g., `housepulse://join/12345`). If a link is caught, it should bypass the manual entry and show a confirmation alert: "Join this household?".

Please provide the SwiftUI code for this entire routing architecture, the views, and the view models needed to make this flow work seamlessly.