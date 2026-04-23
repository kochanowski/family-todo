# ADR-002: Error Handling & Offline-First Strategy

**Status:** ✅ Accepted
**Date:** 2026-01-12
**Deciders:** Wojtek Kochanowski
**Technical Story:** Define offline-first architecture, conflict resolution, and error handling strategy for Family To-Do App

---

## Context and Problem Statement

Family To-Do App must work reliably in various network conditions and handle CloudKit synchronization errors gracefully. The app should provide a seamless user experience regardless of connectivity:

### Key Requirements:
1. **Offline-first**: App must be fully functional without internet connection
2. **Conflict resolution**: Multiple users editing same data must not lose changes
3. **Error handling**: Users should understand what went wrong and what to do
4. **Data integrity**: No data loss during network failures or conflicts
5. **User experience**: Errors should be gentle, not alarming

### Common Scenarios:
- User is on airplane, adds tasks, then goes online → must sync without data loss
- Two partners edit same task simultaneously → must resolve conflict fairly
- CloudKit quota exceeded → must inform user clearly
- User has poor cellular connection → app should work smoothly

---

## Decision Drivers

1. **User trust** - No data loss under any circumstances
2. **Simplicity** - Errors should be rare and understandable
3. **Transparency** - Users should know when they're offline vs online
4. **Performance** - Offline mode should be instant, not degraded
5. **Conflict fairness** - Both users' changes matter equally
6. **Development speed** - Strategy should be implementable in 1-2 weeks
7. **Maintenance** - Error handling should be centralized and testable

---

## Decision Outcome

**Chosen strategy:** **Optimistic UI with Last-Write-Wins conflict resolution and graceful degradation**

### Core Principles:

1. **Local-first database** - All data stored locally in SwiftData/Core Data
2. **Optimistic UI updates** - Show changes immediately, sync in background
3. **Background sync** - CloudKit operations happen asynchronously
4. **Last-Write-Wins (LWW)** - For MVP, newest change wins conflicts
5. **Transparent sync status** - Subtle indicators show sync state
6. **Graceful error messages** - Friendly explanations with clear actions

---

## Architecture Overview

### Data Flow: Write Operations

```
User Action (e.g., "Add Task")
      ↓
1. Write to Local Database (SwiftData) ← INSTANT
      ↓
2. Update UI immediately ← OPTIMISTIC
      ↓
3. Mark record as "pendingUpload" = true
      ↓
4. Background: Attempt CloudKit upload
      ↓
   ┌──┴──┐
   │     │
SUCCESS  FAILURE
   │     │
   ↓     ↓
Save    Retry queue
CKRecord  (exponential backoff)
   ↓     │
Update   │
updatedAt │
   ↓     │
Mark as  │
synced=true │
         │
         └──→ If fails 3x: Show gentle notification
                "Unable to sync. Will retry when online."
```

### Data Flow: Read Operations (Sync from CloudKit)

```
App Launch / Pull-to-Refresh
      ↓
1. Load from Local Database ← INSTANT UI
      ↓
2. Background: Query CloudKit for changes
      ↓
   CKQuery: createdAt > lastSyncTimestamp
      ↓
3. Fetch changed records
      ↓
4. For each changed record:
      ↓
   Compare: record.updatedAt vs local.updatedAt
      ↓
   ┌───────┴────────┐
   │                │
REMOTE > LOCAL   LOCAL > REMOTE
(CloudKit newer) (Local newer)
   │                │
   ↓                ↓
Accept remote    Keep local
Update local     (Upload will sync)
   │                │
   └────────┬───────┘
            ↓
5. Update UI with merged data
6. Update lastSyncTimestamp
```

---

## Conflict Resolution Strategy

### Last-Write-Wins (LWW) Implementation

For MVP, we use **Last-Write-Wins** based on `updatedAt` timestamp:
- Each record has `updatedAt: Date` field
- Newest `updatedAt` always wins conflicts
- Simple, predictable, no complex merge logic

**Example Conflict:**
```swift
// User A (local):
Task(id: 123, title: "Buy milk", updatedAt: "2026-01-12 10:00")

// User B (CloudKit):
Task(id: 123, title: "Buy milk and eggs", updatedAt: "2026-01-12 10:05")

// Resolution:
→ User B's version wins (10:05 > 10:00)
→ Local database updated with "Buy milk and eggs"
→ User A sees change next sync
```

### Why Last-Write-Wins for MVP?

**Pros:**
- ✅ **Simple** - Easy to implement and understand
- ✅ **Fast** - No user intervention needed
- ✅ **Works well for tasks** - Rare simultaneous edits
- ✅ **Predictable** - Always newest wins

**Cons:**
- ⚠️ **Can lose changes** - If two users edit simultaneously, one change lost
- ⚠️ **No merge logic** - Can't combine changes intelligently

**Mitigation for MVP:**
- Family of 2 users rarely edit same task simultaneously
- Task history (future) can show what changed
- For critical fields (like recurring chores), can add optimistic locking (future ADR)

**Post-MVP alternatives:**
- **Operational Transform** (Google Docs-style real-time collaboration)
- **CRDT (Conflict-free Replicated Data Types)** - Automatic merge
- **Manual conflict UI** - Ask user to resolve
- *Decision: Revisit if users report lost changes*

---

## Offline-First Implementation

### Local Database: SwiftData

```swift
@Model
class Task {
    @Attribute(.unique) var id: UUID
    var title: String
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncStatus: SyncStatus = .synced
    var lastSyncedAt: Date?
    var ckRecordID: String?
    var ckSystemFields: Data? // CKRecord.encodeSystemFields()

    enum SyncStatus: String, Codable {
        case synced       // Local matches CloudKit
        case pendingUpload // Local changes not yet uploaded
        case pendingDelete // Marked for deletion, not yet deleted from CloudKit
        case conflict     // Detected conflict (rare with LWW)
    }
}
```

### CloudKitManager: Sync Operations

```swift
actor CloudKitManager {
    // MARK: - Upload Queue

    func syncPendingChanges() async {
        let pendingTasks = await localDatabase.fetch(
            where: \.syncStatus == .pendingUpload
        )

        for task in pendingTasks {
            do {
                let ckRecord = try await uploadTask(task)
                await localDatabase.update(task) {
                    $0.syncStatus = .synced
                    $0.lastSyncedAt = Date()
                    $0.ckRecordID = ckRecord.recordID.recordName
                }
            } catch {
                await handleUploadError(error, for: task)
            }
        }
    }

    // MARK: - Download Changes

    func fetchRemoteChanges() async throws {
        let lastSync = await localDatabase.lastSyncTimestamp

        let query = CKQuery(
            recordType: "Task",
            predicate: NSPredicate(
                format: "modificationDate > %@",
                lastSync as NSDate
            )
        )

        let records = try await database.records(matching: query)

        for record in records {
            await mergeRemoteRecord(record)
        }

        await localDatabase.setLastSyncTimestamp(Date())
    }

    // MARK: - Conflict Resolution

    func mergeRemoteRecord(_ ckRecord: CKRecord) async {
        guard let localTask = await localDatabase.fetch(
            id: ckRecord.recordID.recordName
        ) else {
            // New record from remote, just insert
            await localDatabase.insert(fromCKRecord: ckRecord)
            return
        }

        let remoteUpdatedAt = ckRecord["updatedAt"] as! Date
        let localUpdatedAt = localTask.updatedAt

        if remoteUpdatedAt > localUpdatedAt {
            // Remote is newer, accept remote changes
            await localDatabase.update(localTask, from: ckRecord)
        } else {
            // Local is newer, keep local (will upload on next sync)
            // Do nothing
        }
    }

    // MARK: - Error Handling

    func handleUploadError(_ error: Error, for task: Task) async {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .networkUnavailable, .networkFailure:
                // Retry with exponential backoff
                await retryQueue.add(task, backoff: .exponential)

            case .quotaExceeded:
                // User exceeded CloudKit quota
                await showUserAlert(
                    title: "iCloud Storage Full",
                    message: "Your iCloud storage is full. Please free up space or upgrade your plan."
                )

            case .serverRecordChanged:
                // Someone else modified record, refetch and retry
                await fetchRemoteChanges()
                await retryQueue.add(task, backoff: .immediate)

            case .zoneNotFound:
                // Custom zone deleted, recreate
                await setupCloudKitZone()
                await retryQueue.add(task, backoff: .immediate)

            default:
                // Unknown error, retry with exponential backoff
                await retryQueue.add(task, backoff: .exponential)
            }
        }
    }
}
```

---

## Error Categories & Handling

### 1. Network Errors (Most Common)

**Errors:**
- `CKError.networkUnavailable` - No internet connection
- `CKError.networkFailure` - Request timeout

**Strategy:**
- ✅ **Silent retry** - Add to retry queue, exponential backoff
- ✅ **Show subtle indicator** - "Offline" badge in status bar
- ✅ **No blocking** - User can continue working
- ✅ **Auto-sync** - When network returns, sync automatically

**User Message:**
```
🔄 Syncing...
   ↓ (if still failing after 3 retries)
📴 Working offline
   Changes will sync when online.
```

---

### 2. Quota Exceeded

**Error:**
- `CKError.quotaExceeded` - User's iCloud storage full

**Strategy:**
- ⚠️ **Non-blocking alert** - Show once per session
- ✅ **Continue working** - App still functional offline
- ✅ **Clear action** - Link to iCloud settings

**User Message:**
```
⚠️ iCloud Storage Full

Your iCloud storage is full. Family To-Do
will continue working, but changes won't
sync until you free up space.

[Manage Storage]  [Dismiss]
```

---

### 3. Conflict Errors

**Error:**
- `CKError.serverRecordChanged` - Someone else modified record

**Strategy:**
- ✅ **Automatic resolution** - Last-Write-Wins, no user action needed
- ✅ **Refetch and retry** - Get latest version, apply local changes
- ✅ **Silent for MVP** - No notification unless repeated failures

**User Message (only if repeated conflicts):**
```
💬 Changes Merged

Someone else updated this task.
We've merged your changes.

[View Details]  [Dismiss]
```

---

### 4. Permission Errors

**Error:**
- `CKError.notAuthenticated` - User not signed into iCloud

**Strategy:**
- 🚫 **Blocking** - App requires iCloud
- ✅ **Clear onboarding** - Explain why iCloud is needed
- ✅ **Settings link** - Direct user to iCloud sign-in

**User Message:**
```
☁️ Sign in to iCloud

Family To-Do uses iCloud to sync your
tasks across devices and share with
your household.

1. Open Settings
2. Tap your name at top
3. Sign in to iCloud

[Open Settings]
```

---

### 5. CloudKit Zone Errors

**Error:**
- `CKError.zoneNotFound` - Custom zone deleted (rare)

**Strategy:**
- ✅ **Automatic recovery** - Recreate zone
- ✅ **Re-upload data** - Push local database to CloudKit
- ⚠️ **Notify if data loss** - Only if can't recover

**User Message (rare):**
```
🔄 Setting up sync...

We're reconfiguring your iCloud sync.
This may take a moment.

(This usually happens once)
```

---

## Sync Status Indicators

### Visual Sync States

```
1. Synced ✅
   - No indicator needed
   - Implicit: "everything is fine"

2. Syncing 🔄
   - Small animated spinner in nav bar
   - Shown during active sync operations
   - Auto-dismisses after 2 seconds

3. Offline 📴
   - Small badge in nav bar
   - Persistent while offline
   - Non-intrusive (gray color)

4. Error ⚠️
   - Yellow badge in nav bar
   - Tap for details
   - Rare (only persistent errors)
```

### Implementation Example

```swift
struct ContentView: View {
    @StateObject var syncManager = SyncManager.shared

    var body: some View {
        NavigationStack {
            TaskListView()
                .navigationTitle("My Tasks")
                .toolbar {
                    ToolbarItem(placement: .status) {
                        syncStatusBadge
                    }
                }
        }
    }

    @ViewBuilder
    var syncStatusBadge: some View {
        switch syncManager.status {
        case .synced:
            EmptyView()

        case .syncing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

        case .offline:
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                Text("Offline")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary)
            .clipShape(Capsule())

        case .error(let message):
            Button {
                showErrorDetails(message)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Sync Issue")
                        .font(.caption2)
                }
                .foregroundStyle(.yellow)
            }
        }
    }
}
```

---

## Retry Strategy

### Exponential Backoff Queue

```swift
actor RetryQueue {
    private var pendingRetries: [RetryItem] = []

    struct RetryItem {
        let task: Task
        var attemptCount: Int = 0
        var nextRetryAt: Date

        var backoffInterval: TimeInterval {
            // Exponential: 2^attemptCount seconds
            // 1st retry: 2 seconds
            // 2nd retry: 4 seconds
            // 3rd retry: 8 seconds
            // 4th retry: 16 seconds
            // Max: 60 seconds (1 minute)
            min(pow(2.0, Double(attemptCount)), 60.0)
        }
    }

    func add(_ task: Task, backoff: BackoffStrategy) {
        let nextRetry = Date().addingTimeInterval(
            backoff == .immediate ? 0 : 2.0
        )

        pendingRetries.append(
            RetryItem(task: task, nextRetryAt: nextRetry)
        )

        scheduleNextRetry()
    }

    func processRetries() async {
        let now = Date()
        let readyItems = pendingRetries.filter { $0.nextRetryAt <= now }

        for var item in readyItems {
            do {
                try await CloudKitManager.shared.uploadTask(item.task)
                // Success, remove from queue
                pendingRetries.removeAll { $0.task.id == item.task.id }
            } catch {
                // Failed, reschedule with longer backoff
                item.attemptCount += 1
                item.nextRetryAt = Date().addingTimeInterval(
                    item.backoffInterval
                )

                if item.attemptCount >= 5 {
                    // After 5 attempts, show user notification
                    await showRetryNotification(for: item.task)
                }
            }
        }
    }
}
```

---

## User-Facing Error Messages

### Principles for Error Messages

1. **Friendly tone** - No technical jargon
2. **Explain what happened** - Clear description
3. **Explain why** - Help user understand cause
4. **Provide action** - Clear next step
5. **Don't blame user** - "Unable to sync" not "You forgot to turn on WiFi"

### Example Error Messages

#### Good ✅
```
☁️ Unable to Sync

We couldn't sync your tasks because you're offline.
Your changes are saved and will sync when you're
back online.

[OK]
```

#### Bad ❌
```
Error: CKError.networkUnavailable

The CloudKit operation failed due to network
unavailability. Error code: 3.

[Dismiss]
```

---

## Testing Strategy

### Offline Mode Testing

```swift
// XCTest case
func testOfflineTaskCreation() async throws {
    // 1. Disable network
    NetworkSimulator.setOffline()

    // 2. Create task
    let task = Task(title: "Buy milk")
    await localDatabase.insert(task)

    // 3. Verify: task in local DB
    XCTAssertNotNil(await localDatabase.fetch(id: task.id))

    // 4. Verify: task marked as pending upload
    XCTAssertEqual(task.syncStatus, .pendingUpload)

    // 5. Enable network
    NetworkSimulator.setOnline()

    // 6. Trigger sync
    await CloudKitManager.shared.syncPendingChanges()

    // 7. Verify: task uploaded to CloudKit
    let ckRecord = try await CloudKitManager.shared.fetch(id: task.id)
    XCTAssertNotNil(ckRecord)

    // 8. Verify: task marked as synced
    let updatedTask = await localDatabase.fetch(id: task.id)
    XCTAssertEqual(updatedTask?.syncStatus, .synced)
}
```

### Conflict Resolution Testing

```swift
func testLastWriteWinsConflict() async throws {
    // 1. User A creates task
    let taskA = Task(
        id: UUID(),
        title: "Buy milk",
        updatedAt: Date(timeIntervalSinceNow: -10) // 10 seconds ago
    )
    await localDatabase.insert(taskA)

    // 2. User B modifies same task
    let taskB = Task(
        id: taskA.id,
        title: "Buy milk and eggs",
        updatedAt: Date() // Now
    )
    let ckRecord = try await uploadToCloudKit(taskB)

    // 3. User A syncs
    await CloudKitManager.shared.fetchRemoteChanges()

    // 4. Verify: User B's version won (newer timestamp)
    let resolvedTask = await localDatabase.fetch(id: taskA.id)
    XCTAssertEqual(resolvedTask?.title, "Buy milk and eggs")
}
```

---

## Implementation Plan

### Phase 1: Local Database (Week 1)
1. Set up SwiftData models with sync metadata
2. Implement CRUD operations with `syncStatus` tracking
3. Add local query optimization (indexes)
4. Test offline CRUD operations

### Phase 2: CloudKit Sync (Week 2)
1. Implement CloudKitManager actor
2. Add upload queue with exponential backoff
3. Add download/merge logic with LWW resolution
4. Implement background sync triggers

### Phase 3: Error Handling (Week 3)
1. Add error categorization and handling
2. Implement user-facing error messages
3. Add sync status indicators to UI
4. Test all error scenarios

### Phase 4: Polish & Testing (Week 4)
1. Add integration tests for offline + sync scenarios
2. Test conflict resolution with two devices
3. Test error recovery (quota, network, permissions)
4. Performance testing (sync 100+ tasks)

---

## Validation Metrics

**Success criteria:**
- ✅ App works 100% offline (no crashes, no data loss)
- ✅ Sync completes in < 5 seconds for 50 tasks
- ✅ Conflicts resolve correctly 100% of time (LWW)
- ✅ No data loss during network failures
- ✅ User can understand all error messages without docs
- ✅ Retry queue recovers from temporary failures (3/3 attempts)

**Re-evaluation triggers:**
- ❌ Users report lost changes due to conflicts → Implement CRDT or manual resolution
- ❌ Sync takes > 10 seconds → Optimize queries or batch operations
- ❌ Users confused by error messages → Simplify wording

---

## Positive Consequences

### User Experience ✅
- **Instant feedback** - UI updates immediately, feels responsive
- **Works anywhere** - Airplane mode, poor connection, no internet
- **No data loss** - Local-first ensures changes are never lost
- **Transparent** - User knows when offline vs synced
- **Rare errors** - Most errors handled silently with retries

### Development Benefits ✅
- **Testable** - Can simulate offline, conflicts, errors
- **Centralized** - CloudKitManager handles all sync logic
- **Maintainable** - Clear separation: local DB, sync layer, UI
- **Scalable** - Can add more sophisticated conflict resolution later

### Technical Benefits ✅
- **Performance** - Local DB queries are instant (<10ms)
- **Battery efficient** - Background sync uses minimal power
- **Reliable** - Retry queue ensures eventual consistency
- **Simple** - LWW is easy to reason about and debug

---

## Negative Consequences

### Lost Changes (Low Risk) ⚠️
- **Issue:** LWW can lose simultaneous edits
- **Likelihood:** Low for family app (2 users, rare simultaneous edits)
- **Mitigation:** Add change history (future), show merge notification
- **Decision:** Acceptable for MVP, revisit if users report issues

### Increased Complexity ⚠️
- **Issue:** Managing sync state adds code complexity
- **Mitigation:** Centralize in CloudKitManager actor
- **Trade-off:** Complexity vs offline capability (worth it)

### Storage Overhead 💾
- **Issue:** Local DB + CloudKit = 2x storage
- **Impact:** Minimal (~1-5MB for typical usage)
- **Mitigation:** Add periodic cleanup of old completed tasks

---

## Related Decisions

- **ADR-001:** Use CloudKit as Backend - Defines sync infrastructure
- **ADR-003** (proposed): Use SwiftData vs Core Data for local storage
- **ADR-004** (proposed): Add change history/audit log for transparency

---

## References

- [CloudKit Error Handling](https://developer.apple.com/documentation/cloudkit/ckerror)
- [Conflict Resolution Strategies](https://martin.kleppmann.com/2020/07/06/crdt-hard-parts-hydra.html)
- [Offline-First Architecture](https://offlinefirst.org/)
- [WWDC 2021: CloudKit Best Practices](https://developer.apple.com/videos/play/wwdc2021/10003/)
- [Apple HIG: Handling Errors](https://developer.apple.com/design/human-interface-guidelines/patterns/handling-errors/)

---

**Last Updated:** 2026-01-12
**Next Review:** 2026-04-12 (after MVP launch and 3 months of usage data)
