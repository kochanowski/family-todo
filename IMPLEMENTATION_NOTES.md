# House Pulse - Implementation Notes

## Architecture Overview

House Pulse is a SwiftUI-based family task management app with CloudKit synchronization and SwiftData offline support.

### Layer Structure

```
┌─────────────────────────────────────────┐
│                  Views                   │
│   (SwiftUI screens and components)       │
├─────────────────────────────────────────┤
│                 Stores                   │
│   (ObservableObject state managers)      │
├─────────────────────────────────────────┤
│           CloudKitManager                │
│   (CloudKit CRUD operations)             │
├─────────────────────────────────────────┤
│              SwiftData                   │
│   (Cached* models for offline)           │
└─────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Offline-First with CloudKit Sync

Each store follows a consistent pattern:
1. Load from SwiftData cache first (instant UI)
2. Fetch from CloudKit in background
3. Update cache and UI with fresh data
4. Optimistic updates on user actions

### 2. Theme System

- `ThemeStore`: Observable store for theme selection
- `ThemePreset`: Enum with `.journal`, `.pastel`, `.soft`, `.night`
- `AppColors`: Light/Night palettes for canvas, surface, ink colors
- `CardTheme`: Per-card-type gradient and accent colors

### 3. Haptic Feedback

Centralized `HapticManager` utility provides:
- `lightTap()` / `mediumTap()` / `heavyTap()` - Impact feedback
- `success()` / `warning()` / `error()` - Notification feedback
- `selection()` - Selection feedback for tab switches

### 4. Custom Tab Bar

`FloatingTabBar` uses glassmorphism (`.ultraThinMaterial`) with:
- Capsule shape with shadow
- Animated tab switching
- Haptic feedback on selection

## File Organization

```
FamilyTodo/
├── FamilyTodoApp.swift       # App entry, stores injection
├── ContentView.swift         # Tab container
├── Models/
│   ├── Member.swift          # User model
│   ├── Task.swift            # Task model
│   ├── ShoppingItem.swift    # Shopping item model
│   ├── Household.swift       # Household model
│   ├── Cached*.swift         # SwiftData cache models
│   └── LegacyStubs.swift     # Temporary stubs
├── Stores/
│   ├── ShoppingListStore.swift
│   ├── TaskStore.swift
│   ├── BacklogStore.swift
│   ├── HouseholdStore.swift
│   └── MemberStore.swift
├── Managers/
│   ├── CloudKitManager.swift
│   └── CloudKitManager+Mapping.swift
├── Services/
│   ├── UserSession.swift
│   ├── AuthenticationService.swift
│   └── NotificationService.swift
├── Views/
│   ├── ShoppingListView.swift
│   ├── TasksView.swift
│   ├── BacklogView.swift
│   ├── MoreView.swift
│   ├── MemberManagementView.swift
│   ├── ShareInviteView.swift
│   └── Components/
│       ├── FloatingTabBar.swift
│       └── ToastView.swift
└── Utilities/
    ├── AppColors.swift
    └── HapticManager.swift
```

## CloudKit Record Types

| Record Type | Fields |
|-------------|--------|
| `Household` | id, name, ownerId, createdAt |
| `Member` | id, householdId, userId, displayName, role, joinedAt, isActive |
| `Task` | id, householdId, title, status, priority, dueDate, assigneeId |
| `ShoppingItem` | id, householdId, name, isBought, quantity, unit |
| `BacklogCategory` | id, householdId, name, colorHex, iconName |
| `BacklogItem` | id, categoryId, title, notes |

## Environment Objects

Injected at app root:
- `UserSession` - Current user state
- `ThemeStore` - Theme preferences
- `HouseholdStore` - Household data and sharing

## CI/CD

- GitHub Actions workflow: `.github/workflows/ios-ci.yml`
- Fastlane for TestFlight deployment
- Pre-commit hooks: swiftlint, swiftformat, xcodebuild tests
