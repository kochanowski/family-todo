# HousePulse Testing Strategy

This document outlines the testing infrastructure, automated workflows, and specific test scenarios for the HousePulse application.

## 🤖 CI/CD Pipeline

The project uses **GitHub Actions** for Continuous Integration and Delivery.
- **Workflow**: `iOS CI` (`.github/workflows/ios-ci.yml`)
- **Triggers**: 
  - Push to `main`
  - Pull Requests
  - Manual dispatch
- **Runner**: `macos-15` (Xcode 16.2)

### Pipeline Stages
1.  **Build**: Compiles the application to ensure integrity.
2.  **SwiftLint**: Enforces code style and best practices.
3.  **Unit Tests**: Runs the `FamilyTodoTests` logic suite.
4.  **UI Smoke Tests**: Runs `FamilyTodoUITests` with seeded data scenarios.

---

## 🧪 Unit Tests

Target: `FamilyTodoTests`
Goal: Validate business logic, data models, and store management without UI overhead.

| File | Scope | Description |
|------|-------|-------------|
| **HouseholdTests.swift** | Models | Verifies household creation, member management logic. |
| **TaskTests.swift** | Business Logic | Tests task state transitions, due date calculations. |
| **TaskStoreTests.swift** | Data Layer | Validates persistence and SwiftData interactions for tasks. |
| **RecurringChoreTests.swift** | Feature | Tests logic for repeating chores and next-occurrence calculation. |
| **AreaTests.swift** | Domain | Logic for household areas/rooms. |

---

## 📱 Advanced UI Tests

Target: `FamilyTodoUITests`
Goal: Validate critical user journeys end-to-end using the Simulator.

**Infrastructure**:
- **Seeding**: The app handles the `-uiTestMode` launch argument to inject deterministic data via `UITestHelper`.
- **Reset**: The `-resetData` argument clears the database before each test to ensure isolation.

### Core Flows

#### 1. Shopping List Flow (`testShoppingCoreFlow`)
**Scenario**: User manages their shopping list.
- **Seeding**: Injects items ("Milk", "Bread", "Eggs" [bought]).
- **Steps**:
  1. Verifies seeded items are visible.
  2. Uses **Rapid Entry** to add a new item ("Cheese").
  3. Opens the **Restock Panel**.
  4. Verifies "Eggs" appears in the recently purchased list.

#### 2. Tasks Management Flow (`testTasksCoreFlow`)
**Scenario**: User tracks household to-dos.
- **Seeding**: Injects active and completed tasks.
- **Steps**:
  1. Navigates to **Tasks** tab.
  2. Verifies seeded active task ("Pay bills").
  3. Adds a new task ("Water plants").
  4. Verifies the new task appears in the list.

#### 3. Backlog Organization Flow (`testBacklogCoreFlow`)
**Scenario**: User browses categorized items.
- **Seeding**: Injects "Groceries" category with items.
- **Steps**:
  1. Navigates to **Backlog** tab.
  2. Verifies category "Groceries" exists.
  3. Verifies item "Olive Oil" is correctly nested.

#### 4. Settings Navigation (`testSettingsFlow`)
**Scenario**: User accesses app configuration.
- **Seeding**: None (Clean state).
- **Steps**:
  1. Navigates to **More** tab.
  2. Opens **Settings**.
  3. Verifies navigation stack pushes the Settings view.

---

## 🚀 How to Run Tests

### Locally on CLI
```bash
# Run all tests
xcodebuild test -scheme HousePulse -destination 'platform=iOS Simulator,name=iPhone 16'

# Run only UI Tests
xcodebuild test -scheme HousePulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FamilyTodoUITests
```

### In Xcode
1. Open `FamilyTodo.xcodeproj`.
2. Select target generic iOS device or Simulator.
3. Press `Cmd+U` to run all tests.
