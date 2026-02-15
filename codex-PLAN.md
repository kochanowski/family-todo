# Plan Implementacji: HousePulse Full Flow (Tasks, Backlog, More/Settings, Household & Invite)

## Summary
1. Na podstawie aktualnego kodu: Shopping jest prawie kompletne, ale pełny produkt nadal blokują luki w Tasks, Backlog↔More, Household/Invite i Settings.
2. Kluczowe braki: `CreateHouseholdView.joinHousehold()` jest TODO, `CategoriesManagementView` działa tylko lokalnie, `RepetitiveTasksView` to placeholder, `SettingsView` nie ma realnego sign out, a walidacje ról w `MemberStore` są niewymuszone.
3. Plan docelowy: domknąć pełny flow użytkownika od onboardingu i stworzenia/dołączenia household, przez codzienną pracę na Tasks/Backlog, po zarządzanie household i ustawieniami.
4. W tym trybie plan jest dostarczony inline; docelowy artefakt do zapisania: `codex-TODO.md`.

## Important API / Interface Changes
1. `FamilyTodo/Stores/HouseholdStore.swift`
- Dodać:
`renameCurrentHousehold(_:)`
`leaveCurrentHousehold(userId:)`
`deleteCurrentHousehold(requestedBy:)`
`loadCurrentHouseholdAndMembership(userId:)`
- Doprecyzować `joinHousehold(inviteCode:userId:displayName:)` o walidację błędów i pełny refresh danych po dołączeniu.
2. `FamilyTodo/Stores/MemberStore.swift`
- Wymusić reguły ról:
tylko owner może zmieniać role i usuwać członków,
zawsze minimum 1 owner,
brak możliwości usunięcia samego siebie bez przekazania ownership.
3. `FamilyTodo/Stores/TaskStore.swift`
- Rozszerzyć API edycji:
`createTask(...)` już jest, dodać pełny edit contract dla assignee/dueDate/notes/status z walidacją WIP.
- Dodać operację promo z backlogu:
`createTaskFromBacklogItem(...)`.
4. `FamilyTodo/Stores/BacklogStore.swift`
- Dodać:
`renameCategory(...)`
`reorderCategories(...)`
`updateItem(...)`
`promoteItemToTask(...)`.
5. `FamilyTodo/Stores/RecurringChoreStore.swift` (nowy)
- CRUD dla cyklicznych zadań + wyliczanie `nextScheduledDate`.
6. `FamilyTodo/Views/MoreView.swift`
- `CategoriesManagementView` przepiąć na `BacklogStore` (usunąć lokalne `@State [String]`).
- `RepetitiveTasksView` zastąpić realnym managerem recurring tasks.
- `SettingsView` podpiąć pod realne akcje sesji i notyfikacji.
7. `FamilyTodo/Views/Onboarding/CreateHouseholdView.swift`
- Implementacja realnego join flow z kodem zaproszenia.
8. `FamilyTodo/FamilyTodoApp.swift`
- Rozszerzyć schema o `CachedRecurringChore` (i opcjonalnie `CachedArea`, jeśli Areas wejdą do scope).
9. `FamilyTodo/Views/Components/FloatingTabBar.swift`
- Domknąć widoczny glass transition (jedna ruchoma warstwa indicatora, iOS 26 path bez tłumiących warstw nad glass).

## Implementation Plan

## Faza 0: Spójny stan sesji i household (P0)
1. Ujednolicić bootstrap stanu household:
- `RootView`/`ContentView` ma zawsze jeden punkt prawdy: `UserSession.currentHouseholdID`.
- Po zalogowaniu lub starcie guest: `HouseholdStore.loadCurrentHouseholdAndMembership(userId:)`.
2. Zastąpić rozproszone fallbacki “No Household Selected” przez `GuidedEmptyStateView` w:
`FamilyTodo/Views/ShoppingListView.swift`
`FamilyTodo/Views/TasksView.swift`
`FamilyTodo/Views/BacklogView.swift`.
3. Usunąć funkcjonalne duplikaty onboardingu:
- `FamilyTodo/Views/OnboardingView.swift` jest legacy i nie jest używany przez `RootView`; przenieść do docs/legacy planu lub usunąć po potwierdzeniu.

## Faza 1: Full flow Tasks (P0)
1. Dodać `TaskDetailSheet`:
- edycja `title`, `status`, `assignee`, `dueDate`, `notes`.
- szybki toggle done zostaje na checkboxie, ale tap w treść wiersza otwiera detail.
2. W `TasksView`:
- sekcje: Next, Backlog, Done (obecnie UI skupia się na Next/Done).
- badge assignee i due-date (today/overdue) w wierszu.
3. Wymusić WIP=3 w całym flow:
- tworzenie,
- edycja statusu do `.next`,
- promocja z backlogu.
4. Notyfikacje:
- permission request dopiero przy ustawieniu due date albo aktywacji digest/suggestions.

## Faza 2: Full flow Backlog (P0)
1. Utrzymać category-first model:
- item zawsze należy do kategorii.
2. Dodać pełne operacje:
- rename category,
- reorder categories,
- edycja itemu (title/notes),
- usuwanie itemu,
- confirm kasowania kategorii z itemami (już częściowo jest, trzeba utrzymać też w More).
3. Dodać flow “Promote to Task”:
- swipe action na backlog item,
- tworzy task (domyślnie `.backlog` lub `.next` wg decyzji UX; default: `.next` jeśli WIP pozwala, inaczej `.backlog`),
- usuwa/promuje item z backlogu.

## Faza 3: More i Settings jako realne centrum aplikacji (P0)
1. `More > Backlog Categories`:
- przepięcie na `BacklogStore` danego `householdId`, zero lokalnego stanu.
- pełny sync z zakładką Backlog.
2. `More > Repetitive Tasks`:
- wdrożenie widoku listy recurring chores + Add/Edit sheet.
3. `More > Profile`:
- household name,
- member list,
- wejście do `MemberManagementView`,
- akcje ownera: invite, rename household, transfer ownership, remove member.
4. `More > Settings`:
- Appearance: zostaje.
- Toggles: celebrations/suggestions zostają, ale podpięte do trwałej konfiguracji.
- Notifications sekcja: task reminders, digest, sound.
- Sign out: realne wywołanie `userSession.signOut()` + reset household selection + cleanup subscriptions.

## Faza 4: Shared household + invitation end-to-end (P0)
1. Owner flow:
- create household,
- open invite (`ShareInviteView`),
- wysyła link/kod.
2. Joiner flow:
- `CreateHouseholdView` join sheet realnie wywołuje `householdStore.joinHousehold(...)`.
- Po sukcesie:
`userSession.setCurrentHousehold(...)`,
zamknięcie onboardingu,
pełny reload stores.
3. Membership consistency:
- po join/load członkowie i role są odświeżane z cloud/cache.
4. Error UX:
- invalid invite code,
- cloud disabled (`HPCloudKitEnabled=NO`),
- notAuthenticated,
- network failure.
- Każdy przypadek z czytelnym komunikatem i recovery action.

## Faza 5: Recurring chores i automatyzacja (P1)
1. Dodać `RecurringChoreStore` + cache + sync.
2. Wdrożyć generator cyklicznych tasków:
- uruchamiany przy app foreground/launch,
- tworzy taski po `nextScheduledDate`,
- aktualizuje `lastGeneratedDate` i kolejny termin.
3. Powiązać task z recurring source (`Task.recurringChoreId` już istnieje).

## Faza 6: UX polish i stabilność interakcji (P1)
1. Tab bar:
- finalny glass transition na iOS 26+,
- fallback material na iOS 17-25,
- jednolity hit-area i brak nakładania z CTA/keyboard.
2. Keyboard/chrome:
- przy aktywnej klawiaturze chowamy floating tab bar + CTA (zachowanie natywne iOS).
3. Accessibility:
- pełne `accessibilityIdentifier` dla kluczowych flow (invite, member role change, recurring CRUD, backlog promote).

## Faza 7: Testy i release gate (P0/P1)
1. Unit tests:
- `HouseholdStore`: create/join/rename/leave/delete.
- `MemberStore`: role guardrails.
- `TaskStore`: WIP + backlog promotion.
- `BacklogStore`: reorder/rename/promotion.
- `RecurringChoreStore`: schedule calculations.
2. UI tests:
- onboarding create/join,
- invite flow (w trybie cloud-enabled lane),
- tasks full CRUD + due date + assignee,
- backlog categories management z More i Backlog consistency,
- settings sign out.
3. CI:
- PR: build+lint (jak obecnie).
- Nightly/manual: pełne testy, plus lane `sync-enabled` dla household sharing.
- Regression gate: brak merge jeśli E2E household/invite fail.

## Proponowane funkcje “ciekawe dla użytkownika” (P2)
1. “Weekly Home Pulse”:
- neutralny, nie-rywalizacyjny tygodniowy digest: co zrobione, co czeka.
2. “Smart Restock Suggestions”:
- na podstawie częstotliwości `restockCount`, podpowiedzi przy tworzeniu listy.
3. “Backlog to Sprint”:
- jednym kliknięciem wybór 1-3 backlog itemów jako plan tygodnia.
4. Widgets:
- small: Next tasks,
- medium: Shopping To Buy.
5. Siri Shortcuts / App Intents:
- “Add milk to shopping list”, “What are my next tasks?”.

## Test Cases and Scenarios
1. `Onboarding_CreateHousehold_EndToEnd`
- onboarding -> sync choice -> create -> main app z aktywnym household.
2. `Onboarding_JoinHousehold_EndToEnd`
- onboarding -> join code -> household active -> data visible.
3. `InviteFlow_OwnerToMember`
- owner generuje share, drugi user dołącza, member pojawia się w `MemberStore`.
4. `Tasks_FullCRUD_WithWIP`
- create/edit/complete/reopen/delete + blokada >3 next.
5. `Backlog_FullCRUD_AndPromote`
- add/rename/reorder/delete category + add/edit/delete item + promote do task.
6. `More_CategoriesSync`
- zmiana kategorii w More widoczna natychmiast w Backlog.
7. `Settings_SignOut_AndSessionReset`
- sign out czyści household context i przenosi do sign-in/onboarding.
8. `RecurringChore_Generation`
- task generuje się przy osiągnięciu `nextScheduledDate`.
9. `TabBar_GlassAndHitArea`
- widoczna animacja glass i poprawne klikanie wszystkich tabów.
10. `Keyboard_ChromeBehavior`
- przy klawiaturze tab bar i CTA ukryte, brak overlapu.

## Assumptions and Defaults
1. iOS target zostaje 17; Liquid Glass tylko warunkowo dla iOS 26+.
2. Jednocześnie wspieramy tylko 1 aktywny household na sesję użytkownika (multi-household jako późniejsza rozbudowa).
3. Member delete to semantyka soft-deactivate (`isActive=false`) tam, gdzie potrzebna historia; hard delete tylko dla cleanup bez historii.
4. WIP limit 3 jest nienegocjowalny i obowiązuje wszystkie wejścia do statusu `next`.
5. Cloud sharing działa tylko przy `syncMode == .cloud`; guest mode ma jawny fallback i bez invite.
6. Zakres “fully działa” = pełne flow: onboarding + household/invite + tasks/backlog + more/settings + recurring basics + test gates.
