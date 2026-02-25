# Final TODO (branch: `feature/continue-mvp`)

## Decyzja
Tak, oplaca sie tworzyc nowe pliki i etapowo przebudowac projekt, ale **bez jednorazowego "big-bang" refactoru**.

Powod:
1. `LegacyStubs.swift` i `MoreView.swift` sa zbyt duze i mieszaja wiele odpowiedzialnosci.
2. Przy braku lokalnego `xcodebuild` bezpieczniej i szybciej jest robic male, weryfikowalne kroki.
3. Obecny branch ma juz duzo zmian funkcjonalnych, wiec priorytetem jest stabilizacja i przewidywalny merge.

## Stan po tej iteracji
1. Naprawione krytyczne bledy skladni/formatu po ostatnich zmianach:
   - `SortDescriptor(\.sortOrder)` i `SortDescriptor(\.updatedAt, order: .reverse)` w `LegacyStubs`.
   - poprawki type-sugar i formatowania w `TasksView`.
   - poprawki formatowania w `ShoppingListView`.
2. `pre-commit` przechodzi (`Passed` dla wszystkich hookow).

## Plan wykonawczy (nastepne kroki)

### P0 Stabilizacja (bez zmiany architektury)
1. Reczna walidacja flow:
   - Session bootstrap + guided empty states.
   - Sign out/reset sesji.
   - Join household z onboardingu.
2. Dopiecie testow store:
   - `HouseholdStore`, `MemberStore`, `BacklogStore`, `TaskStore`.
3. Dopiecie brakujacych testow regresji UI smoke.

### P1 Refactor na nowe pliki (etapowy)
1. Rozbicie `LegacyStubs.swift`:
   - `Models/Area.swift`
   - `Models/RecurringChore.swift`
   - `Models/CachedArea.swift`
   - `Models/CachedRecurringChore.swift`
   - `Stores/AreaStore.swift`
   - `Stores/RecurringChoreStore.swift`
   - `Stores/NotificationSettingsStore.swift`
   - `Services/ChoreScheduler.swift`
2. Rozbicie `MoreView.swift`:
   - `Views/More/ProfileView.swift`
   - `Views/More/CategoriesManagementView.swift`
   - `Views/More/RepetitiveTasksView.swift`
   - `Views/More/AreasManagementView.swift`
   - `Views/More/SettingsView.swift`
3. Kazdy krok konczyc:
   - `swiftformat`,
   - `pre-commit run -a`,
   - maly commit.

### P1 UX/Polish
1. Domkniecie glass transition tab bara na iOS 26+ (jedna ruchoma warstwa, bez glass-on-glass).
2. Ujednolicenie metryk CTA (`Add item`, `Add task`, `Done`) przez `AppChromeMetrics`.
3. Finalne dopiecie hit-area i keyboard/chrome behavior na iPhonie.

## Definition of Done dla brancha
1. Wszystkie P0 flow dzialaja end-to-end.
2. Refactor P1 jest wykonany malymi commitami bez regresji.
3. `pre-commit` i CI build sa zielone.
