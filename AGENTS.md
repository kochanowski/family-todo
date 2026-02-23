# CLAUDE.md

Last updated: 2026-02-17

## 1) Cel dokumentu
Ten plik jest praktycznym **source of truth** dla decyzji produktowych i technicznych w tym repo.
Ma pomagać wdrażać zmiany spójnie, bez cofania się do starych koncepcji.

## 2) North Star produktu
**HousePulse / FamilyTodo** to domowe zarządzanie obowiązkami w modelu „home agile lite”:
- minimum tarcia,
- jasna odpowiedzialność,
- współdzielenie w household,
- bez gamifikacji opartej o ranking/presję.

## 3) Decyzje produktowe, których się trzymamy

### 3.1 Backlog-first (Ideas-first)
- Intake zadań jest w **Ideas** (dawny Backlog).
- **Tasks** to tab wykonawczy (`NEXT`, `IDEAS`, `COMPLETED`), nie miejsce do „wrzucania wszystkiego od zera”.
- Promocja `Ideas -> Tasks` ma wspierać przypisanie i reguły wykonawcze.

### 3.2 Przypisania i WIP
- Wejście do `NEXT` wymaga assignee.
- Docelowa reguła produktu: max 3 aktywne taski per osoba.
- W kodzie jest już infrastruktura walidacji (`NextTransitionValidation`), ale obecnie limit 3 działa głównie jako UX guidance (soft), nie pełny hard-block we wszystkich ścieżkach.

### 3.3 Shopping semantics
- Tap w checkbox po lewej = oznacz kupione.
- Tap w tytuł = edycja itemu.
- `Recently Purchased`:
  - dedupe po normalized title,
  - restore jednym tapem,
  - po restore wpis znika z Recent,
  - single delete i clear all są wspierane.

### 3.4 Household i sharing
- Jeden aktywny household per sesja.
- Onboarding ma pełny flow create/join (invite code).
- More/Profile ma akcje household: rename, leave, delete (z guardrails roli).

### 3.5 Areas / Rooms
- Z poziomu produktu Areas/Rooms są usunięte z głównego flow.
- Pola/model `areaId` zostały dla kompatybilności danych i schedulera.

## 4) Aktualna architektura aplikacji (stan kodu)

### 4.1 Shell i nawigacja
- Główny shell jest na **native `TabView`**, nie custom floating tab bar.
- `AppTab`: `Shopping`, `Tasks`, `Ideas` (backlog), `More`.
- `ContentView`:
  - iOS 18+: nowy styl `Tab(...)` API,
  - starsze iOS: klasyczny `tabItem` fallback.
- iOS 26+ korzysta z natywnych systemowych przejść (Liquid Glass behavior od systemu).

### 4.2 Stores (offline-first + cache + cloud)
- `ShoppingListStore`
- `TaskStore`
- `BacklogStore`
- `MemberStore`
- `HouseholdStore`
- `RecurringChoreStore` (obecnie w `LegacyStubs.swift`, ale działa runtime)

Wzorzec wspólny:
1. cache first (SwiftData),
2. optimistic UI,
3. sync z CloudKit jeśli `syncMode == .cloud`.

### 4.3 Sync profiles
- `preview-local`: CloudKit OFF (domyślnie w CI build path i szybkim preview).
- `sync-enabled`: CloudKit ON (manual/nightly testy share/sync).

## 5) Theme/typography system

### 5.1 Unified themes
- `system` (light/dark/auto)
- `retro`
- `paper`

`ThemeStore` jest źródłem:
- kolorów,
- tokenów fontów (`ThemeFontToken`),
- tab tint,
- ustawień celebracji.

### 5.2 Font pipeline
- Fonty w bundle: `PressStart2P`, `SpecialElite`, `CaveatBrush` (reserved).
- Runtime rejestracja przez `FontRegistrar` (`CTFontManagerRegisterFontsForURL`).
- `ThemeStore` robi audit (`verifyBundledFonts` + log mapy fontów).

### 5.3 Tab bar typography
- `TabBarTypographyManager` ustawia tylko `titleTextAttributes` (UIKit appearance).
- Nie ingerujemy w tło/blur tab bara, żeby nie psuć natywnego wyglądu i zachowania systemu.

## 6) UI/UX implementacja kluczowych ekranów

### 6.1 Shopping
- Rapid entry z custom accessory `Done`.
- Floating CTA `Add item` (metryki z `AppChromeMetrics`).
- Recently Purchased jako sheet z restore/delete/clear all.

### 6.2 Tasks
- Sekcje: `NEXT`, `IDEAS`, `COMPLETED`.
- Detail sheet dla taska.
- Start z IDEAS prowadzi przez walidację assignee.

### 6.3 Ideas (Backlog)
- Kategorie + itemy.
- Item ma jawne akcje: edit/assign/promote/delete.
- Przypisanie (`assigneeId`) jest trwałe (model + cache + CloudKit mapping).
- Promote ma rollback przy partial failure (nie zostawia trwałych duplikatów).

### 6.4 More
- Profile (household actions + member management).
- Idea Categories management.
- Repetitive Tasks management.
- Settings (theme, notifications, sign out).

## 7) Repetitive tasks (aktualna semantyka)
- CRUD w `RepetitiveTasksView`.
- Frequencies: daily/weekly/monthly/custom (Every N days).
- Scheduler (`ChoreScheduler`) generuje taski do `status = .backlog`.
- Wygenerowane taski pojawiają się w Tasks sekcji `IDEAS`.

## 8) Celebrations
- `CelebrationOverlay` jest odsprzęgnięty od `EnvironmentObject ThemeStore`.
- Dependencies są przekazywane jawnie z roota (`messageFont`, `accentPalette`).
- Konfetti: blast z dołu, ~90 cząstek, szersza paleta.

## 9) CI/CD i branch policy

### 9.1 Workflows
- `.github/workflows/ios-ci.yml`:
  - push: `main`, `develop`, `rebuild/swiftui-clean-impl`, `feature/continue-mvp`, `r4-features`
  - PR: `main`, `develop`
  - jobs: build + swiftlint (testy na tym workflow są wyłączone)
- `.github/workflows/nightly.yml`:
  - nightly/manual pełne testy

### 9.2 TestFlight deploy
`deploy-testflight` uruchamia się dla:
- `workflow_dispatch`,
- tagów `v*`,
- pushy na `main` lub `r4-features`.

Wniosek: push na inne branche nie wypchnie automatycznie do TestFlight.

## 10) Zasady pracy w repo

1. Nie wracamy do custom floating tab bara.
2. Zmiany UX muszą respektować `TabView` i obecny kontrakt theme/font.
3. Dla większych zmian:
   - najpierw spójny plan,
   - potem implementacja,
   - na końcu `pre-commit`.
4. Domyślnie commitujemy tylko scope taska (chyba że prosisz explicite o commit wszystkich zmian).
5. Nie cofamy cudzych zmian bez wyraźnej prośby.
6. Przy zmianach tylko w dokumentacji (`*.md`) domyślnie **nie robimy push**; push dopiero po wyraźnym poleceniu.

## 11) Known gaps (do domknięcia)
1. Retro font nadal może fallbackować na części urządzeń/buildów (weryfikacja runtime registration + packaging path).
2. WIP=3 nie jest jeszcze twardo egzekwowany wszędzie.
3. Sign Out w Settings potrafi nachodzić na dolny chrome w niektórych konfiguracjach.
4. Glass quality/tab transition zależy od natywnego system behavior i wymaga dalszego strojenia bez overdraw/blur regressions.

## 12) Najważniejsze pliki (quick map)
- App shell: `FamilyTodo/ContentView.swift`
- App entry: `FamilyTodo/FamilyTodoApp.swift`
- Theme: `FamilyTodo/Views/ThemeStore.swift`
- Font registration: `FamilyTodo/Utilities/FontRegistrar.swift`
- Tab bar typography: `FamilyTodo/Utilities/TabBarTypographyManager.swift`
- Shopping: `FamilyTodo/Views/ShoppingListView.swift`, `FamilyTodo/Stores/ShoppingListStore.swift`
- Tasks: `FamilyTodo/Views/TasksView.swift`, `FamilyTodo/Stores/TaskStore.swift`
- Ideas/Backlog: `FamilyTodo/Views/BacklogView.swift`, `FamilyTodo/Stores/BacklogStore.swift`
- More/Settings: `FamilyTodo/Views/MoreView.swift`
- Household: `FamilyTodo/Stores/HouseholdStore.swift`, `FamilyTodo/Stores/MemberStore.swift`
- Recurring/Scheduler: `FamilyTodo/Models/LegacyStubs.swift`
- CI: `.github/workflows/ios-ci.yml`, `.github/workflows/nightly.yml`

## 13) Dokumentacja operacyjna
- `STATUS.md` — krótki status wdrożenia
- `docs/current/ROADMAP.md` — plan dalszych etapów
- `docs/current/TESTING_CI_POLICY.md` — polityka testów i profile CI
- `docs/current/CLOUD_SYNC_PROFILES.md` — profile sync

---
Jeśli ten plik przeczy decyzjom z aktualnego kodu, priorytet ma kod + najnowsze ustalenia produktowe.
