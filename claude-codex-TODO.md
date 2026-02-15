# HousePulse — Merged Implementation Roadmap

> Merged z `claude-TODO.md` (Antigravity) + `codex-PLAN.md` (Codex)
> Data: 2026-02-15

---

## Stan obecny

### ✅ Co działa
| Feature | Pliki |
|---|---|
| **Shopping List** — rapid entry, buy/unbuy, restock, suggestions, swipe delete, Clear All | `ShoppingListView`, `ShoppingListStore` |
| **Tasks** — basic CRUD, add sheet, complete/uncomplete, WIP limit (3/assignee) | `TasksView`, `TaskStore` |
| **Backlog** — categories + items CRUD, swipe delete | `BacklogView`, `BacklogStore` |
| **Auth** — Sign in with Apple + Guest mode | `AuthenticationService`, `UserSession` |
| **CloudKit sync** + SwiftData cache (offline-first) | `CloudKitManager`, Cached* models |
| **Notifications** — task reminders (due date), daily digest | `NotificationService` |
| **Onboarding** — carousel → create household → sync selection | `Onboarding/` |
| **More** — profile card, member management, CKShare invite, appearance | `MoreView`, `MemberManagementView` |
| **Tab bar** — floating glass (iOS 26) + material fallback | `FloatingTabBar` |
| **Themes** — 4 presets (Journal, Pastel, Soft, Night) | `ThemeStore` |

### 🔴 Braki / stuby
| Brak | Obecny stan |
|---|---|
| Task detail/edit | Stub "Coming Soon" (`LegacyStubs.TaskDetailView`) |
| Task assignee/dueDate/notes UI | Modele istnieją, brak UI |
| Recurring chores | Stub "Coming Soon", model `RecurringChore` w `LegacyStubs` |
| Areas/Rooms | Model `Area` + defaults istnieją, `AreaStore` pusty |
| Backlog → Task promotion | Brak flow |
| Categories management (More) | `@State [String]` — **nie wired do BacklogStore** |
| Sign Out | Empty closure w `SettingsView` |
| Notification settings UI | `NotificationSettingsStore` stub |
| `joinHousehold()` | TODO w `CreateHouseholdView` |
| Role guardrails | `MemberStore` nie waliduje `currentUserId` |
| Session bootstrap | Rozproszony, brak jednego źródła prawdy |

---

## Roadmap

### Phase 0: Session Consistency (P0, pre-req) 🔧
> *Źródło: Codex* — konieczne przed jakąkolwiek dalszą pracą

**Cel:** Jeden punkt prawdy o sesji i household.

1. **Ujednolicić bootstrap:** `HouseholdStore.loadCurrentHouseholdAndMembership(userId:)` — konsolidacja logiki ładowania household + membership w jednej metodzie
2. **Zamienić "No Household Selected"** fallbacki na `GuidedEmptyStateView` w `ShoppingListView`, `TasksView`, `BacklogView` (komponent już istnieje!)
3. **Wyczyścić legacy onboarding:** `OnboardingView.swift` (w katalogu Views/) — sprawdzić czy jest używany; jeśli nie, usunąć lub przenieść do docs

**Pliki do modyfikacji:**
- `HouseholdStore.swift` — nowa metoda bootstrap
- `ContentView.swift` / `FamilyTodoApp.swift` — single source of truth
- `ShoppingListView.swift`, `TasksView.swift`, `BacklogView.swift` — `GuidedEmptyStateView`

---

### Phase 1: Full Task Experience (P0) 🎯
> *Źródło: oba plany* — tasks muszą być w pełni użyteczne

#### 1.1 Task Detail / Edit Sheet
- **Nowy plik:** `TaskDetailSheet.swift`
- **Pola:** Title (TextEditor), Status picker (Next/Backlog/Done), Assignee picker, Due date (DatePicker, opcjonalny), Notes (TextEditor), Area (picker — jeśli Phase 6 zaimplementowana)
- **UX:** `.presentationDetents([.medium, .large])`, dismiss on save
- **Trigger:** Tap na task row → sheet; toggle done zostaje na checkboxie
- **Store:** `TaskStore.updateTask()` już istnieje — wystarczy podpiąć UI

#### 1.2 Task Assignee Picker
- **UI:** Horizontal scroll z avatarami + "Unassigned"
- **Wymaga:** `MemberStore` (działa)
- **W task row:** Mały avatar obok tytułu
- **Opcjonalnie:** "My Tasks" / "All Tasks" filter toggle w headerze

#### 1.3 Task Due Date + Overdue Badge
- **W Task Detail:** DatePicker inline
- **W task row:** Date badge ("Mon", "Tomorrow", czerwony jeśli overdue)
- **Sorting:** Overdue at top
- **`Task.isOverdue`** — już zaimplementowane w modelu!

#### 1.4 Task Sections
- **Obecne:** Next + Done
- **Dodać:** sekcja Backlog w TasksView (tasks ze statusem `.backlog`)
- **Badge:** assignee + due-date w wierszu

#### 1.5 WIP Enforcement Completeness
> *Źródło: Codex* — WIP=3 musi obowiązywać wszędzie

- Tworzenie nowego taska
- Edycja statusu do `.next` w detail sheet
- Promocja z backlogu (Phase 2)
- Jasny error message gdy limit osiągnięty

#### 1.6 Notification Permission Timing
> *Źródło: Codex*

- Nie pytaj o permissions przy onboardingu
- Pytaj dopiero przy ustawieniu due date lub aktywacji digest/suggestions

---

### Phase 2: Full Backlog Flow (P0) 📋
> *Źródło: Codex (operacje) + Antigravity (promotion flow)*

#### 2.1 Pełne operacje Backlog
- **Dodać do `BacklogStore`:**
  - `renameCategory(id:newTitle:)` — brak w obecnym API
  - `reorderCategories(orderedIds:)` — brak
  - `updateItem(item:title:notes:)` — brak edycji
- **UI:** Long press na category header → rename alert; drag to reorder

#### 2.2 Backlog → Task Promotion
- **Swipe action** na backlog item → "Promote to Task"
- **Smart default:** `.next` jeśli WIP pozwala, inaczej `.backlog`
- **Opcjonalnie:** otwiera Task Detail Sheet do uzupełnienia
- **Store:** `BacklogStore.promoteItemToTask()` + `TaskStore.createTaskFromBacklogItem()`
- **Po promocji:** item usuwany z backlogu

#### 2.3 "Backlog to Sprint" (one-click)
> *Źródło: Codex — unikalny pomysł*

- Wybór 1–3 backlog items jednym kliknięciem jako "plan tygodnia"
- Bulk promotion z respektem WIP limit

---

### Phase 3: More & Settings jako realne centrum (P0) ⚙️
> *Źródło: Codex — podniesiony do P0, bo sign out jest krytyczny*

#### 3.1 Categories Management → BacklogStore
- **Problem:** `CategoriesManagementView` używa lokalnego `@State [String]` — nic nie persystuje!
- **Fix:** Przekazać `BacklogStore` z `householdId`, użyć `.addCategory()`, `.deleteCategory()`, `.renameCategory()`
- **Sync:** Zmiany z More → widoczne natychmiast w Backlog tab

#### 3.2 Settings — Full Implementation
- **Appearance** ✅ działa
- **Celebrations** ✅ toggle działa
- **Shopping suggestions** ✅ toggle działa
- **Dodać:**
  - **Notifications section:** task reminders toggle, daily digest toggle, digest time picker, sound toggle → podpiąć do `NotificationSettingsStore` (przebudować ze stub na real)
  - **Data section:** sync mode indicator, "Force Refresh" button, version info
  - **Sign Out:** podpiąć `userSession.signOut()` → reset household → cleanup subscriptions → powrót do SignInView

#### 3.3 Repetitive Tasks → Real Manager
- Przepiąć z "Coming Soon" placeholder na realny ekran (Phase 5)

#### 3.4 Profile View Enhancement
- Household name (editable → Phase 4)
- Member count + multi-avatar stack
- Link do `MemberManagementView`

---

### Phase 4: Household & Sharing End-to-End (P0) 👨‍👩‍👧‍👦
> *Źródło: Codex (complete flow) + Antigravity (management UI)*

#### 4.1 Join Household Flow
> *Źródło: Codex — kluczowy brak*

- **Problem:** `CreateHouseholdView.joinHousehold()` jest TODO
- **Implementacja:**
  - Input: invite code / deep link
  - Wywołanie `householdStore.joinHousehold(inviteCode:userId:displayName:)`
  - Po sukcesie: `userSession.setCurrentHousehold()` → zamknięcie onboardingu → pełny reload stores

#### 4.2 Household Management
- **Nowy plik:** `HouseholdEditView.swift` (lub rozszerzenie `ProfileView`)
- **Operacje:**
  - `renameCurrentHousehold(name:)` — nowa metoda w `HouseholdStore`
  - "Leave Household" (non-owner) → `leaveCurrentHousehold(userId:)`
  - "Delete Household" (owner) → `deleteCurrentHousehold(requestedBy:)` + confirmation alert
  - Transfer ownership before leaving

#### 4.3 Role Guardrails
> *Źródło: Codex — luka bezpieczeństwa*

- **`MemberStore`** musi walidować:
  - Tylko owner może zmieniać role i usuwać członków
  - Zawsze minimum 1 owner (blokada degradacji jedynego ownera)
  - Brak usunięcia siebie bez transfer ownership
- Soft-delete: `isActive=false` tam gdzie potrzebna historia

#### 4.4 Error UX
> *Źródło: Codex*

- Invalid invite code → czytelny alert z retry
- Cloud disabled → info + link do Settings
- Network failure → offline mode fallback
- Not authenticated → redirect do sign in

---

### Phase 5: Recurring Chores Engine (P1) 🔄
> *Źródło: oba plany*

#### 5.1 Recurring Chore CRUD
- **Nowy store:** `RecurringChoreStore.swift`
- **Nowy ekran:** przebudowa `RepetitiveTasksView` → lista + Add/Edit sheet
- **Pola:** Title, Recurrence (daily/weekly+day/monthly+dayOfMonth/custom interval), Default assignee(s) z rotation, Area (opcjonalne), Notes, isActive toggle
- **Model:** `RecurringChore` już istnieje w `LegacyStubs` → przenieść do własnego pliku
- **Schema:** Dodać `CachedRecurringChore` do `FamilyTodoApp.swift` model container

#### 5.2 Task Generation Engine
- **Nowy service:** `ChoreScheduler.swift`
- **Timing:** Na app foreground / launch
- **Logic:** Jeśli `nextScheduledDate <= today` → create Task → update `lastGeneratedDate` → oblicz nowy `nextScheduledDate`
- **Rotation:** Cyklicznie przełączaj assignee jeśli `rotationEnabled`
- **Link:** `Task.recurringChoreId` → już istnieje w modelu!
- **UI indicator:** `repeat` icon w task row

---

### Phase 6: Areas / Rooms (P1) 🏠
> *Źródło: Antigravity — Codex pominął*

#### 6.1 Areas CRUD
- Przebudowa `AreaStore` (obecny stub)
- Nowy ekran `AreasManagementView.swift`
- Default areas: Kitchen, Living Room, Bathroom, Bedroom, Garden, Other (w `Area.defaults`)

#### 6.2 Area Integration
- Task Detail: Area picker
- Tasks View: opcjonalny grouping "By Area"
- Recurring Chores: default area

---

### Phase 7: UX Polish (P1) ✨
> *Źródło: Codex (accessibility, chrome) + Antigravity (animations)*

#### 7.1 Tab Bar Final
- Glass transition iOS 26+ (w trakcie implementacji)
- Material fallback iOS 17-25
- Hit-area consistency, brak nakładania z CTA/keyboard

#### 7.2 Celebrations & Micro-Animations
- `celebrationsEnabled` toggle istnieje — ale **brak actual celebrations!**
- Confetti/particles kiedy all tasks done
- Scale + haptic na checkbox tap
- "Well done!" message po completion
- Streak badge animation

#### 7.3 Accessibility
> *Źródło: Codex*

- Pełne `accessibilityIdentifier` dla: invite flow, role changes, recurring CRUD, backlog promote, task detail fields

---

### Phase 8: Testing & Release Gate (P0/P1) 🧪
> *Źródło: Codex — pominięte w moim planie*

#### Unit Tests
- `HouseholdStore`: create / join / rename / leave / delete
- `MemberStore`: role guardrails (owner-only operations)
- `TaskStore`: WIP enforcement + backlog promotion
- `BacklogStore`: reorder / rename / promotion
- `RecurringChoreStore`: schedule calculations

#### UI Tests
- Onboarding create / join household
- Invite flow (cloud-enabled lane)
- Tasks full CRUD + due date + assignee
- Backlog ↔ More categories consistency
- Settings sign out + session reset

#### CI
- PR: build + lint (jak obecnie)
- Nightly: pełne testy + `sync-enabled` lane
- Regression gate: block merge jeśli E2E household/invite fail

---

### Phase 9: Delight Features (P2) 🚀
> *Źródło: oba plany — najlepsze pomysły*

| Feature | Źródło | Opis |
|---|---|---|
| 🔍 **Quick Search** | Antigravity | Search across Tasks + Shopping + Backlog |
| 📊 **Weekly Home Pulse** | Codex | Neutralny tygodniowy digest: co zrobione, co czeka |
| 📱 **WidgetKit** | Oba | Small: Next tasks / Shopping To Buy |
| 🗣️ **Siri & App Intents** | Oba | "Add milk to shopping list", "What are my next tasks?" |
| 📋 **Drag & Drop Reorder** | Antigravity | Shopping, Backlog, Tasks — `.draggable()` |
| 🎨 **Theme Customization** | Antigravity | Custom palette per card type |
| 💡 **Smart Restock Suggestions** | Codex | Na bazie `restockCount` — predykcja co kupić |
| 📋 **Backlog to Sprint** | Codex | One-click wybór 1-3 items na plan tygodnia |
| 🔔 **Smart Notifications** | Antigravity | Geofence "don't forget", "still working on this?" |

---

## Sugerowany order implementacji

```
Sprint 1 (P0 — fundament):
├── Phase 0: Session consistency + GuidedEmptyState
├── Phase 1.1-1.3: Task Detail + Assignee + Due Date
├── Phase 3.2: Sign Out (krytyczne!)
└── Phase 3.1: Categories → BacklogStore

Sprint 2 (P0 — multi-user + backlog):
├── Phase 4.1: Join Household flow
├── Phase 4.2-4.3: Household management + role guardrails
├── Phase 2.1-2.2: Backlog operations + Promote to Task
└── Phase 3.2: Notification settings UI

Sprint 3 (P1 — recurring + areas):
├── Phase 5: Recurring Chores engine
├── Phase 6: Areas / Rooms
├── Phase 7: Tab bar final + celebrations
└── Phase 8: Unit + UI tests

Sprint 4 (P2 — delight):
├── Phase 9: Search, Widgets, Siri, Drag&Drop
├── Phase 9: Weekly Pulse, Smart Restock
└── Phase 9: Theme customization
```

## Effort estimate

| Phase | Effort | Dependencies |
|---|---|---|
| Phase 0: Session | 0.5 dnia | Brak |
| Phase 1: Tasks | 3-4 dni | Phase 0 |
| Phase 2: Backlog | 2 dni | Phase 1 |
| Phase 3: More/Settings | 1-2 dni | Brak |
| Phase 4: Household | 2-3 dni | CloudKit testing |
| Phase 5: Recurring | 3-5 dni | Phase 1 |
| Phase 6: Areas | 1-2 dni | Brak |
| Phase 7: Polish | 1-2 dni | Phases 1-6 |
| Phase 8: Tests | 3-4 dni | All above |
| Phase 9: Delight | 5-8 dni | Phases 1-5 |

**Sprint 1 (MVP):** ~1 tydzień
**Sprint 1-2 (Full P0):** ~2.5 tygodnia
**Sprint 1-3 (v1.0):** ~4 tygodnie
**Sprint 1-4 (Premium):** ~6-7 tygodni

## Assumptions
1. iOS target: 17; Liquid Glass iOS 26+ only
2. Single active household per session (multi-household later)
3. WIP limit = 3, nienegocjowalny
4. Member soft-delete (`isActive=false`) where history needed
5. Cloud sharing only when `syncMode == .cloud`; guest mode = no invite
6. `RecurringChore` model migration: out of `LegacyStubs` → own file
