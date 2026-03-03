# FEATURES_codex

Last updated: 2026-03-03

## 0) Zakres researchu

Przeczytałem `FEATURES.md` (w tym `NEW NEW NEW`) oraz `FEATURES_claude.md` i porównałem oba plany z aktualnym stanem kodu.

Research objął:
- widoki: `ShoppingListView`, `TasksView`, `BacklogView`, `MoreView`, `RepetitiveTasksView`;
- store’y i modele: `TaskStore`, `ShoppingListStore`, `BacklogStore`, `MemberStore`, `Task`, `CachedTask`;
- CloudKit i push: `CloudKitManager`, `CloudKitManager+Mapping`, `CloudKitSubscriptionManager`, `AppDelegateBridge`, schema i skrypty CI;
- system celebracji/toastów: `CelebrationManager`, `ToastView`, `CelebrationOverlay`;
- testy: `FamilyTodoTests`.

## 0b) Research Resolutions

1. Collaborative task editing:
- Każdy domownik może zmieniać stan zadań przypisanych innym osobom (bez twardych blokad uprawnień).
- Transparentność ma być osiągana przez Activity Log, nie przez restrykcje.

2. Part 6 UX direction:
- Part 6 realizujemy jako conversational filter chips:
  - `All tasks`
  - `My tasks`
  - `[Name]'s tasks`
- Filtr pozostaje ID-based (`.member(UUID)` / `AssigneeFilter.member(UUID)`), nie obiektowy.

## 1) Gap analysis (stan obecny vs roadmapa)

| Part | Status w kodzie | Wniosek | Trudność |
|---|---|---|---|
| 1. Empty states | `ContentUnavailableView` częściowo istnieje (`Backlog`, `Tasks/Completed`) | Częściowo gotowe | 🟢 |
| 2. Due date + rotation | `dueDate` jest wdrożone; round-robin recurring nie jest domknięty | Częściowo gotowe | 🟡 |
| 3. Push notifications | Jest `CKDatabaseSubscription`, brak pełnego AppDelegate remote-push bridge i lepszego event pipeline | Fundament jest, ścieżka niepełna | 🔴 |
| 4. Shopping Bundles | Brak modelu/store/UI/CloudKit | Do wdrożenia | 🔴 |
| 5. Activity Log | Brak pełnego modelu/store/UI i integracji akcji | Do wdrożenia | 🟡 |
| 6. Conversational Task Filters (chips) | Brak chipów `All/My/[Name]'s`; jest tylko Active/Completed | Do wdrożenia | 🟢 |
| 7. Poke (friendly reminder) | Brak `lastPokedAt`, cooldown/store/UI swipe | Do wdrożenia | 🟡 |
| 8. Gentle Rewards | `CelebrationManager` + toast/overlay istnieją; brak pełnej logiki pool/milestone/surprise | Częściowo gotowe (rozszerzenie) | 🟢 |

## 2) Public APIs / Interfaces / Types

1. `Task`:
- `var lastPokedAt: Date?`

2. `CachedTask`:
- `var lastPokedAt: Date?`

3. `TaskStore`:
- `func canPoke(task: Task) -> Bool`
- `func pokeTask(_ task: Task) async -> PokeResult`
- `func weeklyCompletedCount(referenceDate: Date = Date()) -> Int`
- `enum PokeResult { case success, cooldown, failed }`

4. `CelebrationManager`:
- `func getCompletionMessage(for task: Task, weeklyCompletedCount: Int, contextName: String?) -> String`
- `func celebrateTaskCompletion(message: String, milestone: Bool)`

5. `TasksView`:
- `enum AssigneeFilter`
- `@State private var selectedAssigneeFilter`

6. Part 5 (Activity Log):
- `ActivityLog.ActionType`:
  - `taskCompleted`
  - `taskCreated`
  - `shoppingItemAdded`
  - `shoppingItemBought`
- `userId` jest wymaganym atrybutem logu (future self-filtering/push).

## 3) Rekomendowana kolejność wdrożenia (zaktualizowana)

1. Part 6: conversational filters (UI-only, niskie ryzyko).
2. Part 7: model + mapping + store + UI swipe (bez push).
3. Part 7: push groundwork (`AppDelegateBridge` + `CloudKitSubscriptionManager`).
4. Part 8: Gentle Rewards (rozszerzenie istniejącego systemu celebracji).
5. Następnie utrzymujemy wcześniejszą kolejność dla Part 2/4/5/3.

Uwaga: to świadome odstępstwo od propozycji Claude (gdzie Part 8 był wcześniej), żeby utrzymać sekwencję NEW NEW NEW ustaloną dla `FEATURES_codex.md`.

## 4) Plan implementacji per feature

## Part 1: Engaging Empty States

### Co zmieniamy
- `ShoppingListView`: spójny `ContentUnavailableView` dla pustej listy zakupów.
- `TasksView`: pusty stan dla `Active`, nie tylko dla `Completed`.
- `BacklogView`: dopasowanie copy/symbolu do roadmapy.

### Pliki
- `FamilyTodo/Views/ShoppingListView.swift`
- `FamilyTodo/Views/TasksView.swift`
- `FamilyTodo/Views/BacklogView.swift`

### Testy
- Empty state dla Shopping/Tasks/Ideas + CTA.

## Part 2: Due Dates & Rotating Repetitive Tasks

### Stan i plan
- `dueDate` jest wdrożone end-to-end.
- Do dowiezienia: round-robin z trwałym cursorem rotacji i normalizacją po zmianie listy assignee.

### Pliki
- `FamilyTodo/Models/LegacyStubs.swift`
- `FamilyTodo/Views/MoreView.swift`
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
- `cloudkit/schema/housepulse-schema.json`
- `scripts/cloudkit/validate_schema.sh`

### Testy
- A->B->A, zmiany listy assignee, brak duplikacji generatora.

## Part 3: Push Notifications (verification + implementation)

### Kierunek
- Bazujemy na `CKDatabaseSubscription` dla shared DB.
- Domykamy remote push callbacki w `AppDelegateBridge`.
- Nie opieramy strategii na `CKQuerySubscription` jako głównej ścieżce shared DB.

### Pliki
- `FamilyTodo/Services/AppDelegateBridge.swift`
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
- `FamilyTodo/Views/SettingsView.swift` (opcjonalny toggle)

### Testy
- 2 urządzenia + 2 Apple ID, brak self-notify, brak duplikatów.

## Part 4: Shopping Bundles

### Plan
- `ShoppingBundle` + cache + store + CloudKit mapping + CRUD UI + quick add przez long press.

### Pliki
- modele/store/widoki bundli + `CloudKitManager`/schema/validator.

### Testy
- CRUD, serializacja itemów, quick add.

## Part 5: Activity Log

### Plan
- `ActivityLog` + cache + store + `ActivityLogView`.
- Integracja logowania w warstwie store (jedno źródło prawdy).

### ActionType i mapping akcji
- `taskCompleted` -> `TaskStore.moveTask(_:to: .done)`
- `taskCreated` -> `TaskStore.createTask(...)`
- `shoppingItemAdded` -> `ShoppingListStore.createItem(...)`
- `shoppingItemBought` -> `ShoppingListStore.toggleBought(...)` (gdy przejście do bought)

### Wymagania danych
- `userId` wymagane w logu.
- `userName` utrzymane dla czytelności UI.

### Pliki
- nowe modele/store/widok + integracje w `TaskStore` i `ShoppingListStore`.

### Testy
- poprawne wpisy, kolejność chronologiczna, mapowanie cache/cloud.

## Part 6: Conversational Task Filters (chips)  [REPLACES old avatar filter plan]

### Zakres
- W `TasksView` pod `Active/Completed` dodaj poziomy `ScrollView(.horizontal)`.
- Filtr:
  - `.all` (default),
  - `.mine`,
  - `.member(UUID)` dla pozostałych członków.
- Etykiety chipów:
  - `All tasks`,
  - `My tasks`,
  - `\(name)'s tasks`.
- Styl:
  - selected: accent + biały tekst + semibold,
  - unselected: jasnoszary + primary.
- Filtrowanie działa jednocześnie z `Active/Completed`.
- Brak duplikacji current user w chipsach.
- Gdy nie da się ustalić current membera: ukryj `My tasks`.

### Pliki
- `FamilyTodo/Views/TasksView.swift`

### Testy
- `All/My/Name's` dla Active i Completed.
- Toggle filtra i powrót do `.all`.

## Part 7: Poke (Friendly Reminder)

### 7.1 Model i mapowanie
- `Task`: dodaj `lastPokedAt: Date?`.
- `CachedTask`: dodaj pole i mapowanie `init/update/toTask`.
- `CloudKitManager+Mapping`: zapis/odczyt `lastPokedAt`.

### 7.2 Schema i CI
- `cloudkit/schema/housepulse-schema.json`: `Task.lastPokedAt` (`Date`, bez indeksu).
- `scripts/cloudkit/validate_schema.sh`: dopisz `lastPokedAt` do `required_map.Task`.

### 7.3 Store
- `TaskStore.canPoke(task:)`: true gdy `lastPokedAt == nil` lub nie jest today.
- `TaskStore.pokeTask(_:)`:
  - guard z `canPoke`,
  - optimistic update (`lastPokedAt = Date()`, `updatedAt = Date()`),
  - sync cache i CloudKit przez istniejące `saveTask`,
  - zwrot `PokeResult`.

### 7.4 UI
- `TasksView`:
  - `swipeActions(edge: .leading, allowsFullSwipe: false)` dla aktywnych tasków,
  - poke tylko dla tasków przypisanych do kogoś innego,
  - aktywny: `hand.wave.fill`, orange/yellow, label `Poke`,
  - cooldown: `moon.zzz.fill` lub `bell.slash.fill`, gray, disabled,
  - guard na multitap: `@State pokingTaskIDs: Set<UUID>`,
  - haptic na sukces: `HapticManager.impact(.soft)`.

### 7.5 Push groundwork
- `CloudKitSubscriptionManager`:
  - zostaje na `CKDatabaseSubscription`,
  - dodać ścieżkę poke-friendly local notification po remote update.
- `AppDelegateBridge`:
  - dodać `didReceiveRemoteNotification` i forwarding payloadu.
- Treść notyfikacji: friendly i krótka; bez arbitralnych parametrów losowania wpisanych na sztywno do planu.

### Pliki
- `FamilyTodo/Models/Task.swift`
- `FamilyTodo/Models/CachedTask.swift`
- `FamilyTodo/Managers/CloudKitManager+Mapping.swift`
- `FamilyTodo/Stores/TaskStore.swift`
- `FamilyTodo/Views/TasksView.swift`
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
- `FamilyTodo/Services/AppDelegateBridge.swift`
- `cloudkit/schema/housepulse-schema.json`
- `scripts/cloudkit/validate_schema.sh`

### Testy
- cooldown dzienny działa i resetuje się następnego dnia,
- `Task -> CachedTask -> CloudKit -> Task` przenosi `lastPokedAt`,
- poke swipe niewidoczne dla własnych tasków,
- brak duplikacji przy multitap.

## Part 8: Gentle Rewards (rozszerzenie istniejącego systemu)

### Audit
- Istnieją: `CelebrationManager`, `ToastView`, `CelebrationOverlay`, toggle `celebrationsEnabled`.
- Rozszerzamy istniejący system; bez przepisywania od zera.

### Plan
- Rozszerzyć `CelebrationManager`:
  - pule wiadomości (general, area-specific, milestone, surprise),
  - priorytet: milestone -> surprise (max 1/tydzień) -> fallback.
- Dodać API:
  - `getCompletionMessage(for:weeklyCompletedCount:contextName:)`,
  - `celebrateTaskCompletion(message:milestone:)`.
- Completion flow:
  - `TaskStore` dostarcza dane (`weeklyCompletedCount(...)`),
  - `TasksView` decyduje o triggerze komunikatu/celebracji.
- Bez score/rankingu; household-positive tone.

### Pliki
- `FamilyTodo/Services/CelebrationManager.swift`
- `FamilyTodo/Stores/TaskStore.swift`
- `FamilyTodo/Views/TasksView.swift`

### Testy
- priorytet milestone > surprise > fallback,
- surprise max raz na tydzień,
- brak triggera gdy `celebrationsEnabled == false`,
- toast auto-dismiss bez regresji overlay/confetti.

## 5) Zmiany przekrojowe (schema, cache, CI)

Dla zmian model/sync obowiązuje pełny łańcuch:
1. model domenowy,
2. model cache SwiftData,
3. `FamilyTodoApp.appSchema`,
4. `SwiftDataContainerFactory.runtimeModelProbes`,
5. CloudKit mapping (`CloudKitManager+Mapping`),
6. CloudKit CRUD (`CloudKitManager`),
7. schema JSON (`cloudkit/schema/housepulse-schema.json`),
8. schema validator (`scripts/cloudkit/validate_schema.sh`),
9. testy (unit + smoke).

Ostrzeżenie:
- pominięcie kroków 3/4 grozi problemami migracji i crashem przy starcie,
- pominięcie kroków 7/8 grozi failem schema gate w CI.

## 6) Ryzyka i guardrails

| Ryzyko | Mitygacja |
|---|---|
| Ograniczenia push w shared DB | Bazować na `CKDatabaseSubscription`, nie na query-only |
| Niespójne `lastPokedAt` między model/cache/cloud | Wymusić komplet zmian w łańcuchu + testy mapowania |
| Przypadkowy coupling store ↔ UI/theme (Part 8) | `TaskStore` dostarcza dane, trigger i prezentacja w warstwie UI |
| Multi-tap i duplikaty akcji | Guardy stanu w UI/store (`pokingTaskIDs`, result enums) |
| Rozjazd schema vs kod | Aktualizować schema JSON i validator w tym samym PR |

## 7) Definition of Done (per part)

Part uznajemy za domknięty, gdy:
1. UX działa lokalnie i w sync cloud.
2. Offline cache nie gubi danych po relaunch.
3. Testy unit/UI dla krytycznych ścieżek są zielone.
4. Schema gate (dla zmian CloudKit) jest zielony.
5. Smoke test 2 kont (dla ścieżek sharing/push) jest zaliczony.
6. GitHub Actions (build + test) przechodzi.
7. `pre-commit`/lint przechodzą.

## 8) Estymacja orientacyjna (operacyjna)

| Part | Trudność | Estymacja |
|---|---|---|
| 1. Empty states | 🟢 | ~0.5 sesji |
| 6. Conversational filters | 🟢 | ~1 sesja |
| 7. Poke (model/store/ui) | 🟡 | ~1.5–2 sesje |
| 7. Poke (push groundwork) | 🟡 | ~1 sesja |
| 8. Gentle Rewards | 🟢 | ~1 sesja |
| 2. Rotation recurring | 🟡 | ~2 sesje |
| 4. Shopping Bundles | 🔴 | ~3–4 sesje |
| 5. Activity Log | 🟡 | ~2–3 sesje |
| 3. Push final polish | 🔴 | ~2–3 sesje |

## 9) Źródła (techniczne)

- Apple QA1917: https://developer.apple.com/library/archive/qa/qa1917/_index.html
- CloudKit DB subscriptions: https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
- CloudKit remote notifications: https://developer.apple.com/documentation/cloudkit/subscribing-to-database-changes
- CloudKit query subscriptions: https://developer.apple.com/documentation/cloudkit/ckquerysubscription
- SwiftUI `ContentUnavailableView`: https://developer.apple.com/documentation/swiftui/contentunavailableview

## 10) Assumptions i domyślne decyzje

1. `FEATURES_codex.md` pozostaje dokumentem planistycznym (bez dużych snippetów kodu).
2. Filtry assignee pozostają ID-based, nie obiektowe.
3. Architektura store/UI nie jest mieszana dla celebracji.
4. Kolejność dla Part 6/7/8 z `FEATURES_codex.md` ma priorytet nad alternatywną kolejnością z `FEATURES_claude.md`.
5. Część push pozostaje kompatybilna z `CKDatabaseSubscription` jako fundamentem shared DB.
