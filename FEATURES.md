Act as a Senior iOS Developer, UX Expert, and CloudKit/SwiftData Architect. I am building an iOS app called "HousePulse" for household management. You have full access to my entire codebase.

I have a roadmap of 6 major features and UX improvements to implement. I want to build these step-by-step to ensure high code quality and proper data modeling.

Here is the complete roadmap. Please read it to understand the context, but **only implement the parts I specifically ask for in my subsequent messages** (or if I ask you to start with Part 1 now).

### Part 1: Engaging Empty States
**Goal:** Replace blank screens with iOS 17 `ContentUnavailableView`.
**Requirements:**
*   Check the `Shopping`, `Tasks`, and `Ideas` views.
*   If the list is empty, display a `ContentUnavailableView`.
*   Use appropriate SF Symbols (e.g., a cart for shopping, a checklist for tasks, a lightbulb for ideas).
*   Include a catchy title (e.g., "Your list is empty"), a descriptive subtitle, and ensure it visually encourages the user to use the "+ Add Item" button.

### Part 2: Due Dates & Rotating Repetitive Tasks
**Goal:** Add deadlines and smart rotation for recurring chores.
**Requirements:**
*   **Data Model:** Add an optional `dueDate: Date?` to the `Task` model.
*   **Repetitive Tasks Logic:** Update the repetitive task generation logic (e.g., `TaskTemplate`). Implement a "Round-Robin" (Alternating) assignment policy. If a repetitive task has multiple assignees (e.g., Wojtek and Natka), the system must track whose turn it is and assign the *next* generated task to the person who didn't do it last time.

### Part 3: Push Notifications (Verification & Implementation)
**Goal:** Notify partners when tasks are completed or items are added. (No gamification/points, just notifications).
**Requirements:**
*   **Audit:** Check `CloudKitManager.swift` (or similar) to see if `CKQuerySubscription` is already set up for push notifications.
*   **Implement:** If not, write the code to create silent or visible push notification subscriptions for the `Household` zone. For example, when User A completes a Task, User B should receive a notification ("Wojtek completed: Vacuuming").

### Part 4: Shopping "Bundles" (Smart Groups)
**Goal:** Allow users to create reusable groups of shopping items (e.g., "Spaghetti Recipe", "Car Wash") for quick adding.
**Requirements:**
*   **Data Model:** Create a `ShoppingBundle` model (requires a `name`, an `icon` string for an emoji/SF Symbol, and an array of `items` strings).
*   **Management UI:** In the `Shopping` view header, add a "box" icon (e.g., `archivebox`) between the "Trash" and "Recently Purchased" icons. Tapping this opens a `BundlesManagementView` where users can CRUD bundles and their items.
*   **Quick Add UX:** Implement a `longPressGesture` (or a context menu) on the main "+ Add Item" button in the Shopping view. Long pressing should display a horizontal popover or menu showing just the icons of the user's Bundles. Tapping a bundle icon instantly adds all its items to the active shopping list.

### Part 5: Activity Log
**Goal:** Track who did what to resolve household disputes (e.g., "Who bought the milk?").
**Requirements:**
*   **Data Model:** Create a lightweight `ActivityLog` model (action type, user name, item name, timestamp).
*   **UI Placement:** In the "More" tab, add an "Activity Log" navigation link right above the "Settings" link.
*   **View:** Create `ActivityLogView` showing a simple, chronological list of recent actions (e.g., "Wojtek added Milk", "Natka completed Vacuuming").
*   **Integration:** Add logging calls to the functions that complete tasks or add shopping items.

### Part 6: Tasks Filtering by Assignee
**Goal:** Allow users to quickly see only their tasks.
**Requirements:**
*   **UI:** At the top of the `Tasks` view (below the Active/Completed picker, but above the list), add a horizontal, scrollable row of member avatars (`ScrollView(.horizontal)`).
*   **Unassigned Option:** Include a specific avatar/icon for "Unassigned" tasks.
*   **Logic:** Tapping an avatar toggles a filter. If an avatar is selected, the list below should only display tasks assigned to that specific person (or unassigned, if that was selected). Tapping it again clears the filter.










NEW NEW NEW:






### Part 7: Feature Request: Implement "Poke" (Friendly Reminder) for Tasks


### Context
We want to add a "Poke" feature in our Family-Todo app (HousePulse). It allows users to send a friendly reminder to a household member about a task assigned to them. To prevent spam, a task can only be "poked" once per day.

Please implement this feature step-by-step, following our existing architecture (SwiftUI, SwiftData for local cache, CloudKit for sync).

### Step 1: Update Data Models
Files to modify: `Task.swift`, `CachedTask.swift`, `CloudKitManager+Mapping.swift`
1. Add `var lastPokedAt: Date?` to the domain model `Task`.
2. Add `@Attribute var lastPokedAt: Date?` to the SwiftData model `CachedTask`.
3. Update initializers to include this new field (default to `nil`).
4. In `CloudKitManager+Mapping.swift`:
   - Update `taskRecord(from:)` to save `lastPokedAt` to the `CKRecord`.
   - Update `task(from:)` to read `lastPokedAt` from the `CKRecord`.

### Step 2: Store Logic
File to modify: `TaskStore.swift`
1. Add a new method: `func canPoke(task: Task) -> Bool`. It should return `true` if `lastPokedAt` is `nil` OR if `lastPokedAt` is not from today (use `Calendar.current.isDateInToday`).
2. Add a new method: `func pokeTask(_ task: Task) async`.
   - Guard check using `canPoke(task:)`.
   - Update `task.lastPokedAt = Date()`.
   - Update the local SwiftData cache (`CachedTask`).
   - Call `CloudKitManager.shared.saveTask(...)` (or your equivalent update method) to sync the change to CloudKit.
   - Trigger a soft haptic feedback: `UIImpactFeedbackGenerator(style: .soft).impactOccurred()`.

### Step 3: UI Implementation
File to modify: `TasksView.swift` (or the specific Task Row component)
1. Add a `swipeActions(edge: .leading, allowsFullSwipe: false)` to the task row.
2. The swipe action should ONLY appear if the task is assigned to someone else (not the current user).
3. Inside the swipe action, add a `Button`:
   - **Icon:** `Image(systemName: "hand.wave.fill")`
   - **Tint:** `.orange` or `.yellow`
   - **Label:** "Poke" / "Przypomnij"
   - **Action:** Call `TaskStore.pokeTask(task)` inside a Task/async context.
4. **Cooldown UX:** If `canPoke(task:)` returns `false` (already poked today):
   - Change the icon to `moon.zzz.fill` or `bell.slash.fill`.
   - Change the tint to `.gray`.
   - Disable the button (`.disabled(true)`).

### Step 4: CloudKit Push Notifications (Groundwork)
File to modify: `CloudKitManager.swift`
1. We need the assignee to receive a push notification when `lastPokedAt` changes.
2. Create or update a `CKQuerySubscription` for the `Task` record type.
3. The subscription should trigger on `.updates`.
4. The `CKNotificationInfo` should have a friendly, randomized localized payload (e.g., "👋 Puk puk! Ktoś przypomina Ci o zadaniu: %1$@", using the task title as an argument).
*(Note: If dynamic random text is too complex for basic CKNotificationInfo, just set a friendly static message like "👋 Masz nową, przyjazną przypominajkę o zadaniu!").*

Please provide the code changes for each file. Ensure the code is safe, handles optionals correctly, and follows SwiftUI best practices.


### Part 8: Feature Request: Implement "Gentle Rewards" (Duolingo-style Micro-celebrations)

### Context
We want to implement a positive reinforcement system in our Family-Todo app. When a user completes a task, we want to show a gentle, playful in-app notification (Toast/Snackbar). We want to avoid toxic competition (no individual scores) and focus on shared household achievements.
The user mentioned that *some* of these notifications might already be implemented.

### Step 1: Audit Existing Code
Before writing new code, please search the codebase for existing toast, snackbar, or notification UI components (e.g., `ToastView`, `NotificationBanner`, or completion logic in `TaskStore.swift`).
- If a Toast system exists, we will reuse and expand it.
- If it doesn't exist, we need to create a simple, reusable SwiftUI Toast modifier.

### Step 2: Create `CelebrationManager.swift`
Create a new service/manager to handle the logic and store a pool of ~20 different messages to prevent repetition.
1. **Message Pools (Arrays of Strings):**
   - **General Micro-celebrations:** "Boom! Done. 💥", "One step closer to a clean home! 🏡", "Nailed it! 🎯", "Task destroyed! 👾", "Love to see it! ✨", "Another one bites the dust! 🎵", "You're on fire! 🔥", "Household hero! 🦸"
   - **Area-specific (if category matches):**
     - Kitchen: "Kitchen is sparkling! ✨", "Chef's domain is clean! 🍳"
     - Bathroom: "Bathroom sorted! 🧼", "Shiny and clean! 🛁"
   - **Milestones (Shared progress):** "10 tasks done this week! Home is happy 🏡", "5 tasks crushed today! High five ✋"
   - **Surprises (Rare):** "Weekend earned! 🎈", "You guys are an unstoppable team! 🏆"

2. **Logic Methods:**
   - `func getCompletionMessage(for task: Task, weeklyCompletedCount: Int) -> String`
   - **Rule 1:** Check if it's a milestone (e.g., `weeklyCompletedCount == 10`). If so, return a milestone message.
   - **Rule 2:** Check for rare surprises. Use `UserDefaults` (e.g., `lastSurpriseDate`) to ensure a surprise message is shown *maximum once per week*.
   - **Rule 3:** If no milestone/surprise, pick a random message from the General or Area-specific pool. Use `Array.randomElement()` to keep it fresh.

### Step 3: Update `TaskStore.swift` (or Task Completion Logic)
1. When a user toggles a task to `isCompleted = true`, calculate the `weeklyCompletedCount` (count of tasks completed by anyone in the household this week).
2. Call `CelebrationManager.shared.getCompletionMessage(...)`.
3. Trigger the UI Toast/Snackbar with the returned message.

### Step 4: UI Implementation (In-App Toast)
If a Toast system wasn't found in Step 1, implement a simple `.overlay` or `.modifier` in SwiftUI:
- A pill-shaped banner at the bottom or top of the screen.
- Smooth transition (`.move(edge: .top)` or `.bottom` with `.opacity`).
- Auto-dismisses after 3 seconds.
- Triggered by a published property, e.g., `appState.currentToastMessage`.

Please provide the code for `CelebrationManager`, the updates to the task completion logic, and the Toast UI component. Ensure the tone remains neutral-positive (household progress, not individual scores).

---
**Instructions for you (the AI):**
Please acknowledge that you have read and understood this roadmap. Then, analyze my codebase and **provide the code ONLY for Part 1**. Wait for my feedback before moving to Part 2.








Research TODO:

1. Jeżeli task jest na kimś innym, to czy mogę (czy powinienem móc?) zmienić jego stan, np go ukończyć lub zrzucić do Ideas?

Odpowiedź do analizy:

Zdecydowanie TAK. Z perspektywy UX i projektowania aplikacji dla domowników (rodzin, par, współlokatorów), powinieneś mieć pełną swobodę zmiany stanu zadań innych osób.
Oto dlaczego to najlepsze podejście:
1. Aplikacja domowa to nie korporacyjna Jira
W systemach firmowych (Jira, Asana) blokuje się zadania, żeby zachować ścisłą odpowiedzialność (tzw. strict permissions). W domu panuje jednak środowisko oparte na zaufaniu i współpracy. Wprowadzanie twardych blokad ("Nie możesz tego kliknąć, bo to zadanie Kasi") rodzi frustrację.
1. Scenariusze z prawdziwego życia
Życie w domu jest dynamiczne. Wyobraź sobie takie sytuacje:
Zastępstwo: Kasia miała wyrzucić śmieci, ale zasnęła. Ty to robisz. Chcesz mieć satysfakcję z odhaczenia tego zadania i wyczyszczenia listy, zamiast prosić ją rano: "Hej, wyrzuciłem śmieci, wejdź w apkę i to odhacz".
Pomyłka: Ktoś przez pomyłkę przypisał zadanie nie tej osobie. Każdy powinien móc to szybko skorygować (zrzucić do Ideas lub zmienić przypisanie).
Zmiana planów: Zadanie "Naprawić router" (przypisane do Ciebie) okazuje się niemożliwe, bo trzeba kupić kabel. Ktoś inny z domowników widzi to na liście i zrzuca z powrotem do Ideas, żeby nie zaśmiecało aktywnych zadań.
1. Mniej tarcia (Low Friction)
Głównym celem takich aplikacji jest to, żeby ludzie chcieli ich używać. Jeśli aplikacja będzie rzucać kłody pod nogi ("Brak uprawnień"), domownicy szybko wrócą do karteczek na lodówce.
Jak to zabezpieczyć przed chaosem? (Na przyszłość)
Skoro każdy może edytować wszystko, jak uniknąć kłótni typu "Kto mi usunął zadanie?!"?
Rozwiązaniem nie są blokady, ale transparentność.
W poprzednich krokach planowaliśmy funkcję Activity Log (Dziennik Aktywności). To idealne rozwiązanie. Jeśli odhaczysz zadanie Kasi, w logach pojawi się po prostu wpis:
"Wojtek completed Kasia's task: Wyrzucić śmieci".
Dzięki temu jest pełna swoboda działania, ale nic nie ginie bez śladu.
Podsumowując: Zostaw pełną swobodę. Każdy domownik powinien móc ukończyć, usunąć lub cofnąć do Ideas zadanie dowolnego innego domownika.



2. Czy filtrowanie zadań może wyglądać tak, żę na górze nie są imiona, ale jest
All tasks, My tasks, Natalia's tasks ?

Odpowiedź do analizy:

To bardzo dobry pomysł z punktu widzenia UX (User Experience). Taki zabieg nazywa się Conversational UI – interfejs mówi do użytkownika naturalnym, ludzkim językiem, zamiast rzucać suchymi danymi.
Oto dlaczego to świetne rozwiązanie:
"My tasks" działa psychologicznie o wiele lepiej niż samo Twoje imię. Od razu wiesz, że to Twoja strefa odpowiedzialności.
"All tasks" jasno komunikuje, że filtr jest wyłączony i widzisz pełen obraz sytuacji w domu.
"[Imię]'s tasks" nie pozostawia wątpliwości, czyje to obowiązki.
Jak to najlepiej zaprojektować (UI)?
Ponieważ teksty typu "Natalia's tasks" są znacznie dłuższe niż same imiona czy ikonki z inicjałami, zwykły pasek może się nie zmieścić na ekranie telefonu, jeśli domowników będzie np. czworo.
Najlepszym rozwiązaniem będzie pozioma, przewijana lista "pigułek" (Filter Chips), umieszczona tuż pod głównymi zakładkami (Active / Completed).
Wybrany filtr ma tło w kolorze wiodącym (Accent Color) i biały tekst.
Niewybrane filtry mają jasnoszare tło i czarny tekst.
Oto gotowy prompt, który możesz wkleić do Codexa/Cursora, aby wdrożył to w elegancki i nowoczesny sposób:
code
Text
## Feature Request: Conversational Task Filters (Filter Chips)

### Context
In `TasksView`, we want to improve the UX of filtering tasks by user. Instead of just showing user names or avatars, we want to use natural language in a horizontally scrollable list of "Filter Chips" (pill-shaped buttons).

### Requirements
1. **Filter Options:**
   - **"All tasks"**: The default state (no filter applied).
   - **"My tasks"**: Filters tasks assigned to the currently logged-in user (`AuthStore.shared.currentUser`).
   - **"[Name]'s tasks"**: For every other member in the household (e.g., "Natalia's tasks", "Kasia's tasks").

2. **UI Design (Filter Chips):**
   - Place a `ScrollView(.horizontal, showsIndicators: false)` just below the "Active / Completed" picker.
   - Inside, use an `HStack` with some spacing.
   - Each filter option should be a pill-shaped button (`Capsule` shape or `.cornerRadius(20)`).
   - **Selected state:** Background should be `.accentColor` (or primary app color), text should be `.white`, font `.subheadline.bold()`.
   - **Unselected state:** Background should be a subtle gray (e.g., `Color(UIColor.systemGray5)` or `.secondary.opacity(0.1)`), text should be primary color, font `.subheadline`.
   - Add a little horizontal padding to the `ScrollView` so the first chip aligns with the rest of the UI.

3. **Logic Implementation:**
   - Create an `enum TaskFilter: Equatable` with cases: `.all`, `.mine`, `.specificUser(User)`.
   - Add a `@State private var selectedFilter: TaskFilter = .all` to `TasksView`.
   - Update the computed property that filters the tasks (e.g., `filteredTasks`) to respect both the Active/Completed state AND the `selectedFilter` state.
   - When generating the chips for other users, ensure you filter out the current user from the household members list so they don't appear twice (once as "My tasks" and once as "[Name]'s tasks").

Please implement this in `TasksView` and ensure the filtering logic works seamlessly with the existing Active/Completed toggle.
Dzięki temu promptowi AI nie tylko zmieni teksty, ale też zadba o to, żeby długie nazwy nie zepsuły layoutu (dodając poziome przewijanie) i żebyś Ty ("My tasks") nie dublował się na liście z Twoim imieniem ("Wojtek's tasks").
