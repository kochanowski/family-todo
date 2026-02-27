# HousePulse — Merged Implementation Roadmap

> Merged z `claude-TODO.md` (Antigravity) + `codex-PLAN.md` (Codex)
> Data: 2026-02-15

---


## Roadmap


### 3. Onboarding carousel (premium)
1. W `OnboardingCarouselView.swift` dodać 4. slajd (`Better Together`, `person.2.fill`).
2. Dodać `Skip` (top trailing), aktywny na każdym slajdzie.
3. Dodać dolny CTA: `Next` na slajdach 1-3, `Get Started` na 4.
4. `Skip` i `Get Started` ustawiają onboarding zakończony i przejście do `auth`.
5. Zachować obecne tło/aurora i animacje.

### Phase 5: Recurring Chores Engine (P1) 🔄

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


#### 7.3 Accessibility

- Pełne `accessibilityIdentifier` dla: invite flow, role changes, recurring CRUD, backlog promote, task detail fields

---

### Phase 8: Testing & Release Gate (P0/P1) 🧪

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

| Feature | Źródło | Opis |
|---|---|---|
| 🔍 **Quick Search** | Antigravity | Search across Tasks + Shopping + Backlog |
| 📊 **Weekly Home Pulse** | Codex | Neutralny tygodniowy digest: co zrobione, co czeka |
| 📱 **WidgetKit** | Oba | Small: Next tasks / Shopping To Buy |
| 🗣️ **Siri & App Intents** | Oba | "Add milk to shopping list", "What are my next tasks?" |
| 📋 **Drag & Drop Reorder** | Antigravity | Shopping, Backlog, Tasks — `.draggable()` |
| 💡 **Smart Restock Suggestions** | Codex | Na bazie `restockCount` — predykcja co kupić |
| 🔔 **Smart Notifications** | Antigravity | Geofence "don't forget", "still working on this?" |

---

## Assumptions
1. iOS target: 17; Liquid Glass iOS 26+ only
2. Single active household per session (multi-household later)
3. WIP limit = 3, nienegocjowalny
4. Member soft-delete (`isActive=false`) where history needed
5. Cloud sharing only when `syncMode == .cloud`; guest mode = no invite
6. `RecurringChore` model migration: out of `LegacyStubs` → own file
