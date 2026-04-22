# Test Coverage Gap Analysis — HousePulse

## Co jest testowane teraz

| Obszar | Pliki testowe | Ocena |
|---|---|---|
| `Task` model (Codable, `isOverdue`, `taskType`) | `TaskTests` | ✅ dobra |
| `TaskStore` — WIP, poke, merge, tombstone, archive, `syncToCache` stale-echo guard | `TaskStoreTests` | ✅ dobra |
| `TaskStore` — sortowanie `nextTasks` (stable sort) | `TaskStoreTests` | ✅ |
| `BacklogStore` — promote, syncToCache tombstone guard, delete blocking, hydration | `BacklogStoreTests` | ✅ dobra |
| `ShoppingListStore` — recent, clear, restore, merge, upsert, bulk add, anchor insert | `ShoppingListStoreTests` | ✅ dobra |
| `Household` / `Member` / `HouseholdStore` — CRUD, zombie guard, pending exit, recovery | `HouseholdTests` | ✅ dobra |
| `UserSession` — guest, cloud override, display name gating, hard reset | `FamilyTodoTests` | ✅ |
| `AuthenticationService` — diagnostics, CK error mapping, flag parsing | `FamilyTodoTests` | ✅ |
| `CloudKitDiagnosticsState` | `FamilyTodoTests` | ✅ |
| `ShareAcceptanceCoordinator` — enqueue/clear | `FamilyTodoTests` | ✅ |
| `CelebrationManager` — milestone, surprise, fallback, resetForDevelopment | `FamilyTodoTests` | ✅ |
| `ThemeStore` — retro family, tab bar colors, reconcile | `FamilyTodoTests` | ✅ |
| `OnboardingState` | `OnboardingStateTests` | ✅ |
| `InviteInputNormalizer` | `InviteInputNormalizerTests` | ✅ |
| `AppTipVisibility` — shopping/ideas/tasks tip sequencing | `AppTipVisibilityTests` | ✅ |
| `TipKit` reset triggers | `AppTipsResetTests` | ✅ |
| `SwiftDataContainerFactory` | `SwiftDataContainerFactoryTests` | ✅ |
| `NotificationSchedulePlanner` (reminder date, daily digest plan) | `TaskTests` | ✅ |
| UI flows — Shopping, Tasks, Backlog, Settings, TipKit, onboarding, perf | `FamilyTodoUITests` | ✅ |

---

## ❌ Czego brakuje (wg priorytetu ryzyka)

### 🔴 Wysokie ryzyko — core flows bez pokrycia

#### `TaskStore` — CRUD mutations (create/update/delete/moveTask)
Testy `TaskStoreTests` pokrywają **read & merge logic**, ale **żaden test nie sprawdza pełnego cyklu zapisu**:
- `createTask(status: .next)` — czy WIP validation faktycznie przechodzi end-to-end?
- `updateTask()` — czy cache aktualizuje się po zmianie pola (title, dueDate, assignee)?
- `deleteTask()` — czy tombstone `pendingDelete` jest tworzony lokalnie?
- `moveTask(_ task, to: .done)` — czy `completedAt` jest ustawiany?
- `toggleTaskCompletion()` — czy przejście `done → next` czyści `completedAt`?

#### `ShoppingListStore` — toggle bought & reorder
- `toggleBought()` — czy `restockCount` wzrasta, `boughtAt` jest ustawiany/czyszczony?
- `moveToBuyItems(from:to:)` — czy `sortOrder` po reorderu jest zapisywany w cache?
- `clearToBuy()` — czy tworzy tombstone `pendingDelete` w cloud mode?
- `markAllAsBought()` — czy wszystkie `toBuyItems` dostają `isBought=true`?

#### `BacklogStore` — edit & reorder
- `updateCategory(newTitle:newColorHex:)` / `renameCategory()` — czy cache i UI są aktualizowane?
- `reorderCategories(orderedIds:)` — czy `sortOrder` jest syncowany?
- `updateItem(title:notes:assigneeId:)` — brak testu przy dostępnym cache row
- `createFromTask()` — zadanie "przenieś z Tasks do Backlog" jako odwrotność promote

### 🟠 Średnie ryzyko — edge cases

#### `TaskStore.syncToCache` z `pendingDelete` w środku
Obecny test `testLoadFromCache_HidesPendingDeleteTasks` sprawdza tylko UI, nie sprawdza, czy cloud echo nie nadpisuje tombstone (**ale** komenda ta jest teraz `private`, co blokuje kompilację — patrz issue #12).

#### `MemberStore` — `updateCurrentUserProfile` z brakującym cachem
- Co gdy `CachedMember` nie istnieje dla danego `userId` podczas `updateCurrentUserProfile`?

#### `ShoppingBundleStore`
Istnieje `ShoppingBundleStoreTests.swift` ale warto sprawdzić co dokładnie pokrywa:
- brakuje testów `applyBundle()` / "quick add bundle to shopping list" flow

#### Household recovery — `recoverableHousehold` z siecią
`testRecoverableHouseholdIgnoresMissingCloudRootAndSuppressesRecovery` istnieje, ale brakuje:
- test gdy `fetchHousehold` zwraca **sukcesowy** wynik z poprawnymi danymi

#### `CelebrationManager` — edge cases
- Co gdy `weeklyCompletedCount == 0`?
- Czy `decideTaskCompletion` jest deterministyczny przy tym samym seedzie?

### 🟡 Niskie ryzyko — brak testów unit, ale jest pokrycie UI

#### `CloudKitManager` / `CloudKitManager+Mapping`
Brak **jakichkolwiek** unit testów dla mappingu CKRecord↔Model poza dwoma testami zaokrąglenia `lastPokedAt` w `TaskTests`. Znaczące pola bez weryfikacji:
- `ShoppingItem` ↔ CKRecord round-trip (quantity, restockCount, boughtAt)
- `BacklogItem` ↔ CKRecord round-trip (notes, categoryId)
- `Member` ↔ CKRecord round-trip (colorHex, role)
- `Household` ↔ CKRecord round-trip (iconSymbol)

Testy CloudKit są hard do napisania bez mockowania — warto rozważyć protokół/mock dla `CloudKitManager`.

#### `NotificationService` / `NotificationSchedulePlanner`
`NotificationSchedulePlanner` jest testowany (daily digest, reminder date), ale:
- `NotificationService.scheduleTaskReminder()` — brak testu implementacji
- `NotificationService.removeTaskReminder()` — brak testu
- `refreshDailyDigest()` — brak testu

#### `RecurringChore` model i store
Obiekt `RecurringChore` pojawia się w schemacie `HouseholdStore` (cleanup w leave/delete), ale brak osobnego `RecurringChoreTests.swift`:
- model Codable round-trip
- logika `recurrenceType` (weekly/monthly)
- brak testu `CachedRecurringChore` mappingu

#### UI Tests — brakujące scenariusze
- **Multi-user sync scenario** — nie da się testować bez prawdziwego CloudKit, ale można zasymulować household z 2 memberami jako seed
- **Hard reset flow** w Settings — brak testu `testSettings_HardReset_RoutesBackToWelcome`
- **Backlog → Tasks promote flow z WIP guardem** — promote gdy assignee ma już 3 taski w Next
- **Task z dueDate** — brak UI testu dla overdue indicator
- **Invite code join flow** — brak UI testu (poza unit testami normalizacji)

---

## Podsumowanie braków wg liczby

| Typ | Ile metod bez pokrycia (szacunek) |
|---|---|
| Store CRUD mutations (create/update/delete) | ~15 |
| Store bulk ops (clearToBuy, markAll, reorder) | ~6 |
| CloudKitManager mapping round-trips | ~8 |
| RecurringChore (model + store) | ~5 |
| NotificationService integration | ~3 |
| UI flows (hard reset, WIP guard promote, dueDate, invite join) | ~4 |

---

## Rekomendacje priorytetów

1. **Napraw kompilację** (issue #11, #12, #13) — bez tego nic nie uruchomi się
2. **Dodaj testy mutacji CRUD** dla `TaskStore`, `ShoppingListStore`, `BacklogStore` — to core protection przed regresją
3. **Dodaj `RecurringChoreTests`** — brakuje całkowicie
4. **Rozważ mock dla `CloudKitManager`** — odblokuje testowanie mapping round-trips bez sieci
5. **Uzupełnij UI testy** o hard reset i WIP guard promote
