# Testing Strategy (Strategia testowania) - wyjaśnienie

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie jak testować aplikację iOS (unit, UI, integration tests)

---

## Czym są testy automatyczne?

**Automated tests** = kod który sprawdza czy Twój kod działa poprawnie.

### Prosta analogia:

Wyobraź sobie że budujesz most:
- **Bez testów:** Budujesz most → Otwierasz → Może się zawalić
- **Z testami:** Budujesz most → Testowy samochód przejed żdża → Widzisz gdzie pęka → Naprawiasz → Otwierasz

**Testy = test drive PRZED otwarciem dla publiczności!**

### Dla aplikacji:

```swift
// Kod bez testów:
func completeTask(task: Task) {
    task.status = "done"
    task.completedAt = Date()
    saveToCloudKit(task)
}
// Jak wiesz że działa? 🤷
// Uruchamiasz app, klikasz, sprawdzasz ręcznie za KAŻDYM razem

// Kod z testami:
func test_completeTask_setsStatusToDone() {
    let task = Task(title: "Test")
    completeTask(task)
    XCTAssertEqual(task.status, "done") // ✅ Auto check!
}
// Uruchamiasz test → natychmiastowy feedback
```

---

## Po co pisać testy?

### 1. **Catch bugs PRZED users**
```
Bez testów:
1. Piszesz kod
2. Wgrywasz do App Store
3. User znajduje bug
4. Zły review ⭐
5. Naprawiasz, wgrywasz znowu
6. 2 tygodnie stracone

Z testami:
1. Piszesz kod
2. Uruchamiasz testy
3. Test fails → bug znaleziony
4. Naprawiasz OD RAZU
5. Test passes → wgrywasz
6. Users szczęśliwi ⭐⭐⭐⭐⭐
```

### 2. **Refactoring bez strachu**
```
Chcesz przepisać CloudKitManager?

Bez testów:
"Boję się - może coś zepsuję i nie zauważę"

Z testami:
1. Przepisujesz kod
2. Uruchamiasz testy
3. 50/60 testów passed ✅, 10 failed ❌
4. Naprawiasz te 10
5. All tests pass → masz pewność że nic nie zepsułeś!
```

### 3. **Dokumentacja kodu**
```swift
func test_recurringChore_schedulesNextOccurrenceAfterCompletion() {
    // Ten test name mówi CO kod robi!
    let chore = RecurringChore(frequency: .weekly)
    completeChore(chore)
    XCTAssertEqual(chore.nextScheduledAt, nextMonday())
}
```

### 4. **Faster development (long-term)**
```
Pierwsze 2 tygodnie: Wolniej (piszesz testy)
Po 2 miesiącach: Szybciej (nie fixed bugs ręcznie)
Po roku: DUŻO szybciej (refactoring bez strachu)
```

---

## Testing Pyramid

![Testing Pyramid]
```
         /\
        /UI\       ← 10% (Slow, Brittle)
       /____\
      /Integ\      ← 20% (Medium speed)
     /______\
    / Unit  \     ← 70% (Fast, Reliable)
   /__________\
```

**Dlaczego piramida?**
- **Unit tests:** Dużo, szybkie, łatwe do utrzymania
- **Integration tests:** Mniej, wolniejsze, test interakcji
- **UI tests:** Najmniej, najwolniejsze, test całego flow

---

## Poziom 1: Unit Tests Only (MVP Recommended)

### Czym są unit tests?

**Unit test** = test pojedynczej funkcji/metody w izolacji.

**Przykład:**
```swift
// Kod do przetestowania:
func calculateNextScheduledDate(
    recurrence: Recurrence,
    from date: Date
) -> Date {
    let calendar = Calendar.current
    switch recurrence {
    case .daily:
        return calendar.date(byAdding: .day, value: 1, to: date)!
    case .weekly:
        return calendar.date(byAdding: .day, value: 7, to: date)!
    case .monthly:
        return calendar.date(byAdding: .month, value: 1, to: date)!
    }
}

// Unit test:
func test_calculateNextScheduledDate_daily_addsOneDay() {
    let today = Date() // Jan 10, 2026
    let next = calculateNextScheduledDate(recurrence: .daily, from: today)
    let expected = Calendar.current.date(byAdding: .day, value: 1, to: today)!
    XCTAssertEqual(next, expected) // Jan 11, 2026
}

func test_calculateNextScheduledDate_weekly_addsSevenDays() {
    let today = Date()
    let next = calculateNextScheduledDate(recurrence: .weekly, from: today)
    let expected = Calendar.current.date(byAdding: .day, value: 7, to: today)!
    XCTAssertEqual(next, expected)
}
```

### Co testować w Family To-Do?

**Critical logic (MUST test):**
1. **RecurringChore scheduling logic**
   ```swift
   test_recurringChore_daily_schedulesNextDay()
   test_recurringChore_weekly_schedulesNextWeek()
   test_recurringChore_completion_updatesNextScheduledDate()
   ```

2. **Task state transitions**
   ```swift
   test_task_moveToNext_updatesStatus()
   test_task_complete_setsCompletedAt()
   test_task_cannotMoveToNextIfWIPLimitReached()
   ```

3. **WIP limit enforcement**
   ```swift
   test_member_cannotHaveMoreThan3TasksInNext()
   test_addingTaskToNext_whenAtLimit_showsError()
   ```

4. **Data validation**
   ```swift
   test_task_titleRequired()
   test_task_assigneeRequired()
   test_household_minimumOneMember()
   ```

**Nice to have (optional):**
- CloudKitManager mocks
- ViewModel logic
- Date formatters
- Utility functions

### XCTest Framework

**Apple's built-in testing framework - FREE, zero setup!**

**Struktura testu:**
```swift
import XCTest
@testable import HousePulse // Import your app module

class RecurringChoreTests: XCTestCase {
    // 1. Setup (runs before each test)
    override func setUp() {
        super.setUp()
        // Initialize test data
    }

    // 2. Teardown (runs after each test)
    override func tearDown() {
        // Clean up
        super.tearDown()
    }

    // 3. Test method (must start with "test")
    func test_recurringChore_daily_schedulesCorrectly() {
        // Arrange - setup test data
        let chore = RecurringChore(
            title: "Test chore",
            recurrence: .daily,
            assignee: testMember
        )

        // Act - perform action
        let nextDate = chore.calculateNextScheduledDate()

        // Assert - verify result
        let expectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertEqual(nextDate, expectedDate)
    }
}
```

### XCTest Assertions

**Most common:**
```swift
// Equality
XCTAssertEqual(actual, expected)
XCTAssertNotEqual(actual, expected)

// Boolean
XCTAssertTrue(condition)
XCTAssertFalse(condition)

// Nil checking
XCTAssertNil(value)
XCTAssertNotNil(value)

// Throwing
XCTAssertThrowsError(try riskyFunction())
XCTAssertNoThrow(try safeFunction())

// With custom message
XCTAssertEqual(task.status, "done", "Task should be marked as done after completion")
```

### Mocking CloudKit

**Problem:** Unit tests shouldn't call real CloudKit (slow, requires internet, costs $$)

**Solution:** Mock CloudKitManager

```swift
// Protocol for dependency injection
protocol CloudKitManagerProtocol {
    func saveTask(_ task: Task) async throws
    func fetchTasks(for household: Household) async throws -> [Task]
}

// Real implementation
class CloudKitManager: CloudKitManagerProtocol {
    func saveTask(_ task: Task) async throws {
        // Real CloudKit call
    }
}

// Mock for testing
class MockCloudKitManager: CloudKitManagerProtocol {
    var savedTasks: [Task] = []
    var shouldThrowError = false

    func saveTask(_ task: Task) async throws {
        if shouldThrowError {
            throw NSError(domain: "Test", code: 1)
        }
        savedTasks.append(task)
    }

    func fetchTasks(for household: Household) async throws -> [Task] {
        return savedTasks
    }
}

// Test using mock
func test_completeTask_savesToCloudKit() async throws {
    let mockManager = MockCloudKitManager()
    let viewModel = TaskViewModel(cloudKitManager: mockManager)

    let task = Task(title: "Test")
    await viewModel.completeTask(task)

    XCTAssertEqual(mockManager.savedTasks.count, 1)
    XCTAssertEqual(mockManager.savedTasks.first?.status, "done")
}
```

### Running Tests

**Opcja 1: Xcode**
```
1. Cmd+U (Run all tests)
2. Cmd+Ctrl+Option+U (Run tests for current file)
3. Click diamond icon next to test method
```

**Opcja 2: Command Line**
```bash
xcodebuild test \
  -scheme HousePulse \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Opcja 3: GitHub Actions (CI)**
```yaml
# Already in .github/workflows/ios-ci.yml!
- name: Run unit tests
  run: |
    xcodebuild test \
      -project FamilyTodo.xcodeproj \
      -scheme HousePulse \
      -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Code Coverage

**Włącz code coverage:**
```
1. Edit Scheme → Test tab
2. Code Coverage → ☑ Gather coverage for some targets
3. Select HousePulse target
4. Run tests (Cmd+U)
5. View coverage: Report Navigator (Cmd+9) → Coverage tab
```

**Target coverage for MVP:**
- **Critical logic:** 80-90%
- **ViewModels:** 60-70%
- **Views:** Skip (UI tests lepsze)
- **Overall:** 60-70%

### Effort Estimate

**Setup:** 1-2 hours
- Create test target (if not exists)
- Setup basic test structure

**Writing tests:** 2-4 hours per feature
- RecurringChore logic: 3h
- Task management: 2h
- WIP limit: 1h
- Data validation: 1h
- Total: ~7-10h

**Maintenance:** ~30min per new feature

---

## Poziom 2: Unit + UI Tests

### Czym są UI tests?

**UI test** = test całej interakcji użytkownika z app.

**Przykład:**
```swift
// Test user flow: Add new recurring chore
func testUI_addRecurringChore_success() {
    let app = XCUIApplication()
    app.launch()

    // Navigate to recurring chores
    app.tabBars.buttons["Household"].tap()
    app.buttons["Recurring Chores"].tap()

    // Tap add button
    app.navigationBars.buttons["Add"].tap()

    // Fill form
    app.textFields["Title"].tap()
    app.textFields["Title"].typeText("Clean bathroom")

    app.buttons["Frequency"].tap()
    app.pickerWheels.element.adjust(toPickerWheelValue: "Every week")

    app.buttons["Day"].tap()
    app.buttons["Friday"].tap()

    // Save
    app.buttons["Save"].tap()

    // Verify chore appears in list
    XCTAssertTrue(app.staticTexts["Clean bathroom"].exists)
    XCTAssertTrue(app.staticTexts["Every Friday"].exists)
}
```

### Co testować UI tests?

**Critical user flows:**
1. **Onboarding**
   ```swift
   testUI_firstLaunch_showsOnboarding()
   testUI_createHousehold_success()
   testUI_inviteMember_success()
   ```

2. **Task management**
   ```swift
   testUI_addTask_success()
   testUI_completeTask_updatesStatus()
   testUI_moveTaskToNext_success()
   testUI_wipLimitReached_showsError()
   ```

3. **Recurring chores**
   ```swift
   testUI_addRecurringChore_success()
   testUI_completeChore_schedulesNext()
   testUI_deleteChore_removesFromList()
   ```

4. **Navigation**
   ```swift
   testUI_navigation_allTabsAccessible()
   testUI_deepLink_opensCorrectScreen()
   ```

### XCUITest Framework

**Apple's UI testing framework - also built-in!**

**Key concepts:**
```swift
let app = XCUIApplication()

// Finding elements
app.buttons["Add Task"]
app.textFields["Title"]
app.navigationBars.buttons["Save"]
app.tabBars.buttons["Tasks"]
app.tables.cells.element(boundBy: 0)
app.staticTexts["Clean bathroom"]

// Interactions
button.tap()
textField.typeText("Hello")
picker.adjust(toPickerWheelValue: "Weekly")
table.swipeUp()

// Assertions
XCTAssertTrue(element.exists)
XCTAssertEqual(element.label, "Done")
XCTAssertTrue(element.isHittable) // Visible and tappable
```

### Accessibility Identifiers

**Problem:** UI może się zmienić (tekst, layout) → testy się psują

**Solution:** Accessibility identifiers (stable IDs)

```swift
// W SwiftUI View:
Button("Add Task") {
    //  action
}
.accessibilityIdentifier("addTaskButton")

// W UI Test:
app.buttons["addTaskButton"].tap() // Stable!
// Instead of:
app.buttons["Add Task"].tap() // Breaks if text changes!
```

### UI Test Best Practices

**1. Page Object Pattern**
```swift
// Instead of repeating UI interactions:
func testAddTask() {
    app.buttons["Add"].tap()
    app.textFields["Title"].typeText("Test")
    app.buttons["Save"].tap()
}

// Use Page Objects:
class TaskListPage {
    let app: XCUIApplication

    func tapAddButton() {
        app.buttons["addButton"].tap()
    }

    func verifyTaskExists(_ title: String) -> Bool {
        return app.staticTexts[title].exists
    }
}

class AddTaskPage {
    let app: XCUIApplication

    func enterTitle(_ title: String) {
        app.textFields["titleField"].tap()
        app.textFields["titleField"].typeText(title)
    }

    func tapSave() {
        app.buttons["saveButton"].tap()
    }
}

// Test becomes:
func testAddTask() {
    let taskList = TaskListPage(app: app)
    taskList.tapAddButton()

    let addTask = AddTaskPage(app: app)
    addTask.enterTitle("Test task")
    addTask.tapSave()

    XCTAssertTrue(taskList.verifyTaskExists("Test task"))
}
```

**2. Wait for elements**
```swift
// BAD (flaky):
app.buttons["Save"].tap() // Może nie być jeszcze widoczny!

// GOOD:
let saveButton = app.buttons["Save"]
XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
saveButton.tap()
```

**3. Reset app state**
```swift
override func setUp() {
    super.setUp()
    continueAfterFailure = false

    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"] // Flag for app
    app.launch()
}

// W AppDelegate/App:
if CommandLine.arguments.contains("--uitesting") {
    // Clear UserDefaults
    // Use mock data
    // Skip onboarding
}
```

### Effort Estimate

**Setup:** 2-3 hours
- Create UI test target
- Setup page objects structure
- Add accessibility identifiers

**Writing tests:** 1-2 hours per flow
- Add task flow: 1.5h
- Complete task flow: 1h
- Add recurring chore flow: 2h
- Navigation tests: 1h
- Total: ~10-15h

**Maintenance:** ~1h per new feature

---

## Poziom 3: Full Coverage (Unit + UI + Integration)

### Czym są integration tests?

**Integration test** = test interakcji między komponentami (np. app ↔ CloudKit)

**Przykład:**
```swift
// Integration test - real CloudKit call!
func testIntegration_saveTask_syncToCloudKit() async throws {
    // Use DEVELOPMENT CloudKit environment
    let manager = CloudKitManager()
    let household = try await manager.createHousehold(name: "Test Household")

    let task = Task(
        title: "Integration test task",
        status: "backlog",
        household: household.id
    )

    // Real CloudKit save
    let savedTask = try await manager.saveTask(task)

    // Fetch back from CloudKit
    let fetchedTasks = try await manager.fetchTasks(for: household)

    // Verify
    XCTAssertEqual(fetchedTasks.count, 1)
    XCTAssertEqual(fetchedTasks.first?.title, "Integration test task")

    // Cleanup
    try await manager.deleteTask(savedTask)
    try await manager.deleteHousehold(household)
}
```

### Co testować integration tests?

**CloudKit sync:**
1. **CRUD operations**
   ```swift
   testIntegration_createTask_persistsToCloudKit()
   testIntegration_updateTask_syncChanges()
   testIntegration_deleteTask_removesFromCloudKit()
   ```

2. **Sharing**
   ```swift
   testIntegration_shareHousehold_createsShare()
   testIntegration_acceptShare_accessesSharedData()
   ```

3. **Conflict resolution**
   ```swift
   testIntegration_offlineEdits_mergeOnSync()
   testIntegration_conflictingEdits_lastWriteWins()
   ```

4. **Performance**
   ```swift
   testIntegration_fetch1000Tasks_completesIn5Seconds()
   testIntegration_syncLargeDataset_doesNotTimeout()
   ```

### Setup CloudKit Development Environment

**1. Enable CloudKit Development in tests:**
```swift
// In test setUp:
let container = CKContainer.default()
container.accountStatus { status, error in
    guard status == .available else {
        XCTFail("CloudKit not available: \\(error?.localizedDescription ?? \"Unknown\")")
        return
    }
}
```

**2. Use separate CloudKit zone for tests:**
```swift
let testZone = CKRecordZone(zoneName: "TestZone")
// Create zone
// Run tests in this zone
// Delete zone after tests
```

**3. Cleanup after tests:**
```swift
override func tearDown() async throws {
    // Delete all test records
    let query = CKQuery(recordType: "Task", predicate: NSPredicate(value: true))
    let records = try await database.records(matching: query)
    try await database.modifyRecords(deleting: records.map { $0.0 })

    super.tearDown()
}
```

### Performance Testing

```swift
func testPerformance_fetchTasks() {
    measure {
        // This block is executed 10 times
        let tasks = try! await cloudKitManager.fetchTasks(for: household)
    }
    // Xcode shows: avg 0.25s, stddev 0.05s
    // You can set baselines to detect regressions
}
```

### Stress Testing

```swift
func testStress_add1000Tasks_succeeds() async throws {
    for i in 1...1000 {
        let task = Task(title: "Task \\(i)", household: household.id)
        try await manager.saveTask(task)
    }

    let allTasks = try await manager.fetchTasks(for: household)
    XCTAssertEqual(allTasks.count, 1000)
}
```

### Effort Estimate

**Setup:** 4-6 hours
- CloudKit test environment
- Test zones and cleanup
- Mock data generators

**Writing tests:** 3-4 hours per integration point
- CloudKit CRUD: 4h
- Sharing: 3h
- Conflict resolution: 4h
- Performance: 2h
- Total: ~15-20h

**Maintenance:** ~2h per major feature

---

## Porównanie poziomów

| | Level 1: Unit Only | Level 2: Unit + UI | Level 3: Full Coverage |
|---|---|---|---|
| **Test types** | Unit | Unit + UI | Unit + UI + Integration |
| **Code coverage** | 60-70% | 70-80% | 80-90% |
| **Test count** | ~50-100 | ~100-150 | ~150-250 |
| **Setup time** | 1-2h | 3-5h | 8-12h |
| **Writing time** | 10-15h | 20-30h | 40-60h |
| **Maintenance** | 30min/feature | 1.5h/feature | 3h/feature |
| **Run time** | <1 min | 2-5 min | 5-15 min |
| **Confidence** | Medium | High | Very High |
| **When it catches bugs** | During dev | During dev + before release | Dev + release + production edge cases |
| **Cost** | Low | Medium | High |
| **Recommended for** | MVP, startups | Established apps | Mission-critical apps |

---

## Rekomendacja dla Family To-Do

### MVP (Rok 1):

**🏆 Poziom 1: Unit Tests Only**

**Dlaczego:**
- ✅ Lowest time investment (~10-15h)
- ✅ Catches most critical bugs (logic errors)
- ✅ Fast feedback loop (<1min test run)
- ✅ Easy to maintain
- ✅ Good enough for MVP with 10-100 users

**Co testować:**
- RecurringChore scheduling (critical!)
- WIP limit enforcement (critical!)
- Task state transitions
- Data validation

**Skip:**
- UI tests (manual testing wystarczy dla MVP)
- Integration tests (CloudKit jest tested by Apple)

### Post-MVP (Rok 2):

**Dodaj Poziom 2: UI Tests**

**Kiedy:**
- User base >100 active users
- Przygotowujesz major release (v2.0)
- Masz budżet czasu (20-30h)

**Co testować:**
- Critical user flows (add task, complete chore)
- Onboarding flow
- Navigation

### Production (Rok 3+):

**Dodaj Poziom 3: Integration Tests**

**Kiedy:**
- User base >1000 active users
- Revenue >$1000/month (można hiring QA)
- CloudKit sync bugs w production

**Co testować:**
- CloudKit CRUD
- Sharing scenarios
- Performance under load

---

## CI/CD Integration

**GitHub Actions już skonfigurowane!**

W `.github/workflows/ios-ci.yml`:
```yaml
- name: Run unit tests
  run: |
    xcodebuild test \
      -project FamilyTodo.xcodeproj \
      -scheme HousePulse \
      -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Co się dzieje:**
1. Push code do GitHub
2. GitHub Actions uruchamia testy automatycznie
3. Jeśli testy failują → build fails → nie możesz merge PR
4. Jeśli testy passują → ✅ safe to merge

**Test coverage reports:**
```yaml
- name: Generate coverage report
  run: |
    xcrun xccov view \
      --report DerivedData/Logs/Test/*.xcresult \
      --json > coverage.json
```

---

## Best Practices

### 1. **Test Naming Convention**
```swift
// Pattern: test_<unitUnderTest>_<scenario>_<expectedResult>
func test_task_moveToNext_updatesStatusToNext() { }
func test_task_cannotMoveToNext_whenWIPLimitReached_throwsError() { }
func test_recurringChore_weekly_schedulesNextMonday() { }
```

### 2. **Arrange-Act-Assert**
```swift
func test_example() {
    // Arrange - setup test data
    let task = Task(title: "Test")
    let member = Member(name: "User")

    // Act - perform action
    task.assignTo(member)

    // Assert - verify result
    XCTAssertEqual(task.assignee, member)
}
```

### 3. **One assertion per test (guideline)**
```swift
// PREFER:
func test_task_complete_setsStatus() {
    completeTask(task)
    XCTAssertEqual(task.status, "done")
}

func test_task_complete_setsCompletedAt() {
    completeTask(task)
    XCTAssertNotNil(task.completedAt)
}

// OVER:
func test_task_complete() {
    completeTask(task)
    XCTAssertEqual(task.status, "done") // Which one failed?
    XCTAssertNotNil(task.completedAt)
    XCTAssertEqual(task.progress, 100)
}
```

### 4. **Fast tests**
```swift
// SLOW (don't do in unit tests):
func testSlow() {
    Thread.sleep(forTimeInterval: 2.0) // ❌
    // Make network call // ❌
    // Write to disk // ❌
}

// FAST:
func testFast() {
    let result = pureFunction(input) // ✅ Pure function
    XCTAssertEqual(result, expected)
}
```

### 5. **Independent tests**
```swift
// BAD - tests depend on each other:
var sharedTask: Task? // ❌

func test_createTask() {
    sharedTask = Task(title: "Shared")
}

func test_completeTask() {
    completeTask(sharedTask!) // Depends on test_createTask!
}

// GOOD - each test is independent:
func test_createTask() {
    let task = Task(title: "Test") // ✅ Fresh data
    XCTAssertNotNil(task)
}

func test_completeTask() {
    let task = Task(title: "Test") // ✅ Fresh data
    completeTask(task)
    XCTAssertEqual(task.status, "done")
}
```

---

## Troubleshooting

### Issue: "Tests pass locally but fail on CI"

**Rozwiązanie:**
1. Sprawdź iOS version (Simulator vs CI)
2. Sprawdź timezone (CI może być UTC)
3. Sprawdź dates/times (use fixed dates in tests)
```swift
// BAD:
let today = Date() // Może być inny w CI!

// GOOD:
let today = DateComponents(year: 2026, month: 1, day: 10).date!
```

### Issue: "UI tests are flaky (sometimes pass, sometimes fail)"

**Rozwiązanie:**
1. Dodaj waits:
   ```swift
   XCTAssertTrue(element.waitForExistence(timeout: 5))
   ```
2. Disable animations:
   ```swift
   app.launchArguments += ["-UIAnimationDisabled", "YES"]
   ```
3. Use accessibility identifiers (nie text)

### Issue: "Tests run too slow"

**Rozwiązanie:**
1. Run tests in parallel:
   ```bash
   xcodebuild test -parallel-testing-enabled YES
   ```
2. Split into test plans (run different suites)
3. Use faster assertions (avoid sleep/waits)

---

## Podsumowanie

### Dla Family To-Do MVP:

**Rekomendacja:** Poziom 1 (Unit Tests Only)

**Co testować:**
- RecurringChore scheduling logic
- WIP limit enforcement
- Task state transitions
- Data validation

**Effort:**
- Setup: 1-2h
- Writing tests: 10-15h
- Maintenance: 30min/feature

**Tools:**
- XCTest (built-in, free)
- GitHub Actions (already configured)
- Code coverage (Xcode built-in)

**Target coverage:** 60-70%

**When to upgrade:**
- Level 2 (UI tests): >100 active users, major release
- Level 3 (Integration): >1000 active users, revenue >$1K/mo

**Benefits:**
- Catch bugs early
- Refactor with confidence
- Faster development (long-term)
- Better code quality

---

## Przydatne linki

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [UI Testing Guide](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html)
- [Test-Driven Development](https://www.objc.io/issues/15-testing/)
- [iOS Unit Testing by Example](https://qualitycoding.org/)
- [Testing in SwiftUI](https://www.swiftbysundell.com/articles/testing-swiftui-views/)

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
**Status:** Recommended for MVP (Level 1), expand post-MVP
