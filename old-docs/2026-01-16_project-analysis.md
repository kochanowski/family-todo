# Analiza projektu Family To-Do - Stan obecny

**Data:** 2026-01-16
**Typ:** Raport z analizy kodu i dokumentacji
**Wniosek:** Projekt w fazie inicjalnej - solidny fundament danych, brakuje warstwy aplikacyjnej

---

## 1. Podsumowanie wykonawcze

Projekt Family To-Do znajduje się w **stadium scaffold + modele danych (25-30% gotowości do MVP)**.

### Co działa:
✅ Kompletne 5 modeli danych (Household, Member, Task, Area, RecurringChore)
✅ Podstawowy CloudKitManager (CRUD dla pojedynczych rekordów)
✅ Konfiguracja CI/CD (GitHub Actions + TestFlight pipeline)
✅ Kompletna dokumentacja techniczna (ADR, wireframes, schema, strategia marketingowa)
✅ Kod buduje się na GitHubie

### Co nie działa / brakuje:
❌ Autentykacja (Sign in with Apple) - 0%
❌ Lokalny cache offline-first (SwiftData) - 0%
❌ UI aplikacji (widoki, ViewModele) - ~5%
❌ Synchronizacja CloudKit ↔ lokalna baza - 0%
❌ Logika biznesowa (WIP limit, recurring automation) - 0%
❌ Testy jednostkowe - 2% (placeholder)

**Estymacja do MVP:** 15-20 godzin developerskich

---

## 2. Analiza modeli danych (100% ✅)

Wszystkie 5 kluczowych encji MVP są **w pełni zaimplementowane** i zgodne ze specyfikacją:

### Task.swift - Status: Gotowy ✅
```swift
- Statusy Kanban: backlog | next | done
- Typy: oneOff | recurring
- Pola: title, assigneeId, areaId, dueDate, completedAt, notes
- Computed property: isOverdue
- Zgodność ze spec: 100%
```

### Household.swift - Status: Gotowy ✅
```swift
- Shared-first approach: zawiera members i areas
- Pola: id, name, ownerId, createdAt, updatedAt
- Zgodność ze spec: 100%
```

### Member.swift - Status: Gotowy ✅
```swift
- Role minimalne: owner | member (jak w spec)
- Pola: userId, displayName, role, joinedAt, isActive
- Zgodność ze spec: 100%
```

### Area.swift - Status: Gotowy ✅
```swift
- Domyślne areas: Kitchen, Bathroom, Living Room, Bedroom, Garden, Repairs
- Helper: Area.defaults(for:) - tworzy 6 domyślnych obszarów z ikonami
- Zgodność ze spec: 100%
```

### RecurringChore.swift - Status: Gotowy (częściowo) ⚠️
```swift
- RecurrenceType: daily | weekly | biweekly | monthly
- Logika: calculateNextScheduledDate() - działa poprawnie
- Brakuje: Integracja z automatycznym generowaniem Task po completion
- Zgodność ze spec: 80% (model OK, brak automatyzacji)
```

**Jakość kodu modeli:**
- Formatowanie: Zgodne z SwiftLint
- Naming: Konsystentne, jasne
- Thread-safety: Wszystkie struct (value types)
- Validation: ❌ Brak (np. pusty title, invalid dates)

---

## 3. CloudKitManager - Status: Szkielet (60% ⚠️)

**Lokalizacja:** `FamilyTodo/Managers/CloudKitManager.swift` (359 linii)

### Co jest zaimplementowane ✅:
```swift
✅ Actor pattern (thread-safe, modern Swift Concurrency)
✅ CKContainer + sharedDatabase setup
✅ CRUD dla pojedynczych rekordów:
   - saveHousehold(), fetchHousehold(id:), deleteHousehold(id:)
   - saveMember(), fetchMember(id:), deleteMember(id:)
   - saveTask(), fetchTask(id:), deleteTask(id:)
   - saveArea(), fetchArea(id:), deleteArea(id:)
   - saveRecurringChore(), fetchRecurringChore(id:), deleteRecurringChore(id:)
✅ Mapowanie Swift models ↔ CKRecord (kompletne)
✅ UUID-based references (CKRecord.Reference)
✅ Optional fields handling (dueDate, notes, assigneeId, etc.)
```

### Co brakuje ❌:
```swift
❌ Query operations (fetch all, filter, sort):
   - fetchAllTasks(for householdId:) -> [Task]
   - fetchTasksForAssignee(userId:, householdId:) -> [Task]
   - fetchTasksByStatus(status:, householdId:) -> [Task]
   - countTasksInNext(for assigneeId:, householdId:) -> Int
❌ Subscriptions (real-time sync):
   - subscribeToHouseholdChanges(householdId:) -> AsyncStream<CKRecord>
❌ Conflict resolution dla offline changes
❌ Error handling (tylko CloudKitManagerError.invalidRecord)
❌ Retry logic z exponential backoff
❌ Network state monitoring
```

**Ocena:** Manager jest użyteczny do zapisywania pojedynczych rekordów, ale **nie nadaje się do MVP** bez query operations. UI potrzebuje `fetchAllTasks()`, nie `fetchTask(id:)`.

---

## 4. UI i ViewModele - Status: Placeholder (5% ❌)

### ContentView.swift - Placeholder
```swift
Obecny kod:
- NavigationStack z tekstem "Family To-Do"
- "Project scaffold ready for CI."
- Brak: Data binding, task list, forms, navigation

Potrzebne:
- TaskListView z segmented control (Next/Backlog/Done)
- TaskRow component
- Task creation sheet
- Household selection flow
```

### Brakujące widoki (krytyczne dla MVP):
```
❌ HouseholdSelectionView - onboarding + wybór household
❌ TaskListView - main view z Kanban columns
❌ TaskDetailView - edycja/podgląd tasku
❌ TaskCreateView - formularz nowego tasku
❌ RecurringChoreListView - zarządzanie cyklami
❌ MemberManagementView - zapraszanie członków
❌ SettingsView - preferencje notyfikacji
```

### Brakujące ViewModele:
```
❌ HouseholdViewModel - state: current household, members, tasks
❌ TaskListViewModel - filtered tasks (Next/Backlog/Done)
❌ TaskDetailViewModel - single task editing
❌ CloudKitSyncViewModel - offline/online orchestration
```

**Ocena:** UI wymaga **całkowitej implementacji od zera**. Obecny ContentView to tylko compliance scaffold.

---

## 5. Autentykacja - Status: Nie zaimplementowana (0% ❌)

### Wymagane komponenty:
```
❌ Sign in with Apple integration
❌ AppleAuthManager - handle signin, token storage
❌ UserSession - current user state management
❌ CloudKitUserProvider - mapowanie Apple ID → CloudKit userID
❌ Keychain storage dla credentials
```

**Blokada:** Bez autentykacji app nie może działać. Jest to **krytyczny blocker dla MVP**.

---

## 6. Offline-first architecture - Status: Nie zaimplementowana (0% ❌)

Dokumentacja (ADR-002) opisuje strategię "offline-first with Last-Write-Wins", ale **zero kodu**:

### Co powinno być (zgodnie z ADR-002):
```
❌ SwiftData/CoreData local database
❌ Optimistic UI updates (write local → sync in background)
❌ Background sync queue
❌ Conflict resolution (Last-Write-Wins)
❌ Retry logic z exponential backoff
❌ Sync status indicators (online/offline/syncing)
```

**Blokada:** Specyfikacja mówi "offline-first", ale cały CloudKitManager działa tylko online. Brak local cache = brak offline mode.

---

## 7. Logika biznesowa - Status: Częściowa (40% ⚠️)

### Co działa ✅:
- Task.isOverdue - oblicza czy task jest zaległy
- RecurringChore.calculateNextScheduledDate() - oblicza następny termin
- Area.defaults() - tworzy 6 domyślnych obszarów

### Co brakuje ❌:
```
❌ WIP Limit enforcement (max 3 tasks w "Next")
   - Brak walidacji przy dodawaniu tasku do "Next"
   - Brak computed property countTasksInNext(for userId)

❌ Recurring chore automation:
   - Brak mechanizmu tworzącego Task po completion
   - Brak scheduled background job sprawdzającego nextScheduledDate

❌ Gentle celebrations:
   - Opisane w CLAUDE.md, zero kodu
   - Brak soft feedback systemu

❌ Notification policy:
   - Daily digest - nie zaimplementowany
   - Deadline alerts - nie zaimplementowane
   - CloudKit silent push - nie skonfigurowane
```

---

## 8. Testy - Status: Placeholder (2% ❌)

**FamilyTodoTests/FamilyTodoTests.swift:**
```swift
func testExample() throws {
    XCTAssertTrue(true) // Placeholder test
}
```

**Brakuje:**
- Unit tests dla modeli (Task, RecurringChore logic)
- Unit tests dla CloudKitManager
- Integration tests dla sync logic
- UI tests dla kritycznych flow

**CI/CD:** GitHub Actions skonfigurowane, ale testy są puste - pipeline przejdzie nawet jeśli kod się sypie.

---

## 9. Dokumentacja - Status: Kompletna (95% ✅)

### Technical Documentation:
✅ ADR-001: CloudKit Backend Selection
✅ ADR-002: Error Handling & Offline-First
✅ CloudKit Schema (5 entities, Swift models, queries)
✅ Core Screens Wireframes (ASCII art + UX decisions)
✅ GitHub Actions Setup Guide
✅ TestFlight Setup Guide

### Product Documentation:
✅ instructions.md - Product North Star, domain model
✅ CLAUDE.md - Developer guidance, tech stack
✅ Analytics Strategy
✅ Monetization Strategy (Freemium model, $4.99/mo)
✅ Localization Guide (6 languages)
✅ Marketing Strategy (Product Hunt, Apple Search Ads)
✅ Testing Strategy
✅ Getting Started Checklist

**Ocena:** Dokumentacja jest **bardziej zaawansowana niż kod**. Wszystkie decyzje architektoniczne są udokumentowane, ale nie zaimplementowane.

---

## 10. Struktura projektu

### Obecna struktura:
```
FamilyTodo/
├── Models/              ✅ 5 plików - kompletne
│   ├── Household.swift
│   ├── Member.swift
│   ├── Task.swift
│   ├── Area.swift
│   └── RecurringChore.swift
├── Managers/            ⚠️ 1 plik - częściowy
│   └── CloudKitManager.swift
├── FamilyTodoApp.swift  ❌ Placeholder
├── ContentView.swift    ❌ Placeholder
└── LaunchScreen.storyboard

FamilyTodoTests/         ❌ Tylko placeholder test

docs/                    ✅ 17 plików - kompletne
.github/workflows/       ✅ CI/CD skonfigurowane
```

### Brakująca struktura (powinna być):
```
FamilyTodo/
├── Views/               ❌ Folder nie istnieje
├── ViewModels/          ❌ Folder nie istnieje
├── Services/            ❌ Folder nie istnieje
│   ├── AuthService.swift
│   ├── SyncService.swift
│   └── NotificationService.swift
├── Utilities/           ❌ Folder nie istnieje
└── Extensions/          ❌ Folder nie istnieje
```

---

## 11. Konfiguracja infrastruktury

### GitHub Actions CI/CD ✅:
```yaml
Jobs:
1. build-and-test ✅ - kompilacja + testy (nawet jeśli puste)
2. swiftlint ✅ - formatowanie kodu
3. deploy-testflight ⚠️ - wymaga secrets (nie skonfigurowane)
4. notify-failure ✅ - notyfikacje

Status: Działa dla build, ale TestFlight wymaga dodania secrets
```

### Pre-commit hooks ✅:
```yaml
Hooki:
- swiftlint (formatowanie)
- swift-format (code style)
- pytest (testy - placeholder)

Status: Skonfigurowane, działają
```

### Bundle Identifier:
```
com.example.familytodo (placeholder)
com.example.familytodo.tests (testy)

⚠️ TODO: Zmienić na production bundle ID przed TestFlight
```

---

## 12. Luki w implementacji - Priorytety

### KRYTYCZNE (blokerowe dla MVP):
1. ❌ **Sign in with Apple** - bez tego app nie wystartuje
2. ❌ **SwiftData offline cache** - spec mówi "offline-first"
3. ❌ **CloudKit queries** - brak fetchAll operations
4. ❌ **UI Views** - ContentView to placeholder
5. ❌ **Household invitation flow** - brak UI do dodawania członków
6. ❌ **Task CRUD views** - Create/Edit/Delete

### WYSOKIE (potrzebne do MVP):
7. ❌ **WIP limit enforcement** - max 3 tasks w "Next"
8. ❌ **Recurring chore automation** - auto-create task
9. ❌ **Basic notifications** - daily digest, deadlines
10. ❌ **Unit tests** - przynajmniej dla modeli

### ŚREDNIE (post-MVP):
11. ❌ Error handling UI
12. ❌ Conflict resolution dla offline changes
13. ❌ Activity log / change history
14. ❌ Settings screen

---

## 13. Zgodność z założeniami produktowymi

### Zgodne ✅:
- ✅ Shared-first: Model Household zawiera members od początku
- ✅ Kanban 3-statusowy: backlog | next | done
- ✅ Recurring chores: Model + calculate logic
- ✅ Simplicity: Modele mają minimalne pola
- ✅ Areas: Domyślne 6 obszarów (Kitchen, Bathroom, etc.)

### Niezgodne / Brakujące ❌:
- ❌ **WIP Limit** (max 3 w "Next"): Zero walidacji
- ❌ **No micromanagement**: Brak kodu, nie można ocenić
- ❌ **Gentle nudges**: Notifications nie zaimplementowane
- ❌ **Gentle celebrations**: Zero kodu
- ❌ **One source of truth**: Brak offline cache = brak prawdy offline

---

## 14. Estymacja do MVP

| Komponent | Czas (h) | Priorytet |
|-----------|----------|-----------|
| Sign in with Apple | 2-3h | Krytyczny |
| SwiftData setup + models | 3-4h | Krytyczny |
| CloudKit queries + sync | 3-4h | Krytyczny |
| TaskListView (main UI) | 2-3h | Krytyczny |
| TaskDetailView (CRUD) | 2-3h | Krytyczny |
| HouseholdSelectionView | 1-2h | Krytyczny |
| WIP limit logic | 1h | Wysoki |
| Recurring automation | 2h | Wysoki |
| Basic notifications | 1-2h | Wysoki |
| Unit tests (critical paths) | 2-3h | Wysoki |

**RAZEM: 15-20 godzin** (przy normalnym tempie developerskim)

---

## 15. Następne kroki rekomendowane

### Faza 1: Fundament (2-3 sesje)
1. Dodać Sign in with Apple
2. Wdrożyć SwiftData offline cache
3. Rozszerzyć CloudKitManager o query operations
4. Zbudować dependency injection layer (Services)

### Faza 2: Core UI (3-4 sesje)
1. HouseholdSelectionView (onboarding)
2. TaskListView (main kanban view)
3. TaskDetailView (edit/view)
4. Synchronizacja CloudKit ↔ SwiftData

### Faza 3: Features (2-3 sesje)
1. Recurring chore automation
2. WIP limit validation
3. Basic notifications
4. Unit tests

### Faza 4: Polish (1-2 sesje)
1. Settings screen
2. Error handling UI
3. Offline mode indicator
4. TestFlight submission

---

## 16. Mocne strony projektu

✅ **Modele danych są solidne** - zgodne ze spec, kompletne
✅ **Dokumentacja jest wzorowa** - ADR, wireframes, strategie
✅ **CI/CD pipeline gotowy** - GitHub Actions + TestFlight
✅ **CloudKitManager używa modern Swift** - actor pattern, async/await
✅ **RecurringChore logic jest przemyślana** - calculateNextScheduledDate() działa
✅ **Formatowanie skonfigurowane** - SwiftLint + pre-commit hooks

---

## 17. Słabe strony projektu

❌ **Brak warstwy aplikacyjnej** - ViewModels, Services nie istnieją
❌ **UI to placeholder** - wymaga rebuildu od zera
❌ **Offline-first nie zaimplementowany** - mimo że to core feature
❌ **Autentykacja brakuje całkowicie** - critical blocker
❌ **Testy są puste** - CI przechodzi nawet gdy kod się sypie
❌ **CloudKitManager niepełny** - brak queries, subscriptions, error handling

---

## Podsumowanie końcowe

**Projekt Family To-Do jest w fazie "data models + scaffold".**

Masz:
- ✅ 100% modeli danych MVP
- ✅ 95% dokumentacji technicznej i produktowej
- ✅ 60% CloudKitManager (CRUD pojedynczych rekordów)
- ✅ CI/CD pipeline gotowy

Brakuje:
- ❌ Autentykacji (0%)
- ❌ Offline cache (0%)
- ❌ UI aplikacji (5%)
- ❌ Logiki biznesowej (40%)
- ❌ Testów (2%)

**Można zbudować na GitHubie, ale aplikacja nie robi nic poza wyświetleniem tekstu "Family To-Do".**

Do MVP potrzeba **15-20 godzin pracy** nad:
1. Autentykacją
2. SwiftData + sync
3. UI (TaskList, TaskDetail, Household)
4. Query operations w CloudKitManager
5. Podstawowymi testami

**Rekomendacja:** Zacznij od Sign in with Apple → SwiftData → TaskListView → CloudKit sync. To najprostsza ścieżka do działającego MVP.
