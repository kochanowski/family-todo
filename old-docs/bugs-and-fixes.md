Act as an expert iOS Developer and UX Designer. I have thoroughly tested the app and found a few UI/UX areas that need refinement, a regression bug, and a critical CloudKit database error. Please implement the following 6 fixes:

### 1. Fix CloudKit SharedDB Error (CRITICAL)
In the screenshots, there is an error: "Action failed: SharedDB does not support Zone Wide queries". 
- **Fix:** You are likely performing a `CKQueryOperation` on the `sharedCloudDatabase` without specifying a `zoneID`. Shared databases require queries to be scoped to a specific `CKRecordZone.ID`. Please update the CloudKit manager/service to properly scope queries in the shared database to the correct zone.

### 2. User Profile & "Guest" Logic
- When a user is not signed in, their display name should default to "Guest".
- **Fix:** After a user successfully signs in with Apple OR joins/creates a household, prompt them to set a "Display Name" (Nickname). This ensures we don't rely solely on Apple's one-time name payload and avoids duplicate names in the household.

### 3. Household Creation & "More" Tab Redesign
- **Creation:** When creating a Household, allow the user to select an Icon from a predefined list of 5 simple, black-and-white SF Symbols (e.g., `house.fill`, `star.fill`, `heart.fill`, `leaf.fill`, `pawprint.fill`) along with the Name.
- **More Tab UI:** The current Household banner in the "More" tab is too small and left-aligned. Redesign it to be a large, premium, centered header. Show the selected SF Symbol prominently above the centered Household Name.
- **Inline Rename:** In the Profile/Household settings, remove the dedicated "Rename Household" button. Instead, make the Household Name itself a `TextField` so the user can tap it and edit it inline seamlessly.

### 4. Fix Font in "Recently Purchased" Sheet
- The `RecentlyPurchasedView` (sheet) is ignoring the custom fonts in the "Retro" and "Paper" themes and defaulting to the iOS system font.
- **Fix:** Explicitly apply the `themeStore.font(...)` modifiers to the texts, lists, and empty states inside the `RecentlyPurchasedView`.

### 5. Remove "Ideas" from "Tasks" Tab (Regression Bug)
- The "Ideas" list is currently rendering at the bottom of the "Tasks" tab. This is a regression.
- **Fix:** Remove the Ideas section completely from `TasksView`. The Tasks tab should ONLY show Active and Completed tasks. Ideas belong exclusively in the Ideas tab.

### 6. Progressive Disclosure in Ideas Tab
- Currently, the "Send to Tasks" (Up Arrow) icon is visible even if no one is assigned to the idea.
- **Fix:** Hide the "Up Arrow" icon completely if `item.assignee == nil`. The user should only see the `+` (Assign) and `Trash` icons initially. Once an assignee is selected, the "Up Arrow" should appear (preferably with a smooth `.transition(.scale)` or `.opacity` animation).