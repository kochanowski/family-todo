# FEATURES_codex

Last updated: 2026-03-03

## 0) Zakres researchu

Przeczytałem cały `FEATURES.md` (łącznie z sekcją `NEW NEW NEW`) i zrobiłem aktualny audit kodu pod wszystkie części roadmapy.
Research objął:
- widoki: `ShoppingListView`, `TasksView`, `BacklogView`, `MoreView`, `RepetitiveTasksView`;
- store’y i modele: `TaskStore`, `ShoppingListStore`, `BacklogStore`, `MemberStore`, `Task`, `CachedTask`;
- CloudKit i push: `CloudKitManager`, `CloudKitManager+Mapping`, `CloudKitSubscriptionManager`, `AppDelegateBridge`, schema i skrypty CI;
- istniejący system celebracji/toastów: `CelebrationManager`, `ToastView`, `CelebrationOverlay`;
- testy: `FamilyTodoTests`.

## 1) Gap analysis (stan obecny vs roadmapa)

| Part | Status w kodzie | Wniosek |
|---|---|---|
| 1. Empty states | `ContentUnavailableView` częściowo istnieje (`Backlog`, `Tasks/Completed`), brak pełnej spójności | Częściowo gotowe |
| 2. Due date + rotation | `dueDate` jest wdrożone; round-robin dla recurring chores nie jest domknięty | Częściowo gotowe |
| 3. Push notifications | Jest `CKDatabaseSubscription` w `CloudKitSubscriptionManager`, ale brak pełnego AppDelegate remote-push bridge i event pipeline | Fundament jest, ścieżka niepełna |
| 4. Shopping Bundles | Brak modelu/store/UI/CloudKit dla bundli | Do wdrożenia |
| 5. Activity Log | Brak pełnego modelu/store/UI i integracji akcji | Do wdrożenia |
| 6. Conversational Task Filters (chips) | Brak chipów `All tasks / My tasks / [Name]'s tasks`; jest tylko Active/Completed | Do wdrożenia |
| 7. Poke (friendly reminder) | Brak pola `lastPokedAt`, brak logiki cooldown/store/UI swipe | Do wdrożenia |
| 8. Gentle Rewards | `CelebrationManager` + `ToastView` + `CelebrationOverlay` już istnieją, ale bez nowej logiki message-pool/milestone/surprise | Częściowo gotowe (rozszerzenie) |

## 2) Public APIs / Interfaces / Types do dodania

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

## 3) Rekomendowana kolejność wdrożenia (zaktualizowana)

1. Part 6: Conversational filters (UI-only, niskie ryzyko).
2. Part 7: model + mapping + store + UI swipe (bez push).
3. Part 7: push groundwork (`AppDelegateBridge` + `CloudKitSubscriptionManager`).
4. Part 8: Gentle Rewards (rozszerzenie istniejącego systemu celebracji).
5. Następnie utrzymujemy wcześniej ustaloną kolejność dla Part 2/4/5/3.

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
- `dueDate` jest już wdrożone end-to-end.
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

### Pliki
- `FamilyTodo/Services/AppDelegateBridge.swift`
- `FamilyTodo/Managers/CloudKitSubscriptionManager.swift`
- `FamilyTodo/Views/SettingsView.swift` (opcjonalny toggle)

### Testy
- 2 urządzenia, 2 Apple ID, brak self-notify, brak duplikatów.

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
- Integracja logowania przy add shopping item i complete task.

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
- Brak duplikacji własnego użytkownika (`My tasks` nie dubluje `Wojtek's tasks`).
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
- Teksty notyfikacji: krótka statyczna lub lokalnie losowana pula.

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
- Nie tworzymy nowego systemu od zera, tylko rozszerzamy logikę.

### Plan
- Rozszerzyć `CelebrationManager`:
  - pule wiadomości (~20): general, area-specific, milestone, surprise,
  - priorytet: milestone -> surprise (max 1/tydzień przez `UserDefaults`) -> general/area.
- Dodać API:
  - `getCompletionMessage(for:weeklyCompletedCount:contextName:)`,
  - `celebrateTaskCompletion(message:milestone:)`.
- Completion flow:
  - `TaskStore.weeklyCompletedCount(...)`,
  - `TasksView` po udanym przejściu do `.done` pobiera message i pokazuje toast przez `CelebrationManager`.
- Zero score/rankingu; tone household-positive.

### Pliki
- `FamilyTodo/Services/CelebrationManager.swift`
- `FamilyTodo/Stores/TaskStore.swift`
- `FamilyTodo/Views/TasksView.swift`
- (bez zmian architektury dla `ToastView`/`CelebrationOverlay`, tylko kompatybilność)

### Testy
- milestone wygrywa nad message standardowym,
- surprise max raz na tydzień,
- toast auto-dismiss bez regresji overlay/confetti.

## 5) Zmiany przekrojowe (schema, cache, CI)

Przy zmianach modelu/sync (w tym Part 7 `lastPokedAt`) obowiązkowo:
1. model domenowy (`Task`);
2. cache SwiftData (`CachedTask`);
3. mapping CloudKit (`CloudKitManager+Mapping`);
4. schema JSON (`cloudkit/schema/housepulse-schema.json`);
5. schema validator (`scripts/cloudkit/validate_schema.sh`);
6. smoke test sync cloud + testy lokalne.

Pominięcie kroku 4 lub 5 skończy się failem schema gate w CI.

## 6) Ryzyka i guardrails

- Shared DB push ma ograniczenia; nie zakładamy `CKQuerySubscription` jako jedynej ścieżki.
- `lastPokedAt` musi być obsłużone spójnie w model/cache/cloud, inaczej pojawią się desynchronizacje.
- Part 8 ma nie wejść w gamifikację rankingową (kontrakt produktowy).
- Multi-tap przy poke i completion wymaga jawnych guardów UI/store.

## 7) Definition of Done (per part)

Part uznajemy za domknięty, gdy:
1. UX działa lokalnie i w sync cloud.
2. Offline cache nie gubi danych po relaunch.
3. Testy unit/UI dla krytycznych ścieżek są zielone.
4. Schema gate (dla zmian CloudKit) jest zielony.
5. Smoke test na 2 kontach (jeśli feature dotyczy household sharing/push) jest zaliczony.
6. GitHub Actions (build + test) przechodzi.

## 8) Estymacja orientacyjna (z aktualizacją NEW NEW NEW)

- Part 6 (chips): ~1 sesja
- Part 7 model/store/ui: ~1.5-2 sesje
- Part 7 push groundwork: ~1 sesja
- Part 8 rewards extension: ~1 sesja

## 9) Źródła (techniczne)

- Apple QA1917: https://developer.apple.com/library/archive/qa/qa1917/_index.html
- CloudKit DB subscriptions: https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription
- CloudKit remote notifications: https://developer.apple.com/documentation/cloudkit/subscribing-to-database-changes
- SwiftUI `ContentUnavailableView`: https://developer.apple.com/documentation/swiftui/contentunavailableview


