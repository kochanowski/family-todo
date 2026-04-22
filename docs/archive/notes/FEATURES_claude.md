# FEATURES_claude

Ostatnia aktualizacja: 2026-03-02

## 0) Zakres researchu

Przeczytałem cały `FEATURES.md` i przeprowadziłem pełny audit kodu pod implementację wszystkich 6 części roadmapy.

Research objął:
- **Widoki**: `ShoppingListView.swift` (937 linii), `TasksView.swift` (1194 linii), `BacklogView.swift` (1036 linii), `MoreView.swift` (999 linii), `SettingsView.swift`
- **Modele**: `Task.swift`, `ShoppingItem.swift`, `Member.swift`, `Household.swift`, `BacklogCategory.swift`, `LegacyStubs.swift` (Area, RecurringChore, CachedArea, CachedRecurringChore, AreaStore, RecurringChoreStore, ChoreScheduler)
- **Store'y**: `TaskStore.swift`, `ShoppingListStore.swift`, `BacklogStore.swift`, `HouseholdStore.swift`, `MemberStore.swift`
- **CloudKit**: `CloudKitManager.swift` (66KB), `CloudKitManager+Mapping.swift` (522 linii), `CloudKitSubscriptionManager.swift` (229 linii)
- **Serwisy**: `AppDelegateBridge.swift`, `NotificationService.swift`, `UserSession.swift`, `CelebrationManager.swift`
- **Infrastruktura**: `FamilyTodoApp.swift` (appSchema), `SwiftDataContainerFactory.swift` (runtimeModelProbes), `cloudkit/schema/`
- **Testy**: `FamilyTodoTests/` (HouseholdTests, MemberTests)

---

## 0b) Research Resolutions

Odpowiedzi na pytania UX z pliku `FEATURES.md` (sekcja "Research TODO"), które wpływają na plan implementacji.

### Resolution 1: Edycja zadań przypisanych innym osobom

**Decyzja**: Pełna swoboda — każdy domownik może ukończyć, cofnąć do backlogu lub zmienić stan zadania przypisanego innej osobie.

**Uzasadnienie**: Aplikacja domowa opiera się na zaufaniu i współpracy, a nie na twardych blokadach uprawnień jak w korporacyjnym Jira. Realistyczne scenariusze (zastępstwo, pomyłka, zmiana planów) wymagają pełnej elastyczności.

**Wpływ na plan**:
- `TaskStore` — brak guard'ów na `assigneeId != currentUserId` przy zmianie statusu
- Part 5 (Activity Log) jest kluczowy — zapewnia transparentność zamiast blokad ("Wojtek completed Natalia's task: Vacuuming")
- Part 7 (Poke) — ograniczenie do cudzych zadań pozostaje (wysyłasz poke tylko cudzym)

### Resolution 2: Conversational Filter Chips zamiast Avatar Chips

**Decyzja**: Part 6 używa "pill" przycisków z naturalnym językiem zamiast kółek z inicjałami.

**Tekst filtrów**: `"All tasks"` → `"My tasks"` → `"[Imię]'s tasks"` (np. "Natalia's tasks")

**Uzasadnienie**: Dłuższe teksty komunikują się bardziej naturalnie ("My tasks" brzmi lepiej psychologicznie niż inicjał "W"), a horizontalne przewijanie rozwiązuje problem długości przy większej liczbie domowników.

**Wpływ na plan**: Sekcja Part 6 poniżej jest zaktualizowana względem poprzedniej wersji.

---

## 1) Gap analysis (stan obecny vs roadmapa)

| Part | Co już jest w kodzie | Co brakuje | Trudność |
|---|---|---|---|
| **1. Empty States** | `ContentUnavailableView` w `BacklogView` (empty categories); w `TasksView` dla Completed | Empty state dla Shopping (pusta lista toBuy); empty state dla Tasks Active (pusty `visibleNextTasks`) | 🟢 Niska |
| **2. Due Dates + Rotation** | `Task.dueDate` w pełni wdrożone (model, cache, CloudKit mapping, UI w TaskDetailSheet, sortowanie, remindery). `RecurringChore` ma fieldy `assigneeIds`, `rotationEnabled`, `frequencyDays` | Round-robin: `ChoreScheduler.runIfNeeded` not rotation-aware, brak `nextAssigneeIndex`, `RecurringChoreStore` to stub z basic CRUD, `CachedRecurringChore` brakuje persistence pól rotacji, brak multi-assignee UI | 🟡 Średnia |
| **3. Push Notifications** | `CloudKitSubscriptionManager` z `CKDatabaseSubscription` na shared DB, `registerForPushNotifications`, basic `handleRemoteNotification` z parsowaniem CKNotification | `AppDelegateBridge` nie ma `didReceiveRemoteNotification:fetchCompletionHandler`, pipeline z konkretną treścią zdarzeń nie istnieje, treść notyfikacji generyczna ("Shared Update"), brak self-notify filtering na poziomie DB notification | 🔴 Wysoka |
| **4. Shopping Bundles** | Brak — zerowy fundament | Nowy model `ShoppingBundle`, nowy cache `CachedShoppingBundle`, nowy store `ShoppingBundleStore`, CloudKit record type, mapping, UI zarządzania bundlami, quick-add przez long press | 🔴 Wysoka |
| **5. Activity Log** | Brak | Nowy model `ActivityLog`, cache `CachedActivityLog`, store `ActivityLogStore`, CloudKit record type, mapping, UI w MoreView + ActivityLogView, integracja logging w istniejących store'ach | 🟡 Średnia |
| **6. Tasks Filter by Assignee** | Brak filtrowania. Są przełączniki Active/Completed (`activeFilter`). `MemberStore` dostarcza listę `members` z `colorHex` | Poziomy `ScrollView(.horizontal)` z avatarami, stan filtra (`.all`/`.member(UUID)`/`.unassigned`), empty state dla filtra bez wyników | 🟢 Niska |

---

## 2) Rekomendowana kolejność wdrożenia

```
1. Part 1 — Empty States              🟢 UI-only, zero risk, szybki UX win
2. Part 6 — Conversational Filters    🟢 UI + logika, bez schema changes (UPDATED design)
3. Part 8 — Gentle Rewards            🟢 Audit-first; CelebrationManager już istnieje
4. Part 7 — Poke                      🟡 Nowe pole modelu + swipe UI + push
5. Part 2 — Due Dates + Rotation      🟡 Round-robin wymaga schema + scheduler update
6. Part 4 — Shopping Bundles          🔴 Nowy model end-to-end (model → cache → CK → store → UI)
7. Part 5 — Activity Log              🟡 Nowy model, ale prostszy niż Bundles
8. Part 3 — Push Notifications        🔴 Najlepiej po Part 5 (ActivityLog jako źródło komunikatów)
```

**Powód**: Part 8 jest nisko ryzykowne (CelebrationManager i ToastView już istnieją — to głównie audit + gap fill). Part 7 (Poke) wymaga nowego pola w modelu Task, ale bez nowych tabel — dobry punkt wejścia przed ciężkimi zmianami schematu. Part 3 bez Part 5 wymaga ciężkiego parsowania zmian CKRecord; z ActivityLog push może bazować na gotowych wpisach.

---

## 3) Plan implementacji per feature

---

## Part 1: Engaging Empty States

### Co robimy

Trzy widoki potrzebują `ContentUnavailableView` gdy listy są puste:

#### ShoppingListView
- **Warunek**: `store.toBuyItems.isEmpty && !isRapidEntryActive`
- **Umiejscowienie**: w `ShoppingListContent.body`, zamiast pustego `ScrollView` z `ForEach`
- **Konfiguracja**:
  - Symbol: `cart` (SF Symbol)
  - Tytuł: "Your list is empty"
  - Opis: "Tap + to add your first item"
  - Action: button wywołujący `startRapidEntry()` (rapid entry jest już zaimplementowane)

#### TasksView
- **Warunek**: `activeFilter == .active && visibleNextTasks.isEmpty`
- **Umiejscowienie**: w `activeTasksContent` (linia ~240), zamiast pustego `ForEach`
- **Konfiguracja**:
  - Symbol: `checklist`
  - Tytuł: "No active tasks"
  - Opis: "Promote ideas from Backlog or create a new task"
  - Uwaga: jest już empty state dla Completed (zachować)

#### BacklogView
- **Stan**: Już ma `emptyState` (linia ~91 — `store.categories.isEmpty`)
- **Do zrobienia**: Dopasowanie ikony do roadmapy (`lightbulb` zamiast obecnej), ewentualny tuning copy/subtitle

### Pliki do modyfikacji
- `FamilyTodo/Views/ShoppingListView.swift`
- `FamilyTodo/Views/TasksView.swift`
- `FamilyTodo/Views/BacklogView.swift` (minor copy/icon adjustment)

### Testy
- **Unit**: Nie dotyczy (UI-only)
- **Manual smoke na urządzeniu**:
  1. Wyczyść dane shopping → sprawdź empty state z ikoną cart i CTA
  2. Usuń wszystkie active Tasks → sprawdź empty state z checklist
  3. Usuń wszystkie Backlog categories → sprawdź empty state z lightbulb
  4. Tap CTA w Shopping empty state → sprawdź, że rapid entry się aktywuje

---

## Part 2: Due Dates & Rotating Repetitive Tasks

### Co już jest (dueDate — DONE ✅)
- `Task.dueDate: Date?` — model, `CachedTask`, CloudKit mapping, UI (TaskDetailSheet), sortowanie, remindery
- **Nie trzeba nic robić dla dueDate**

### Co trzeba dowieźć (Round-Robin Rotation)

#### 2a. Model `RecurringChore` — rozszerzenie

Obecny stan w `LegacyStubs.swift` (linia 62-132):
```swift
struct RecurringChore: Identifiable, Codable {
    // ... existing fields ...
    var frequencyDays: Int = 7
    var assigneeIds: [UUID] = []        // ✅ Już jest!
    var rotationEnabled: Bool = false   // ✅ Już jest!
}
```

**Brakuje**:
- `nextAssigneeIndex: Int` — cursor do round-robin (lub `lastAssignedMemberId: UUID?`)
- Logika wyliczania "kto następny" na bazie `assigneeIds` + cursor

**Rekomendacja**: Dodać `nextAssigneeIndex: Int = 0` do `RecurringChore`. Po wygenerowaniu task'a cursor leci o +1 (modulo `assigneeIds.count`).

#### 2b. `CachedRecurringChore` — uzupełnienie cache

Obecny `CachedRecurringChore` w `LegacyStubs.swift` prawdopodobnie nie trzyma `assigneeIds`, `rotationEnabled`, `nextAssigneeIndex`. Trzeba:
- Dodać `assigneeIdsJSON: String` (JSON string z UUID-ami)
- Dodać `rotationEnabled: Bool`
- Dodać `nextAssigneeIndex: Int`
- Metody konwersji `toRecurringChore()` / `init(from:)`

#### 2c. `ChoreScheduler.runIfNeeded` — logika rotacji

Obecny `ChoreScheduler` (w `LegacyStubs.swift`) generuje taski ale nie uwzględnia rotacji:

**Nowa logika**:
```
1. Iteruj active chores gdzie nextScheduledDate <= now
2. Jeśli chore.rotationEnabled && chore.assigneeIds.count > 1:
   a. Weź assigneeIds[chore.nextAssigneeIndex]
   b. Stwórz Task z tym assigneeId
   c. chore.nextAssigneeIndex = (nextAssigneeIndex + 1) % assigneeIds.count
3. W przeciwnym razie: zachowane dotychczasowe zachowanie (pierwszy assignee)
4. Zapisz chore z zaktualizowanym cursor → cache + cloud
```

#### 2d. CloudKit schema

- Dodać pole `nextAssigneeIndex` (Int64) do record type `RecurringChore`
- Aktualizacja mapping w `CloudKitManager+Mapping.swift` — `recurringChoreRecord(from:)` i `recurringChore(from:)`

#### 2e. UI konfiguracji recurring

- W `RepetitiveTasksView` (stub w LegacyStubs) dodać multi-assignee picker (min 2 osoby) i toggle "Rotate assignees"
- Przy edycji istniejącego chore — pokazać kto jest "następny"

### Pliki do modyfikacji
- `FamilyTodo/Models/LegacyStubs.swift` (RecurringChore + CachedRecurringChore + ChoreScheduler)
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift` (recurring chore mapping)
- `FamilyTodo/Views/MoreView.swift` lub dedykowany `RepetitiveTasksView.swift`
- `cloudkit/schema/housepulse-schema.json`

### Pliki nowe
- Brak (rozszerzenie istniejących)

### Testy
- **Unit**: Rotacja A→B→A→B dla 2 assignees
- **Unit**: Zmiana listy assignee w trakcie (cursor normalization: `min(cursor, count-1)`)
- **Unit**: Brak duplikacji task'ów dla tego samego dnia
- **Manual**: Smoke test na urządzeniu — nowy recurring chore z 2 osobami, sprawdzić generowanie

---

## Part 3: Push Notifications (verification + implementation)

### Wynik audytu

| Komponent | Stan | Wniosek |
|---|---|---|
| `CloudKitSubscriptionManager` | `CKDatabaseSubscription` na shared DB ✅ | Fundament jest |
| `registerForPushNotifications` | Rejestracja remote push ✅ | OK |
| `handleRemoteNotification` | Parsuje `CKNotification`, ale treść generyczna ("Shared Update") | Do wzbogacenia |
| `handleQueryNotification` | Filtr `creatorId == currentUserId` (self-notify OFF) ✅ | Ale CKQueryNotification nie przychodzi (brak query subscriptions) |
| `AppDelegateBridge` | Tylko `userDidAcceptCloudKitShareWith` | **Brak `didReceiveRemoteNotification:fetchCompletionHandler`** ← główna luka |
| Payload notyfikacji | Generyczne "New shared items" | Brak kontekstu "kto co zrobił" |

### Ważna decyzja techniczna
- W shared DB **nie polegamy** na `CKQuerySubscription` (Apple QA1917 — query subscriptions nie działają w shared DB)
- Bazujemy na `CKDatabaseSubscription` + odczyt zmian po push

### Plan implementacji

#### 3a. `AppDelegateBridge` — dodać remote push handler

```swift
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    CloudKitSubscriptionManager.shared.handleRemoteNotification(userInfo: userInfo)
    completionHandler(.newData)
}

func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    // Log success
}

func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
) {
    // Log failure
}
```

#### 3b. `CloudKitSubscriptionManager` — wzbogacenie pushów

**Strategia zależy od Part 5 (Activity Log)**:

- **Z Part 5** (rekomendowane): Po otrzymaniu push, pobierz nowe wpisy `ActivityLog` z CloudKit, filtruj (tylko inne userId), wygeneruj czytelne notyfikacje ("Wojtek completed: Vacuuming")
- **Bez Part 5**: Po push, użyj `CKFetchDatabaseChangesOperation` → `CKFetchRecordZoneChangesOperation` aby pobrać zmienione rekordy, porównaj ze stanem, wygeneruj notyfikację na bazie diff'u (cięższe, mniej czytelne)

**Rekomendacja**: Implementuj Part 5 przed Part 3.

#### 3c. Self-notify filter

- Obecny filtr w `handleQueryNotification` (po `creatorId`) jest poprawny ale martwy (brak query subscriptions)
- Dla database subscription: po pobraniu zmian sprawdzić `creatorUserRecordID` rekordu vs `currentUserId`
- Alternatywnie (z ActivityLog): sprawdzić `activityLog.userId != currentUserId`

#### 3d. Opcjonalny toggle

- W `SettingsView` dodać sekcję "Notifications" z toggle "Partner updates" (default ON)
- Zapisać w `@AppStorage` lub `NotificationSettingsStore`

### Pliki do modyfikacji
- `FamilyTodo/Services/AppDelegateBridge.swift` — remote push handler
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` — wzbogacona logika
- `FamilyTodo/Views/SettingsView.swift` — toggle
- `FamilyTodo/Models/LegacyStubs.swift` — `NotificationSettingsStore` (opcjonalne rozszerzenie)

### Testy
- **Manual (wymagane 2 Apple ID + 2 urządzenia)**:
  1. User A ukończy task → User B dostaje notyfikację "A completed: [task]"
  2. User A dodaje shopping item → User B dostaje notyfikację
  3. Self-notify: User A nie dostaje swoich zmian
  4. Toggle OFF → brak pushów
- **Unit**: mockowanie `CKNotification` parsing
- **Uwaga**: Push nie działa na Simulatorze — wymagane fizyczne urządzenia

---

## Part 4: Shopping Bundles (Smart Groups)

### 4a. Model danych

#### Nowy model domenowy `ShoppingBundle`

```swift
// FamilyTodo/Models/ShoppingBundle.swift [NEW]
struct ShoppingBundle: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String              // emoji lub SF Symbol name
    var items: [String]           // lista nazw produktów
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
}
```

#### Nowy cache `CachedShoppingBundle`

```swift
// FamilyTodo/Models/CachedShoppingBundle.swift [NEW]
@Model
final class CachedShoppingBundle {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var name: String
    var icon: String
    var itemsJSON: String         // JSON-encoded [String]
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var syncStatusRaw: String
    var lastSyncedAt: Date?

    // Computed: items ↔ itemsJSON
}
```

**Decyzja**: `items` jako `itemsJSON` (JSON string) zamiast listy — mniej zmian w CloudKit parserach/validatorze schema, jeden field zamiast sub-recordów.

### 4b. Store

```swift
// FamilyTodo/Stores/ShoppingBundleStore.swift [NEW]
@MainActor
final class ShoppingBundleStore: ObservableObject {
    @Published private(set) var bundles: [ShoppingBundle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // Pattern: cache-first → cloud sync (jak inne store'y)
    func loadBundles() async { ... }
    func createBundle(name:icon:items:) async { ... }
    func updateBundle(_:) async { ... }
    func deleteBundle(_:) async { ... }
}
```

### 4c. CloudKit

- Nowy record type `ShoppingBundle` z polami: `id`, `householdId` (Reference), `name`, `icon`, `itemsJSON`, `sortOrder`, `createdAt`, `updatedAt`
- Mapping w `CloudKitManager+Mapping.swift` — `shoppingBundleRecord(from:)` i `shoppingBundle(from:)`
- CRUD w `CloudKitManager.swift` — `saveShoppingBundle()`, `fetchShoppingBundles()`, `deleteShoppingBundle()`

### 4d. UI

#### BundlesManagementView [NEW]
- Lista bundli z ikoną + nazwą + liczbą items
- Create: formularz z name, icon picker (emoji/SF Symbol), lista items (add/remove)
- Edit: inline edit
- Delete: swipe
- Nawigacja: z `ShoppingListView` header

#### ShoppingListView header — nowa ikona
- Dodać ikonę `archivebox` między `trash` a `clock.badge.checkmark` (restock)
- Tap → NavigationLink do `BundlesManagementView`

#### Quick Add (long press)
- `longPressGesture` na głównym "+" (Add Item) w `ShoppingListView`
- Wyświetlenie poziomej listy ikon bundli (popover lub overlay)
- Tap bundla → `store.createItem(title:)` dla każdego item z bundle

### Pliki nowe
- `FamilyTodo/Models/ShoppingBundle.swift`
- `FamilyTodo/Models/CachedShoppingBundle.swift`
- `FamilyTodo/Stores/ShoppingBundleStore.swift`
- `FamilyTodo/Views/BundlesManagementView.swift`

### Pliki do modyfikacji
- `FamilyTodo/Views/ShoppingListView.swift` — header icon + long press
- `FamilyTodo/Managers/CloudKitManager.swift` — CRUD
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift` — mapping
- `FamilyTodo/FamilyTodoApp.swift` — dodać `CachedShoppingBundle.self` do `appSchema`
- `FamilyTodo/Utilities/SwiftDataContainerFactory.swift` — dodać probe do `runtimeModelProbes`
- `cloudkit/schema/housepulse-schema.json` — nowy record type

### Testy
- **Unit**: CRUD bundle, serializacja/deserializacja `itemsJSON`, batch quick-add
- **Manual**: Stworzenie bundla "Spaghetti Recipe" z items, long press "+" → tap bundle → sprawdzić, że items dodane
- **Manual cloud**: Sync bundli między 2 urządzeniami

---

## Part 5: Activity Log

### 5a. Model danych

#### Model `ActivityLog` [NEW]

```swift
struct ActivityLog: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    let actionType: ActionType
    let userName: String
    let userId: String            // do self-filtering
    let itemName: String
    let timestamp: Date

    enum ActionType: String, Codable {
        case taskCompleted
        case taskCreated
        case shoppingItemAdded
        case shoppingItemBought
        // rozszerzalne w przyszłości
    }
}
```

#### Cache `CachedActivityLog` [NEW]

```swift
@Model
final class CachedActivityLog {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var actionTypeRaw: String
    var userName: String
    var userId: String
    var itemName: String
    var timestamp: Date
    var syncStatusRaw: String
    var lastSyncedAt: Date?
}
```

### 5b. Store

```swift
// FamilyTodo/Stores/ActivityLogStore.swift [NEW]
@MainActor
final class ActivityLogStore: ObservableObject {
    @Published private(set) var logs: [ActivityLog] = []

    func loadLogs() async { ... }
    func logAction(type:userName:userId:itemName:) async { ... }

    // Retention: max 500 wpisów lub 30 dni (opcjonalne, rekomendowane)
}
```

### 5c. Integracja logging w istniejących store'ach

**Gdzie dodać wywołania `activityLogStore.logAction(...)`:**

| Akcja | Store | Metoda | ActionType |
|---|---|---|---|
| Ukończenie taska | `TaskStore` | `moveTask(_:to: .done)` | `.taskCompleted` |
| Utworzenie taska | `TaskStore` | `createTask(title:...)` | `.taskCreated` |
| Dodanie item'u zakupowego | `ShoppingListStore` | `createItem(title:...)` | `.shoppingItemAdded` |
| Kupienie item'u | `ShoppingListStore` | `toggleBought(_:)` (gdy `isBought=true`) | `.shoppingItemBought` |

**Ważne**: Logging w warstwie Store (nie UI) — jedno źródło prawdy.

**Challenge**: Store'y nie mają dziś dostępu do `userName`/`userId`. Trzeba:
- Przekazać `UserSession` do store'ów (lub injektować `currentUser` info przy tworzeniu store)
- Lub mieć `ActivityLogStore` jako singleton (jak `CloudKitManager.shared`)

### 5d. CloudKit schema

- Nowy record type `ActivityLog` z polami: `id`, `householdId` (Reference), `actionType`, `userName`, `userId`, `itemName`, `timestamp`
- Index po `householdId` + sort po `timestamp` desc

### 5e. UI

#### MoreView — nowe miejsce
- Dodać `NavigationLink` "Activity Log" z ikoną `clock.arrow.circlepath` **nad** "Settings"
- Obecna struktura w `MoreView.swift` (linia ~41-76): sekcja z NavigationLinks

#### ActivityLogView [NEW]
- Lista chronologiczna (najnowsze na górze)
- Każdy wiersz: ikona ActionType + opis ("Wojtek added Milk") + timestamp (relative: "2h ago")
- Pull to refresh
- Empty state gdy brak wpisów

### Pliki nowe
- `FamilyTodo/Models/ActivityLog.swift`
- `FamilyTodo/Models/CachedActivityLog.swift`
- `FamilyTodo/Stores/ActivityLogStore.swift`
- `FamilyTodo/Views/ActivityLogView.swift`

### Pliki do modyfikacji
- `FamilyTodo/Stores/TaskStore.swift` — dodać logging
- `FamilyTodo/Stores/ShoppingListStore.swift` — dodać logging
- `FamilyTodo/Views/MoreView.swift` — dodać link
- `FamilyTodo/Managers/CloudKitManager.swift` — CRUD
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift` — mapping
- `FamilyTodo/FamilyTodoApp.swift` — appSchema
- `FamilyTodo/Utilities/SwiftDataContainerFactory.swift` — runtimeModelProbes
- `cloudkit/schema/housepulse-schema.json`

### Testy
- **Unit**: Poprawne tworzenie wpisów dla add/complete
- **Unit**: Sortowanie chronologiczne, mapowanie cache ↔ cloud
- **Unit**: Filtrowanie self (dla push — Part 3)
- **Manual**: Ukończ task → sprawdź wpis w Activity Log. Dodaj item → sprawdź wpis.

---

## Part 6: Tasks Filtering by Assignee — Conversational Filter Chips

> **UPDATED** (2026-03-02): Zmieniono projekt z avatar chips na conversational text pills zgodnie z Research Resolution 2.

### 6a. Stan filtra

```swift
// Nowy enum — language-first zamiast UUID-first
enum TaskFilter: Equatable {
    case all                    // "All tasks"
    case mine                   // "My tasks" — currentUserId
    case member(Member)         // "[Name]'s tasks"
}

@State private var taskFilter: TaskFilter = .all
```

### 6b. UI — Conversational Pills

**Umiejscowienie**: W `TasksView`, pod przełącznikiem Active/Completed (linia ~110-120), nad `List`.

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        // "All tasks"
        FilterChip(label: "All tasks", isSelected: taskFilter == .all)
            .onTapGesture { toggleTaskFilter(.all) }

        // "My tasks" — current user
        FilterChip(label: "My tasks", isSelected: taskFilter == .mine)
            .onTapGesture { toggleTaskFilter(.mine) }

        // "[Name]'s tasks" — every OTHER active member
        ForEach(otherActiveMembers) { member in
            FilterChip(
                label: "\(member.displayName)'s tasks",
                isSelected: taskFilter == .member(member)
            )
            .onTapGesture { toggleTaskFilter(.member(member)) }
        }
    }
    .padding(.horizontal, 16)
}

// Helper — wyklucz bieżącego usera z listy (żeby nie był zdublowany)
var otherActiveMembers: [Member] {
    memberStore.members.filter {
        $0.isActive && $0.userId != userSession.currentUserID
    }
}
```

### 6c. FilterChip — komponent

```swift
// Opcjonalnie wyciągnąć do Components/FilterChip.swift
struct FilterChip: View {
    let label: String
    let isSelected: Bool

    var body: some View {
        Text(label)
            .font(.subheadline.weight(isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(UIColor.systemGray5))
            )
    }
}
```

### 6d. Logika filtrowania

```swift
var filteredActiveTasks: [Task] {
    switch taskFilter {
    case .all:
        return visibleNextTasks
    case .mine:
        guard let cuid = userSession.currentUserID else { return visibleNextTasks }
        return visibleNextTasks.filter {
            $0.assigneeId == UUID(uuidString: cuid)
                || $0.assigneeIds.map(\.uuidString).contains(cuid)
        }
    case .member(let member):
        return visibleNextTasks.filter {
            $0.assigneeId == member.id
                || $0.assigneeIds.contains(member.id)
        }
    }
}
```

**Uwaga**: Filtrowanie stosowane zarówno do active jak i completed tasks.

### 6e. Toggle'owanie

```swift
func toggleTaskFilter(_ filter: TaskFilter) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        taskFilter = taskFilter == filter ? .all : filter
    }
}
```

### 6f. Empty state dla filtra

```swift
// Gdy filtr aktywny ale brak wyników:
ContentUnavailableView(
    "No tasks for this filter",
    systemImage: "person.crop.circle.badge.minus",
    description: Text("Try selecting a different person or view all tasks")
)
```

### Pliki do modyfikacji
- `FamilyTodo/Views/TasksView.swift` — nowy ScrollView z pill chips + logika filtra

### Pliki nowe
- `FamilyTodo/Views/Components/FilterChip.swift` (opcjonalne — można zdefiniować inline)

### Testy
- **Unit**: `filteredActiveTasks` — filtr `.all` zwraca wszystkie; `.mine` zwraca tylko moje; `.member(x)` zwraca tylko x
- **Unit**: `otherActiveMembers` wyklucza currentUser z listy
- **Manual**: Tap "My tasks" → lista filtrowana. Tap "Natalia's tasks" → lista filtrowana. Ponowy tap → filtr zdjęty (wróć do "All tasks").

---

---

## Part 7: Poke — Przyjazne Przypomnienie

### Kontekst

Swipe left na cudzym zadaniu wysyła "poke" — friendly reminder dla assignee. Ograniczenie: 1x dziennie per task, żeby nie spamować.

### 7a. Model danych

**`Task.swift`** — nowe pole:
```swift
var lastPokedAt: Date?   // nil = never poked
```

**`CachedTask.swift`** — nowe pole:
```swift
@Attribute var lastPokedAt: Date?
```

Aktualizacja inicjalizatorów: `init(from: Task)`, `update(from: Task)`, `toTask()` — wszystkie muszą obsługiwać `lastPokedAt`.

**`CloudKitManager+Mapping.swift`**:
```swift
// taskRecord(from:) — dodać:
if let lastPokedAt = task.lastPokedAt {
    record["lastPokedAt"] = lastPokedAt
}

// task(from:) — dodać:
lastPokedAt: record["lastPokedAt"] as? Date
```

### 7b. Store — `TaskStore.swift`

```swift
func canPoke(task: Task) -> Bool {
    guard let pokedAt = task.lastPokedAt else { return true }
    return !Calendar.current.isDateInToday(pokedAt)
}

func pokeTask(_ task: Task) async {
    guard canPoke(task: task) else { return }

    let snapshot = task
    var updated = task
    updated.lastPokedAt = Date()

    // Optimistic UI update
    if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
        tasks[idx] = updated
    }
    updateCachedTask(updated)

    // CloudKit sync
    do {
        _ = try await cloudKit.saveTask(updated)
    } catch {
        // Rollback
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = snapshot
        }
        updateCachedTask(snapshot)
        self.error = error
    }

    // Haptic (soft — nie nachalny)
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
}
```

### 7c. UI — `TasksView.swift`

Dodać `swipeActions(edge: .leading, allowsFullSwipe: false)` do task row. Akcja widoczna **tylko** dla zadań przypisanych komuś innemu (nie currentUser).

```swift
// Na task row:
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    if isTaskAssignedToOther(task) {
        let pokeable = taskStore.canPoke(task: task)
        Button {
            Task { await taskStore.pokeTask(task) }
        } label: {
            Label(
                pokeable ? "Poke" : "Poked today",
                systemImage: pokeable ? "hand.wave.fill" : "moon.zzz.fill"
            )
        }
        .tint(pokeable ? .orange : .gray)
        .disabled(!pokeable)
    }
}

// Helper w TasksView:
private func isTaskAssignedToOther(_ task: Task) -> Bool {
    guard let cuid = userSession.currentUserID else { return false }
    let mine = task.assigneeId == UUID(uuidString: cuid)
        || task.assigneeIds.map(\.uuidString).contains(cuid)
    let hasAssignee = task.assigneeId != nil || !task.assigneeIds.isEmpty
    return !mine && hasAssignee
}
```

**Cooldown UX**:
- Można poke: `hand.wave.fill` + `.orange` + enabled
- Już poke'd dzisiaj: `moon.zzz.fill` + `.gray` + `.disabled(true)`

### 7d. Push Notification

**Ważne ograniczenie**: `CKQuerySubscription` nie działa w shared DB (Apple QA1917). Nie tworzymy nowego subscription.

**Strategia**: Istniejący `CKDatabaseSubscription` (silent push) dostarczy powiadomienie o zmianie Task record.

W `CloudKitSubscriptionManager.handleRemoteNotification()` — po pobraniu zmienionych rekordów:
1. Sprawdź czy Task ma `lastPokedAt` z dzisiaj
2. Sprawdź, czy `lastPokedAt` nie pochodzi od currentUsera (self-notify OFF)
3. Sprawdź, czy task jest przypisany do currentUsera
4. Jeśli tak → wyświetl local notification z randomizowaną treścią

```swift
static let pokeMessages = [
    "👋 Puk puk! Ktoś przypomina Ci o: %@",
    "🔔 Mała przypominajka o: %@",
    "💬 Hej, pamiętasz o: %@?",
    "✨ Friendly nudge: %@"
]
```

> Jeśli Part 5 (ActivityLog) jest wdrożony wcześniej, można oprzeć notyfikację na wpisach ActivityLog zamiast sprawdzania pola bezpośrednio — czytelniejsze i reużywalne.

### Pliki do modyfikacji
- `FamilyTodo/Models/Task.swift`
- `FamilyTodo/Models/CachedTask.swift`
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
- `FamilyTodo/Stores/TaskStore.swift`
- `FamilyTodo/Views/TasksView.swift`
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` (push handling)

### Pliki nowe
- Brak

### Testy
- **Unit**: `canPoke` → `false` gdy `lastPokedAt` jest z dzisiaj; `true` gdy `nil` lub wczoraj
- **Unit**: `pokeTask` → optimistic update + rollback na błąd CloudKit
- **Unit**: `isTaskAssignedToOther` → false dla własnych zadań, false dla unassigned, true dla cudzych
- **Manual**: Swipe left na cudzym task → pomarańczowy "Poke". Ponowny swipe tego samego dnia → szary "Poked today" + disabled. Własne task → brak swipe action.

---

## Part 8: Gentle Rewards — Duolingo-style Micro-celebrations

### Kontekst

Po ukończeniu zadania wyświetl krótki, pozytywny Toast. Bez punktów, rankingów ani presji — czysta satysfakcja z odhaczenia.

> **Uwaga**: `CelebrationManager.swift` i `ToastView.swift` już istnieją w codebase. Plan jest audit-first — najpierw sprawdź co jest, potem uzupełnij luki.

### 8a. Audit istniejących komponentów (Step 1 — obowiązkowy)

Przed pisaniem kodu sprawdzić:

| Komponent | Lokalizacja | Sprawdź |
|-----------|-------------|---------|
| `CelebrationManager.swift` | `FamilyTodo/Services/` | Czy ma message pools? `getCompletionMessage(for:weeklyCompletedCount:)`? `lastSurpriseDate` logikę? |
| `ToastView.swift` | `FamilyTodo/Views/Components/` | Czy ma auto-dismiss po 3s? Pill shape? Animację? |
| `TaskStore.swift` | `FamilyTodo/Stores/` | Czy completion wywołuje `CelebrationManager`? |
| `ThemeStore.celebrationsEnabled` | `FamilyTodo/Views/ThemeStore.swift` | Czy toggle jest podpięty do logiki celebrations? |

### 8b. Message Pools (uzupełnić w `CelebrationManager` jeśli brakuje)

```swift
// General (≥8 wiadomości)
static let generalMessages = [
    "Boom! Done. 💥",
    "One step closer to a clean home! 🏡",
    "Nailed it! 🎯",
    "Task destroyed! 👾",
    "Love to see it! ✨",
    "Another one bites the dust! 🎵",
    "You're on fire! 🔥",
    "Household hero! 🦸"
]

// Area-specific (jeśli task ma powiązany area/category)
static let kitchenMessages  = ["Kitchen is sparkling! ✨", "Chef's domain is clean! 🍳"]
static let bathroomMessages = ["Bathroom sorted! 🧼", "Shiny and clean! 🛁"]

// Milestones — wyzwalane przez weeklyCompletedCount
static let milestoneMessages = [
    "10 tasks done this week! Home is happy 🏡",
    "5 tasks crushed today! High five ✋"
]

// Surprises — max 1 raz na tydzień (UserDefaults "lastSurpriseDate")
static let surpriseMessages = [
    "Weekend earned! 🎈",
    "You guys are an unstoppable team! 🏆"
]
```

### 8c. Logika `getCompletionMessage` (uzupełnić jeśli brakuje)

```swift
func getCompletionMessage(for task: Task, weeklyCompletedCount: Int) -> String {
    // Rule 1: Milestone (check threshold first)
    if weeklyCompletedCount == 10 || weeklyCompletedCount == 5 {
        return Self.milestoneMessages.randomElement()!
    }

    // Rule 2: Rare surprise — max 1x/tydzień
    let defaults = UserDefaults.standard
    let lastSurprise = defaults.object(forKey: "lastSurpriseDate") as? Date
    let oneWeekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
    if lastSurprise == nil || lastSurprise! < oneWeekAgo {
        if Int.random(in: 1...10) == 1 {   // 10% szansa
            defaults.set(Date(), forKey: "lastSurpriseDate")
            return Self.surpriseMessages.randomElement()!
        }
    }

    // Rule 3: Fallback — general lub area-specific
    // (task.areaId → sprawdź czy kitchen/bathroom → wybierz odpowiednią pulę)
    return Self.generalMessages.randomElement()!
}
```

### 8d. Integracja w `TaskStore.swift` (uzupełnić jeśli brakuje)

W metodzie `moveTask(_:to: .done)` lub `completeTask()`:

```swift
// Po udanym zapisie do CloudKit / zmianie statusu:
let weeklyCount = countWeeklyCompleted()   // FetchDescriptor z SwiftData
if themeStore.celebrationsEnabled {
    let msg = CelebrationManager.shared.getCompletionMessage(
        for: task,
        weeklyCompletedCount: weeklyCount
    )
    await MainActor.run {
        toastMessage = msg
        showToast = true
    }
}
```

### 8e. ToastView — wymagania minimalne (uzupełnić jeśli brakuje)

```swift
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Capsule().fill(.ultraThinMaterial))
            .shadow(radius: 8)
    }
}

// Użycie jako overlay w głównym widoku:
.overlay(alignment: .bottom) {
    if showToast {
        ToastView(message: toastMessage)
            .padding(.bottom, 90)   // ponad tab bar
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { showToast = false }
                }
            }
    }
}
.animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
```

### Pliki do modyfikacji (po audycie — zależnie od wyników)
- `FamilyTodo/Services/CelebrationManager.swift` — uzupełnienie puli i logiki
- `FamilyTodo/Stores/TaskStore.swift` — integracja z CelebrationManager
- `FamilyTodo/Views/Components/ToastView.swift` — uzupełnienie jeśli niekompletny

### Pliki nowe
- Brak (oba pliki już istnieją)

### Testy
- **Unit**: `getCompletionMessage` → milestone dla count==10; surprise max 1/week (`lastSurpriseDate`); fallback general
- **Unit**: `canTriggerSurprise` → false jeśli poniżej tygodnia od ostatniego
- **Manual**: Ukończ task → Toast pojawia się na 3s i auto-dismisses. Brak widoczności gdy `celebrationsEnabled = false`. Milestone przy 5. i 10. zadaniu w tygodniu.

---

## 4) Zmiany przekrojowe (schema, cache, CI)

Przy Part 2/4/5 obowiązuje pełny łańcuch danych:

```
1. Model domenowy (struct) ................ Models/*.swift
2. Model cache SwiftData (@Model) ......... Models/Cached*.swift
3. FamilyTodoApp.appSchema ................ FamilyTodoApp.swift
4. SwiftDataContainerFactory.runtimeModelProbes . Utilities/SwiftDataContainerFactory.swift
5. CloudKit mapping ........................ Managers/CloudKitManager+Mapping.swift
6. CloudKit CRUD .......................... Managers/CloudKitManager.swift
7. cloudkit/schema/housepulse-schema.json .. Schema gate
8. scripts/cloudkit/validate_schema.sh ..... CI validation
9. Testy ................................... FamilyTodoTests/
```

> [!WARNING]
> Pominięcie któregokolwiek kroku spowoduje crash przy uruchomieniu (SwiftData migration) lub fail CI (schema gate).

---

## 5) Ryzyka i guardrails

| Ryzyko | Mitygacja |
|---|---|
| `RecurringChore` jest w `LegacyStubs.swift` — zmiany mogą naruszyć stare ścieżki cache | Pełne testy unit przed merge; rozważyć wyciągnięcie do dedykowanego pliku |
| Push wymaga testów na realnych urządzeniach + 2 Apple ID | Smoke test na fizycznych urządzeniach (iPhone 15 + drugie urządzenie) |
| Schema gate musi być zaktualizowany równolegle z modelem | Aktualizować `housepulse-schema.json` + `validate_schema.sh` w tym samym PR |
| `ShoppingBundle.items` jako sub-records byłoby cięższe | Trzymać jako `itemsJSON` (JSON string) |
| SwiftData migration przy dodawaniu nowych `@Model` do istniejącej bazy | Testy na czystym install + upgrade z poprzedniej wersji |
| `ActivityLogStore` integracja z istniejącymi store'ami wymaga dostępu do `userName` | Injektować `UserSession` reference lub używać singletonowego `ActivityLogStore.shared` |

---

## 6) Definition of Done (per part)

Part uznajemy za domknięty, gdy:
1. ✅ UX działa lokalnie (guest mode) i w sync cloud
2. ✅ Offline cache nie gubi danych po relaunch
3. ✅ Testy unit dla krytycznych ścieżek zielone
4. ✅ Schema gate (dla zmian CloudKit) zielony
5. ✅ GitHub Actions CI przechodzi (build + test)
6. ✅ Smoke test na 2 kontach (jeśli feature dotyczy household sharing/push) zaliczony
7. ✅ Pre-commit hooks (SwiftLint/SwiftFormat) przechodzą

---

## 7) Podsumowanie estymacji

| Part | Trudność | Estymacja (sesje ~4h) | Nowe pliki | Modyfikowane pliki |
|---|---|---|---|---|
| 1. Empty States | 🟢 | 0.5 | 0 | 3 |
| 6. Conversational Filters (UPDATED) | 🟢 | 1 | 0–1 | 1 |
| 8. Gentle Rewards | 🟢 | 0.5–1 | 0 | 2–3 |
| 7. Poke | 🟡 | 1–2 | 0 | 5 |
| 2. Rotation | 🟡 | 2 | 0 | 4–5 |
| 4. Bundles | 🔴 | 3–4 | 4 | 6–7 |
| 5. Activity Log | 🟡 | 2–3 | 4 | 7–8 |
| 3. Push | 🔴 | 2–3 | 0 | 4–5 |
| **TOTAL** | | **~13–17 sesji** | **8** | **~15–22** |

---

## 8) Źródła researchu (techniczne)

- Apple QA1917: https://developer.apple.com/library/archive/qa/qa1917/_index.html
- CloudKit Remote Notifications: https://developer.apple.com/documentation/cloudkit/subscribing-to-database-changes
- CloudKit query/zone subscription constraints:
  - https://developer.apple.com/documentation/cloudkit/ckquerysubscription
  - https://developer.apple.com/documentation/cloudkit/ckrecordzonesubscription
- SwiftUI `ContentUnavailableView`: https://developer.apple.com/documentation/swiftui/contentunavailableview
- CKDatabaseSubscription: https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
- CKFetchDatabaseChangesOperation: https://developer.apple.com/documentation/cloudkit/ckfetchdatabasechangesoperation
