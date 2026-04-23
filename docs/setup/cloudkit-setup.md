# CloudKit Setup Guide

**Date:** 2026-01-10
**Project:** Family To-Do App
**Purpose:** Step-by-step guide to configure CloudKit backend for iOS app

---

## What is CloudKit?

**CloudKit** is Apple's Backend-as-a-Service (BaaS) platform that provides:
- ☁️ **Cloud database** (no server management needed)
- 🔐 **Authentication** via iCloud accounts (automatic)
- 🔄 **Automatic sync** across user's devices
- 📱 **Offline-first** architecture built-in
- 💰 **Free tier** (1GB storage, 10GB transfer/month)

**Perfect for Family To-Do App because:**
- No backend code to write
- No server costs for MVP
- Works seamlessly with Sign in with Apple
- Native iOS integration
- Built-in privacy and security

---

## Prerequisites

Before you start, ensure you have:
- ✅ **Apple Developer Account** ($99/year) - required for CloudKit
- ✅ **Xcode** installed (on macOS or via GitHub Actions)
- ✅ **iOS project** created in Xcode
- ✅ **Bundle Identifier** configured (e.g., `com.yourname.familytodo`)

---

## Step 1: Enable CloudKit in Xcode

### 1.1 Open Your Project
```bash
# On macOS:
open FamilyTodo.xcodeproj

# If using GitHub Actions:
# You'll configure this in Xcode project settings, then commit changes
```

### 1.2 Add iCloud Capability
1. In Xcode, select your **project** in the navigator
2. Select your **target** (e.g., "FamilyTodo")
3. Go to **"Signing & Capabilities"** tab
4. Click **"+ Capability"** button
5. Select **"iCloud"**

### 1.3 Enable CloudKit
1. In the newly added iCloud section, check **"CloudKit"**
2. Xcode will automatically create a **container** named:
   ```
   iCloud.com.yourname.familytodo
   ```
3. Make note of this **Container Identifier** - you'll need it later

### 1.4 Enable "Background Modes" (for sync)
1. Click **"+ Capability"** again
2. Select **"Background Modes"**
3. Check **"Remote notifications"**
   - This allows CloudKit to notify your app of changes

### 1.5 Verify Configuration
Your `FamilyTodo.entitlements` file should now contain:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.yourname.familytodo</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array>
        <string>iCloud.com.yourname.familytodo</string>
    </array>
</dict>
</plist>
```

---

## Step 2: Design CloudKit Schema

### 2.1 Understanding CloudKit Databases

CloudKit provides **two databases** per container:
- **Public Database**: Shared data visible to all users
  - ❌ NOT suitable for Family To-Do (privacy concerns)
- **Private Database**: User's personal data, synced across their devices
  - ✅ Use this for Household data
- **Shared Database**: Data shared between specific users
  - ✅ Use this for multi-user Households

### 2.2 Record Types (Tables)

For Family To-Do App, create these **Record Types**:

#### `Household`
| Field | Type | Notes |
|-------|------|-------|
| `name` | String | e.g., "Smith Family" |
| `createdAt` | Date/Time | Auto |
| `ownerID` | Reference | Creator's user ID |

#### `Member`
| Field | Type | Notes |
|-------|------|-------|
| `userID` | String | iCloud user identifier |
| `displayName` | String | e.g., "Wojtek" |
| `household` | Reference | → Household |
| `role` | String | "Owner" or "Member" |
| `joinedAt` | Date/Time | |

#### `Area`
| Field | Type | Notes |
|-------|------|-------|
| `name` | String | e.g., "Kitchen" |
| `household` | Reference | → Household |
| `emoji` | String | Optional (e.g., "🍳") |

#### `Task`
| Field | Type | Notes |
|-------|------|-------|
| `title` | String | e.g., "Wipe dust" |
| `status` | String | "Backlog", "Next", "Done" |
| `assignee` | Reference | → Member |
| `area` | Reference | → Area (optional) |
| `priority` | String | "Today", "This Week", "Someday" |
| `dueDate` | Date/Time | Optional |
| `isRecurring` | Int64 | 0 or 1 (boolean) |
| `recurrence` | String | "daily", "weekly", "monthly" (optional) |
| `household` | Reference | → Household |
| `createdAt` | Date/Time | |
| `completedAt` | Date/Time | Optional |

#### `RecurringChore`
| Field | Type | Notes |
|-------|------|-------|
| `title` | String | e.g., "Clean bathroom" |
| `recurrence` | String | "daily", "weekly", "biweekly", "monthly" |
| `dayOfWeek` | Int64 | 1-7 (Monday-Sunday) for weekly |
| `dayOfMonth` | Int64 | 1-31 for monthly |
| `assignee` | Reference | → Member |
| `area` | Reference | → Area (optional) |
| `household` | Reference | → Household |
| `lastCompletedAt` | Date/Time | Optional |
| `nextScheduledAt` | Date/Time | |

### 2.3 Create Schema in CloudKit Dashboard

**Option A: Via Xcode (Recommended)**
1. Write Swift code using `CKRecord` types
2. Run app in **Development environment**
3. CloudKit auto-creates schema from your code

**Option B: Via CloudKit Dashboard**
1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Select your container (iCloud.com.yourname.familytodo)
3. Click **"Schema"** → **"Record Types"**
4. Click **"+"** to create each Record Type manually
5. Add fields as per table above

**Recommendation:** Use **Option A** (code-first) for faster development.

---

## Step 3: Implement CloudKit in Swift

### 3.1 Create CloudKit Manager

Create a singleton manager to handle all CloudKit operations:

```swift
// CloudKitManager.swift
import CloudKit
import Foundation

class CloudKitManager {
    static let shared = CloudKitManager()

    // Use Private Database for user's personal data
    private let database = CKContainer.default().privateCloudDatabase

    // Use Shared Database for Household data shared with partner
    private let sharedDatabase = CKContainer.default().sharedCloudDatabase

    private init() {}

    // MARK: - Household Operations

    func createHousehold(name: String) async throws -> CKRecord {
        let record = CKRecord(recordType: "Household")
        record["name"] = name as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        return try await database.save(record)
    }

    func fetchHousehold(recordID: CKRecord.ID) async throws -> CKRecord {
        return try await database.record(for: recordID)
    }

    // MARK: - Task Operations

    func createTask(
        title: String,
        status: String,
        assignee: CKRecord.ID,
        household: CKRecord.ID,
        priority: String = "Someday",
        area: CKRecord.ID? = nil
    ) async throws -> CKRecord {
        let record = CKRecord(recordType: "Task")
        record["title"] = title as CKRecordValue
        record["status"] = status as CKRecordValue
        record["assignee"] = CKRecord.Reference(recordID: assignee, action: .none)
        record["household"] = CKRecord.Reference(recordID: household, action: .deleteSelf)
        record["priority"] = priority as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["isRecurring"] = 0 as CKRecordValue

        if let area = area {
            record["area"] = CKRecord.Reference(recordID: area, action: .none)
        }

        return try await database.save(record)
    }

    func updateTaskStatus(recordID: CKRecord.ID, newStatus: String) async throws {
        let record = try await database.record(for: recordID)
        record["status"] = newStatus as CKRecordValue

        if newStatus == "Done" {
            record["completedAt"] = Date() as CKRecordValue
        }

        try await database.save(record)
    }

    func fetchTasks(for householdID: CKRecord.ID, status: String? = nil) async throws -> [CKRecord] {
        let householdRef = CKRecord.Reference(recordID: householdID, action: .none)
        var predicate: NSPredicate

        if let status = status {
            predicate = NSPredicate(
                format: "household == %@ AND status == %@",
                householdRef,
                status
            )
        } else {
            predicate = NSPredicate(format: "household == %@", householdRef)
        }

        let query = CKQuery(recordType: "Task", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await database.records(matching: query)
        return results.compactMap { try? $0.1.get() }
    }

    // MARK: - Recurring Chores

    func createRecurringChore(
        title: String,
        recurrence: String,
        dayOfWeek: Int?,
        assignee: CKRecord.ID,
        household: CKRecord.ID,
        area: CKRecord.ID? = nil
    ) async throws -> CKRecord {
        let record = CKRecord(recordType: "RecurringChore")
        record["title"] = title as CKRecordValue
        record["recurrence"] = recurrence as CKRecordValue
        record["assignee"] = CKRecord.Reference(recordID: assignee, action: .none)
        record["household"] = CKRecord.Reference(recordID: household, action: .deleteSelf)

        if let dayOfWeek = dayOfWeek {
            record["dayOfWeek"] = dayOfWeek as CKRecordValue
        }

        if let area = area {
            record["area"] = CKRecord.Reference(recordID: area, action: .none)
        }

        // Calculate next scheduled date
        record["nextScheduledAt"] = calculateNextScheduledDate(
            recurrence: recurrence,
            dayOfWeek: dayOfWeek
        ) as CKRecordValue

        return try await database.save(record)
    }

    func completeRecurringChore(recordID: CKRecord.ID) async throws {
        let record = try await database.record(for: recordID)
        let recurrence = record["recurrence"] as? String ?? "weekly"
        let dayOfWeek = record["dayOfWeek"] as? Int

        // Mark as completed
        record["lastCompletedAt"] = Date() as CKRecordValue

        // Schedule next occurrence
        record["nextScheduledAt"] = calculateNextScheduledDate(
            recurrence: recurrence,
            dayOfWeek: dayOfWeek
        ) as CKRecordValue

        try await database.save(record)

        // Create a new Task for the next occurrence
        let title = record["title"] as? String ?? "Recurring Task"
        let assignee = (record["assignee"] as? CKRecord.Reference)?.recordID
        let household = (record["household"] as? CKRecord.Reference)?.recordID
        let area = (record["area"] as? CKRecord.Reference)?.recordID

        if let assignee = assignee, let household = household {
            _ = try await createTask(
                title: title,
                status: "Backlog",
                assignee: assignee,
                household: household,
                priority: "This Week",
                area: area
            )
        }
    }

    // MARK: - Helpers

    private func calculateNextScheduledDate(recurrence: String, dayOfWeek: Int?) -> Date {
        let calendar = Calendar.current
        let now = Date()

        switch recurrence {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now

        case "weekly":
            guard let dayOfWeek = dayOfWeek else { return now }
            let today = calendar.component(.weekday, from: now)
            let daysToAdd = (dayOfWeek - today + 7) % 7
            return calendar.date(byAdding: .day, value: daysToAdd == 0 ? 7 : daysToAdd, to: now) ?? now

        case "biweekly":
            guard let dayOfWeek = dayOfWeek else { return now }
            let today = calendar.component(.weekday, from: now)
            let daysToAdd = (dayOfWeek - today + 14) % 14
            return calendar.date(byAdding: .day, value: daysToAdd == 0 ? 14 : daysToAdd, to: now) ?? now

        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: now) ?? now

        default:
            return calendar.date(byAdding: .day, value: 7, to: now) ?? now
        }
    }
}
```

### 3.2 Create SwiftUI Models

```swift
// Models/Task.swift
import CloudKit
import Foundation

struct Task: Identifiable {
    let id: CKRecord.ID
    var title: String
    var status: String // "Backlog", "Next", "Done"
    var assignee: CKRecord.ID
    var priority: String // "Today", "This Week", "Someday"
    var dueDate: Date?
    var area: CKRecord.ID?
    var createdAt: Date
    var completedAt: Date?

    init(from record: CKRecord) {
        self.id = record.recordID
        self.title = record["title"] as? String ?? ""
        self.status = record["status"] as? String ?? "Backlog"
        self.assignee = (record["assignee"] as? CKRecord.Reference)?.recordID ?? CKRecord.ID(recordName: "unknown")
        self.priority = record["priority"] as? String ?? "Someday"
        self.dueDate = record["dueDate"] as? Date
        self.area = (record["area"] as? CKRecord.Reference)?.recordID
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.completedAt = record["completedAt"] as? Date
    }
}
```

### 3.3 Use in SwiftUI Views

```swift
// Views/TaskListView.swift
import SwiftUI
import CloudKit

struct TaskListView: View {
    @State private var tasks: [Task] = []
    @State private var isLoading = false

    let householdID: CKRecord.ID

    var body: some View {
        List(tasks) { task in
            TaskRow(task: task)
        }
        .navigationTitle("My Tasks")
        .task {
            await loadTasks()
        }
        .refreshable {
            await loadTasks()
        }
    }

    private func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let records = try await CloudKitManager.shared.fetchTasks(
                for: householdID,
                status: "Next"
            )
            tasks = records.map { Task(from: $0) }
        } catch {
            print("Error loading tasks: \(error)")
        }
    }
}
```

---

## Step 4: Handle Sharing (Multi-User Households)

CloudKit provides **CKShare** for sharing data between users.

### 4.1 Create a Share

```swift
extension CloudKitManager {
    func createShare(for household: CKRecord) async throws -> CKShare {
        let share = CKShare(rootRecord: household)
        share[CKShare.SystemFieldKey.title] = "Join our Household" as CKRecordValue
        share.publicPermission = .none // Only invited users can access

        let (savedRecord, savedShare) = try await database.modifyRecords(
            saving: [household, share],
            deleting: []
        )

        return savedShare.first as! CKShare
    }

    func generateShareLink(for share: CKShare) async throws -> URL {
        let container = CKContainer.default()
        let url = try await container.shareURL(for: share)
        return url
    }
}
```

### 4.2 Accept a Share

```swift
extension CloudKitManager {
    func acceptShare(metadata: CKShare.Metadata) async throws {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        _ = try await container.accept(metadata)
    }
}
```

### 4.3 Handle Share URLs in App

```swift
// In your App file:
import SwiftUI
import CloudKit

@main
struct FamilyTodoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        await handleIncomingURL(url)
                    }
                }
        }
    }

    private func handleIncomingURL(_ url: URL) async {
        // Check if it's a CloudKit share URL
        guard url.scheme == "https",
              url.host?.contains("icloud") == true else {
            return
        }

        do {
            let metadata = try await CKContainer.default().shareMetadata(for: url)
            try await CloudKitManager.shared.acceptShare(metadata: metadata)
            print("Successfully joined household!")
        } catch {
            print("Error accepting share: \(error)")
        }
    }
}
```

---

## Step 5: Testing CloudKit

### 5.1 Development vs Production

CloudKit has **two environments**:
- **Development**: For testing (isolated data)
- **Production**: For real users (requires schema deployment)

**During MVP development, use Development environment.**

### 5.2 View Data in CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Select your container
3. Choose **"Development"** environment
4. Click **"Data"** → Select Record Type (e.g., "Task")
5. View all records created by your app

### 5.3 Deploy Schema to Production

Once your schema is stable:
1. In CloudKit Dashboard, go to **"Schema"**
2. Click **"Deploy to Production"**
3. Confirm deployment
4. **⚠️ WARNING**: Production schema changes are permanent!

---

## Step 6: Handle Offline-First Architecture

CloudKit automatically handles offline sync, but you need local caching.

### 6.1 Use SwiftData for Local Cache

```swift
import SwiftData

@Model
class TaskModel {
    @Attribute(.unique) var cloudKitID: String
    var title: String
    var status: String
    var priority: String
    var createdAt: Date
    var syncStatus: String // "synced", "pending", "conflict"

    init(cloudKitID: String, title: String, status: String, priority: String, createdAt: Date) {
        self.cloudKitID = cloudKitID
        self.title = title
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.syncStatus = "synced"
    }
}
```

### 6.2 Sync Strategy

```swift
class SyncManager {
    static let shared = SyncManager()

    private let modelContext: ModelContext

    func syncTasks() async {
        // 1. Fetch from CloudKit
        let cloudTasks = try? await CloudKitManager.shared.fetchTasks(for: householdID)

        // 2. Fetch from local SwiftData
        let localTasks = try? modelContext.fetch(FetchDescriptor<TaskModel>())

        // 3. Merge changes
        // - If cloudTask.modifiedAt > localTask.modifiedAt → Update local
        // - If localTask.syncStatus == "pending" → Push to CloudKit
        // - If conflict → Use conflict resolution strategy
    }
}
```

---

## Step 7: Monitor CloudKit Usage

### 7.1 Free Tier Limits
- **Storage**: 1GB
- **Data Transfer**: 10GB/month
- **Requests**: 40/second

### 7.2 Estimate Usage for Family To-Do

**Assumptions:**
- 2 users
- 100 tasks/month
- 10 areas
- 5 recurring chores

**Estimated Storage:**
- Task record: ~1KB
- 100 tasks × 1KB = 100KB/month
- **Total: <1MB/month** ✅ Well within free tier

**Estimated Transfer:**
- 100 reads/day × 1KB = 100KB/day
- **Total: ~3MB/month** ✅ Well within free tier

### 7.3 View Usage in Dashboard
1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
2. Click **"Usage"**
3. View storage and transfer metrics

---

## Troubleshooting

### Issue: "CloudKit Not Available"
**Solution:** User must be signed into iCloud on their device
```swift
CKContainer.default().accountStatus { status, error in
    if status == .available {
        print("CloudKit ready")
    } else {
        print("Sign into iCloud in Settings")
    }
}
```

### Issue: "Permission Denied"
**Solution:** Check entitlements and container identifier match

### Issue: "Record Not Found"
**Solution:** Ensure you're querying correct database (private vs shared)

### Issue: "Schema Mismatch"
**Solution:** Delete app, reset Development environment in Dashboard, reinstall

---

## Next Steps

Once CloudKit is configured:
1. ✅ Implement SwiftUI views that use CloudKitManager
2. ✅ Add local caching with SwiftData
3. ✅ Implement sharing flow for inviting partner
4. ✅ Test offline-first behavior (Airplane Mode)
5. ✅ Deploy schema to Production when stable

---

## Resources

- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
- [WWDC: Getting Started with CloudKit](https://developer.apple.com/videos/play/wwdc2021/10003/)
- [Sharing CloudKit Data](https://developer.apple.com/documentation/cloudkit/shared_records)

---

**Last Updated:** 2026-01-10
**Author:** Claude Code Assistant
