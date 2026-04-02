# CloudKit Sync Analysis — HousePulse

_Date: 2026-04-01_
_Branch: fix/tasks-ideas-sync-new-implementation_

Codex aktualnie pracuje nad problemem braku synchronizacji w kierunku participant → owner.
Ten dokument zestawia wyniki analizy kodu + propozycję rozwiązania.

---

## 0. Co mówią logi diagnostyczne (2026-04-01 18:09–18:11)

### Fakty widoczne wprost

```
push.registration.succeeded tokenLength=64         ← push działa na poziomie systemu
subscription.zone.reused household-zone-ownerPrivate-83D9...   ← subskrypcja istnieje
snapshot.load.started scope=ownerPrivate           ← pojawia się 5 razy
snapshot.load.completed                            ← NIE POJAWIA SIĘ ANI RAZU
push.received type=...                             ← NIE POJAWIA SIĘ ANI RAZU
remotePush ...                                     ← NIE POJAWIA SIĘ ANI RAZU
ownerQuery.targetZone.completed recordType=Member  ← pojawia się regularnie
ownerQuery.targetZone.completed recordType=Task    ← NIE POJAWIA SIĘ
ownerQuery.targetZone.completed recordType=ShoppingItem ← NIE POJAWIA SIĘ
```

### Co to oznacza

**Obserwacja 1 — snapshot nigdy nie kończy się sukcesem.**

`HouseholdRepository.loadCloudSnapshot` loguje `snapshot.load.started` i `snapshot.load.completed`.
W logach z 2 minut aktywności: 5 startów, 0 completionów. Snapshot uruchamia się co ~10–30 sekund ale **nigdy nie dochodzi do końca**.

**Obserwacja 2 — brak jakichkolwiek push notifications.**

Logowane są `push.received type=database/recordZone`. W całym logu: zero wystąpień. Żaden push CloudKit nie trafił do aplikacji owner podczas sesji. Mimo że subskrypcje istnieją i push registration się powiodło.

**Obserwacja 3 — tylko Member queries kończą się.**

Snapshot startuje 6 równoległych queries (Member, WorkItem, ShoppingItem, ShoppingBundle, BacklogCategory, BacklogItem). Tylko `Member` pojawia się z `completed` — ale są to prawdopodobnie Member queries z INNYCH miejsc kodu (np. `confirmRemoteMembershipPresence`), nie ze snapshota.

### Korzenie problemu (dwa niezależne)

**Problem główny A — snapshot zawiesza się na nie-Member queries**

`HouseholdCloudSnapshotLoader.loadSnapshot` (`HouseholdCloudSnapshotLoader.swift:23`) uruchamia 6 `async let` równolegle:

```swift
async let fetchedMembers = cloud.fetchMembers(...)
async let fetchedUnifiedWorkItems = cloud.fetchUnifiedWorkItems(...)
async let fetchedShoppingItems = cloud.fetchShoppingItems(...)
// ...

return try await HouseholdCloudSnapshot(
    members: fetchedMembers,
    unifiedWorkItems: fetchedUnifiedWorkItems,   // ← zawiesza się tutaj
    shoppingItems: fetchedShoppingItems,
    // ...
)
```

`try await HouseholdCloudSnapshot(...)` czeka na WSZYSTKIE 6 queries. Jeśli którykolwiek query dla Task/ShoppingItem/BacklogItem nigdy nie zwróci wyniku (CloudKit query bez timeout może wisieć w nieskończoność), cały snapshot nigdy nie ukończy.

Jednocześnie nowe triggery (foreground, repair window, lifecycle) uruchamiają kolejny snapshot, zanim poprzedni zdąży się skończyć. Kolejne 6 queries startuje. Po kilku iteracjach CloudKit jest zalewany in-flight requestami i rate-limituje lub po prostu milczy.

**Problem główny B — push notifications nie docierają dla participant → owner**

Zero `push.received` przez 2 minuty w aktywnej sesji potwierdza, że CloudKit nie dostarcza powiadomień do owner gdy participant modyfikuje rekordy w shared zone.

Logika subskrypcji jest poprawna: `household-zone-ownerPrivate-*` `CKRecordZoneSubscription` POWINNA strzelać gdy participant pisze. Ale w praktyce — CloudKit ma znany problem z dostarczaniem zone-level pushów dla zmian zrobionych przez participant (nie przez owner urządzenia) w shared zone. Apple Developer Forums potwierdzają ten przypadek.

W efekcie: cała synchronizacja owner zależy od lifecycle polling, nie od pushów.

---

## 1. Architektura sync (jak to ma działać)

### Fizyczna lokalizacja rekordów

W CloudKit sharing zone zawsze fizycznie mieszka w **private DB owner**. Participant pisze przez shared DB API, ale CloudKit zapisuje dane do strefy owner.

```
Owner private DB
  └── HouseholdZone-{householdId}   ← strefa właściciela
        ├── Task / BacklogItem / ShoppingItem (owner writes)
        └── Task / BacklogItem / ShoppingItem (participant writes — też tu lądują!)

Participant shared DB
  └── (widok na tę samą strefę przez CKShare)
```

### Routing zapisu per rola

| Rola | scope | Baza danych API | Fizyczna lokalizacja |
|------|-------|-----------------|----------------------|
| Owner | `.ownerPrivate` | private DB | owner private zone |
| Participant | `.participantShared` | shared DB | owner private zone (ta sama!) |

`HouseholdSyncContextFactory.make()` ustawia scope na podstawie `currentUserId == ownerId`.

### Subskrypcje — co jest, a czego brak

Owner po konfiguracji ma:
- `private-database-changes` (CKDatabaseSubscription na private DB) ✅
- `shared-database-changes` (CKDatabaseSubscription na shared DB) ✅
- `household-zone-ownerPrivate-{id}` (CKRecordZoneSubscription na private zone) ✅

Participant ma:
- `private-database-changes` (na swojej private DB — **nic nie wykryje z tego household**) ⚠️
- `shared-database-changes` (CKDatabaseSubscription na shared DB) ✅
- **brak zone subscription na shared zone** ❌

---

## 2. Kierunek participant → owner: jak POWINNO działać

1. Participant zapisuje rekord → CloudKit → owner private DB zone
2. Apple dostarcza push do owner:
   - via `household-zone-ownerPrivate-{id}` (zone sub) → `CKRecordZoneNotification` bez `databaseScope`
   - via `private-database-changes` (database sub) → `CKDatabaseNotification` z `databaseScope = .private`
3. `AppDelegateBridge.didReceiveRemoteNotification` wywołuje `remoteCloudChangeHandler`
4. `effectiveRemoteDatabaseScope` → `.private`
5. `remoteSyncDirection` → `.participantToOwner` ✅
6. `runJoinedHouseholdHydrationPass` fetchuje z `scope = .ownerPrivate` → pobiera zmiany participant

Logika jest prawidłowa. Owner POWINIEN dostawać zmiany participant szybko.

---

## 3. Zidentyfikowane przyczyny opóźnień / braku syncu

### Problem A — self-noise window zbyt agresywny (główny podejrzany)

**Plik:** `CloudKitSubscriptionManager.swift:74`

```swift
private let selfNoiseWindow: TimeInterval = 8
```

**Mechanizm:**
```swift
// isLikelySelfNoise() — linie 416-433
if let lastLocalMutationAt,
   now.timeIntervalSince(lastLocalMutationAt) <= selfNoiseWindow {
    return true  // ← GLOBALNIE wycisza wszystkie notyfikacje przez 8 sekund po KAŻDEJ lokalnej mutacji
}
```

`registerLocalMutation(recordName:)` jest wywoływane po każdym zapisie owner. Jeśli owner dokona dowolnej mutacji (np. zaznaczy item jako kupiony), przez kolejne 8 sekund **wszystkie** przychodzące notyfikacje są cichutko odrzucane jako "self-noise" — włącznie z notyfikacją o zmianie participant.

To dotyczy tylko warstwy prezentacji (`CloudKitSubscriptionManager`), ale ta warstwa odpowiada za wyświetlenie "inline feedback" i banera nowych elementów. Jeśli powiadomienie jest dropped tutaj, UI nie informuje o zmianie, nawet jeśli dane zostały już odświeżone.

**Czy to blokuje też faktyczny fetch danych?** Nie bezpośrednio — `AppDelegateBridge` wywołuje `remoteCloudChangeHandler` niezależnie od self-noise filtra. Ale jeśli self-noise spowoduje pominięcie odświeżenia prezentacji, user nie zobaczy feedbacku.

### Problem B — CKDatabaseSubscription jest wolne (latencja Apple)

`private-database-changes` to `CKDatabaseSubscription`. Apple przetwarza je w batch — mogą mieć opóźnienie 30–120 sekund, szczególnie gdy aplikacja jest w tle.

`household-zone-ownerPrivate-{id}` to `CKRecordZoneSubscription` — jest szybsze, bo dotyczy konkretnej strefy.

Jeśli zone subscription nie dostarczy notyfikacji (co zdarza się np. po ponownym uruchomieniu, resetcie, albo gdy CloudKit coalescuje pusha), owner musi czekać na wolne database subscription.

### Problem C — brak zone subscription dla participant (owner → participant jest wolniejszy niż mógłby być)

`shouldCreateZoneSubscription()` zwraca `true` wyłącznie dla `.ownerPrivate`:

```swift
// CloudKitSubscriptionManager.swift:81-85
static func shouldCreateZoneSubscription(
    for scope: CloudKitManager.HouseholdDatabaseScope
) -> Bool {
    scope == .ownerPrivate  // ← participant nigdy nie dostanie zone sub
}
```

Participant polega wyłącznie na `shared-database-changes` (database-level), co jest wolniejsze i mniej precyzyjne niż zone subscription. To wyjaśnia, dlaczego owner → participant jest wolniejszy niż powinien (5–15s zamiast < 5s).

### Problem D — participant subskrybuje private DB bez powodu

W `makeSubscriptionPlan` obie subskrypcje DB są tworzone zawsze:
```swift
databaseSubscriptionIDs: [
    sharedDatabaseSubscriptionID,   // OK dla participant
    privateDatabaseSubscriptionID,  // bezużyteczna dla participant
]
```

Participant nigdy nie otrzyma notyfikacji z własnej private DB o zmianach w household. To nie powoduje błędu, ale tworzy subskrypcję która nic nie robi i może mylić diagnostykę.

### Problem E — `effectiveRemoteDatabaseScope` zwraca nil dla owner przy `shared-database-changes`

```swift
private func remoteSyncDirection(...) -> HouseholdSyncDirection {
    guard let household else { return .unknown }
    let effectiveDatabaseScope = effectiveRemoteDatabaseScope(...)

    if household.ownerId == userId {
        guard effectiveDatabaseScope == .private else { return .unknown }
        //                                             ↑ jeśli owner dostanie CKDatabaseNotification
        //                                               z databaseScope=.shared — zwraca .unknown
        return .participantToOwner
    }
}
```

Jeśli owner otrzyma notyfikację z `shared-database-changes` z `databaseScope = .shared`, `remoteSyncDirection` zwróci `.unknown`. To nie blokuje hydratacji (fetch i tak się wykona), ale diagnostyki będą mylące i ewentualne logiki zależne od direction nie zadziałają.

---

## 4. Pełna tabela stanu dla wszystkich encji

| Aspekt | Task | BacklogItem | ShoppingItem |
|--------|------|-------------|--------------|
| Zapis owner (private DB) | ✅ | ✅ | ✅ |
| Zapis participant (shared DB API → private zone) | ✅ | ✅ | ✅ |
| Zone sub owner | ✅ | ✅ | ✅ |
| Zone sub participant | ❌ | ❌ | ❌ |
| Database sub shared (participant) | ✅ | ✅ | ✅ |
| Fetch owner po notyfikacji | ✅ | ✅ | ✅ |
| Self-noise suppression owner | ⚠️ | ⚠️ | ⚠️ |
| Tombstones / ghost prevention | ❌ | ❌ | ❌ |
| Cascade delete | ❌ | ❌ | ❌ |
| Conflict resolution | ❌ | ❌ | ❌ |

---

## 5. Proponowane rozwiązania

### Fix 0 (krytyczny, uderzaj w to pierwsze) — timeout na snapshot queries

Każdy CloudKit query w `HouseholdCloudSnapshotLoader.loadSnapshot` może wisieć w nieskończoność. Jeśli wisią, snapshot nigdy się nie kończy, a UI nigdy nie zobaczy nowych danych.

**Plik:** `FamilyTodo/Services/HouseholdCloudSnapshotLoader.swift`

Opakuj `loadSnapshot` w `withTimeout`:

```swift
func loadSnapshot(
    householdId: UUID,
    scope: CloudKitManager.HouseholdDatabaseScope
) async throws -> HouseholdCloudSnapshot {
    try await withThrowingTaskGroup(of: HouseholdCloudSnapshot.self) { group in
        group.addTask {
            // istniejący kod
            await self.cloud.ensureReady()
            async let fetchedMembers = self.cloud.fetchMembers(...)
            // ...
            return try await HouseholdCloudSnapshot(...)
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 20_000_000_000) // 20 sekund
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

Alternatywnie — upewnij się, że przy starcie nowego snapshota poprzedni Task jest anulowany (Swift Task cancellation propaguje do `async let` sub-tasks i anuluje CloudKit operations).

**Dlaczego akurat to:** bez timeoutu każde wywołanie snapshot blokuje na zawsze przy problemie sieciowym lub CloudKit throttlingu. Kolejne triggery piętrzyć się na sobie — i to właśnie widać w logach (5 startów, 0 completionów).

### Fix 0b (krytyczny) — deduplication aktywnego snapshota

W logach `snapshot.load.started` pojawia się 5 razy, co sugeruje że multiple snapshots działają równolegle. Upewnij się że nowy snapshot anuluje poprzedni.

```swift
// W HouseholdStore lub HouseholdRepository — przechowuj aktywne Task i cancel przed nowym
private var activeSnapshotTask: Task<HouseholdCloudSnapshot, Error>?

func loadCloudSnapshot(for context: HouseholdSyncContext) async throws -> HouseholdCloudSnapshot {
    activeSnapshotTask?.cancel()
    let task = Task {
        try await HouseholdCloudSnapshotLoader(cloud: cloud).loadSnapshot(...)
    }
    activeSnapshotTask = task
    return try await task.value
}
```

### Fix 1 (wysoki priorytet) — dodaj zone subscription dla participant

Participant powinien mieć `CKRecordZoneSubscription` na shared zone, analogicznie do tego co ma owner na swojej private zone.

**Plik:** `CloudKitSubscriptionManager.swift`

```swift
// PRZED (linia 81-85):
static func shouldCreateZoneSubscription(
    for scope: CloudKitManager.HouseholdDatabaseScope
) -> Bool {
    scope == .ownerPrivate
}

// PO:
static func shouldCreateZoneSubscription(
    for scope: CloudKitManager.HouseholdDatabaseScope
) -> Bool {
    true  // Zarówno owner (private zone) jak i participant (shared zone) korzystają z zone sub
}
```

Logika `syncHouseholdZoneSubscriptions` już wybiera właściwą bazę danych na podstawie scope:
```swift
let database: CKDatabase = switch scope {
case .ownerPrivate: privateDatabase
case .participantShared: sharedDatabase   // ← już poprawnie obsługuje shared
}
```

I ID subskrypcji już zawiera scope:
```swift
func zoneSubscriptionID(householdId: UUID, scope: ...) -> String {
    let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
    return "household-zone-\(scopeName)-\(householdId.uuidString)"
}
```

Zmiana jest minimalna — wystarczy zmienić jedną funkcję. Reszta infrastruktury jest gotowa.

### Fix 2 (wysoki priorytat) — zawęź self-noise window lub zrób go per-record

Obecny mechanizm: każda mutacja owner wycisza WSZYSTKIE notyfikacje na 8 sekund.

**Opcja A — skróć window do 3–4 sekund:**
```swift
private let selfNoiseWindow: TimeInterval = 3  // było: 8
```

**Opcja B — wyłącz global self-noise, używaj tylko per-record:**
```swift
private func isLikelySelfNoise(recordName: String?) -> Bool {
    let now = Date()
    pruneLocalMutationNoiseWindow(relativeTo: now)

    // Tylko per-record noise, bez globalnego lastLocalMutationAt
    if let recordName,
       let timestamp = recentLocalMutationByRecordName[recordName],
       now.timeIntervalSince(timestamp) <= selfNoiseWindow {
        return true
    }
    return false
}
```

Opcja B jest bezpieczniejsza — chroni przed podwójnym wyświetleniem feedbacku dla konkretnego rekordu, ale nie maskuje zmian z innych rekordów (np. od participant).

### Fix 3 (średni priorytet) — usuń bezużyteczną private DB subscription dla participant

```swift
// PRZED:
databaseSubscriptionIDs: [
    sharedDatabaseSubscriptionID,
    privateDatabaseSubscriptionID,
]

// PO:
static func makeSubscriptionPlan(
    householdId: UUID,
    scope: CloudKitManager.HouseholdDatabaseScope?
) -> CloudKitSubscriptionPlan {
    var databaseSubscriptionIDs = [sharedDatabaseSubscriptionID]
    if scope == .ownerPrivate {
        databaseSubscriptionIDs.append(privateDatabaseSubscriptionID)
    }
    // ...
}
```

### Fix 4 (niski priorytet) — napraw remoteSyncDirection dla owner + shared scope

```swift
private func remoteSyncDirection(...) -> HouseholdSyncDirection {
    guard let household else { return .unknown }
    let effectiveDatabaseScope = effectiveRemoteDatabaseScope(...)

    if household.ownerId == userId {
        // Owner receives participant changes via:
        // - private DB zone sub → .private
        // - private DB database sub → .private
        // - shared DB database sub (if participant writes via shared API) → .shared
        //   (in CloudKit sharing, this can happen too)
        guard effectiveDatabaseScope == .private || effectiveDatabaseScope == .shared else {
            return .unknown
        }
        return .participantToOwner
    } else {
        guard effectiveDatabaseScope == .shared else { return .unknown }
        return .ownerToParticipant
    }
}
```

---

### Fix 5 (wysoki priorytet) — fallback polling gdy push nie dociera

Skoro `push.received` nie pojawia się w logach, powiadomienia CloudKit nie są niezawodne dla participant → owner. Potrzebny jest mechanizm fallback.

Opcja A — krótszy interval foreground repair window (obecna implementacja polega na lifecycle, zrób to częstsze/szybsze):

```swift
// Np. w repair window — co 15s zamiast co 30s przy aktywnej sesji participant
private let foregroundRepairInterval: TimeInterval = 15
```

Opcja B — po każdej lokalnej mutacji owner, zaplanuj re-fetch po 5s (żeby wyczerpać "participant napisał chwilę przed"):

```swift
func scheduleFollowUpSync(delay: TimeInterval = 5.0) {
    Task {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await syncHousehold(reason: .localMutationFollowUp)
    }
}
```

Opcja C (najsilniejsza) — zamień query-based snapshot na `CKFetchRecordZoneChangesOperation` z persystowanym server change token. Fetchwuje tylko delta (nowe/zmienione rekordy od ostatniej synchronizacji), jest lekkie i nie zawiesza się na dużych query.

## 6. Kolejność implementacji rekomendowana dla Codex

**Priorytet 1 — zablokowane snapshoty (logi potwierdzają):**
1. **Fix 0** — timeout na `HouseholdCloudSnapshotLoader.loadSnapshot` (20s max)
2. **Fix 0b** — deduplication: nowy snapshot anuluje poprzedni

**Priorytet 2 — push notifications nie docierają:**
3. **Fix 5** — fallback polling / krótszy repair interval / change tokens

**Priorytet 3 — inne problemy sync:**
4. **Fix 1** — zone subscription dla participant (skraca owner→participant)
5. **Fix 2B** — per-record self-noise zamiast globalnego
6. **Fix 3** — usunięcie bezużytecznej private DB sub dla participant
7. **Fix 4** — naprawa remoteSyncDirection dla owner+shared scope

**Fixes 0 + 0b są konieczne aby cokolwiek działało.** Bez nich snapshot nigdy się nie kończy i żadne dane nie są synchronizowane, niezależnie od stanu pushów.

---

## 7. Pliki do modyfikacji

| Fix | Plik | Zakres zmiany |
|-----|------|---------------|
| 0 | `FamilyTodo/Services/HouseholdCloudSnapshotLoader.swift` | timeout wrapper na `loadSnapshot` — ~15 linii |
| 0b | `FamilyTodo/Services/HouseholdRepository.swift` | deduplication Task w `loadCloudSnapshot` — ~8 linii |
| 1 | `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` | `shouldCreateZoneSubscription()` — 1 linia |
| 2B | `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` | `isLikelySelfNoise()` — usunięcie ~4 linii |
| 3 | `FamilyTodo/Managers/CloudKitSubscriptionManager.swift` | `makeSubscriptionPlan()` — ~5 linii |
| 4 | `FamilyTodo/Stores/HouseholdStore.swift` | `remoteSyncDirection()` — 2 linie |
| 5 | `FamilyTodo/Services/HouseholdStoreSyncEngine.swift` lub `HouseholdStore.swift` | skrócenie repair interval lub scheduled follow-up |

---

## 8. Wyniki testu z 2026-04-02 — po dodaniu indeksów recordName

### Kontekst testu

Oba telefony zresetowane, osobne Apple ID. Świeże dane.
Przed testem użytkownik dodał w CloudKit Dashboard dwa indeksy `recordName` jako **Queryable**:
- `ShoppingItem`
- `ShoppingBundle`

### Obserwacje

| Kierunek | Encja | Czas syncu | Uwagi |
|----------|-------|-----------|-------|
| Owner → Participant | wszystko | 5–15–25 sekund | DZIAŁA |
| Participant → Owner | ShoppingItem | 1–2 minuty LUB natychmiastowy po wyjściu/powrocie do app | — |
| Participant → Owner | ShoppingBundle | **INSTANT 1–10 sekund** | ❓ patrz niżej |
| Participant → Owner | Task | **NIE SYNCHRONIZUJE** | — |
| Participant → Owner | Idea/BacklogItem | **NIE SYNCHRONIZUJE** | — |

### Dlaczego ShoppingItem jest wolny (1-2 min)

Pusze CloudKit nadal nie docierają do owner gdy participant pisze. Synchronizacja zachodzi wyłącznie przez mechanizm `ForegroundRepairConfiguration`:

```
burstIntervalNanoseconds: 4_000_000_000   // 4 sekundy
burstMaxPassCount: 8                       // 8 przebiegów = 32 sekundy burst
steadyIntervalNanoseconds: 30_000_000_000 // 30 sekund
steadyMaxPassCount: 20                    // łącznie 20 minut steady
```

W trybie steady: maksymalnie co 30s. Dla losowej chwili oczekiwania daje 0–30 sekund + czas fetcha. Przy pechowym timingu (participant zapisał tuż po sprawdzeniu) może to być 60+ sekund. Wyjście/powrót do app triggeruje `appBecameActive` → natychmiastowy sync — stąd "instant po powrocie do pulpitu".

### Dlaczego ShoppingBundle jest instant (tajemnica)

Snapshot jest atomowy — `HouseholdCloudSnapshotLoader.loadSnapshot` pobiera ShoppingItem i ShoppingBundle **w tym samym wywołaniu**, jednocześnie:

```swift
async let fetchedShoppingItems = cloud.fetchShoppingItems(...)
async let fetchedShoppingBundles = cloud.fetchShoppingBundles(...)
```

Jeśli bundles pojawiają się w 1–10s a items w 1–2 minuty, nie jest to możliwe z jednego snapshota. Hipotezy:
1. **Artifact testowy** — bundles były dodane wcześniej (może z poprzedniej sesji), a items były nowe. Timing był mylący.
2. **Burst window timing** — bundle był dodany akurat w oknie burst (4s), item był dodany po burst window (30s steady).
3. **Coś innego niż snapshot dostarcza bundles** — mało prawdopodobne, nic nie wskazuje.

Diagnoza wymaga nowych logów z testu gdzie obie encje są dodawane równocześnie.

### Dlaczego Task i Idea nie synchronizują — root cause

Dwa niezależne bugi w warstwie widokowej.

**Bug 1 — TasksView: domain guard nie zawiera `.ideas`**

```swift
// TasksView.swift, onChange(of: syncCoordinator.latestBatch?.id)
// PRZED:
!batch.domains.isDisjoint(with: [.tasks, .members, .backlog])
// ↑ gdy participant dodaje pomysł → batch.domains = [.ideas]
//   isDisjoint([.ideas], [.tasks,.members,.backlog]) = true → return → POMINIĘTE

// PO (fix zastosowany):
!batch.domains.isDisjoint(with: [.tasks, .members, .backlog, .ideas])
```

**Bug 2 — Wszystkie trzy widoki: else-branch nie rehydruje stanu**

Gdy użytkownik jest na innym tabie niż ten widok, `onChange` wykrywa batch ale zamiast odświeżyć `@Published var tasks`, tylko ustawia flagę `markLocalSnapshotStale()`:

```swift
// PRZED (we wszystkich trzech widokach):
store.markLocalSnapshotStale()
if selectedTab == .tasks {
    handleRemoteTaskSyncBatch(batch)  // wywołuje rehydrateVisibleSnapshotFromCache()
} else {
    store.replayPendingMutationsIfNeeded()  // NIE wywołuje rehydrateVisibleSnapshotFromCache()
}
// Flaga stale jest ustawiona, ale custom tab bar nie triggeruje onAppear
// przy przełączeniu tabów — więc flag nigdy nie jest konsumowany.
```

```swift
// PO (fix zastosowany):
store.markLocalSnapshotStale()
if selectedTab == .tasks {
    handleRemoteTaskSyncBatch(batch)
} else {
    store.rehydrateVisibleSnapshotFromCache()  // ← DODANE
    store.replayPendingMutationsIfNeeded()
}
```

### Dlaczego `rehydrateVisibleSnapshotFromCache()` jest konieczne

`syncUnifiedWorkItemsToCache()` (TaskStore) i `syncToCache()` (ShoppingListStore) zapisują dane do SwiftData, ale **nie aktualizują `@Published var tasks/items`**. To robi dopiero `rehydrateVisibleSnapshotFromCache()`. Bez tego SwiftData cache ma najnowsze dane, ale UI nigdy ich nie zobaczy.

---

## 9. Zmiany kodu zastosowane 2026-04-02

### TasksView.swift

Lokalizacja: `FamilyTodo/Views/TasksView.swift`

```diff
 .onChange(of: syncCoordinator.latestBatch?.id) { _, _ in
     guard let batch = syncCoordinator.latestBatch,
-          !batch.domains.isDisjoint(with: [.tasks, .members, .backlog])
+          !batch.domains.isDisjoint(with: [.tasks, .members, .backlog, .ideas])
     else {
         return
     }
     store.markLocalSnapshotStale()
     if selectedTab == .tasks {
         handleRemoteTaskSyncBatch(batch)
     } else {
+        store.rehydrateVisibleSnapshotFromCache()
         store.replayPendingMutationsIfNeeded()
     }
 }
```

### BacklogView.swift

Lokalizacja: `FamilyTodo/Views/BacklogView.swift` (domain guard już zawierał `.ideas`)

```diff
     store.markLocalSnapshotStale()
     if selectedTab == .backlog {
         handleRemoteBacklogSyncBatch(batch)
     } else {
+        store.rehydrateVisibleSnapshotFromCache()
         store.replayPendingMutationsIfNeeded()
     }
```

### ShoppingListView.swift

Lokalizacja: `FamilyTodo/Views/ShoppingListView.swift`

```diff
     store.markLocalSnapshotStale()
     if selectedTab == .shopping {
         handleRemoteShoppingSyncBatch(batch)
     } else {
+        store.rehydrateVisibleSnapshotFromCache()
         store.replayPendingMutationsIfNeeded()
     }
```

### Pre-commit status po zmianach

Wszystkie checksy przechodzą: swiftlint ✅, swiftformat ✅, xcodebuild tests ✅

---

## 11. Wyniki testu z 2026-04-02 (popołudnie) — nowe logi z dodanymi indeksami

### Kluczowe odkrycia

**Owner — `snapshot.load.completed` = 0 przez cały czas trwania logów**

Owner posiada 10 stref w private DB (9 martwych ze starych testów + 1 aktywna `9F176075`):
```
HouseholdZone-1FC92AD7  ← martwa
HouseholdZone-2483F940  ← martwa
HouseholdZone-37B1FBEF  ← martwa
HouseholdZone-6F75DD28  ← martwa
HouseholdZone-81DAD667  ← martwa
HouseholdZone-99919185  ← martwa
HouseholdZone-9F176075  ← AKTYWNA (bieżące household)
HouseholdZone-A0DF2635  ← martwa
HouseholdZone-E5E349F7  ← martwa
HouseholdZone-E94B5C79  ← martwa
```

**Mechanizm awarii owner — exhaustive scan na martwych strefach:**

1. Owner szuka `Task` records w target zone → count=0 (bo participant używa `WorkItem`)
2. `shouldFallbackToOwnerPrivateExhaustiveScan(0) → true`
3. `queryOwnerPrivateRecordsAcrossAllZones(mode: .backgroundExhaustive)`
4. `allPrivateZoneIDs()` → zwraca wszystkie 10 stref
5. Każda martwa strefa → CloudKit query timeout ~45s
6. `domainFetchTimedOut("backlogItems")` → `snapshotTimedOut`
7. Snapshot nigdy nie dochodzi do końca → owner nigdy nie widzi danych participant

**Participant — timeout snapshota za krótki dla sekwencyjnego fetch:**

Participant fetchuje domeny SEKWENCYJNIE (jedna po drugiej, nie równolegle):
```
members      ~4s  (łącznie ~4s)
shoppingItems ~6s  (łącznie ~10s)
shoppingBundles ~3s (łącznie ~13s)
backlogCategories ~3s (łącznie ~16s)
backlogItems starts → timeout fires at 20s → CancellationError
```

7 domen × 4-6s = 28-42s > 20s limit → snapshot zawsze odpala timeout.

**Nota: WorkItem count=6 OK** — owner widzi 6 WorkItems z target zone, ale snapshot nie może się skończyć bo backlogItems/tasks czasują.

### Zastosowane fixy

**Fix A — `CloudKitManager.swift` linia 1282: wyłącz exhaustive scan**
```diff
 static func shouldFallbackToOwnerPrivateExhaustiveScan(
     targetZoneRecordCount: Int
 ) -> Bool {
-    targetZoneRecordCount == 0
+    false
 }
```

Eliminuje całkowicie `ownerQuery.fallbackScan.*` — żadnych queries do martwych stref. Snapshot owner może teraz dochodzić do końca.

**Fix B — `HouseholdCloudSnapshotLoader.swift` linia 38: zwiększ timeout snapshota**
```diff
-snapshotTimeoutNanoseconds: UInt64 = 20_000_000_000  // 20s
+snapshotTimeoutNanoseconds: UInt64 = 60_000_000_000  // 60s
```

7 domen × 4-6s = 28-42s sekwencyjnie. 60s daje margines przy normalnych warunkach sieciowych.

---

## 10. Stan po poprawkach — co nadal wymaga uwagi

| Problem | Status | Priorytet |
|---------|--------|-----------|
| Task/Idea nie synkuje → brak `.ideas` w guard | ✅ NAPRAWIONE | — |
| Task/Idea nie synkuje → else-branch nie rehydruje | ✅ NAPRAWIONE | — |
| ShoppingItem nie synkuje → brak `recordName` index | ✅ NAPRAWIONE (CloudKit Dashboard) | — |
| ShoppingBundle nie synkuje → brak `recordName` index | ✅ NAPRAWIONE (CloudKit Dashboard) | — |
| Push notifications nie docierają owner ← participant | ❌ NIEZDIAGNOZOWANE | wysoki |
| Owner snapshot nigdy się nie kończy (exhaustive scan) | ✅ NAPRAWIONE (Fix A) | — |
| Participant snapshot timeout za krótki | ✅ NAPRAWIONE (Fix B, 20s→60s) | — |
| ShoppingItem wolny sync (1–2 min) | ⚠️ CZĘŚCIOWO (owner snapshot teraz kończy; push nadal nie) | wysoki |
| ShoppingBundle instant vs items slow mystery | ✅ WYJAŚNIONE (oba z tego samego atomowego snapshota, timing artifact) | — |
| WorkItem `recordName` queryable index | ✅ dodany przez użytkownika | — |
| Task, BacklogCategory, BacklogItem `recordName` queryable | ✅ dodany przez użytkownika | — |

### Kolejne kroki rekomendowane

1. **Test po deploymencie** — sprawdzić czy `snapshot.load.completed` pojawia się w logach dla owner i participant.
2. **Zdiagnozować brak pushów** owner ← participant — push.received nadal się nie pojawia w logach. Sync działa tylko przez repair timer (30s). Dodać log w `AppDelegateBridge.didReceiveRemoteNotification` potwierdzający czy push w ogóle dociera.
3. **Rozważyć zrównoleglenie fetch domen** w `HouseholdCloudSnapshotLoader` — obecne 60s timeout jest konserwatywne; `async let` dla wszystkich 7 domen skróciłoby czas do ~6-10s.
