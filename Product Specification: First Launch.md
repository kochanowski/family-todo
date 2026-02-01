Product Specification: First Launch & Onboarding Experience
App Name: FamilySync (Internal Working Title)
Role: iOS Product Design Lead
Status: Approved for Implementation
A. Flow Overview (State Machine)
The app launch logic is governed by a persistent state machine.
State: FirstLaunch (Default)
Trigger: App opens, no local flags found (hasCompletedOnboarding == false).
View: OnboardingCarouselView.
Action: User taps "Get Started" on the final slide → Transitions to SyncChoice.
State: SyncChoice
View: SyncSelectionView.
Action A: User selects "Sync with iCloud" → Sets syncMethod = .iCloud → Transitions to HouseholdSetup.
Action B: User selects "Continue as Guest" → Sets syncMethod = .local → Transitions to HouseholdSetup.
State: HouseholdSetup
View: CreateHouseholdView.
Action A: User inputs name & creates → Sets householdId → Transitions to MainApp.
Action B: User selects "Join" → Inputs code → Sets householdId → Transitions to MainApp.
Action C: User taps "Skip" → Sets householdStatus = .none → Transitions to MainApp.
State: MainApp (Active)
Condition: If householdStatus == .none, tabs display GuidedEmptyStateView.
Condition: If householdStatus == .active, tabs display live content.
B. Onboarding Screens
Layout Strategy:
Full-screen paging view.
Content anchored to the bottom 40% of the screen.
Large, minimalist SF Symbol iconography floating in the center (glassmorphic container).
Slide 1: Synchronize
Icon: Cloud (Symbol) inside a frosted glass squircle.
Headline: Sync your home.
Subtext: Keep your shopping lists and daily tasks perfectly in sync with your partner.
Slide 2: Shop & Restock
Icon: ShoppingBasket (Symbol).
Headline: Never forget the milk.
Subtext: Items move to 'Restock' when checked, ready to be added back for the next trip.
Slide 3: Plan Ahead
Icon: Layers (Symbol).
Headline: Dream together.
Subtext: A dedicated backlog for home projects, vacations, and gift ideas.
Primary Action: "Get Started" button (Pill shape, solid, appears only on this slide).
C. Onboarding Backgrounds
This section defines the "Aurora" background system. Each background consists of 3-4 large, blurred colored orbs moving slowly in a ZStack behind a frosted glass overlay.
Shared Technical Specs
Blur Radius: 60pt - 100pt (Heavy diffusion).
Animation: Slow breathing (scale up/down) and slight rotation.
Overlay: A ThinMaterial or white/black layer with 10% opacity to unify the colors.
Background 1: "Calm Sync" (Slide 1)
Concept: Technology meeting tranquility. Represents the cloud and data stability.
Mood: Trustworthy, airy, frictionless.
Palette:
Orb 1 (Top Left): Indigo-300 (Light Mode) / Indigo-900 (Dark Mode).
Orb 2 (Bottom Right): Blue-300 / Blue-900.
Orb 3 (Center, low opacity): Sky-200 / Sky-800.
Rationale: Blue tones evoke stability and communication.
Background 2: "Fresh Action" (Slide 2)
Concept: Fresh groceries, vitality, checking things off.
Mood: Energetic, organic, crisp.
Palette:
Orb 1 (Top Right): Emerald-300 / Emerald-900.
Orb 2 (Bottom Left): Teal-300 / Teal-900.
Orb 3 (Center): Green-100 / Green-900.
Rationale: Greens suggest freshness (groceries) and productivity ("Go").
Background 3: "Warm Dreams" (Slide 3)
Concept: Sunsets, comfort, future planning, warmth of home.
Mood: Cozy, aspirational, emotional.
Palette:
Orb 1 (Top Left): Orange-300 / Orange-900.
Orb 2 (Bottom Right): Rose-300 / Rose-900.
Orb 3 (Bottom Center): Amber-200 / Amber-900.
Rationale: Warm tones evoke the feeling of "Home" and "Family."
D. Sync Choice Screen
Layout: Clean, centered card layout or bottom sheet.
Header: "Choose how to save."
Subheader: "Select where your data lives."
Option A (Primary - Card Style)
Visual: Large tappable card with an iCloud icon in a blue rounded square.
Headline: Sync with iCloud
Body: Seamlessly share data across devices. No new passwords required.
Badge: "Recommended" (Small capsule, top right of card).
Action: Tapping triggers system prompt (if needed) -> Transitions to Household Setup.
Option B (Secondary - Text Button)
Visual: Simple row with a User icon.
Headline: Continue as Guest
Body: Data is saved only on this device.
Action: Tapping immediately transitions to Household Setup.
E. Household Setup Screen
Purpose: Establish the shared identity.
Layout: Form-focused. Keyboard automatically opens.
UI Components
Nav Bar: "Skip" button (Top Right, System Gray).
Header: "Name your household."
Input Field: Large text (Title size). Placeholder: "e.g. Smith Family".
Helper Text: "This name will be visible to members you invite."
Main Action: "Create Household" (Solid Button, disabled if input is empty).
Secondary Action: "Have an invite code? Join Household" (Bottom text link).
F. Empty States Behavior
If the user taps "Skip" during Household Setup, they enter the MainApp. The app must not look broken.
The Guided Empty State (Component):
Replaces the list view in Shopping, Tasks, and Backlog.
Illustration: A large, thin-stroke icon (House or Users) inside a circle with a subtle shadow.
Headline: No Household Active
Body: "To share shopping lists and tasks, you need to create or join a household."
Button 1 (Primary): "Create Household" -> Opens the Setup Modal.
Button 2 (Secondary): "Join Existing" -> Opens Join Modal.
G. UX & iOS Best Practices Summary
Permissions Strategy:
Notification: DO NOT ask on launch. Ask only when the user sets a due date on a task or enables "Celebrations" in settings.
Location: Ask only if they use a location-based reminder (future feature).
Transitions:
Onboarding: Smooth parallax (text moves slower than background).
Color Shift: The background gradients should cross-dissolve smoothly as the user swipes between slides.
Haptics:
Light .selection haptic on slide changes.
.success haptic when "Create Household" is tapped.
Resumability:
If the user force-quits during HouseholdSetup, the app should re-launch directly to that screen, not the start of onboarding.
H. Implementation Notes (Conceptual)
Background Implementation: Use SwiftUI Circle().blur(radius: 80) inside a ZStack. Animate the fill color and offset based on the tabSelection index of the TabView.
Glassmorphism: Use .background(.ultraThinMaterial) for the icon containers in the onboarding carousel to allow the colored orbs to bleed through.
Dark Mode: Ensure the orb colors in Dark Mode are deeper/saturated (e.g., Indigo-900 instead of Indigo-300) to prevent the screen from looking "muddy" or too bright.
Text Contrast: Since backgrounds are colorful, ensure text has a distinct weight (Semibold) or a subtle shadow if readability is low (though soft pastel backgrounds usually allow black text in light mode).