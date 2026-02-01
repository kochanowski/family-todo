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
4.  **UI Smoke Tests**: Runs `FamilyTodoUITests` (excluding Performance tests).
5.  **Nightly Regression**: Runs full suite + Performance tests on multiple simulators.

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

## 📱 Advanced UI Tests (Regression Suite)

Target: `FamilyTodoUITests`
Goal: Validate critical user journeys end-to-end using the Simulator.

**Infrastructure**:
- **Seeding**: The app handles the `-uiTestMode` launch argument.
- **Scenarios**:
    - `-seedScenario guest_no_household`: Pure guest state.
    - `-seedScenario household_basic`: Seeds Household, User, Shopping Items, Tasks.
    - `-seedScenario heavy_data`: Stress test data (50+ items).

### Core Flows

#### 1. Shopping List Flow
- **Rapid Entry**: adding multiple items via keyboard.
- **Item Removal**: toggle moves to restock.
- **Restock**: items appear in restock panel.

#### 2. Tasks Management Flow
- **Completion**: tasks move to completed section.
- **Persistence**: tasks persist after app termination.

#### 3. Backlog Organization Flow
- **Category Management**: create, delete categories.
- **Warning Logic**: verifies delete protections.

#### 4. Settings Navigation
- **Appearance**: toggle Dark/Light mode.
- **Navigation**: stability checks.

---

## 🏎️ Performance Tests

Target: `FamilyTodoPerformanceTests` (in `FamilyTodoUITests` bundle)
Goal: Detect regressions in launch time and scrolling.
- **Launch**: Measures `XCTApplicationLaunchMetric`.
- **Scroll**: Measures frame rate/hitch ratio on heavy lists.

**Running**:
- `ios-ci.yml` (PR): SKIPS performance tests.
- `nightly.yml`: RUNS performance tests.

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
