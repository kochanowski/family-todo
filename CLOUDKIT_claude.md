# CloudKit & Data Layer — Professional Analysis

**Project:** Family Todo (iOS)
**Date:** 2026-03-02
**Scope:** CloudKit CRUD, SwiftData cache, offline-first sync, household sharing

---

## Executive Summary

The networking layer follows a sound offline-first architecture: SwiftData is the source of truth for the UI, CloudKit is the sync backend, and optimistic writes give instant feedback. However, 20 concrete issues were identified across four severity tiers — the most critical being silent data loss from swallowed `modelContext.save()` errors, records permanently stuck in `pendingUpload` due to absent retry logic, and N+1 CloudKit queries that will degrade linearly with data size. Before the first App Store release, at minimum the 5 critical and 5 high-severity issues must be resolved.

---

## 1. Architecture Overview

### 1.1 Offline-First Three-Phase Pattern

Every store follows this pattern (example: `TaskStore.loadTasks()`):

```
┌─────────────────────────────────────────────────────┐
│ PHASE 1 — Cache (instant, synchronous)             │
│   FetchDescriptor → SwiftData → tasks = [Task]     │
│   UI renders immediately (no spinner)               │
├─────────────────────────────────────────────────────┤
│ PHASE 2 — CloudKit (background, async)             │
│   cloudKit.fetchTasks(householdId:)                │
│   Runs in Task { } — does not block UI             │
├─────────────────────────────────────────────────────┤
│ PHASE 3 — Merge + Cache Update                     │
│   mergeCloudSnapshot(cloud, pendingSnapshot)        │
│   syncToCache(cloudTasks)                          │
│   tasks = merged result                            │
└─────────────────────────────────────────────────────┘
```

### 1.2 CloudKit Database Layout

```
CKContainer("iCloud.com.kochanowski.housepulse")
├── privateDatabase      ← Owner: Household, Members, Tasks, Items
├── sharedDatabase       ← Participants: same record types in custom zone
└── publicDatabase       ← InviteToken (fallback join mechanism)
```

**Scope switching** (`householdScope`):
- `.ownerPrivate` → `privateDatabase` (household creator)
- `.participantShared` → `sharedDatabase` (invited members)

### 1.3 Write Path

```
UI Action
  → Store (optimistic UI update)
  → modelContext.insert / update
  → modelContext.save()              ← persists locally
  → cached.syncStatusRaw = "pendingUpload"
  → cloudKit.save*(record)           ← async, background
  → on success: syncStatusRaw = "synced"
  → on failure: syncStatusRaw stays "pendingUpload"  ⚠️ no retry
```

### 1.4 Read / Merge Path (Pending-Aware)

```
mergeCloudSnapshot(cloudRecords, pendingSnapshot):
  base = Dictionary(uniqueKeysWithValues: cloudRecords)
  override with pendingUpload records    ← local wins
  remove pendingDelete IDs              ← local wins
  override with in-flight mutations     ← local wins
  return sorted array
```

> **Note:** Local always wins regardless of `updatedAt`. See CK-05 for risks.

### 1.5 Sharing Flow (End-to-End)

```
Owner                        Recipient
  │                              │
  ├─ createHousehold()           │
  ├─ ensureHouseholdOwnerZone()  │
  ├─ saveHousehold() [private]   │
  │                              │
  ├─ createShare()               │
  │   ├─ migrateToCustomZone()   │
  │   ├─ CKModifyRecordsOp       │
  │   └─ returns CKShare         │
  │                              │
  ├─ UICloudSharingController ──►│ (tap link or enter code)
  │                              │
  │                    ├─ redeemInviteCode() [public DB]
  │                    │   or parseShareMetadata(URL)
  │                    │
  │                    ├─ CKAcceptSharesOperation
  │                    ├─ setHouseholdScope(.participantShared)
  │                    ├─ fetchAcceptedRootRecord() [5-retry]
  │                    └─ upsertMembership()
  │                              │
  └── CloudKitSubscriptionManager.configure() ◄─┘
      └─ CKDatabaseSubscription [shared DB]
```

---

## 2. Issues by Severity

---

### 🔴 CRITICAL — Fix Before Any Release

---

#### CK-01: N+1 Queries in `syncToCache()`

**Files:** `TaskStore.swift:167–184`, `ShoppingListStore.swift:108–120`, `BacklogStore.swift:119–152`

**Problem:** For each of N cloud records, a separate `FetchDescriptor` is executed against SwiftData. Fetching 200 tasks → 200 individual database reads per sync cycle.

```swift
// CURRENT (bad):
for task in cloudTasks {
    let descriptor = FetchDescriptor<CachedTask>(
        predicate: #Predicate { $0.id == task.id }  // 1 query per task
    )
    if let existing = try? modelContext.fetch(descriptor).first { ... }
}

// FIX — batch fetch once, merge in memory:
func syncToCache(_ cloudTasks: [Task]) {
    let cloudIDs = Set(cloudTasks.map(\.id))
    let descriptor = FetchDescriptor<CachedTask>(
        predicate: #Predicate { cloudIDs.contains($0.id) }  // 1 query total
    )
    let existing = (try? modelContext.fetch(descriptor)) ?? []
    let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

    for task in cloudTasks {
        if let cached = existingByID[task.id] {
            guard cached.syncStatusRaw != "pendingUpload",
                  cached.syncStatusRaw != "pendingDelete" else { continue }
            cached.update(from: task)
        } else {
            modelContext.insert(CachedTask(from: task))
        }
    }
    saveContext()
}
```

**Impact:** O(n) → O(1) database round-trips. Critical for households with many tasks.

---

#### CK-02: No Retry Logic for Failed CloudKit Writes

**Files:** `TaskStore.swift:277–278`, `ShoppingListStore.swift`, `BacklogStore.swift`, `HouseholdStore.swift`

**Problem:** If `cloudKit.saveTask()` throws (network offline, quota exceeded, etc.), the record stays in `syncStatusRaw = "pendingUpload"` indefinitely. On next app launch, nothing reads these pending records and retries them.

```swift
// CURRENT (bad):
do {
    _ = try await cloudKit.saveTask(task)
    markCachedTaskSynced(id: task.id)
} catch {
    self.error = error  // ← pending forever
}

// FIX — add a startup sync flush in each Store:
func flushPendingSync() async {
    let descriptor = FetchDescriptor<CachedTask>(
        predicate: #Predicate { $0.syncStatusRaw == "pendingUpload" }
    )
    let pending = (try? modelContext.fetch(descriptor)) ?? []
    for cached in pending {
        let task = cached.toTask()
        try? await cloudKit.saveTask(task)
        cached.syncStatusRaw = "synced"
    }

    let deleteDescriptor = FetchDescriptor<CachedTask>(
        predicate: #Predicate { $0.syncStatusRaw == "pendingDelete" }
    )
    let toDelete = (try? modelContext.fetch(deleteDescriptor)) ?? []
    for cached in toDelete {
        try? await cloudKit.deleteTask(id: cached.id, householdId: cached.householdId)
        modelContext.delete(cached)
    }
    saveContext()
}
```

Call `flushPendingSync()` from each store's `loadXxx()` method after the cloud fetch.

---

#### CK-03: Silent Error Swallowing in `modelContext.save()`

**Files:** `TaskStore.swift:183, 255, 270, 315, 321, 421` and many more across all stores

**Problem:** `try? modelContext.save()` silently discards all errors. A locked database, disk full, or SwiftData constraint violation produces no log, no crash, no user feedback — data appears saved but is not.

```swift
// CURRENT (bad) — 11+ occurrences in TaskStore alone:
try? modelContext.save()

// FIX — replace with logging everywhere:
private func saveContext(file: String = #file, line: Int = #line) {
    do {
        try modelContext.save()
    } catch {
        logger.error("[\(file):\(line)] modelContext.save failed: \(error)")
        // Optionally surface via self.error = error
    }
}
```

Use this helper in place of every `try? modelContext.save()`.

---

#### CK-04: No Rollback on CloudKit Failure

**Files:** `TaskStore.createTask():245–278`, `TaskStore.updateTask():284–346`, `ShoppingListStore`, `BacklogStore`

**Problem:** The UI is updated optimistically before the CloudKit write. If CloudKit fails, the UI shows the new state but the cloud has the old state. On next sync, the cloud version overwrites the local one — the user's change is silently lost.

```swift
// CURRENT (bad):
tasks.append(task)          // optimistic
cacheInsert(task)           // local persist
do {
    try await cloudKit.saveTask(task)
} catch {
    self.error = error      // UI stays wrong
}

// FIX — follow MemberStore.updateMember() pattern (already correct there):
let snapshot = tasks       // capture state
tasks.append(task)
cacheInsert(task)
do {
    try await cloudKit.saveTask(task)
} catch {
    tasks = snapshot        // revert UI
    cacheDelete(task.id)    // revert cache
    self.error = error
}
```

`MemberStore.updateMember()` already does this correctly — replicate the pattern across all stores.

---

#### CK-05: No Conflict Resolution in `mergeCloudSnapshot()`

**File:** `TaskStore.swift:615–642`

**Problem:** `pendingUpload` always overwrites the cloud version unconditionally. If Device A updates a task while offline, then Device B updates the same task while online — when Device A syncs, it silently overwrites Device B's newer change.

```swift
// CURRENT (bad):
for (id, pendingTask) in pendingSnapshot.pendingUploadByID {
    merged[id] = pendingTask  // always wins, no timestamp check
}

// FIX — last-write-wins with timestamp:
for (id, pendingTask) in pendingSnapshot.pendingUploadByID {
    if let cloudTask = merged[id] {
        // Keep whichever was modified more recently
        if pendingTask.updatedAt >= cloudTask.updatedAt {
            merged[id] = pendingTask
        }
        // else cloud is newer: pending is stale, mark as synced
    } else {
        merged[id] = pendingTask  // no cloud version, pending is new
    }
}
```

Requires ensuring `updatedAt` is reliably set on every mutation and persisted in CloudKit.

---

### 🟠 HIGH — Fix Before Production Launch

---

#### CK-06: No Batch CloudKit Operations for Creates

**File:** `CloudKitManager.swift:857, 937, 1128, 1226, 1335`

**Problem:** Each record create/update fires a separate network request. Guest-mode seeding (8 tasks + 5 items + 2 categories = 15 records) issues 15 sequential round-trips.

```swift
// FIX — use CKModifyRecordsOperation for bulk writes:
func saveTasks(_ tasks: [Task], householdId: UUID) async throws {
    let records = tasks.map { taskRecord(from: $0, householdId: householdId) }
    let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
    operation.savePolicy = .changedKeys
    operation.qualityOfService = .userInitiated
    operation.isAtomic = false  // partial success acceptable for bulk
    try await withCheckedThrowingContinuation { continuation in
        operation.modifyRecordsResultBlock = { result in
            continuation.resume(with: result)
        }
        database.add(operation)
    }
}
```

CloudKit supports up to 400 records per `CKModifyRecordsOperation`.

---

#### CK-07: No Pagination on CloudKit Queries

**File:** `CloudKitManager.swift:1146–1184, 1246–1255`

**Problem:** All `fetchXxx()` methods have no `resultsLimit` or cursor handling. A household with hundreds of completed tasks fetches them all into memory on every sync.

```swift
// FIX — add pagination support:
func fetchTasks(householdId: UUID, cursor: CKQueryOperation.Cursor? = nil) async throws -> (tasks: [Task], nextCursor: CKQueryOperation.Cursor?) {
    let query = CKQuery(recordType: "Task", predicate: NSPredicate(format: "householdId == %@", ...))
    query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

    let operation = CKQueryOperation(query: query)
    operation.resultsLimit = 200
    if let cursor { operation.cursor = cursor }

    var results: [Task] = []
    var nextCursor: CKQueryOperation.Cursor?

    operation.recordMatchedBlock = { _, result in
        if case .success(let record) = result, let task = try? self.task(from: record) {
            results.append(task)
        }
    }
    operation.queryResultBlock = { result in
        if case .success(let cursor) = result { nextCursor = cursor }
    }

    try await withCheckedThrowingContinuation { ... }
    return (results, nextCursor)
}
```

For MVP: set `resultsLimit = 500` as a quick fix until full cursor support is implemented.

---

#### CK-08: Color Migration on Every `fetchMembers()` Call

**File:** `CloudKitManager.swift:1074–1088`

**Problem:** Every call to `fetchMembers()` checks and potentially saves a color migration for every member. With 2 members fetched on every screen transition, this can trigger 2+ CloudKit saves per navigation.

```swift
// CURRENT (bad) — runs on every fetch:
for record in records {
    let migratedColor = try await migrateColorIfNeeded(record, database: db)
    ...
}

// FIX — one-time migration at sign-in / household load:
// In HouseholdStore.loadHousehold():
if !UserDefaults.standard.bool(forKey: "memberColorMigrationComplete") {
    await cloudKit.runMemberColorMigration(householdId: householdId)
    UserDefaults.standard.set(true, forKey: "memberColorMigrationComplete")
}

// fetchMembers() reads color directly, no migration:
func fetchMembers(householdId: UUID) async throws -> [Member] {
    let records = try await queryRecords(type: "Member", ...)
    return try records.map { try member(from: $0) }  // no migration here
}
```

---

#### CK-09: Zone Context Cache Has No Invalidation

**File:** `CloudKitManager.swift:206–249`

**Problem:** Shared zone IDs are cached in `UserDefaults`. If the zone is deleted/recreated (e.g. owner leaves and rejoins), participants get `unknownItem` errors with no automatic recovery.

```swift
// FIX — clear stale cache on zone errors and re-resolve:
func fetchWithZoneRecovery<T>(householdId: UUID, operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
        // Stale cache — clear and re-resolve
        clearSharedZoneContext(householdId: householdId)
        _ = try await resolveHouseholdZone(householdId: householdId)
        return try await operation()  // single retry
    }
}
```

---

#### CK-10: Invite Code Brute-Force Vulnerability

**File:** `CloudKitManager.swift:1705–1733`

**Problem:** 6-character alphanumeric codes (base-36) allow ~2.2 billion combinations in theory, but the public CloudKit database accepts unlimited unauthenticated queries — making enumeration feasible with a script.

**Fixes (apply in combination):**
1. Extend code length to **8 characters** (base-36: ~2.8 trillion combinations)
2. Add **CloudKit Security Roles** on `InviteToken` to require authentication for reads
3. Add an **attempt counter** field on the token; revoke after 10 failed redemptions
4. Keep TTL short (current implementation — verify it is ≤ 48h)

---

### 🟡 MEDIUM — Address Before v1.1

---

#### CK-11: Missing `@Attribute(.indexed)` on Foreign Keys

**Files:** All `Models/Cached*.swift`

**Problem:** Fields like `householdId`, `categoryId`, `assigneeId` used in `FetchDescriptor` predicates have no index — every query performs a full table scan.

```swift
// FIX:
@Model final class CachedTask {
    @Attribute(.unique) var id: UUID
    @Attribute(.indexed) var householdId: UUID    // ← add indexed
    @Attribute(.indexed) var assigneeId: UUID?    // ← add indexed
    @Attribute(.indexed) var syncStatusRaw: String // ← add indexed (for pending queries)
    ...
}
```

Apply to: `CachedTask.householdId`, `CachedShoppingItem.householdId`, `CachedBacklogItem.categoryId`, `CachedBacklogItem.householdId`, `CachedMember.householdId`.

---

#### CK-12: No `@Relationship` Cascade Delete

**Files:** All `Models/Cached*.swift`

**Problem:** Relationships are stored as raw `UUID` values. Deleting a `CachedHousehold` leaves `CachedTask`, `CachedMember`, `CachedShoppingItem`, etc. as orphans.

```swift
// FIX — use SwiftData relationships:
@Model final class CachedHousehold {
    @Attribute(.unique) var id: UUID
    @Relationship(deleteRule: .cascade) var tasks: [CachedTask] = []
    @Relationship(deleteRule: .cascade) var members: [CachedMember] = []
    @Relationship(deleteRule: .cascade) var shoppingItems: [CachedShoppingItem] = []
    @Relationship(deleteRule: .cascade) var backlogCategories: [CachedBacklogCategory] = []
}

@Model final class CachedBacklogCategory {
    @Relationship(deleteRule: .cascade) var items: [CachedBacklogItem] = []
    var household: CachedHousehold?
}
```

> **Note:** This is a schema change — requires a `SchemaMigrationPlan` (see CK-14).

---

#### CK-13: Legacy Models Pollute the Schema

**File:** `FamilyTodoApp.swift:22–31`

**Problem:** `CachedArea` and `CachedRecurringChore` are included in the schema but never read or written by any store. They consume schema space and complicate migrations.

```swift
// CURRENT:
private static let appSchema = Schema([
    CachedTask.self, CachedMember.self, CachedShoppingItem.self,
    CachedBacklogCategory.self, CachedBacklogItem.self, CachedHousehold.self,
    CachedArea.self,            // ← remove or move to future version
    CachedRecurringChore.self,  // ← remove or move to future version
])

// FIX — define a versioned schema:
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        CachedTask.self, CachedMember.self, CachedShoppingItem.self,
        CachedBacklogCategory.self, CachedBacklogItem.self, CachedHousehold.self,
        // Area and RecurringChore added in V2 when features land
    ]
}
```

---

#### CK-14: No Schema Migration Plan

**File:** `FamilyTodoApp.swift`, `SwiftDataContainerFactory.swift`

**Problem:** No `VersionedSchema` or `SchemaMigrationPlan` is defined. Any field rename or type change will cause undefined behavior (silent data wipe or crash) on existing installations.

```swift
// FIX — define migration infrastructure now (even if no migrations yet):
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self]
    static var stages: [MigrationStage] = []  // add stages when needed
}

// In FamilyTodoApp:
let config = ModelConfiguration(
    schema: Schema(AppSchemaV1.models),
    isStoredInMemoryOnly: false
)
sharedModelContainer = try ModelContainer(
    for: Schema(AppSchemaV1.models),
    migrationPlan: AppMigrationPlan.self,
    configurations: [config]
)
```

---

#### CK-15: Database-Level Subscription Instead of Zone Subscription

**File:** `CloudKitSubscriptionManager.swift:48–61`

**Problem:** A single `CKDatabaseSubscription` fires for all changes to `sharedDatabase` regardless of zone or household. Users belonging to multiple households would receive notifications for all of them.

```swift
// CURRENT:
let sub = CKDatabaseSubscription(subscriptionID: "shared-database-changes")

// FIX — use CKRecordZoneSubscription per household zone:
func setupSubscriptions(householdId: UUID, zoneID: CKRecordZone.ID) async throws {
    let subscriptionID = "household-\(householdId.uuidString)"
    let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
    let info = CKSubscription.NotificationInfo()
    info.shouldSendContentAvailable = true
    sub.notificationInfo = info
    try await sharedDatabase.save(sub)
}
```

---

#### CK-16: Unbounded Retry Loop Without Backoff

**File:** `CloudKitManager.updateMemberRecord():952–980`

**Problem:** `while true` retries on `.serverRecordChanged` with no delay. Under high contention (multiple devices editing simultaneously), this creates a busy loop consuming CPU and CloudKit quota.

```swift
// FIX — exponential backoff with max retries:
func updateMemberRecord(...) async throws -> Member {
    let delays: [UInt64] = [100_000_000, 200_000_000, 400_000_000] // 100ms, 200ms, 400ms
    for (attempt, delay) in delays.enumerated() {
        do {
            return try await attemptMemberUpdate(...)
        } catch let error as CKError where error.code == .serverRecordChanged {
            if attempt == delays.count - 1 { throw error }
            try await Task.sleep(nanoseconds: delay)
        }
    }
    throw CloudKitManagerError.unknownError(...)
}
```

---

### 🟢 LOW — Track for Future Releases

---

#### CK-17: CloudKit Container Early Init in `AuthenticationService`

**File:** `Services/AuthenticationService.swift:115–128`

**Problem:** `CKContainer` is created in `init()`. `CloudKitManager` correctly defers this with `ensureReady()` (1-second delay), but `AuthenticationService` does not.

**Fix:** Move container init to the body of `checkCloudKitStatus()`, or share the same `CKContainer` instance from `CloudKitManager`.

---

#### CK-18: Owner Departure — No Transfer UI

**File:** `HouseholdStore.swift:571–586`

**Problem:** When the owner tries to leave with active members, code throws `requiresOwnershipTransfer` — but there is no UI to initiate or accept the transfer. The household is left in limbo.

**Fix:** Implement a two-step transfer: owner selects new owner → new owner receives in-app prompt → accepts. Display a blocker in the UI until resolved.

---

#### CK-19: No Read-Only Share Permission

**File:** `Views/ShareInviteView.swift:12`

**Problem:** `availablePermissions = [.allowReadWrite, .allowPrivate]` — participants can always edit. There is no viewer/read-only role.

**Fix:** Add `.allowReadOnly` if a viewing-only use case arises (e.g. extended family viewing the shopping list).

---

#### CK-20: Guest SwiftData Store Not Encrypted

**Problem:** Guest mode stores data in SwiftData on-disk with no encryption. On jailbroken devices, task and member data is readable via the container filesystem.

**Fix:** Enable the `Data Protection` entitlement in the project (`NSFileProtectionComplete`) — this encrypts the entire sandbox when the device is locked, including the SwiftData store, with zero code changes required.

---

## 3. Summary Table

| ID | Severity | Area | One-Line Description |
|----|----------|------|---------------------|
| CK-01 | 🔴 Critical | SwiftData | N+1 queries in syncToCache (O(n) fetches) |
| CK-02 | 🔴 Critical | Sync | Failed CloudKit writes never retried |
| CK-03 | 🔴 Critical | SwiftData | `try? modelContext.save()` silently swallows errors |
| CK-04 | 🔴 Critical | Sync | No rollback on CloudKit failure (only MemberStore is correct) |
| CK-05 | 🔴 Critical | Sync | No conflict resolution — local always wins |
| CK-06 | 🟠 High | CloudKit | No batch operations — one round-trip per record |
| CK-07 | 🟠 High | CloudKit | No pagination — fetches all records |
| CK-08 | 🟠 High | CloudKit | Color migration runs on every fetchMembers() |
| CK-09 | 🟠 High | CloudKit | Zone context cache never invalidated |
| CK-10 | 🟠 High | Security | Invite codes brute-forceable via public DB |
| CK-11 | 🟡 Medium | SwiftData | No @Attribute(.indexed) on foreign keys |
| CK-12 | 🟡 Medium | SwiftData | No @Relationship cascade delete |
| CK-13 | 🟡 Medium | SwiftData | Legacy models (Area, RecurringChore) in schema |
| CK-14 | 🟡 Medium | SwiftData | No VersionedSchema / SchemaMigrationPlan |
| CK-15 | 🟡 Medium | CloudKit | Single DB subscription instead of per-zone |
| CK-16 | 🟡 Medium | CloudKit | Retry loop without exponential backoff |
| CK-17 | 🟢 Low | Auth | CloudKit container early init in AuthenticationService |
| CK-18 | 🟢 Low | UX | No ownership transfer UI on owner leave |
| CK-19 | 🟢 Low | CloudKit | No read-only share permission |
| CK-20 | 🟢 Low | Security | Guest SwiftData not encrypted |

---

## 4. Implementation Roadmap

### Phase 1 — Data Integrity (Before TestFlight)

Target: eliminate silent data loss and stuck pending records.

| # | Task | Files | Effort |
|---|------|-------|--------|
| 1 | Replace `try? modelContext.save()` with `saveContext()` helper | All Stores | 1h |
| 2 | Add rollback pattern to `createTask`, `updateTask`, `ShoppingListStore`, `BacklogStore` | TaskStore, ShoppingListStore, BacklogStore | 2h |
| 3 | Batch `syncToCache()` — single fetch + in-memory merge | TaskStore, ShoppingListStore, BacklogStore | 2h |
| 4 | Add `flushPendingSync()` — resend stuck pendingUpload on launch | All Stores | 2h |
| 5 | Add `updatedAt` timestamp comparison in `mergeCloudSnapshot()` | TaskStore | 1h |

**Total Phase 1: ~8h**

---

### Phase 2 — Performance & Scale (Before App Store Submission)

Target: handle 100+ users, 1000+ records without performance degradation.

| # | Task | Files | Effort |
|---|------|-------|--------|
| 6 | Add `resultsLimit = 500` to all CloudKit queries (quick fix) | CloudKitManager | 1h |
| 7 | Implement `CKModifyRecordsOperation` for bulk saves | CloudKitManager | 3h |
| 8 | Move color migration to one-time startup step | CloudKitManager, HouseholdStore | 1h |
| 9 | Add zone cache invalidation on `.zoneNotFound` | CloudKitManager | 1h |
| 10 | Extend invite codes to 8 chars, add attempt counter | CloudKitManager | 2h |

**Total Phase 2: ~8h**

---

### Phase 3 — Maintenance & Robustness (Before v1.1)

Target: reduce technical debt, enable safe schema evolution.

| # | Task | Files | Effort |
|---|------|-------|--------|
| 11 | Add `@Attribute(.indexed)` on all FK fields | All Cached*.swift | 1h |
| 12 | Define `VersionedSchema` + `SchemaMigrationPlan` | FamilyTodoApp.swift, new file | 2h |
| 13 | Remove legacy models from V1 schema | FamilyTodoApp.swift | 0.5h |
| 14 | Replace `CKDatabaseSubscription` with `CKRecordZoneSubscription` | CloudKitSubscriptionManager | 2h |
| 15 | Add exponential backoff to `updateMemberRecord()` retry | CloudKitManager | 1h |
| 16 | Enable `Data Protection` entitlement | Xcode project settings | 0.25h |

**Total Phase 3: ~7h**

---

## 5. What Is Working Well

The following aspects of the implementation are correct and should be preserved:

- **Guest mode isolation** — completely separated from CloudKit, `localOnly` flag consistently checked ✅
- **`MemberStore.updateMember()` rollback** — the correct pattern; replicate to other stores ✅
- **`BacklogStore.loadData()` parallel fetches** — `async let` for categories + items simultaneously ✅
- **`CKModifyRecordsOperation` for share creation** — atomic, correct `savePolicy` ✅
- **`fetchAcceptedRootRecord()` with backoff** — 5-retry with growing delays handles CloudKit propagation delay ✅
- **Self-notification suppression** — subscription manager ignores changes made by current user ✅
- **Diagnostics without PII** — auth diagnostics log stages without email or credential data ✅
- **Zone context persistence** — UserDefaults zone cache avoids repeated zone discovery queries ✅

---

*Analysis performed: 2026-03-02 | Analyzed by: Claude Sonnet 4.6 via swift-expert skill*
