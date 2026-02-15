# HousePulse — Full Implementation Roadmap

## Stan obecny (po research 2026-02-15)

### ✅ Co działa
| Feature | Stan | Pliki |
|---|---|---|
| **Shopping List** | ✅ pełny flow | `ShoppingListView.swift`, `ShoppingListStore.swift` |
| Rapid entry (typ i enter) | ✅ | `RapidEntryTextField` |
| Buy/unbuy (checkbox) | ✅ | `ShoppingListStore.toggleBought()` |
| Recently Purchased + restock | ✅ | `RestockSheet`, swipe delete, Clear All |
| Shopping suggestions | ✅ | `suggestedItems`, normalized dedupe |
| **Tasks** — basic CRUD | ✅ | `TasksView.swift`, `TaskStore.swift` |
| Task create (title only) | ✅ | Add sheet z TextFieldem |
| Task complete/uncomplete | ✅ | `moveTask(.done)` + animation |
| WIP limit (3 per assignee) | ✅ | `canMoveToNext()` |
| Completed section | ✅ | `doneTasks` sorted by completedAt |
| **Backlog** — categories + items | ✅ | `BacklogView`, `BacklogStore` |
| Category CRUD | ✅ | add/delete category |
| Items CRUD | ✅ | add/delete items w kategoriach |
| **More — hub** | ✅ (partial) | `MoreView.swift` |
| Profile card (avatar + name) | ✅ | `ProfileCard` |
| Appearance (Light/Dark/System) | ✅ | `SettingsView` + `ThemeStore` |
| Members management | ✅ | `MemberManagementView` |
| Share via CloudKit (CKShare) | ✅ bazowy | `ShareInviteView` |
| **Auth** — Sign in with Apple | ✅ | `AuthenticationService` |
| Guest mode (localOnly) | ✅ | `OnboardingState`, seed data |
| **Sync** — CloudKit + SwiftData | ✅ | `CloudKitManager`, cached models |
| **Notifications** — task reminders | ✅ | `NotificationService` |
| Daily digest | ✅ | `scheduleDailyDigest()` |
| **Onboarding** | ✅ | Carousel → Create household → Sync selection |
| **Tab bar** — floating glass (iOS 26) | ✅ (fixing) | `FloatingTabBar.swift` |
| **Themes** — 4 presets | ✅ | Journal, Pastel, Soft, Night |

### 🔴 Co NIE działa / jest stubem
| Feature | Stan | Plik |
|---|---|---|
| Task detail/edit view | ❌ stub "Coming Soon" | `LegacyStubs.swift:TaskDetailView` |
| Task assignee picker | ❌ brak UI | `Task.assigneeId` istnieje w modelu |
| Task due date picker | ❌ brak UI | `Task.dueDate` istnieje w modelu |
| Task notes | ❌ brak UI | `Task.notes` istnieje w modelu |
| Task areas (pokoje) | ❌ brak UI | `Task.areaId`, `Area` model exists |
| Recurring chores | ❌ stub "Coming Soon" | `RepetitiveTasksView`, `RecurringChore` model |
| Backlog → Task promotion | ❌ brak flow | Backlog items nie mają linku do Tasks |
| Categories management (More) | ❌ local-only stub | `CategoriesManagementView` nie wired do BacklogStore |
| Sign Out action | ❌ empty closure | `SettingsView` line 346 |
| Notifications settings UI | ❌ stub store | `NotificationSettingsStore` |
| Household rename | ❌ brak UI | `Household.name` is `var` |
| Areas management | ❌ stub store | `AreaStore` empty |
| Multi-avatar w profilu | ❌ TODO komentarz | `ProfileCard` line 116 |

---

## 🗺️ ROADMAP

### Phase 1: Core Task Experience (P0) 🎯
> Cel: Tasks stają się w pełni użyteczne jako codzienny task manager

#### 1.1 Task Detail / Edit Sheet
- **Nowy plik**: `TaskDetailSheet.swift`
- **Pola do edycji**:
  - Tytuł (TextEditor)
  - Status picker (Next / Backlog / Done)
  - Assignee picker (lista członków household)
  - Due date (DatePicker, opcjonalny)
  - Notes (TextEditor, opcjonalne)
  - Area (picker, opcjonalny — jeśli Areas zaimplementowane)
- **UX**: Sheet `.presentationDetents([.medium, .large])`, dismiss on save
- **Trigger**: Tap na task row → otwiera sheet
- **Store changes**: `TaskStore.updateTask()` już istnieje, wystarczy podpiąć UI

#### 1.2 Task Assignee Picker
- **Wymaga**: `MemberStore` — already loads members
- **UI**: Horizontal scroll z avatarami + "Unassigned" option
- **W Task row**: Mały avatar obok tytułu (jak w Apple Reminders)
- **Filter**: opcjonalny "My Tasks" / "All Tasks" toggle w header

#### 1.3 Task Due Date
- **UI**: DatePicker inline w Task Detail Sheet
- **W Task row**: Mały date badge (np. "Mon", "Tomorrow", czerwony jeśli overdue)
- **Sorting**: Overdue tasks → at top z czerwonym badge
- **`Task.isOverdue`**: Już zaimplementowane w modelu!

#### 1.4 Backlog → Task Promotion
- **UI**: Swipe action na backlog item → "Promote to Task"
- **Flow**: 
  1. Swipe → pojawia się confirmation
  2. Creates task z tytułem backlog item + status `.next`
  3. Opcjonalnie: otwiera Task Detail Sheet do uzupełnienia
  4. Usuwa item z Backlog
- **Store**: nowa metoda `BacklogStore.promoteToTask()` → wywołuje `TaskStore.createTask()`

---

### Phase 2: Household & Sharing (P0) 👨‍👩‍👧‍👦
> Cel: Pełny multi-user flow — zaproś rodzinę, widz kto co robi

#### 2.1 Invitation Flow (ulepszyć istniejący)
- **Obecny stan**: `ShareInviteView` używa `UICloudSharingController` — DZIAŁA
- **Do poprawienia**:
  - Po zaakceptowaniu zaproszenia: automatyczne dołączenie nowego Member do household
  - `HouseholdStore.joinViaShare()` — istnieje, ale wymaga testowania
  - Feedback UI po wysłaniu zaproszenia (Toast/Sheet)
  - Deep link handling (`cloudkit-icloud.com` URLs)

#### 2.2 Household Management
- **Ekran**: Nowy `HouseholdEditView.swift`
  - Zmiana nazwy household
  - Lista członków (link do `MemberManagementView`)
  - "Leave Household" dla non-owner members
  - "Delete Household" dla owner (z potwierdzeniem)
- **Trigger**: Z `ProfileView` → NavigationLink
- **Store**: Dodać `HouseholdStore.renameHousehold()`, `leaveHousehold()`, `deleteHousehold()`

#### 2.3 Multi-Household Support (opcjonalne)
- **Cel**: User może być członkiem wielu households (np. dom + biuro)
- **UI**: Household picker w ProfileView lub jako dropdown w headerze
- **Store**: `HouseholdStore.households: [Household]` + `switchHousehold()`
- **⚠️ Complexity**: Wymaga zmian w CloudKit queries — scopować do MVP first

---

### Phase 3: Recurring Chores Engine (P1) 🔄
> Cel: Automatyczne generowanie zadań cyklicznych

#### 3.1 Recurring Chore CRUD
- **Nowy ekran**: Przebudowa `RepetitiveTasksView` (obecnie "Coming Soon")
- **Pola**:
  - Tytuł
  - Recurrence: Daily / Weekly (+ day picker) / Monthly (+ day of month) / Custom interval
  - Default assignee(s) — z rotation option
  - Area (opcjonalne)
  - Notes
  - Is Active toggle
- **Store**: Nowy `RecurringChoreStore.swift`
  - CRUD operations z CloudKit sync
  - Model `RecurringChore` już istnieje w `LegacyStubs.swift` — przenieść do własnego pliku

#### 3.2 Task Generation Engine
- **Service**: Nowy `ChoreScheduler.swift`
- **Logic**:
  1. Na app launch → sprawdź `nextScheduledDate` każdego aktywnego chore
  2. Jeśli `nextScheduledDate <= today` → wygeneruj Task z tytułem, assignee, area
  3. Update `lastGeneratedDate` i oblicz nowy `nextScheduledDate`
  4. Rotation: jeśli `rotationEnabled`, cyklicznie przełączaj assignee
- **Integration**: Wywoływany z `FamilyTodoApp.swift` w `.task {}`
- **Background**: Opcjonalnie `BGTaskScheduler` dla generation o świcie

#### 3.3 Chore → Task Link
- `Task.recurringChoreId` — **już istnieje** w modelu!
- W Task row: mały `repeat` icon jeśli wygenerowany z chore
- W Task Detail: link do parent Recurring Chore

---

### Phase 4: Areas / Rooms (P1) 🏠
> Cel: Organizacja zadań wg pokojów/stref

#### 4.1 Areas CRUD
- **Nowy store**: Przebudowa `AreaStore` (obecny stub)
- **Nowy ekran**: `AreasManagementView.swift`
  - Lista areas z ikonkami i kolorami
  - Add / Edit / Delete / Reorder
  - Default areas: Kitchen, Living Room, Bathroom, Bedroom, Garden, Other (już w `Area.defaults`)
- **Trigger**: Z MoreView → nowy NavigationLink "Rooms / Areas"

#### 4.2 Area Integration
- **Task Detail**: Area picker (lista z ikonkami)
- **Tasks View**: Opcjonalny grouping "By Area" toggle
- **Recurring Chores**: Default area

---

### Phase 5: Settings & Polish (P1) ⚙️
> Cel: Kompletne ustawienia, sign out, notification preferences

#### 5.1 Settings — Full Implementation
- **Appearance** ✅ — już działa
- **Celebrations** ✅ — toggle działa
- **Suggestions** ✅ — toggle działa
- **Dodać**:
  - **Notifications section**:
    - Task reminders toggle
    - Daily digest toggle
    - Digest time picker
    - Sound toggle
  - **Data section**:
    - Sync mode indicator (Cloud / Local Only)
    - "Refresh from Cloud" force sync button
    - Version info
  - **Sign Out**: Podpiąć `AuthenticationService.signOut()` + clear session

#### 5.2 Categories Management — Wire to BacklogStore
- Obecny `CategoriesManagementView` jest local-only (nie persystuje!)
- **Fix**: Przekazać `BacklogStore` do widoku, użyć `addCategory()` / `deleteCategory()`

#### 5.3 Profile View — Enhancement
- Avatar customization (initials color, opcjonalnie zdjęcie)
- Multi-avatar stack dla household members
- Display name edit (already in `MemberManagementView`)

---

### Phase 6: Quality of Life Features (P2) ✨
> Cel: Features które wow'ują użytkownika

#### 6.1 🔍 Quick Search
- **UI**: Search bar / Spotlight-style overlay
- **Scope**: Tasks + Shopping Items + Backlog Items
- **Trigger**: Pull down in any list, lub search icon w headerze
- **Dlaczego**: Przy 50+ items finding stuff jest crucial

#### 6.2 📊 Household Dashboard / Stats
- **Ekran**: Nowy tab lub sekcja w More
- **Data**:
  - Tasks completed this week per member (bar chart)
  - Shopping items bought this week
  - Streak: "X days in a row with all tasks done"
  - Most active member badge
- **Dlaczego**: Gamification zachęca rodzinę do współpracy (competition + recognition)

#### 6.3 📋 Drag & Drop Reorder
- **Shopping list**: Reorder items w "To Buy"
- **Backlog**: Reorder categories i items w kategorii
- **Tasks**: Reorder tasks w Next
- **SwiftUI**: `.draggable()` + `.dropDestination()` (iOS 16+)

#### 6.4 🎨 Theme Store — Full Palette Picker
- 4 presets: Journal, Pastel, Soft, Night → ✅
- **Dodać**: Color customization per card type
- **Preview**: Live preview w settings

#### 6.5 📱 Widget Kit
- **Small widget**: "Next 3 tasks" lub "Shopping list today"
- **Medium widget**: Tasks by assignee z avatarami
- **Lock screen widget**: Overdue tasks count
- **Dlaczego**: Widgets = daily engagement without opening app

#### 6.6 🔔 Smart Notifications
- **"Leaving home" reminder**: geofence trigger → "Don't forget: Milk, Bread" (shopping items)
- **"Morning brief"**: Daily digest z personalizowaną treścią
- **"This looks done"**: Jeśli task jest w Next >3 dni, push "Still working on this?"
- **⚠️**: Wymaga Location permissions — opcjonalny feature

#### 6.7 ↔️ Siri & Shortcuts Integration
- "Hey Siri, add milk to shopping list"
- "Hey Siri, what are my tasks for today?"
- `AppIntents` framework (iOS 16+)
- **Dlaczego**: Hands-free w kuchni = killer feature dla shopping list

#### 6.8 🎉 Celebrations & Micro-Animations
- `celebrationsEnabled` toggle ✅ — ale brak actual celebrations!
- **Dodać**:
  - Confetti/particles kiedy all tasks done
  - Streak badge animation
  - "Well done!" message po completion
  - Scale + haptic na checkbox tap

---

## Priorytyzacja (sugerowany order implementacji)

```
Sprint 1 (P0 — musi być dla MVP):
├── 1.1 Task Detail / Edit Sheet
├── 1.2 Task Assignee Picker
├── 1.3 Task Due Date + overdue badge
├── 5.1 Sign Out (podpiąć istniejący AuthService)
└── 5.2 Categories Management ← wire to BacklogStore

Sprint 2 (P0 — multi-user):
├── 2.1 Invitation flow testing + feedback UI
├── 2.2 Household management (rename, leave, delete)
├── 1.4 Backlog → Task promotion
└── 5.1 Notifications settings UI

Sprint 3 (P1 — recurring):
├── 3.1 Recurring Chore CRUD
├── 3.2 Task Generation Engine
├── 3.3 Chore → Task link UI
└── 4.1-4.2 Areas / Rooms

Sprint 4 (P2 — delight):
├── 6.1 Quick Search
├── 6.5 WidgetKit
├── 6.7 Siri Shortcuts
├── 6.8 Celebrations animations
└── 6.2 Household Dashboard / Stats
```

---

## Szacunkowy effort (w roboczodniach, solo dev)

| Phase | Effort | Dependencies |
|---|---|---|
| Phase 1: Core Tasks | 3-4 dni | Brak blokerów |
| Phase 2: Household | 2-3 dni | CloudKit testing |
| Phase 3: Recurring | 3-5 dni | Phase 1 |
| Phase 4: Areas | 1-2 dni | Brak blokerów |
| Phase 5: Settings | 1-2 dni | Brak blokerów |
| Phase 6: QoL | 5-8 dni | Phases 1-4 |

**MVP (Phases 1-2):** ~1.5 tygodnia
**Full v1.0 (Phases 1-5):** ~3 tygodnie
**Premium (wszystko):** ~5-6 tygodni
