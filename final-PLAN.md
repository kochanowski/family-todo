# Final Plan v1 (`final-TODO.md`) — P0+P1 Execution Roadmap

## Summary
To jest plan wykonawczy po analizie `claude-codex-TODO.md` i aktualnego kodu.
Zakres: **P0 + P1** (bez P2), żeby domknąć pełne działanie produktu i stabilny release.

## Korekty względem `claude-codex-TODO.md`
1. **Usuwam P2 z głównego planu**: zostaje jako “Later backlog”, nie blokuje dostarczenia działającej v1.
2. **Przesuwam Sign Out i Session Consistency na sam początek**: bez tego kolejne flow są niestabilne.
3. **Scalam backlog management**: jedno źródło prawdy (`BacklogStore`) dla `BacklogView` i `More > Categories`.
4. **Domykam household/invite jako pełny flow onboardingowy**: nie tylko CKShare UI, ale też join + bootstrap sesji.
5. **Dodaję twarde Definition of Done per etap**: żeby implementacja była kontrolowalna krok po kroku.

## Important API / Interface Changes
1. `FamilyTodo/Stores/HouseholdStore.swift`
- `loadCurrentHouseholdAndMembership(userId:)`
- `renameCurrentHousehold(_:)`
- `leaveCurrentHousehold(userId:)`
- `deleteCurrentHousehold(requestedBy:)`
2. `FamilyTodo/Stores/MemberStore.swift`
- Walidacje ról w `updateRole` i `deleteMember` (owner-only, min. 1 owner, self-removal rules)
3. `FamilyTodo/Stores/BacklogStore.swift`
- `renameCategory(...)`
- `reorderCategories(...)`
- `updateItem(...)`
- `promoteItemToTask(...)`
4. `FamilyTodo/Stores/TaskStore.swift`
- Obsługa pełnej edycji taska (assignee/dueDate/notes/status) z pełnym enforcement WIP
- `createTaskFromBacklogItem(...)`
5. Nowe pliki:
- `FamilyTodo/Views/TaskDetailSheet.swift`
- `FamilyTodo/Stores/RecurringChoreStore.swift`
- `FamilyTodo/Services/ChoreScheduler.swift`
- opcjonalnie `FamilyTodo/Views/AreasManagementView.swift` (P1)
6. `FamilyTodo/Views/MoreView.swift`
- `CategoriesManagementView` przepięty na `BacklogStore`
- `RepetitiveTasksView` jako realny manager recurring chores
- `SettingsView` z realnym Sign Out i notification settings

## Krok po kroku (implementacja)

## Etap 1 — Session & Navigation Consistency (P0)
1. Ustalić single source of truth dla household (`UserSession.currentHouseholdID` + bootstrap w `HouseholdStore`).
2. W `Shopping/Tasks/Backlog` zastąpić fallbacki `No Household Selected` komponentem `GuidedEmptyStateView`.
3. Podpiąć realny Sign Out w `SettingsView` (reset sesji, household, subscriptions).
4. Posprzątać legacy onboarding (`Views/OnboardingView.swift`) po weryfikacji użycia.

**Definition of Done**
1. Po starcie/zalogowaniu zawsze poprawnie wybierany household.
2. Po Sign Out brak “wiszących” danych household.
3. Wszystkie 3 taby mają spójny empty state.

## Etap 2 — Full Tasks Flow (P0)
1. Dodać `TaskDetailSheet` i otwieranie po tapie w task.
2. Wdrożyć pola: assignee, due date, notes, status.
3. Dodać backlog section w `TasksView` i badge metadata w wierszach.
4. WIP limit = 3 wymusić dla wszystkich wejść do `.next`.
5. Permission request do notyfikacji tylko przy pierwszym due-date lub aktywacji digest.

**Definition of Done**
1. Task można stworzyć/edytować/przenieść/delete bez utraty danych.
2. WIP jest egzekwowany w create/edit/promotion.
3. Due-date i assignee widoczne i działają w UI.

## Etap 3 — Full Backlog Flow + Promotion (P0)
1. Dodać rename/reorder/edit item w `BacklogStore` + UI.
2. Dodać “Promote to Task” ze swipe action.
3. Smart default promocji: do `.next` gdy WIP pozwala, inaczej do `.backlog`.
4. Spójny delete confirm dla kategorii z elementami.

**Definition of Done**
1. Backlog ma pełne CRUD + reorder.
2. Promotion działa i nie łamie WIP.
3. Zmiany są trwałe lokalnie i w sync mode.

## Etap 4 — More jako centrum zarządzania (P0)
1. `CategoriesManagementView` przepiąć na realny `BacklogStore`.
2. Dodać sekcję household management (rename/leave/delete z guardrails roli).
3. Uporządkować Profile (members + household actions) i spójne komunikaty błędów.

**Definition of Done**
1. Category changes z More od razu widoczne w Backlog.
2. Household actions respektują role i nie psują sesji.

## Etap 5 — Household Sharing & Invitation E2E (P0)
1. Zaimplementować TODO w `CreateHouseholdView.joinHousehold()`.
2. Domknąć flow join: invite code/deep link -> `joinHousehold` -> ustawienie current household -> przejście do MainApp.
3. Dodać pełne error handling: invalid code, cloud off, auth off, network fail.
4. Zweryfikować member onboarding po dołączeniu.

**Definition of Done**
1. Owner zaprasza, member dołącza, dane household są wspólne.
2. Join działa zarówno z kodem, jak i linkiem share (jeśli dostępny).
3. Błędy są czytelne i odwracalne.

## Etap 6 — Recurring Tasks Engine (P1)
1. Wyprowadzić `RecurringChore` z `LegacyStubs` do docelowego modelu/store.
2. Zbudować `RecurringChoreStore` + CRUD UI w `RepetitiveTasksView`.
3. Dodać `ChoreScheduler` uruchamiany na launch/foreground.
4. Generować taski wg `nextScheduledDate`, aktualizować harmonogram i rotację assignee.

**Definition of Done**
1. Użytkownik może zdefiniować cykliczne zadania.
2. Taski generują się automatycznie zgodnie z harmonogramem.
3. Brak duplikacji tasków przy wielokrotnym wejściu do app.

## Etap 7 — Areas/Rooms (P1)
1. Urealnić `AreaStore` (obecnie stub).
2. Dodać `AreasManagementView` i CRUD stref.
3. Podpiąć area picker do task detail i recurring chores.

**Definition of Done**
1. Areas da się tworzyć/edytować/usunąć.
2. Task i recurring chore mogą być przypisane do area.

## Etap 8 — Tab Bar Glass & Interaction Polish (P1)
1. Domknąć widoczny glass transition na iOS 26+.
2. Utrzymać fallback dla iOS 17–25.
3. Sprawdzić hit-area i relację z keyboard/CTA (brak overlap i przypadkowego przechwytywania tapów).

**Definition of Done**
1. Przełączanie tabów jest płynne i czytelne.
2. Interakcje tabów są niezawodne na realnym iPhonie.

## Etap 9 — Test & CI Gate (P0/P1)
1. Unit tests:
- HouseholdStore, MemberStore guardrails
- TaskStore WIP + promotion
- BacklogStore rename/reorder/promotion
- RecurringChoreStore schedule logic
2. UI smoke:
- onboarding create/join
- tasks full flow
- backlog+more consistency
- sign out
3. CI:
- PR: build+lint
- nightly/manual: pełne testy + lane `sync-enabled`

**Definition of Done**
1. Green pre-commit i green CI dla docelowego zakresu.
2. Kluczowe flow mają testy regresyjne.

## Test Cases and Scenarios
1. `SessionBootstrap_NoHousehold_ShowsGuidedEmptyState`
2. `Settings_SignOut_ClearsSessionAndHousehold`
3. `Tasks_EditAssigneeDueDateNotes_Persists`
4. `Tasks_WIPLimit_EnforcedInAllEntryPoints`
5. `Backlog_PromoteToTask_RespectsWIP`
6. `More_Categories_ReflectInBacklogImmediately`
7. `JoinHousehold_FromOnboarding_SetsActiveHousehold`
8. `HouseholdRoleGuardrails_OwnerOnlyMutations`
9. `RecurringScheduler_GeneratesOncePerWindow`
10. `TabBar_GlassTransition_AndHitTestingStable`

## Assumptions and Defaults
1. Zakres zatwierdzony: **P0 + P1 only**.
2. iOS target: 17, Liquid Glass tylko iOS 26+.
3. Jeden aktywny household per sesja (multi-household poza zakresem).
4. WIP=3 jest twardą regułą produktową.
5. Guest mode nie obsługuje invitation/share.
6. P2 “delight features” zostają w backlogu po stabilizacji P0/P1.

## Later Backlog (P2, poza tym planem)
1. Quick Search (cross-tab)
2. Weekly Home Pulse dashboard
3. WidgetKit
4. Siri/App Intents
5. Smart suggestions/notifications
