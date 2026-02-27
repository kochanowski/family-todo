# AGENTS.md

Last updated: 2026-02-27

## 1) Cel dokumentu
Ten plik jest praktycznym source of truth dla decyzji produktowych i technicznych w repo.
Ma utrzymać spójny sposób pracy i ograniczyć regresje przy kolejnych iteracjach.

## 2) North Star produktu
HousePulse / FamilyTodo to domowe zarządzanie obowiązkami w modelu "home agile lite":
- minimum tarcia,
- jasna odpowiedzialność,
- współdzielenie w household,
- bez gamifikacji opartej o presję rankingu.

## 3) Decyzje produktowe

### 3.1 Backlog-first (Ideas-first)
- Intake zadań trafia do Ideas.
- Tasks to tab wykonawczy (NEXT / IDEAS / COMPLETED), nie inbox.
- Promote z Ideas do Tasks wspiera przypisanie i reguły wykonawcze.

### 3.2 Przypisania i WIP
- Wejście do NEXT wymaga assignee.
- WIP docelowo: max 3 aktywne taski per osoba.
- Obecnie część ścieżek nadal traktuje limit jako UX guidance.

### 3.3 Shopping semantics
- Checkbox po lewej oznacza kupione.
- Tap w tytuł = edycja.
- Recently Purchased:
- dedupe po normalized title,
- restore jednym tapem,
- po restore wpis znika z Recent,
- single delete i clear all są wspierane.

### 3.4 Household i sharing
- Jeden aktywny household per sesja.
- Flow create/join household jest częścią aktywnego onboarding/auth.
- More/Profile zawiera rename, leave, delete z guardrails roli.

### 3.5 Areas / Rooms
- Areas/Rooms są usunięte z głównego UX.
- `areaId` zostaje dla kompatybilności danych i schedulera.

## 4) Aktualna architektura

### 4.1 Shell i routing
- Native `TabView` (bez custom floating tab bara).
- Zakładki: Shopping, Tasks, Ideas, More.
- Routing launch state: onboarding -> auth -> householdSetup/mainApp.
- Deep-link invite jest deferred do momentu gotowej sesji.

### 4.2 Stores i data flow
- `ShoppingListStore`, `TaskStore`, `BacklogStore`, `MemberStore`, `HouseholdStore`, `RecurringChoreStore`.
- Wzorzec: cache-first (SwiftData), optimistic UI, sync cloud gdy `syncMode == .cloud`.

### 4.3 CloudKit
- Scope rozdzielony: owner private vs participant shared.
- Invite flow: link/QR/deep-link + `ShareAcceptanceCoordinator`.
- CKShare traktowany jako krytyczna ścieżka produkcyjna (TestFlight).

## 5) Session Learnings: CloudKit Share/Schema (2026-02-27)

### 5.1 Sygnatura błędu krytycznego
- `Cannot create new type cloudkit.share in production schema`
- kontekst: `createShare.modifyRecords`, `CKErrorDomain code=12`.

### 5.2 Root cause
- Brak systemowego typu `cloudkit.share` w Production.
- Początkowo brak także w Development.

### 5.3 Kluczowa różnica
- `cloudkit.share` to typ systemowy CloudKit.
- Nie pochodzi z `cloudkit/schema/housepulse-schema.json`.

### 5.4 Jednorazowy runbook bootstrap
1. Wejść do CloudKit Console -> Development -> Private Database.
2. `Act As iCloud Account`.
3. Utworzyć custom zone.
4. Zapisać root record typu `Household` w tej strefie.
5. `Share Record` (to tworzy `cloudkit.share` w Development).
6. `Stop Acting As`.
7. `Deploy Schema Changes...` z Development do Production.

### 5.5 Guardraile CI po tej sesji
- Schema gate weryfikuje także `cloudkit.share` w Production.
- `scripts/cloudkit/apply_schema.sh` obsługuje błąd:
- `invalid attempt to delete cloudkit managed record type`
- i przechodzi do walidacji kontraktu zamiast twardego faila w benign case.
- Parser eksportu normalizuje nazwy typów (bez false-negative przez cudzysłowy).

### 5.6 Szybka diagnostyka
- Podgląd statusu: `gh run list --limit 5`.
- Szczegóły: `gh run view <run_id> --json status,conclusion,jobs`.
- Tylko błędy: `gh run view <run_id> --log-failed`.
- Jeśli fail mówi o `cloudkit.share`, najpierw sprawdzić bootstrap Dev i deploy Dev->Prod.

## 6) CI/CD i branch policy

### 6.1 Workflows
- `.github/workflows/ios-ci.yml`: build + SwiftLint + schema gate + deploy.
- `.github/workflows/nightly.yml`: pełniejsze testy manual/nightly.

### 6.2 Branch policy (TestFlight deploy)
- Deploy TestFlight uruchamia się dla:
- `workflow_dispatch`,
- tagów `v*`,
- pushy na: `main`, `r4-features`, `appleid-login`, `features-and-testing`.
- Zasada: schema gate musi być green przed deployem TestFlight.

## 7) Zasady pracy w repo
1. Nie wracamy do custom floating tab bara.
2. Zmiany UX mają trzymać kontrakt `TabView` + theme/font.
3. Dla większych zmian: plan -> implementacja -> weryfikacja.
4. Domyślnie commitujemy tylko scope taska (chyba że prosisz o commit wszystkiego).
5. Nie cofamy cudzych zmian bez wyraźnej prośby.
6. Przy zmianach tylko w dokumentacji nie pushujemy bez wyraźnego polecenia.

## 8) Najważniejsze pliki
- App shell: `FamilyTodo/ContentView.swift`
- App entry: `FamilyTodo/FamilyTodoApp.swift`
- Theme: `FamilyTodo/Views/ThemeStore.swift`
- Shopping: `FamilyTodo/Views/ShoppingListView.swift`, `FamilyTodo/Stores/ShoppingListStore.swift`
- Tasks: `FamilyTodo/Views/TasksView.swift`, `FamilyTodo/Stores/TaskStore.swift`
- Ideas: `FamilyTodo/Views/BacklogView.swift`, `FamilyTodo/Stores/BacklogStore.swift`
- Household: `FamilyTodo/Stores/HouseholdStore.swift`, `FamilyTodo/Stores/MemberStore.swift`
- CloudKit manager: `FamilyTodo/Managers/CloudKitManager.swift`
- CI: `.github/workflows/ios-ci.yml`, `.github/workflows/cloudkit-schema.yml`

## 9) Dokumentacja operacyjna
- `STATUS.md` - aktualny status wdrożenia.
- `TODO.md` - aktywne i domknięte zadania.
- `docs/current/CLOUD_SYNC_PROFILES.md` - profile sync i schema gate.
- `docs/current/TESTING_CI_POLICY.md` - polityka testów i CI.

Jeśli ten plik przeczy aktualnemu kodowi, priorytet ma kod i najnowsze uzgodnienia produktowe.
