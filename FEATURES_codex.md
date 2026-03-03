# FEATURES_codex

Last updated: 2026-02-28

## 0) Zakres researchu

Przeczytałem cały `FEATURES.md` i zrobiłem audit kodu oraz architektury pod wszystkie 6 części roadmapy.
Research objął:
- widoki: `ShoppingListView`, `TasksView`, `BacklogView`, `MoreView`, `RepetitiveTasksView`;
- store’y i modele: `TaskStore`, `ShoppingListStore`, `RecurringChoreStore`/`ChoreScheduler`, `Task`, `RecurringChore`, modele cache SwiftData;
- CloudKit: `CloudKitManager`, `CloudKitManager+Mapping`, `CloudKitSubscriptionManager`, `AppDelegateBridge`, schema i skrypty CI;
- testy: `FamilyTodoTests`.

Dodatkowo zweryfikowałem ograniczenia CloudKit push dla shared DB (Apple QA1917 / Remote Notifications docs).

## 1) Gap analysis (stan obecny vs roadmapa)

| Part | Status w kodzie | Wniosek |
|---|---|---|
| 1. Empty states | `ContentUnavailableView` już jest w `BacklogView` i dla Completed w `TasksView`; brak dla pustej listy `Shopping` i pustego `Active` w `Tasks` | Częściowo gotowe, potrzebny UX polish i ujednolicenie |
| 2. Due date + rotation | `Task.dueDate` już istnieje (model, cache, UI, CloudKit). Round-robin nie istnieje. | Due date: done; rotation: do wdrożenia |
| 3. Push notifications | Jest `CloudKitSubscriptionManager` z `CKDatabaseSubscription` (shared DB), ale brak spięcia `AppDelegate` dla remote push i brak pipeline z konkretną treścią eventów. | Audit wykazał częściowy fundament, brak końca procesu |
| 4. Shopping Bundles | Brak modelu, store, CloudKit record type i UI bundli | Do wdrożenia od zera |
| 5. Activity Log | Brak modelu/store/UI/integracji akcji | Do wdrożenia od zera |
| 6. Task filtering by assignee | Brak poziomego filtra avatarów; są tylko przełączniki Active/Completed | Do wdrożenia |

## 2) Rekomendowana kolejność wdrożenia

Kolejność roadmapy jest sensowna, ale technicznie najbezpieczniej:
1. Part 1 (szybki UX win, niskie ryzyko).
2. Part 6 (UI-only + logika filtrowania, bez schema).
3. Part 2 (round-robin + dane recurring).
4. Part 4 (nowy model + CRUD + quick add).
5. Part 5 (ActivityLog, fundament pod konkretne komunikaty push).
6. Part 3 (push end-to-end, najlepiej już na bazie ActivityLog).

Powód: Part 3 bez Part 5 wymaga cięższego parsowania zmian rekordów; z Part 5 push może bazować na gotowych wpisach aktywności.

## 3) Plan implementacji per feature

## Part 1: Engaging Empty States

### Co zmieniamy
- `ShoppingListView`:
  - gdy `store.toBuyItems.isEmpty` i rapid-entry nie jest aktywne, pokazujemy `ContentUnavailableView` zamiast pustej listy;
  - symbol: `cart`; tytuł/subtitle z CTA;
  - action button: „Add first item” -> `startRapidEntry()`.
- `TasksView`:
  - dla `activeFilter == .active` i pustego `visibleNextTasks` wyświetlamy `ContentUnavailableView`;
  - symbol: `checklist`; tekst kierujący do Ideas/promocji do Tasks.
- `BacklogView` (Ideas):
  - obecny empty state jest już poprawny technicznie; tylko dopasowanie copy/symbolu do roadmapy (`lightbulb`).

### Pliki
- `FamilyTodo/Views/ShoppingListView.swift`
- `FamilyTodo/Views/TasksView.swift`
- `FamilyTodo/Views/BacklogView.swift`

### Testy
- UI testy snapshotowe/semantyczne dla pustych ekranów.
- Sprawdzenie, że CTA z empty state faktycznie uruchamia dodawanie.

## Part 2: Due Dates & Rotating Repetitive Tasks

### Co już jest
- `Task.dueDate` jest wdrożone w:
  - modelu (`Task`), cache (`CachedTask`), mapowaniu CloudKit,
  - UI (`TasksView` + `TaskDetailSheet`), sortowaniu, reminderach.
- `RecurringChore` ma już pola pomocnicze dla rotacji (`assigneeIds`, `rotationEnabled`), ale nie są użyte w schedulerze.

### Co trzeba dowieźć
- Round-robin dla recurring chores:
  - rozbudowa `RecurringChore` o trwały cursor rotacji (`nextAssigneeIndex: Int`, rekomendowane);
  - aktualizacja scheduler’a (`ChoreScheduler.runIfNeeded`) aby przypisywał kolejną osobę, nie zawsze `first`;
  - aktualizacja po wygenerowaniu zadania (`markGenerated`) razem ze stanem rotacji.
  - normalizacja cursora przy zmianie listy assignee (`nextAssigneeIndex = min(cursor, max(0, count - 1))`).
- Uzupełnienie modelu cache recurring:
  - obecny `CachedRecurringChore` przechowuje za mało pól (ryzyko utraty danych po offline/online);
  - trzeba zapisać pola recurrence + assignee list + rotation cursor.
- UI konfiguracji recurring:
  - w `RepetitiveTasksView` dodać multi-assignee selection (co najmniej 2 osoby) i tryb rotacji.

### CloudKit schema
- Rekord `RecurringChore`: dodać pole stanu rotacji (`nextAssigneeIndex` Int64 lub równoważne).
- Aktualizacja mapowania w `CloudKitManager+Mapping`.

### Pliki
- `FamilyTodo/Models/LegacyStubs.swift` (RecurringChore / CachedRecurringChore / ChoreScheduler)
- `FamilyTodo/Views/MoreView.swift` (sekcja RepetitiveTasksView)
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
- `cloudkit/schema/housepulse-schema.json`
- `scripts/cloudkit/validate_schema.sh`

### Testy
- rotacja 2+ osób: A->B->A...
- zmiana listy assignee w trakcie (cursor normalization)
- brak duplikacji wygenerowanych tasków dla tego samego dnia

## Part 3: Push Notifications (verification + implementation)

### Wynik audytu
- Jest `CloudKitSubscriptionManager`, ale:
  - brak podpięcia zdalnych push callbacków w `AppDelegateBridge`;
  - obsługa `CKQueryNotification` najpewniej martwa (brak realnych query subscriptions);
  - aktualnie komunikaty są generyczne.

### Ważna decyzja techniczna
- W shared DB nie polegamy na `CKQuerySubscription` jako głównym mechanizmie (Apple QA1917).
- Bazujemy na `CKDatabaseSubscription` + odczycie zmian danych po push.

### Plan
- `AppDelegateBridge`:
  - dodać `didReceiveRemoteNotification:fetchCompletionHandler` i przekazanie payload do `CloudKitSubscriptionManager`.
  - dodać także `didRegisterForRemoteNotificationsWithDeviceToken` i `didFailToRegisterForRemoteNotificationsWithError` (diagnostyka runtime).
- `CloudKitSubscriptionManager`:
  - utrzymać subskrypcję shared DB;
  - wyciąć/ograniczyć martwą ścieżkę query-notification;
  - na push pobierać nowe zdarzenia i składać czytelne notyfikacje.
- Najprostsza stabilna ścieżka:
  - po wdrożeniu Part 5 używać `ActivityLog` jako źródła wiadomości push:
  - filtr: tylko wpisy innych użytkowników,
  - deduplikacja po `activityLog.id`,
  - komunikaty typu „Wojtek completed: Vacuuming”.
- Fallback bez Part 5 (mniej preferowany):
  - pobieranie zmian przez `CKFetchDatabaseChangesOperation` / `CKFetchRecordZoneChangesOperation`,
  - budowanie treści notyfikacji z diffów rekordów.
- Ustawienia:
  - osobny toggle „Partner updates” w `SettingsView` (opcjonalnie, rekomendowane).

### Pliki
- `FamilyTodo/Services/AppDelegateBridge.swift`
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
- `FamilyTodo/Views/SettingsView.swift` (opcjonalny toggle)
- `FamilyTodo/Models/LegacyStubs.swift` (jeśli rozszerzamy NotificationSettingsStore)

### Testy i weryfikacja
- Manualny test 2 Apple ID (fizyczne urządzenia, background/foreground).
- Walidacja: brak self-notify, brak duplikatów, poprawna treść.

## Part 4: Shopping Bundles (Smart Groups)

### Model danych
- Nowy model domenowy `ShoppingBundle`:
  - `id`, `householdId`, `name`, `icon`, `items`, `createdAt`, `updatedAt`, opcjonalnie `sortOrder`.
- Dla CloudKit i obecnych skryptów schema:
  - `items` najlepiej trzymać jako JSON string (`itemsJSON`) zamiast listy stringów (mniej zmian w parserach/validatorze).
- Dodać `CachedShoppingBundle` (SwiftData offline-first).

### Store i sync
- Nowy `ShoppingBundleStore` analogiczny do istniejących store’ów:
  - CRUD bundle,
  - load cache-first,
  - sync cloud w trybie `.cloud`.
- W `CloudKitManager` + mapping dodać save/fetch/delete dla `ShoppingBundle`.

### UI
- `ShoppingListView` header:
  - ikona `archivebox` między `trash` a `clock.badge.checkmark`.
- `BundlesManagementView`:
  - lista bundli,
  - create/edit/delete,
  - edycja listy itemów w bundle.
- Quick add:
  - long press na `shoppingAddItemButton` otwiera poziomą listę ikon bundli;
  - tap bundla dodaje wszystkie itemy do aktywnej listy.

### Pliki
- nowe: `FamilyTodo/Models/ShoppingBundle.swift`, `FamilyTodo/Models/CachedShoppingBundle.swift`, `FamilyTodo/Stores/ShoppingBundleStore.swift`, `FamilyTodo/Views/BundlesManagementView.swift`
- modyfikacje: `FamilyTodo/Views/ShoppingListView.swift`, `FamilyTodo/Managers/CloudKitManager.swift`, `FamilyTodo/Managers/CloudKitManager+Mapping.swift`, `FamilyTodo/FamilyTodoApp.swift`, `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`, `cloudkit/schema/housepulse-schema.json`, `scripts/cloudkit/validate_schema.sh`

### Testy
- unit: CRUD + serializacja `itemsJSON` + quick-add wszystkich pozycji
- UI: otwarcie Bundles i long-press quick add

## Part 5: Activity Log

### Model danych
- Nowy `ActivityLog`:
  - `id`, `householdId`, `actionType`, `userName`, `userId` (rekomendowane), `itemName`, `timestamp`.
- Nowy cache `CachedActivityLog`.
- Store `ActivityLogStore` (load/sync/logAction + opcjonalny retention, np. 30 dni / max 500 wpisów).

### Integracja akcji
- Logowanie przy:
  - dodaniu pozycji zakupowej (`ShoppingListStore.createItem`),
  - ukończeniu taska (`TaskStore.moveTask` przy przejściu do `.done`).
- Wpis logu tworzony w warstwie store (jedno źródło prawdy, nie w samym UI).
- Wymaganie architektoniczne:
  - store’y muszą dostać `userId`/`userName` (przez iniekcję `UserSession` lub adapter kontekstu użytkownika), bo obecnie nie mają tych danych wprost.

### UI
- `MoreView`: link „Activity Log” nad „Settings”.
- `ActivityLogView`: chronologiczna lista (najnowsze na górze), proste opisy.

### CloudKit schema
- nowy record type `ActivityLog` + indeks po `householdId` i sort po `timestamp`.

### Pliki
- nowe: `FamilyTodo/Models/ActivityLog.swift`, `FamilyTodo/Models/CachedActivityLog.swift`, `FamilyTodo/Stores/ActivityLogStore.swift`, `FamilyTodo/Views/ActivityLogView.swift`
- modyfikacje: `FamilyTodo/Stores/TaskStore.swift`, `FamilyTodo/Stores/ShoppingListStore.swift`, `FamilyTodo/Views/MoreView.swift`, `FamilyTodo/Managers/CloudKitManager.swift`, `FamilyTodo/Managers/CloudKitManager+Mapping.swift`, `FamilyTodo/FamilyTodoApp.swift`, `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`, `cloudkit/schema/housepulse-schema.json`, `scripts/cloudkit/validate_schema.sh`

### Testy
- unit: poprawne tworzenie wpisów dla add/complete
- unit: sortowanie chronologiczne i mapowanie cache/cloud

## Part 6: Tasks Filtering by Assignee

### UI i logika
- W `TasksView` pod przełącznikiem Active/Completed dodać poziomy `ScrollView(.horizontal)` z avatarami członków + „Unassigned”.
- Stan filtra:
  - `.all`, `.member(UUID)`, `.unassigned`.
- Tap toggluje filtr, ponowny tap czyści.
- Filtrowanie stosowane do listy poniżej (dla active i completed).

### Detale UX
- Avatar: inicjał + kolor członka (`Member.colorHex`).
- Chip „Unassigned” z ikoną (np. `person.crop.circle.badge.questionmark`).
- Empty state dla aktywnego filtra bez wyników.

### Pliki
- `FamilyTodo/Views/TasksView.swift`

### Testy
- unit (pure filtering helper)
- UI: wybór członka, unassigned, toggle-off

## 4) Zmiany przekrojowe (schema, cache, CI)

Przy Part 2/4/5 trzeba spiąć pełny łańcuch danych:
1. Model domenowy.
2. Model cache SwiftData.
3. `FamilyTodoApp.appSchema`.
4. `SwiftDataContainerFactory.runtimeModelProbes`.
5. CloudKit mapping + CRUD w `CloudKitManager`.
6. `cloudkit/schema/housepulse-schema.json`.
7. `scripts/cloudkit/validate_schema.sh` required map/indexes.
8. Testy unit + smoke manualny cloud.

Pominięcie któregokolwiek z kroków 1-7 grozi albo crashem przy starcie (niespójny model/cache), albo failem schema gate w CI.

## 5) Ryzyka i guardrails

- `RecurringChore` jest dziś w `LegacyStubs.swift`; modyfikacje łatwo mogą naruszyć stare ścieżki cache.
- Push cloud wymaga testów na realnych urządzeniach i 2 Apple ID.
- Schema gate musi być aktualizowany równolegle z modelem (inaczej CI fail).
- Dla `ShoppingBundle.items` rekomenduję JSON string, żeby nie rozszerzać od razu parsera typów schema.
- Dodanie nowych modeli `@Model` wymaga smoke testu upgrade z istniejącej instalacji (ryzyko migracji SwiftData).
- Integracja `ActivityLog` wymaga jawnej strategii dostępu do kontekstu usera w store’ach (bez tego łatwo o logi bez autora).

## 6) Definition of Done (per part)

Part uznajemy za domknięty, gdy:
1. UX działa lokalnie i w sync cloud.
2. Offline cache nie gubi danych po relaunch.
3. Testy unit/UI dla krytycznych ścieżek są zielone.
4. Schema gate (dla zmian CloudKit) jest zielony.
5. Smoke test na 2 kontach (jeśli feature dotyczy household sharing/push) jest zaliczony.
6. GitHub Actions (build + test) przechodzi dla PR.
7. Lokalny lint/hooks (SwiftLint / pre-commit) przechodzą.

## 7) Estymacja orientacyjna

- Part 1: ~0.5 sesji
- Part 6: ~1 sesja
- Part 2: ~2 sesje
- Part 4: ~3-4 sesje
- Part 5: ~2-3 sesje
- Part 3: ~2-3 sesje
- Całość: ~11-14 sesji (przy sesji ~4h)

## 8) Źródła researchu (techniczne)

- Apple QA1917: https://developer.apple.com/library/archive/qa/qa1917/_index.html
- CloudKit Remote Notifications (Apple): https://developer.apple.com/documentation/cloudkit/subscribing-to-database-changes
- CloudKit query/zone subscription constraints in shared DB (Apple docs):
  - https://developer.apple.com/documentation/cloudkit/ckquerysubscription
  - https://developer.apple.com/documentation/cloudkit/ckrecordzonesubscription
- SwiftUI `ContentUnavailableView` (Apple): https://developer.apple.com/documentation/swiftui/contentunavailableview
- CKDatabaseSubscription (Apple): https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
- CKFetchDatabaseChangesOperation (Apple): https://developer.apple.com/documentation/cloudkit/ckfetchdatabasechangesoperation



