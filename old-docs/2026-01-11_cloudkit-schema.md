# CloudKit Data Schema - Family To-Do App

**Date:** 2026-01-11
**Project:** Family To-Do App (iOS)
**Purpose:** Detailed CloudKit record type definitions, relationships, and implementation guide

---

## Overview

This document defines the complete CloudKit data schema for Family To-Do App. All data is stored in CloudKit with the following zones:
- **Private Database:** User's own data (preferences, local state)
- **Shared Database:** Household data shared among members

---

## Database Architecture

### CloudKit Zones

```
CloudKit Container: iCloud.com.yourname.familytodo

├── Private Database
│   └── User preferences, local cache
│
└── Shared Database
    └── CKShare-based sharing
        ├── Household (root share)
        ├── Tasks (shared via household)
        ├── RecurringChores (shared via household)
        ├── Areas (shared via household)
        └── Members (shared via household)
```

---

## Core Entities

### 1. Household

**Record Type:** `Household`
**Database:** Shared (via CKShare)
**Purpose:** Root entity representing a shared household

#### Fields

| Field | Type | Required | Indexed | Description |
|-------|------|----------|---------|-------------|
| `id` | String (UUID) | ✅ | ✅ | Unique identifier |
| `name` | String | ✅ | ❌ | Household name ("Smith Family") |
| `ownerId` | CKRecord.Reference | ✅ | ✅ | Creator user ID |
| `createdAt` | Date | ✅ | ✅ | Creation timestamp |
| `updatedAt` | Date | ✅ | ❌ | Last modification timestamp |

#### Relationships
- **Owner:** One User (via `ownerId`)
- **Members:** Many Members (via Member.householdId)
- **Tasks:** Many Tasks (via Task.householdId)
- **Areas:** Many Areas (via Area.householdId)
- **RecurringChores:** Many RecurringChores (via RecurringChore.householdId)

#### CloudKit Sharing
```swift
// Household is the root share object
let share = CKShare(rootRecord: householdRecord)
share[CKShare.SystemFieldKey.title] = "Smith Family To-Do"
share.publicPermission = .none // Private to invited members only
```

#### Swift Model
```swift
struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    let ownerId: String // User's CKRecord.ID.recordName
    let createdAt: Date
    var updatedAt: Date

    // Relationships (not stored in CloudKit, populated via queries)
    var members: [Member] = []
    var areas: [Area] = []
}
```

---

### 2. Member

**Record Type:** `Member`
**Database:** Shared (via Household share)
**Purpose:** Represents a user's membership in a household

#### Fields

| Field | Type | Required | Indexed | Description |
|-------|------|----------|---------|-------------|
| `id` | String (UUID) | ✅ | ✅ | Unique identifier |
| `householdId` | CKRecord.Reference | ✅ | ✅ | Reference to Household |
| `userId` | String | ✅ | ✅ | User's CKRecord.ID.recordName |
| `displayName` | String | ✅ | ❌ | User's display name |
| `role` | String | ✅ | ✅ | "owner" or "member" |
| `joinedAt` | Date | ✅ | ✅ | When user joined household |
| `isActive` | Int64 (bool) | ✅ | ✅ | Whether member is active (1) or left (0) |

#### Relationships
- **Household:** One Household (via `householdId`)
- **Assigned Tasks:** Many Tasks (via Task.assigneeId)

#### Indexes
- Primary: `householdId` + `userId` (for querying member by user in household)
- Secondary: `householdId` + `isActive` (for querying active members)

#### Swift Model
```swift
struct Member: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    let userId: String // CloudKit User Record ID
    var displayName: String
    let role: MemberRole
    let joinedAt: Date
    var isActive: Bool

    enum MemberRole: String, Codable {
        case owner
        case member
    }
}
```

---

### 3. Area

**Record Type:** `Area`
**Database:** Shared (via Household share)
**Purpose:** Logical area/board for organizing tasks (Kitchen, Bathroom, Garden, etc.)

#### Fields

| Field | Type | Required | Indexed | Description |
|-------|------|----------|---------|-------------|
| `id` | String (UUID) | ✅ | ✅ | Unique identifier |
| `householdId` | CKRecord.Reference | ✅ | ✅ | Reference to Household |
| `name` | String | ✅ | ❌ | Area name ("Kitchen", "Bathroom") |
| `icon` | String | ❌ | ❌ | SF Symbol name (optional) |
| `sortOrder` | Int64 | ✅ | ❌ | Display order (0, 1, 2...) |
| `createdAt` | Date | ✅ | ✅ | Creation timestamp |

#### Relationships
- **Household:** One Household (via `householdId`)
- **Tasks:** Many Tasks (via Task.areaId)

#### Swift Model
```swift
struct Area: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String? // SF Symbol name
    var sortOrder: Int
    let createdAt: Date

    // Suggested default areas
    static let defaults = [
        Area(name: "Kitchen", icon: "fork.knife", sortOrder: 0),
        Area(name: "Bathroom", icon: "shower", sortOrder: 1),
        Area(name: "Living Room", icon: "sofa", sortOrder: 2),
        Area(name: "Bedroom", icon: "bed.double", sortOrder: 3),
        Area(name: "Garden", icon: "leaf", sortOrder: 4),
        Area(name: "Repairs", icon: "wrench", sortOrder: 5)
    ]
}
```

---

### 4. Task

**Record Type:** `Task`
**Database:** Shared (via Household share)
**Purpose:** Individual task/chore to be completed

#### Fields

| Field | Type | Required | Indexed | Description |
|-------|------|----------|---------|-------------|
| `id` | String (UUID) | ✅ | ✅ | Unique identifier |
| `householdId` | CKRecord.Reference | ✅ | ✅ | Reference to Household |
| `title` | String | ✅ | ❌ | Task title ("Take out trash") |
| `status` | String | ✅ | ✅ | "backlog", "next", "done" |
| `assigneeId` | CKRecord.Reference? | ❌ | ✅ | Reference to Member (nullable) |
| `areaId` | CKRecord.Reference? | ❌ | ✅ | Reference to Area (nullable) |
| `dueDate` | Date? | ❌ | ✅ | Optional due date |
| `completedAt` | Date? | ❌ | ✅ | When task was completed |
| `completedById` | String? | ❌ | ❌ | User ID who completed task |
| `taskType` | String | ✅ | ✅ | "one-off" or "recurring" |
| `recurringChoreId` | CKRecord.Reference? | ❌ | ✅ | If recurring, link to parent chore |
| `notes` | String? | ❌ | ❌ | Optional notes/description |
| `createdAt` | Date | ✅ | ✅ | Creation timestamp |
| `updatedAt` | Date | ✅ | ❌ | Last modification timestamp |

#### Relationships
- **Household:** One Household (via `householdId`)
- **Assignee:** One Member (via `assigneeId`)
- **Area:** One Area (via `areaId`)
- **RecurringChore:** One RecurringChore (via `recurringChoreId`)

#### Indexes (Query Performance)
- Primary: `householdId` + `status` (for "My Tasks" view)
- Secondary: `assigneeId` + `status` (for filtering user's tasks)
- Tertiary: `householdId` + `dueDate` (for deadline sorting)

#### Swift Model
```swift
struct Task: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    var status: TaskStatus
    var assigneeId: UUID?
    var areaId: UUID?
    var dueDate: Date?
    var completedAt: Date?
    var completedById: String?
    let taskType: TaskType
    var recurringChoreId: UUID?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    enum TaskStatus: String, Codable {
        case backlog
        case next
        case done
    }

    enum TaskType: String, Codable {
        case oneOff = "one-off"
        case recurring
    }

    // Computed
    var isOverdue: Bool {
        guard let dueDate = dueDate, status != .done else { return false }
        return dueDate < Date()
    }
}
```

---

### 5. RecurringChore

**Record Type:** `RecurringChore`
**Database:** Shared (via Household share)
**Purpose:** Template for recurring tasks (weekly trash, daily dishes, etc.)

#### Fields

| Field | Type | Required | Indexed | Description |
|-------|------|----------|---------|-------------|
| `id` | String (UUID) | ✅ | ✅ | Unique identifier |
| `householdId` | CKRecord.Reference | ✅ | ✅ | Reference to Household |
| `title` | String | ✅ | ❌ | Chore title ("Take out trash") |
| `recurrenceType` | String | ✅ | ✅ | "daily", "weekly", "biweekly", "monthly" |
| `recurrenceDay` | Int64? | ❌ | ❌ | Day of week (1=Mon, 7=Sun) for weekly |
| `recurrenceDayOfMonth` | Int64? | ❌ | ❌ | Day of month (1-31) for monthly |
| `defaultAssigneeId` | CKRecord.Reference? | ❌ | ❌ | Optional default assignee |
| `areaId` | CKRecord.Reference? | ❌ | ✅ | Reference to Area |
| `isActive` | Int64 (bool) | ✅ | ✅ | Whether chore is active (1) or paused (0) |
| `lastGeneratedDate` | Date? | ❌ | ✅ | Last date task was auto-generated |
| `nextScheduledDate` | Date? | ❌ | ✅ | Next date to generate task |
| `notes` | String? | ❌ | ❌ | Optional notes |
| `createdAt` | Date | ✅ | ✅ | Creation timestamp |
| `updatedAt` | Date | ✅ | ❌ | Last modification timestamp |

#### Relationships
- **Household:** One Household (via `householdId`)
- **Default Assignee:** One Member (via `defaultAssigneeId`)
- **Area:** One Area (via `areaId`)
- **Generated Tasks:** Many Tasks (via Task.recurringChoreId)

#### Recurrence Logic

**Daily:**
```swift
// Generate task every day at midnight
nextScheduledDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
```

**Weekly:**
```swift
// Generate task every Monday (recurrenceDay = 1)
var components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
components.weekday = recurrenceDay
nextScheduledDate = Calendar.current.date(from: components)
```

**Biweekly:**
```swift
// Generate task every 2 weeks on specified day
nextScheduledDate = lastGeneratedDate.addingTimeInterval(14 * 86400)
```

**Monthly:**
```swift
// Generate task on specific day of month (recurrenceDayOfMonth = 15)
var components = Calendar.current.dateComponents([.year, .month], from: Date())
components.day = recurrenceDayOfMonth
nextScheduledDate = Calendar.current.date(from: components)
```

#### Swift Model
```swift
struct RecurringChore: Identifiable, Codable {
    let id: UUID
    let householdId: UUID
    var title: String
    let recurrenceType: RecurrenceType
    var recurrenceDay: Int? // 1-7 for weekly (1=Mon)
    var recurrenceDayOfMonth: Int? // 1-31 for monthly
    var defaultAssigneeId: UUID?
    var areaId: UUID?
    var isActive: Bool
    var lastGeneratedDate: Date?
    var nextScheduledDate: Date?
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    enum RecurrenceType: String, Codable {
        case daily
        case weekly
        case biweekly
        case monthly
    }

    // Calculate next scheduled date
    func calculateNextScheduledDate(after date: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch recurrenceType {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))

        case .weekly:
            guard let weekday = recurrenceDay else { return nil }
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            components.weekday = weekday
            let thisWeek = calendar.date(from: components)!
            if thisWeek > date {
                return thisWeek
            } else {
                return calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeek)
            }

        case .biweekly:
            guard let last = lastGeneratedDate else { return date }
            return calendar.date(byAdding: .day, value: 14, to: last)

        case .monthly:
            guard let dayOfMonth = recurrenceDayOfMonth else { return nil }
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = dayOfMonth
            let thisMonth = calendar.date(from: components)!
            if thisMonth > date {
                return thisMonth
            } else {
                return calendar.date(byAdding: .month, value: 1, to: thisMonth)
            }
        }
    }
}
```

---

## CloudKit Queries

### Common Query Patterns

#### 1. Fetch All Tasks for Household
```swift
let predicate = NSPredicate(format: "householdId == %@", householdReference)
let query = CKQuery(recordType: "Task", predicate: predicate)
query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

let results = try await database.records(matching: query)
```

#### 2. Fetch User's "Next" Tasks
```swift
let predicate = NSPredicate(
    format: "assigneeId == %@ AND status == %@",
    memberReference,
    "next"
)
let query = CKQuery(recordType: "Task", predicate: predicate)
query.sortDescriptors = [NSSortDescriptor(key: "dueDate", ascending: true)]
```

#### 3. Fetch Active Recurring Chores
```swift
let predicate = NSPredicate(
    format: "householdId == %@ AND isActive == 1",
    householdReference
)
let query = CKQuery(recordType: "RecurringChore", predicate: predicate)
```

#### 4. Fetch Tasks by Area
```swift
let predicate = NSPredicate(
    format: "householdId == %@ AND areaId == %@",
    householdReference,
    areaReference
)
let query = CKQuery(recordType: "Task", predicate: predicate)
```

---

## CloudKit Sharing Implementation

### Sharing Flow

1. **Owner creates Household**
```swift
// Create household record
let household = CKRecord(recordType: "Household")
household["name"] = "Smith Family"
household["ownerId"] = currentUserID

// Save to shared database
let savedHousehold = try await sharedDatabase.save(household)

// Create CKShare
let share = CKShare(rootRecord: savedHousehold)
share[CKShare.SystemFieldKey.title] = "Smith Family To-Do"
share.publicPermission = .none

let (savedShare, _) = try await sharedDatabase.modifyRecords(
    saving: [savedHousehold, share],
    deleting: []
)
```

2. **Owner invites member via email/SMS**
```swift
let shareURL = savedShare.url!
let activityVC = UIActivityViewController(
    activityItems: [shareURL],
    applicationActivities: nil
)
// User sends via Messages, Email, etc.
```

3. **Invitee accepts share**
```swift
// CloudKit automatically handles when user taps share link
// App receives notification via CKSharingSupported scene delegate method

func windowScene(_ windowScene: UIWindowScene,
                userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
    let acceptOperation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])
    acceptOperation.perShareResultBlock = { metadata, result in
        switch result {
        case .success:
            // Share accepted, fetch household data
            fetchSharedHousehold()
        case .failure(let error):
            print("Failed to accept share: \(error)")
        }
    }
    CKContainer.default().add(acceptOperation)
}
```

---

## Sync Strategy

### Change Notifications

Subscribe to CloudKit remote notifications to keep data fresh:

```swift
// Subscribe to Task changes
let subscription = CKQuerySubscription(
    recordType: "Task",
    predicate: NSPredicate(format: "householdId == %@", householdReference),
    options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
)

let notificationInfo = CKSubscription.NotificationInfo()
notificationInfo.shouldSendContentAvailable = true // Silent notification

subscription.notificationInfo = notificationInfo

try await database.save(subscription)
```

### Handling Remote Notifications

```swift
func application(_ application: UIApplication,
                didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

    let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)

    if notification.notificationType == .query,
       let queryNotification = notification as? CKQueryNotification {

        // Fetch changed record
        if let recordID = queryNotification.recordID {
            Task {
                do {
                    let record = try await database.record(for: recordID)
                    await updateLocalCache(with: record)
                    completionHandler(.newData)
                } catch {
                    completionHandler(.failed)
                }
            }
        }
    }
}
```

---

## Indexes & Performance

### Recommended Indexes

CloudKit automatically indexes:
- Record ID
- Record Type
- Creation Date
- Modification Date

**Additional indexes needed:**

```swift
// Task indexes
Task.householdId (QUERYABLE) // For fetching all tasks in household
Task.status (QUERYABLE) // For filtering by status
Task.assigneeId (QUERYABLE) // For "My Tasks" view
Task.dueDate (SORTABLE) // For sorting by deadline

// Member indexes
Member.householdId + Member.userId (QUERYABLE) // For checking membership
Member.isActive (QUERYABLE) // For fetching active members

// RecurringChore indexes
RecurringChore.householdId (QUERYABLE)
RecurringChore.isActive (QUERYABLE)
RecurringChore.nextScheduledDate (SORTABLE) // For scheduled task generation
```

---

## Data Size Limits

**CloudKit Limits:**
- Max record size: 1 MB
- Max asset size: 250 MB (not relevant for this app)
- Max string field: ~1 MB
- Max records per query: 100 (use cursor for pagination)

**Family To-Do Limits:**
- Task title: 200 characters (reasonable limit)
- Task notes: 5,000 characters
- Household name: 50 characters
- Member display name: 50 characters

---

## Migration Strategy

**Initial Schema Version: 1.0**

For future schema changes:
1. Add new fields (CloudKit supports adding fields without migration)
2. Never delete fields (backward compatibility)
3. Use versioning if breaking changes needed

```swift
// Example: Adding priority field to Task in v1.1
task["priority"] = "medium" // New field in v1.1
// Old clients (v1.0) will ignore this field
```

---

## Summary

### Record Types Overview

| Record Type | Database | Shareable | Key Fields | Purpose |
|-------------|----------|-----------|------------|---------|
| **Household** | Shared | ✅ (Root) | name, ownerId | Shared household container |
| **Member** | Shared | ✅ | householdId, userId, role | User membership |
| **Area** | Shared | ✅ | householdId, name, sortOrder | Task organization |
| **Task** | Shared | ✅ | householdId, title, status, assigneeId | Individual tasks |
| **RecurringChore** | Shared | ✅ | householdId, recurrenceType, nextScheduledDate | Recurring task templates |

### Key Relationships

```
Household (1) ←→ (N) Member
Household (1) ←→ (N) Area
Household (1) ←→ (N) Task
Household (1) ←→ (N) RecurringChore

Member (1) ←→ (N) Task (assigneeId)
Area (1) ←→ (N) Task (areaId)
RecurringChore (1) ←→ (N) Task (recurringChoreId)
```

---

**Next Steps:**
1. Create Xcode project
2. Enable CloudKit capability
3. Implement Swift models based on this schema
4. Implement CloudKitManager for CRUD operations
5. Test sharing flow with 2+ users

**Document Version:** 1.0
**Last Updated:** 2026-01-11
