# Plan v5: Uspojnienie Backlog→Tasks, WIP=3, Glass i Settings (decision-complete)

## Summary
Na bazie review kodu i Twoich decyzji ustalamy finalny kierunek:
1. `Tasks` przechodzi na model **Backlog-only intake**: nowe zadania tworzymy w `Backlog`, a do aktywnych (`NEXT`) trafiaja przez promocje/przydzial.
2. Limit WIP jest **twardy per osoba**: `NEXT` wymaga assignee i max `3` aktywne taski na osobe.
3. Ostrzezenia WIP: **inline banner + blokada akcji** (bez dodawania 4. taska).
4. `Rooms/Areas` usuwamy z produktu (UI + entrypointy), ale zachowujemy kompatybilnosc danych.
5. `Repetitive Tasks` tworzy taski do `Tasks.Backlog` z oznaczeniem recurring; `Custom` dostaje realna konfiguracje.
6. `Add item` ujednolicamy jako **inline-first** (Shopping + Backlog), CTA traktujemy jako skrot, nie osobny model.
7. Naprawiamy `Settings` overlap i tab bar glass: chowamy dolne menu na ekranach detail + poprawiamy iOS26 glass transition.

## Research Findings (stan obecny)
1. `SettingsView` jest `List` bez dolnego insettingu pod custom tab bar; dlatego `Sign Out` wpada pod dolne menu.
2. W `FloatingTabBar` iOS26 jest tylko przesuwany indicator z `.glassEffect`, ale bez struktury transition (`glassEffectID`/`matchedGeometry`), przez co efekt "kropli" jest slaby.
3. `TasksView` nadal ma `Add task` i tworzy task bez assignee; obecny `TaskStore.canMoveToNext` zwraca `true` dla `nil assignee`, wiec WIP jest omijany.
4. `BacklogStore.promoteItemToTask` usuwa item po promocji i opiera fallback o `store.error`; semantyka nie jest atomowa dla blokad WIP.
5. `MoreView` nadal ma `Rooms / Areas` i `AreasManagementView`.
6. `RepetitiveTasksView` dla `Frequency = Custom` nie pokazuje dodatkowych ustawien; UX sprawia wrazenie "nic sie nie dzieje".

## Important API / Interface Changes
1. `FamilyTodo/Views/Components/FloatingTabBar.swift`
- Dodac prawdziwy iOS26 transition:
  - `GlassEffectContainer`
  - `glassEffectID("activeTabDroplet", in: namespace)`
  - `glassEffectTransition(.matchedGeometry)`
- iOS17-25 fallback zostaje material + matched geometry.
- Zachowac rowne hit area tabow i `allowsHitTesting(false)` dla warstw dekoracyjnych.

2. `FamilyTodo/ContentView.swift` + nowy helper (np. `FamilyTodo/Views/Components/TabBarVisibility.swift`)
- Wprowadzic preference-key do sterowania widocznoscia dolnego menu:
  - `appTabBarVisibility(_ visible: Bool)`
- `MainAppView` pokazuje tab bar tylko gdy:
  - klawiatura schowana
  - i aktywny ekran zgadza sie na widocznosc tab bara.
- Detail screens (`Settings`, `Profile`, `Categories`, `RepetitiveTasks`) ustawiaja `appTabBarVisibility(false)`.

3. `FamilyTodo/Views/TasksView.swift`
- Usunac tworzenie taska z Tasks (`Add task` CTA + add sheet).
- `Tasks` staje sie ekranem wykonawczym:
  - sekcje: `NEXT`, `BACKLOG` (tylko taski systemowe/recurring), `DONE`.
- Dla akcji przejscia do `NEXT`: wymagany assignee.

4. `FamilyTodo/Stores/TaskStore.swift`
- Zmienic walidacje WIP:
  - `canMoveToNext(assigneeId:)` zwraca `false` dla `nil` przy statusie `.next`.
- Dodac jawny wynik walidacji (np. enum):
  - `.ok`
  - `.assigneeRequired`
  - `.wipLimitReached(current: Int, limit: Int)`
- `createTask` i `updateTask` zwracaja ten wynik (lub rzucaja typowany blad), zamiast polegania na `error` side effect.

5. `FamilyTodo/Stores/BacklogStore.swift`
- `promoteItemToTask` musi byc atomowe i jawne:
  - przyjmuje `assigneeId`
  - zwraca `PromotionResult` (`success`, `assigneeRequired`, `wipLimitReached`, `failed`)
  - usuwa `BacklogItem` **tylko po sukcesie** utworzenia taska.
- UI backlogu pokazuje inline banner przy blokadzie WIP.

6. `FamilyTodo/Views/BacklogView.swift`
- Dodac flow przydzialu przy promocji:
  - np. sheet "Assign to" (member picker) przed promocja do `NEXT`.
- `Add item` pozostaje inline per kategoria, ale stylowo zrownany z Shopping rapid-entry tokens (spacing, typography, icon sizing).

7. `FamilyTodo/Views/MoreView.swift`
- Usunac link i ekran `Rooms / Areas`.
- `SettingsView`: gwarantowany dolny odstęp (defensive), ale glowny fix to chowanie tab bara na detail.
- `RepetitiveTasksView`:
  - dla `Custom` pokazac realne pola (`Every N days`, `Stepper`/input).
  - walidacja i podglad "next run".

8. `FamilyTodo/Models/LegacyStubs.swift` / scheduler
- `ChoreScheduler` tworzy taski z:
  - `taskType = .recurring`
  - `recurringChoreId = chore.id`
  - `status = .backlog`
- `Custom` w v1: interpretacja jako "co N dni" (bez dodatkowych jednostek), zeby uniknac migracji modelu.

9. `codex-TODO.md`
- Docelowo zapisac ten plan jako single source dla tej iteracji (sekcje: P0/P1, DoD, test matrix, rollout).

## Implementation Steps (kolejnosc)
1. P0 UX blocker:
- Tab bar visibility preference + hide on detail screens.
- Weryfikacja, ze `Sign Out` nie nachodzi na dolne menu.

2. P0 Product consistency:
- Usunac `Add task` z `TasksView`.
- Wdrozyc backlog-only intake + promocja z assignee pickerem.

3. P0 WIP enforcement:
- Refactor `TaskStore` walidacji i `BacklogStore.promoteItemToTask`.
- Banner + blokada przy 4. tasku.

4. P1 Recurring:
- `Custom` frequency UI + walidacja.
- Scheduler tworzy recurring taski do `Tasks.Backlog` z powiazaniem `recurringChoreId`.

5. P1 Simplification:
- Usunac `Rooms/Areas` z More.
- Zostawic `areaId` technicznie w modelach (compat), bez UI.

6. P1 Visual polish:
- iOS26 glass transition refactor (GlassEffectContainer + glassEffectID + matchedGeometry).
- fallback iOS17-25 bez regresji.

7. Delivery:
- `pre-commit run -a`
- poprawki
- commit/push.

## Test Cases and Scenarios
1. `Settings_SignOutVisible_NoOverlap`
- wejscie More -> Settings; `Sign Out` w pelni widoczne i klikalne; tab bar ukryty na detail.

2. `TabBar_GlassTransition_iOS26`
- na root tabach widoczny plynny ruch "droplet" miedzy tabami, bez utraty hit-area.

3. `Tasks_NoDirectCreate`
- w `Tasks` brak przycisku tworzenia nowych taskow.

4. `Backlog_PromoteRequiresAssignee`
- promocja bez assignee blokowana z komunikatem.
- po wyborze assignee sukces tworzy task w `NEXT`.

5. `WIP_PerAssignee_Strict`
- przy 3 aktywnych taskach dla osoby:
  - 4. promocja do `NEXT` zablokowana
  - widoczny inline banner
  - BacklogItem nie znika.

6. `Recurring_CustomFrequency_Works`
- `Custom` umozliwia ustawienie `N`.
- scheduler generuje task wg interwalu.

7. `Recurring_TaskMetadata`
- wygenerowany task ma `taskType = .recurring` i `recurringChoreId`.

8. `More_NoAreasEntry`
- brak pozycji `Rooms/Areas` w More.

9. `AddItem_InlineConsistency`
- Shopping i Backlog maja spojny inline pattern dodawania (spojne spacing/typografia/hit area).

## Assumptions and Defaults
1. iOS target zostaje 17; pelny Liquid Glass transition wymagamy dla iOS26+.
2. WIP=3 to twarda regula produktowa per assignee.
3. `NEXT` bez assignee jest niedozwolone.
4. `Tasks.Backlog` pozostaje dla taskow systemowych/recurring; manualny intake tylko przez `Backlog` (kategorie).
5. `Rooms/Areas` usuwamy z produktu na UI, ale nie robimy teraz migracji usuwajacej stare pola z modeli.
6. `Custom` recurrence v1 = "co N dni" (minimalna, czytelna implementacja bez migracji).
7. Ten dokument jest docelowa trescia do `codex-TODO.md` w kroku implementacyjnym.
