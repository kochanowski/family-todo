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

---

## 🔬 Design Research (2026-02-15 22:56)

### DR-1: Sign Out zachodzi za tab bar (brak glass effect)

**Problem**: Na screenie widać, że przycisk "Sign Out" jest renderowany za floating tab barem. Tab bar jest nałożony jako `.overlay()` w `ContentView.swift`, więc z-ordering jest naturalnie wyżej niż content wewnątrz tabów.

**Przyczyna**: `SettingsView` jest wewnątrz `NavigationStack` w `MoreView`, ale Sign Out jest na samym dole `List` — gdy lista jest dłuższa niż ekran, Sign Out ląduje w strefie przykrytej przez FloatingTabBar. To NIE jest problem glass effect — to problem z bottom inset.

**Rozwiązanie (rekomendowane)**:
1. Dodać `listBottomInset` do `SettingsView` (tak jak w `ShoppingListView` i `TasksView`) — `MoreView` i jej sub-views nie używają `AppChromeMetrics.contentBottomInset()`:
   ```swift
   // W SettingsView:
   List { ... }
       .safeAreaInset(edge: .bottom) {
           Spacer().frame(height: AppChromeMetrics.contentBottomInset(tabBarHeight: tabBarHeight))
       }
   ```
2. Alternatywnie: Przenieść Sign Out z dołu List na sticky button poniżej.

**Effort**: ~15 min, zmiana w jednym pliku (`MoreView.swift`).

---

### DR-2: Backlog → Tasks — architektura flow

**Problem**: Aktualnie istnieją **dwa niezależne sposoby** dodawania tasków:
1. **Tasks tab** → `+ Add task` → sheet z polem tytułu → `createTask(status: .next)` — task trafia od razu do NEXT
2. **Backlog tab** → swipe left na item → "Promote" → `promoteItemToTask()` → task trafia do NEXT (lub .backlog jeśli WIP=3)

To jest niespójne z oryginalnym pomysłem **"Backlog = worek, Tasks = sprint board"**.

**Analiza obecnego stanu kodu**:
- `TasksView` showuje **3 sekcje**: NEXT, BACKLOG, COMPLETED
- Ale `+ Add task` tworzy **bezpośrednio** z `.next` status
- `BacklogStore.promoteItemToTask()` — **już istnieje** i działa, w tym WIP fallback
- `TaskStore.createTaskFromBacklogItem()` — **istnieje** jako helpers
- W TasksView linia 82-95: jest sekcja "BACKLOG" z `store.backlogTasks` — czyli Tasks tab już wyświetla taski ze statusem `.backlog`!

**Opcje rozwiązania**:

#### Opcja A: "Pure Scrum" — Backlog to jedyny punkt wejścia ⭐ (rekomendowana)
- **Usunąć** `+ Add task` z Tasks taba
- Tasks tab = **read-only sprint board** (max 3 w NEXT per osobę)
- Dodawanie tasków **wyłącznie** przez Backlog → Promote
- W Tasks: swipe right na backlog task → "Move to Next" (promote wewnątrz Tasks)
- UX: naturalny flow "pomyśl → zapisz w backlogu → wybierz co robisz dziś"

**Plusy**: Czysty mental model, wymusza priorytetyzację, spójna filozofia "nie nagging"
**Minusy**: Więcej kroków żeby dodać task na "teraz" (2 taby zamiast 1)

#### Opcja B: "Quick Add" — Backlog jako default, Tasks jako skrót
- `+ Add task` w Tasks tworzy task z domyślnym statusem `.backlog` (nie `.next`!)
- Żeby przenieść do NEXT: tap na task → w Detail Sheet zmień status, LUB swipe → "Start"
- Backlog tab nadal działa jak worek z kategoriami
- Tasks tab `+ Add task` = szybkie dodanie do "unsorted backlog" (bez kategorii)

**Plusy**: Nadal wymusza WIP, ale szybszy flow
**Minusy**: "Quick add" vs Backlog add to conceptually to samo — dlaczego dwa UI?

#### Opcja C: "Hybrid" — Inteligentny `+ Add task`
- `+ Add task` w Tasks — jeśli WIP<3: dodaj do NEXT. Jeśli WIP=3: dodaj do BACKLOG z toast "Added to Backlog — you have 3 active tasks"
- W Backlog: Promote dalej działa
- **Backlog categories** = organizacja, **Tasks** = flat lista z segregacją

**Plusy**: Zero friction, zachowuje WIP
**Minusy**: Ukrywa flow od użytkownika — "dlaczego mój task jest w Backlog?"

#### 📌 Rekomendacja: **Opcja A** (Pure Scrum)
Spójne z filozofią "gentle, not nagging" i z oryginalnym pomysłem. User:
1. Wpisuje pomysły do Backlog (szybko, bez presji)
2. Otwiera Tasks → widzi swoje 3 aktywne
3. Kończy task → otwiera Backlog → promuje kolejny do NEXT
4. W Tasks: sekcja "BACKLOG" pokazuje taski ze statusem backlog, z opcją swipe do "NEXT"

**Implementacja**: Usunąć `addPillButton` + `addTaskSheet` z `TasksView`, dodać swipe "Move to Next" na tasks w sekcji BACKLOG.

---

### DR-3: WIP warning — UX dla >3 tasków

**Problem**: Aktualnie `addTask()` w `TasksView` (linia 277-281) sprawdza WIP i jeśli limit osiągnięty:
- Odtwarza haptic `.warning`
- **Nic nie pokazuje** — user nie wie dlaczego task się nie dodał

**Obecny flow bannera**: Jest `focusRuleBanner` (linia 59) — niebieski pasek "Focus on max 3 active tasks" — ale wyświetlany **zawsze**, nie jako warning.

**Opcje rozwiązania**:

#### Opcja A: Animated banner z CTA ⭐ (rekomendowana)
Kiedy user próbuje dodać >3:
1. `focusRuleBanner` zmienia kolor na `.orange` / `.red`
2. Tekst zmienia się na: "You have 3 active tasks. Complete one or move it to Done to add more."
3. Banner animuje się (pulse/shake) + haptic
4. Banner wraca do normalnego koloru po 3s
5. Opcjonalny CTA: "View your tasks" (scroll do NEXT)

#### Opcja B: Alert z wyjaśnieniem
- Standard `.alert()` z teksem "WIP Limit Reached" + opcja "View Backlog" / "OK"
- Prosty, ale przerywający flow

#### Opcja C: Toast (overlay)
- Slide-in toast na dole: "🛑 Max 3 active tasks. Complete something first."
- Auto-dismiss po 3s
- Nieinwazyjny

#### 📌 Rekomendacja:
- Jeśli **Opcja A z DR-2** (Pure Scrum): WIP warning nie jest potrzebny w "Add" flow — bo Add nie istnieje w Tasks. Warning jest potrzebny tylko przy **Promote** → użyj Toast (Opcja C): "3 active tasks — complete one before promoting."
- Jeśli **Opcja B/C z DR-2**: użyj **Opcja A** (animated banner) — bo banner "Focus on 3" już istnieje, wystarczy animować zmianę.

---

### DR-4: Rooms / Areas — usunięcie

**Problem**: Areas/Rooms zostały usunięte konceptualnie, ale kod nadal zawiera:
- `Area` model w `LegacyStubs.swift` (linie 25-60) — z `defaults` (Kitchen, Living Room...)
- `AreaStore` stub w `LegacyStubs.swift` (linia ~120) — empty CRUD
- `AreasManagementView` w `MoreView.swift` (linie 550-615)
- NavigationLink "Rooms / Areas" w `MoreView`
- `Task.areaId` — optional field w Task modelu
- `RecurringChore.areaId` — optional field

**Analiza**: Zgadzam się z usunięciem. Kategorie w Backlogu spełniają tę rolę organizacyjną (Dom, Zakupy duże, Ogród itp.). Areas jako osobny koncept dodają niepotrzebną warstwę abstrakcji.

**Rekomendacja**: ✅ **Usunąć**, ale zachować migration safety:
1. **Usunąć z UI**: `AreasManagementView`, NavigationLink w MoreView
2. **Usunąć store**: `AreaStore` z `LegacyStubs.swift`
3. **Usunąć model**: `Area` z `LegacyStubs.swift`
4. **Zachować (na razie)**: `Task.areaId` i `RecurringChore.areaId` jako optional nil — nie łamie nic, a unika problemów z migration
5. **Usunąć z roadmapu**: Phase 4 (Areas) → zastąpić bardziej przydatną fazą (np. "Backlog UX Polish")
6. **Wyczyścić referencje**: `CachedArea` model, CloudKit `Area` record type

**Effort**: ~30 min, kilka plików.

---

### DR-5: Repetitive Tasks — jak się dodają?

**Problem**: `RepetitiveTasksView` jest w stanie **half-implemented**:
- ✅ Lista aktywnych chores z toggle Active/Inactive
- ✅ Swipe delete
- ✅ Add form: tytuł + Picker(frequency)
- ✅ `RecurringChoreStore.addChore()` + `loadChores()` — **działają!**
- ❌ `custom` frequency → Picker pokazuje "Custom" ale **brak odznaczania co to custom oznacza** (brak `recurrenceInterval` UI)
- ❌ Brak day picker dla Weekly (który dzień tygodnia?)
- ❌ Brak day-of-month picker dla Monthly
- ❌ **Brak `ChoreScheduler`** — chores istnieją, ale **nie generują tasków**!

**Jak powinny się dodawać? Rekomendacje**:

#### Flow dodawania Recurring Task:
1. User otwiera More → Repetitive Tasks
2. Wypełnia tytuł + frequency (daily/weekly/monthly/custom)
3. Jeśli weekly: dodatkowy picker "Which day?" (Mon-Sun)
4. Jeśli monthly: picker "Which day of month?" (1-28)
5. Jeśli custom: picker "Every X days" (1-365)
6. Opcjonalny default assignee
7. Save → chore jest aktywny

#### Gdzie trafiają wygenerowane taski? Rekomendacja:
**Opcja A** ⭐: Do **Backlog** (jako task ze statusem `.backlog`) z tagiem/ikoną 🔄 wskazującym że to recurring. User musi ręcznie promować do NEXT.
- ✅ Spójne z Pure Scrum (DR-2)
- ✅ Nie zaśmieca NEXT automatycznie
- ✅ Daje control — user decyduje kiedy tym się zająć

**Opcja B**: Bezpośrednio do **NEXT** (jeśli WIP<3, inaczej do BACKLOG)
- ❌ Ryzyko: "rano otwierasz app i masz 5 tasków wygenerowanych automatycznie" = stresujące

**Implementacja**: Nowy `ChoreScheduler` service:
- Wywoływany na app launch w `.task {}`
- Sprawdza `nextScheduledDate` aktywnych chores
- Generuje taski z `Task.recurringChoreId` ustawionym
- W TaskRow: mała ikonka 🔄 jeśli `recurringChoreId != nil`

#### Custom frequency fix:
Zamienić prosty `Picker` na rozbudowany UI:
- Daily: brak dodatkowych opcji
- Weekly: multi-select days (Mon-Sun buttons)
- Monthly: day picker (1-28)
- Custom: `Stepper("Every X days")` → zamiast napisu "Custom" w Picker

---

### DR-6: Add Item UX — unifikacja wzorca

**Problem**: 3 różne patterns dodawania elementów:

| Screen | Pattern | Trigger | UX |
|--------|---------|---------|-----|
| Shopping | Floating pill `+ Add item` → **rapid entry inline** | Pill → row z TextField wewnątrz listy | ✅ Szybki, chain adding |
| Tasks | Floating pill `+ Add task` → **modal sheet** | Pill → NavigationStack sheet | ⚠️ Cięższy, bardziej formalny |
| Backlog | **Inline `+ Add item`** wewnątrz CategoryCard | Button w card → TextField w card | ✅ Kontekstowy, ale inny pattern |

**Opcje unifikacji**:

#### Opcja A: Everywhere inline (rapid entry style) ⭐
- **Shopping**: ✅ bez zmian — rapid entry działa świetnie
- **Tasks**: Jeśli DR-2 Opcja A → Tasks nie ma Add w ogóle. Jeśli DR-2 Opcja B/C → zamienić sheet na inline rapid entry (jak Shopping)
- **Backlog**: ✅ inline `+ Add item` w CategoryCard — już działa, ale zmienić na ten sam styl co Shopping (Circle placeholder + TextField) zamiast `plus.circle.fill + text`

**Plusy**: Jeden wzorzec, zero context-switching, szybsze dodawanie
**Minusy**: Backlog add musi wiedzieć do której kategorii → inline w card to rozwiązuje naturalnie

#### Opcja B: Everywhere floating pill → sheet
- Każdy screen: floating pill na dole → prezentuje sheet z formularzem
- Spójne, ale wolniejsze (dodatkowy tap + modal)
- Backlog traci kontekst kategorii (trzeba wybrać kategorię w sheecie)

#### Opcja C: Floating pill → rapid entry (hybrid)
- **Shopping + Tasks**: Floating pill → inline rapid entry w liście (jak teraz Shopping)
- **Backlog**: Inline w card (bo kontekst kategorii jest istotny)
- **Wizualny styl**: Ten sam look for all (Circle + TextField + tinted accent)

#### 📌 Rekomendacja: **Opcja C** (hybrid)
Shopping i Backlog są już dobrze — ujednolicić tylko styl wizualny:
1. **Shopping rapid entry** → ✅ zostawić
2. **Backlog inline** → Zamienić `plus.circle.fill` + "Add item" na styl z Shopping: `Circle().stroke() + TextField("Add item")`
3. **Tasks** → Jeśli Pure Scrum (DR-2A): usunąć Add. Jeśli zachowujemy: zamienić sheet na rapid entry inline jak Shopping.

**Kluczowy styl do ujednolicenia**:
```
[○ empty circle] [TextField "Add item..."]  ← consistent across all screens
```
Z jedną różnicą: w Backlog jest wewnątrz karty, w Shopping jest na dole listy.

---

## 📋 Podsumowanie decyzji do podjęcia

| # | Temat | Rekomendacja | Effort |
|---|-------|-------------|--------|
| DR-1 | Sign Out za tab barem | Dodać `listBottomInset` do MoreView | 15 min |
| DR-2 | Backlog→Tasks flow | **Opcja A: Pure Scrum** — usunąć Add z Tasks | 1-2h |
| DR-3 | WIP warning | Toast "3 active — complete one first" | 30 min |
| DR-4 | Areas/Rooms | **Usunąć** UI + store, zachować model fields | 30 min |
| DR-5 | Recurring tasks | Do Backlog z tagiem 🔄, fix Custom picker | 2-3h |
| DR-6 | Add item unifikacja | **Hybrid** — inline rapid entry + backlog card | 1h |

---

## 🔄 Analiza krzyżowa: Codex Plan vs Design Research (2026-02-15 23:12)

> Porównanie `codex-PLAN.md` z własnymi rekomendacjami DR-1 do DR-6.

### ✅ Pełna zgodność (identyczne wnioski)

| Temat | Codex | DR | Zgodność |
|-------|-------|-----|----------|
| Backlog-only intake | "Tasks przechodzi na Backlog-only intake" | DR-2 Opcja A "Pure Scrum" | 🟢 100% |
| Areas/Rooms | "Usuwamy z produktu, zachowujemy kompatybilność danych" | DR-4: usunąć UI/store, zachować `areaId` | 🟢 100% |
| Recurring → Backlog | "`ChoreScheduler` tworzy taski z `status = .backlog`" | DR-5: do Backlog z tagiem 🔄 | 🟢 100% |
| Custom frequency | "co N dni, Stepper/input" | DR-5: `Stepper("Every X days")` | 🟢 100% |
| Inline Add item | "inline-first (Shopping + Backlog)" | DR-6 Opcja C: Hybrid inline | 🟢 100% |
| Sign Out diagnoza | "brak insettingu, Sign Out wpada pod dolne menu" | DR-1: brak `listBottomInset` | 🟢 identyczna diagnoza |

### ⚠️ Rozbieżności — warto przyjąć z Codex

#### CX-1: Tab bar visibility (nowy preference-key)
- **Codex**: Nowy `appTabBarVisibility(false)` preference-key + chowaj tab bar na Settings, Profile, Categories
- **DR-1**: Dodaj `listBottomInset` do SettingsView (prostsze)
- **Ocena**: Codex lepszy **długoterminowo** (nie trzeba martwić się o inset na żadnym detail screen), ale bardziej ryzykowna zmiana (animacja show/hide, timing).
- **📌 Decyzja**: `listBottomInset` jako **P0 quick fix**, tab bar visibility jako **P1 polish**

#### CX-2: Assignee wymagany przy NEXT ⭐
- **Codex**: "NEXT bez assignee jest niedozwolone", `canMoveToNext(nil)` → `false`
- **DR**: nie poruszony
- **Ocena**: **Ważny bug** — aktualnie `canMoveToNext(assigneeId: nil)` zwraca `true` (TaskStore linia 52-53), więc WIP limit jest **omijany** dla tasków bez assignee!
- **📌 Decyzja**: ✅ Przyjąć. Wyjątek: **single-member household** → auto-assign do current user (nie zmuszać do ręcznego assigning)

#### CX-3: Assignee picker przy Promote
- **Codex**: Sheet "Assign to" (member picker) przed promocją do NEXT
- **DR-2**: nie opisany szczegółowo
- **Ocena**: Logiczna konsekwencja CX-2. Jeśli NEXT wymaga assignee, promote musi pytać
- **📌 Decyzja**: ✅ Przyjąć. Flow: Swipe "Promote" → if 1 member: auto-assign → create. If >1 members: member picker sheet → wybierz → create

#### CX-4: `PromotionResult` enum (typowane wyniki)
- **Codex**: `PromotionResult` enum (`.success`, `.assigneeRequired`, `.wipLimitReached`, `.failed`) + **atomowa operacja** (nie usuwaj BacklogItem jeśli task creation fails)
- **DR**: opisuję intent ale bez typed result
- **Ocena**: ✅ Zdecydowanie lepsze niż obecne poleganie na `store.error` side effect. Obecny `promoteItemToTask()` **nie jest atomowy** — może usunąć item nawet jeśli task creation fails
- **📌 Decyzja**: ✅ Przyjąć. Zmienić `promoteItemToTask()` na zwracanie `PromotionResult`, usuwanie BacklogItem **tylko** po `.success`

#### CX-5: Glass transition refactor
- **Codex**: `GlassEffectContainer` + `glassEffectID` + `glassEffectTransition(.matchedGeometry)` jako osobny task
- **DR**: pokryty w wcześniejszym research sesji (spoza DR-1-6)
- **📌 Decyzja**: Spójne z wcześniejszym research — **P1 polish**, not blocker

### ❌ Rozbieżność — nie przyjmujemy z Codex

#### CX-6: Tasks.BACKLOG = only recurring
- **Codex**: "sekcja BACKLOG w Tasks tylko dla tasków systemowych/recurring; manualny intake tylko przez Backlog tab"
- **DR-2**: "sekcja BACKLOG w Tasks jako staging area — user widzi co jest na radarze"
- **Ocena**: Codex jest **zbyt restrykcyjny**. Tasks.BACKLOG jako general staging area jest bardziej elastyczny — user może promować item z Backlog do Task(status=.backlog), potem swipeować do NEXT w Tasks. Ograniczenie do "recurring only" wymaga dodatkowej filtracji i zmniejsza value Tasks taba
- **📌 Decyzja**: ❌ Nie przyjmować. Tasks.BACKLOG = **general staging area** (promoted z Backlog + recurring)

---

### 📋 Finalna lista zmian do implementacji (po merge obu planów)

| # | Zmiana | Priorytet | Effort | Źródło |
|---|--------|-----------|--------|--------|
| 1 | `listBottomInset` w MoreView/SettingsView | P0 | 15 min | DR-1 |
| 2 | Usunąć `+ Add task` z TasksView | P0 | 30 min | DR-2 + Codex |
| 3 | Assignee required @ NEXT (fix `canMoveToNext(nil)`) | P0 | 30 min | CX-2 |
| 4 | Auto-assign w single-member household | P0 | 20 min | CX-2 ext |
| 5 | Assignee picker sheet @ Promote | P0 | 1h | CX-3 |
| 6 | `PromotionResult` enum + atomic promote | P0 | 45 min | CX-4 |
| 7 | WIP toast "3 active — complete one" | P0 | 30 min | DR-3 |
| 8 | Usunąć Areas/Rooms (UI + store + model) | P1 | 30 min | DR-4 + Codex |
| 9 | Backlog `+ Add item` styl unifikacja | P1 | 30 min | DR-6 |
| 10 | Custom frequency UI (Stepper) | P1 | 1h | DR-5 + Codex |
| 11 | `ChoreScheduler` service | P1 | 2h | DR-5 + Codex |
| 12 | Tab bar hide na detail screens (preference-key) | P1 | 1.5h | CX-1 |
| 13 | iOS 26 glass transition refactor | P1 | 2h | CX-5 |

**P0 total: ~3.5h** · **P1 total: ~7.5h** · **All: ~11h**
