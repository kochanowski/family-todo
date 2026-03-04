# Plan FINAL: Naprawa bugów z `bugs-and-fixes.md` + błędy potwierdzone na screenshotach/wideo

## Summary
Plan obejmuje 6 punktów z [bugs-and-fixes.md](/home/wkochanowski/code/family-todo/bugs-and-fixes.md) oraz błąd widoczny na nagraniu: częsty rollback promocji z Ideas do Tasks.
Priorytet wykonania: najpierw CloudKit/shared-zone (bo blokuje poprawność danych), potem UI/UX i regresje.

## Zweryfikowane problemy (repo + media)
1. `SharedDB does not support Zone Wide queries` jest realny i wynika z query bez `zoneID` w shared scope w [CloudKitManager.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Managers/CloudKitManager.swift).
2. W `Tasks` aktywny widok renderuje sekcję `IDEAS` (regresja) w [TasksView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/TasksView.swift:277).
3. W `Ideas` strzałka promote jest widoczna także dla nieprzypisanych itemów w [BacklogView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/BacklogView.swift:886).
4. `Recently Purchased` nie jest w pełni tematyzowany fontami (szczególnie empty state/nav title) w [ShoppingListView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/ShoppingListView.swift:736).
5. `More`/`Profile` nie spełnia wymaganego UX (mały banner, rename przez osobny przycisk) w [MoreView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/MoreView.swift:13).
6. Wideo potwierdza też rollback promocji (`Couldn't remove item from Ideas. Promotion was rolled back.`), spójny z problemem CloudKit scope/zone.

## Decyzje zamknięte
1. CloudKit fix scope: `Robust zone context` (nie hotfix minimalny).
2. `Tasks > Active`: tylko `NEXT` (bez `IDEAS`, bez quick recently-done).
3. Display name policy: unikalny w obrębie household (hard validation).
4. To żądanie nadpisuje poprzednią politykę „Tasks zawiera IDEAS”; dokumentacja zostanie zaktualizowana.

## Zakres implementacji

### 1) CloudKit SharedDB: zone-aware query/read/delete (CRITICAL)
1. W [CloudKitManager.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Managers/CloudKitManager.swift) dodać wewnętrzny kontekst strefy dla aktywnego household:
2. `activeSharedZoneID` + cache `householdId -> zoneID` (persist w `UserDefaults`).
3. Każdy query w `participantShared` wykonywać przez `records(matching:inZoneWith:)`, nigdy zone-wide.
4. Dodać helper, który przy braku aktywnej strefy iteruje po dostępnych shared zones i wybiera tę dającą wyniki.
5. Przepiąć wszystkie `fetch*` i `fetchMemberByUserId` na nowy helper scoped.
6. `acceptShare(metadata:)` zapisuje `metadata.rootRecordID.zoneID` jako aktywną strefę household.
7. Operacje `record(for:)`, `deleteRecord(withID:)`, `CKRecord.Reference` dla shared scope budować z właściwym `zoneID` (koniec domyślnego `recordID(for:)` bez strefy).
8. Dodać bezpieczne logi diagnostyczne `CloudKitScope:` (scope, zoneName, operation, bez PII).
9. W [HouseholdStore.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Stores/HouseholdStore.swift) ustawiać/odtwarzać kontekst strefy przy `loadHousehold`, `joinHousehold`, `leaveCurrentHousehold`, `deleteCurrentHousehold`.

### 2) Display Name / Guest logic
1. W [UserSession.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Services/UserSession.swift):
2. Guest default display name zawsze `Guest`.
3. Dodać `preferredDisplayName` (persist), `hasConfirmedDisplayName`, `needsDisplayNamePrompt`.
4. Dla signed-in: `displayName` = confirmed nickname > Apple payload > fallback.
5. Dodać walidator `DisplayNameValidator` (trim/collapse, długość, dozwolone znaki, normalized key).
6. W [SignInView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/SignInView.swift) dodać obowiązkowy prompt nickname po udanym Apple sign-in (zanim user pójdzie dalej).
7. W [CreateHouseholdView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/Onboarding/CreateHouseholdView.swift) usunąć fallback `"Me"`; create/join używają potwierdzonego nickname.
8. W [HouseholdStore.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Stores/HouseholdStore.swift) dodać hard check unikalności nickname w household przy join/upsert (błąd domenowy przy duplikacie).
9. W [MemberStore.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Stores/MemberStore.swift) przy edit name też wymusić household-unique.

### 3) Household creation + More redesign + inline rename
1. Dodać ikonę household do modelu:
2. [Household.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Models/Household.swift): `iconSymbol: String?` (default `nil`).
3. [CachedHousehold.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Models/CachedHousehold.swift): analogiczne pole + mapowania.
4. [CloudKitManager+Mapping.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Managers/CloudKitManager+Mapping.swift): mapowanie `iconSymbol` do rekordu.
5. W [CreateHouseholdView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/Onboarding/CreateHouseholdView.swift) dodać picker 5 ikon: `house.fill`, `star.fill`, `heart.fill`, `leaf.fill`, `pawprint.fill`.
6. W [HouseholdStore.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Stores/HouseholdStore.swift) rozszerzyć `createHousehold` o `iconSymbol`.
7. W [MoreView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/MoreView.swift) zastąpić mały banner dużym, wycentrowanym hero header:
8. ikona household na górze, nazwa household centralnie, premium spacing, cały header klikalny do `Profile`.
9. W `ProfileView` usunąć przycisk `Rename Household` i w sekcji household dodać inline `TextField` z zapisem onSubmit/debounce.

### 4) Recently Purchased font fix
1. W `RestockSheet` w [ShoppingListView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/ShoppingListView.swift:736):
2. zastąpić goły `ContentUnavailableView` własnym themed empty state (wszystkie teksty przez `themeStore.font(...)`).
3. dodać themed tytuł paska (`ToolbarItem(.principal)`).
4. dopiąć font tokeny dla listy/sekcji i sprawdzić Retro/Paper.
5. zachować bieżące akcje: restore/delete/clear all.

### 5) Regression: usunięcie Ideas z Tasks
1. W [TasksView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/TasksView.swift):
2. usunąć sekcję `IDEAS` z `activeTasksContent`.
3. usunąć `recentlyDoneTasks` z widoku `Active`.
4. `Active` pokazuje tylko `nextTasks`; `Completed` pokazuje `doneTasks`.
5. pozostawić demote `Move to Ideas` jako akcję dla tasków aktywnych (przeniesienie do Ideas tab).

### 6) Progressive disclosure w Ideas
1. W [BacklogView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/BacklogView.swift):
2. `BacklogItemRow`: strzałka promote widoczna tylko gdy `item.assigneeId != nil`.
3. dodać animację pojawiania `transition(.opacity.combined(with: .scale))`.
4. ukryć też leading swipe `Promote` gdy brak assignee (spójność UI i gestów).
5. zostawić tylko `Assign (+)` i `Trash` dla nieprzypisanych.

## Public API / interfejsy / typy do zmiany
1. `CloudKitManager`:
2. nowe wewnętrzne API do zone-scoped query (`recordsMatchingScoped`, `resolveSharedZones`, context set/get).
3. zone-aware budowanie `CKRecord.ID` i `CKRecord.Reference` dla shared scope.
4. `Household` i `CachedHousehold`: nowe pole `iconSymbol`.
5. `HouseholdStore.createHousehold(...)`: nowy parametr `iconSymbol`.
6. `HouseholdError`: nowy case `displayNameAlreadyTaken`.
7. `UserSession`: nowe pola/metody dot. confirmed nickname (`preferredDisplayName`, `needsDisplayNamePrompt`, setter).
8. Nowy util `DisplayNameValidator` (normalizacja + walidacja + uniqueness key).

## Testy i scenariusze akceptacyjne

### Unit tests
1. `CloudKitManagerSharedScopeTests`:
2. shared DB query idzie przez `inZoneWith`, bez zone-wide.
3. zone context zapisuje się po `acceptShare`.
4. read/delete w shared scope używa właściwego zone ID.
5. `HouseholdStoreTests`:
6. join/leave participant nie rzuca `SharedDB does not support Zone Wide queries`.
7. duplicate nickname w household zwraca `displayNameAlreadyTaken`.
8. `TasksView/TaskStore` tests:
9. active view nie zawiera backlog/IDEAS/recently-done.
10. `BacklogViewTests`:
11. promote icon ukryty bez assignee, widoczny po przypisaniu.
12. `ShoppingListViewTests`:
13. empty state w `RestockSheet` używa tokenów fontów theme.
14. `UserSessionTests`:
15. guest default name = `Guest`, signed-in prompt requirement działa.

### UI tests
1. Profile: inline rename działa bez przycisku rename.
2. Create household: wybór ikony + zapis + render ikony w More hero.
3. Tasks Active: tylko Active Tasks.
4. Ideas: strzałka promote pojawia się dopiero po assign.
5. Shared household member actions: brak alertu `SharedDB does not support Zone Wide queries`.
6. Sign-in flow: po Apple loginie pojawia się prompt nickname.

### Manual / TestFlight
1. Scenariusz ze screenshotu „Action failed: SharedDB…” nie występuje.
2. Scenariusz z wideo „Promotion was rolled back” nie występuje przy normalnym promote.
3. Retro/Paper: `Recently Purchased` ma poprawną typografię.
4. More: duży wycentrowany household header z ikoną.
5. Guest: nadal działa lokalnie, nazwa `Guest` jest spójna.

## Rollout
1. Commit A: CloudKit zone context + shared queries/read/delete.
2. Commit B: display-name pipeline + walidacja uniqueness.
3. Commit C: household icon data model + create flow.
4. Commit D: More hero + Profile inline rename.
5. Commit E: Tasks regression fix + Ideas progressive disclosure.
6. Commit F: Recently Purchased typography + testy.
7. Po każdym commicie: uruchomienie testów unit/UI dotkniętego obszaru.
8. Na końcu: aktualizacja dokumentacji produktu (zmiana polityki Tasks bez IDEAS).

## Założenia i defaulty
1. Priorytet danych: poprawność CloudKit/shared zone ponad szybkie UI fixy.
2. W projekcie obowiązuje 1 aktywny household na sesję.
3. `Tasks` i `Ideas` są rozdzielone: Active/Completed wyłącznie w Tasks.
4. Display name w household ma być unikalny (hard rule).
5. Brak automatycznej telemetrii PII; logi techniczne zostają lokalne/debug-safe.
