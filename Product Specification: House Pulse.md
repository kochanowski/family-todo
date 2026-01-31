Product Specification: House Pulse (iOS)
1. App Overview
App Name: House Pulse (Internal Working Title)
Purpose: A high-fidelity, shared home management application designed for couples and families to synchronize daily chores, shopping needs, and long-term projects.
Target Audience: Couples and small families living together who value minimalism and efficiency.
Core Value Proposition: Information density, speed of entry, and clear separation of concerns (Shopping vs. Daily Tasks vs. Long-term Backlog).
High-Level Structure: Single-window application with a persistent floating bottom navigation bar containing four distinct tabs.
2. Global UI & Design Rules
Aesthetic: "Premium Minimalist." Uses native iOS conventions but elevated with custom spacing and subtle glassmorphism.
Typography:
Font: Inter (or San Francisco).
Philosophy: Small, dense, legible.
Headers: Bold, tight tracking.
Body: 14pt-15pt for list items, maximizing rows visible per screen.
Secondary Text: 10pt-12pt, muted colors (gray/secondary label).
Layout:
Edge-to-Edge: Content flows behind the status bar and bottom navigation.
Floating Tab Bar: A custom pill-shaped container floating ~24pt above the bottom safe area, distinct from the standard iOS tab bar.
Glassmorphism: Used on the Tab Bar and Toast notifications (blur + translucency).
Motion & Transitions:
Tab Switching: Transitions between tabs must NOT be instantaneous.
Fade-In Animation: When changing tabs, the new screen enters with a subtle, elegant animation:
Opacity: 0% → 100%
Scale: 99% → 100% (very slight zoom in)
Blur: 2px → 0px (comes into focus)
Duration: ~0.3s with a cubic-bezier easing for a smooth, organic feel.
Dark Mode: Full support required.
Light Mode: Off-white backgrounds (#F9F9F9), white cards.
Dark Mode: Pure black backgrounds, dark gray cards (#1C1C1E).
3. Data Model (Conceptual)
The app relies on a shared state model accessible across tabs.
Entities
ShoppingItem
id: Unique Identifier
text: String (Name of item)
isCompleted: Boolean
state: Enum (Active, RestockPool, Deleted)
Task (TodoItem)
id: Unique Identifier
title: String
isCompleted: Boolean
assignee: User (Optional)
dueDate: Date/String (Optional)
BacklogCategory (Section)
id: Unique Identifier
title: String (e.g., "Home Projects")
items: List of Tasks
User / Member
name: String (e.g., "Anna", "Tom")
initials: String
color: Theme color for UI avatars
AppTheme
mode: Light, Dark, or System
4. Screen-by-Screen Breakdown
4.1 Shopping List Tab
Purpose: Quick capture and management of groceries and household essentials.
Layout:
Top: Header with Title ("Shopping"), Item Count Badge, Action Buttons (Clear All, Restock).
Body: Scrollable list of active items.
Bottom: Floating "Add Item" input row (above tab bar context).
Components:
Row: Minimalist row. Left: Circular Checkbox. Center: Text.
Input: Text field that remains active after "Enter" is pressed to allow rapid-fire entry of multiple items.
Transitions:
Checking an item triggers an immediate animation: the item disappears from the list and moves to the "Restock" pool.
4.2 Tasks Tab (Todo List)
Purpose: Daily chores and immediate to-dos.
Layout:
Top: Header ("Tasks").
Banner: "Focus Rule" info banner (Blue, rounded) informing users of the "Max 3 active tasks" philosophy.
Body: Split list: "Active" items at top, "Completed" items at bottom (grouped).
Components:
Task Row:
Left: Checkbox (Square/Rounded Square).
Center: Title + Metadata Row.
Metadata: Due date (Orange if Today) • Assignee Pill (Gray background).
Right: None (Clean edge).
Behavior:
Tapping a task toggles its state between Active and Completed.
Completed tasks move to the bottom section with strikethrough text.
4.3 Backlog Tab
Purpose: Long-term storage for ideas and projects, categorized to avoid cluttering the daily task list.
Layout:
Top: Header ("Backlog").
Body: List of Categories, not just flat tasks.
Empty State: If no categories exist, show a prompt directing user to the "More" tab to manage categories.
Components:
Category Card: A grouped inset list (rounded container).
Header: Category Title (small caps, gray).
Rows: List of items inside.
Footer: "Add item" button specific to that category.
Backlog Item Row: Dot indicator (visual only), Text, Chevron (indicating detail view or action).
4.4 More Tab
Purpose: Hub for settings, profile management, and global data configuration (like Backlog Categories).
Layout:
Top: Header ("More").
Body: Grouped inset lists (Settings-style).
Menu Options:
Profile Card: Shows "Anna & Tom", plan details. Tapping opens Profile Detail.
Backlog Categories: Opens Category Management.
Repetitive Tasks: Opens Recurring Task manager.
Settings: Opens App Settings.
5. Shopping List – Detailed Logic
The Cycle of Items:
Active: Item is in the main list.
Bought (Checked): User taps checkbox. Item vanishes from main list and enters RestockPool.
Restock (Recovery):
User taps the "Refresh" (Cycle) icon in the header.
A modal/sheet slides up showing "Recently Purchased" (The Restock Pool).
User taps a "+" icon next to a restock item.
Item moves back to the Active list.
Mental Model: "I bought Milk (check). Next week, I need Milk again (Restock -> Add)."
Clear All / Undo:
Tapping "Trash" clears the visible list.
A "Toast" notification appears at the bottom with an "Undo" button for 4 seconds.
If Undo is pressed, state reverts.
6. Tasks Screen – Detailed Logic
Visual Hierarchy:
Active tasks have high contrast (Black/White text).
Completed tasks have low contrast (Gray text, strikethrough) and sit at the bottom under a small "Completed" header.
Assignee logic: Tasks assigned to "Me" or specific names ("Tom") show a small pill badge. "Today" dates are highlighted in Orange/Red to induce urgency.
7. Backlog – Detailed Logic
Category-First Architecture:
Items cannot exist outside a Category.
Items here are for storage. They are not "active" daily tasks.
Navigation: Changes to the structure of the backlog (adding/removing categories) happen in the More tab, but the content (adding items to a category) happens here in the Backlog tab.
8. More Screen – Functionality & Sub-screens
8.1 Profile Screen
Data: Display household name ("Smith Family Home"), Members list ("Anna", "Tom").
Edit Mode: Members can be removed (Trash icon).
8.2 Backlog Categories Management
List: Shows all current categories (e.g., Home Projects, Vacation).
Add: Input field at bottom to create a new Category.
Delete: Trash icon on rows.
Validation Rule: If a category has items inside, the app MUST show a confirmation modal ("Delete Category? This contains active items.") before deletion. If empty, delete immediately.
State Sync: Changes here immediately reflect on the main Backlog tab.
8.3 Settings
Appearance: 3-way toggle (Light / Dark / System). Changing this forces the app UI to update immediately.
Toggles: Simple booleans for "Celebrations" (confetti effects) and "Suggestions".
9. Navigation & State Management
Navigation Stack:
The Root view is the Custom Bottom Tab Bar.
The "More" tab operates as a NavigationStack. Tapping a menu item pushes a new view (Profile, Settings, etc.) while hiding or keeping the bottom tab bar.
"Shopping" Restock view is a Sheet/Modal (slides up over context).
Animation State:
The root view must track the activeTab.
Upon activeTab changing, the render key for the content view changes, triggering the fadeIn CSS animation defined in Global Rules.
Persistence:
All lists (Shopping, Tasks, Backlog Categories/Items) should be stored in a persistent store.
Theme selection must persist.
10. Implementation Notes for SwiftUI Agent
Shared State (@EnvironmentObject / @Observable):
BacklogContext: Must be shared between BacklogScreen (to display items) and MoreScreen -> BacklogCategoriesView (to manage sections).
ThemeContext: Must wrap the root view to inject color schemes dynamically.
Custom Components:
BottomNav: Do not use the native TabView. Construct a ZStack with the content views and a custom overlay for the floating pill bar.
StatusBar: Since this is a custom non-standard UI, a custom Status Bar component is overlayed at the top ZStack level.
Interaction Details:
Animations: Use explicit transition modifiers (.transition(.opacity.combined(with: .scale))) when switching tabs to match the specified fade/scale/blur behavior.
Haptics: Implicitly required for a "premium" feel on check actions.
Data Constraints:
Ensure "Anna & Tom" is hardcoded as the default profile state.
Ensure quantity is removed from the Shopping List UI (name only).
lightbulb_tips
