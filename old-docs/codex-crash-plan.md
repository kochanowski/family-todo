# codex-crash-plan.md - Plan naprawy crasha startup (build 309)

## Summary
- Potwierdzony crash z `2026-02-25 20:25:30 +0100` (TestFlight, build `309`) pochodzi z `fatalError` w `SwiftDataContainerFactory.swift:143`, wywolanym po nieudanym fallbacku in-memory.
- Obecny recovery nadal ma hard-crash path; trzeba usunac wszystkie runtime `fatalError` z bootstrapu store i dodac tryb awaryjny, ktory zawsze uruchomi aplikacje.
- Plan jest 2-etapowy:
1. P0: crash-proof startup + diagnostyka przyczyny.
2. P1: naprawa wlasciwej przyczyny nieudanego `ModelContainer` in-memory (na podstawie diagnostyki modeli).

## Zakres i cele
1. Aplikacja nie moze juz crashowac podczas startu przy bledzie SwiftData.
2. Uzytkownik musi zobaczyc kontrolowany ekran awaryjny zamiast SIGTRAP.
3. Musimy zebrac wystarczajaca diagnostyke, by wskazac ktory model/schema powoduje failure.
4. Zachowac obecny flow cloud/local, jesli bootstrap sie powiedzie.

## Implementacja (decision-complete)

### P0 - Startup crash-proof (bez hard-crash)
1. Zmienic bootstrap w `SwiftDataContainerFactory`:
- Zachowac kroki:
1. persistent (URL jawny),
2. cleanup artefaktow + persistent retry,
3. in-memory full schema.
- Dodac krok 4:
4. emergency minimal container (`isStoredInMemoryOnly: true`) na schema awaryjnym (`StartupSentinel`).
- Usunac runtime `fatalError` dla `#if !CI`; `fatalError` zostaje tylko dla `#if CI` i tylko gdy nawet emergency container nie powstanie.

2. Dodac nowy model awaryjny:
- `@Model final class StartupSentinel { @Attribute(.unique) var id: UUID }`
- Plik: `FamilyTodo/Models/StartupSentinel.swift`.

3. Dodac tryb bootstrapu do wyniku factory:
- `enum StartupBootstrapState { case ready, emergency }`
- `struct BootstrapDiagnostics` z polami:
- `errorChain: [String]` (max 3 wpisy),
- `failingModelNames: [String]`,
- `timestampISO8601: String`,
- `recoveryMode: StoreRecoveryMode`.
- `ModelContainerBootstrapResult` rozszerzyc o:
- `bootstrapState`,
- `diagnostics`.

4. Dodac probe modeli przy failu full in-memory:
- Funkcja `probeModelsIndividually()`:
- iteruje po kazdym modelu z app schema,
- probuje `ModelContainer(for: Schema([ThatModel]), inMemoryOnly: true)`,
- zapisuje liste modeli, ktore failuja.
- Wynik trafia do `diagnostics.failingModelNames`.

5. Persist telemetry:
- `UserDefaults`:
- `lastStoreRecoveryEvent` (dotychczas),
- `lastStoreBootstrapDiagnostics` (JSON string).
- Logi `print("StoreRecovery: ...")` bez PII, z modelem i etapem bootstrapu.

### P0 - Integracja app shell
1. W `FamilyTodoApp`:
- Rozszerzyc stan launch:
- `startupMode: StartupBootstrapState`,
- `startupRecoveryMessage`,
- `startupDiagnostics`.
- Gdy `startupMode == .ready`:
- obecny flow bez zmian.
- Gdy `startupMode == .emergency`:
- render `StartupRecoveryView` (bez `RootView`, bez `.task` konfigurujacych store/sync/scheduler).

2. Dodac nowy widok `StartupRecoveryView`:
- Komunikat:
- "Wykryto problem lokalnej bazy danych. Aplikacja uruchomiona w trybie awaryjnym."
- Akcje:
- `Restart App` (instrukcja dla usera),
- `Reset Local Data` (ustawia flage `pendingStoreReset = true`; reset wykonywany przy nastepnym starcie),
- `Copy Diagnostics` (kopiuje skrot diagnostyki do schowka).
- Widok nie uzywa zadnych store'ow ani `@Query`.

3. Dodac flage resetu:
- `UserDefaults.pendingStoreReset`.
- Przy starcie, jesli flaga `true`, wykonac cleanup artefaktow przed pierwsza proba persistent i skasowac flage.

### P1 - Usuniecie rzeczywistej przyczyny model/schema failure
1. Na podstawie `failingModelNames` z TestFlight:
- wskazac konkretny model(y) niedzialajace w in-memory.
2. Dla wskazanego modelu:
- sprawdzic kompatybilnosc pol `@Model` z aktualnym runtime i migracja.
- jesli to breaking schema change, dodac jawny plan migracji/wersjonowania modelu.
3. Dodac test regresji dla konkretnego modelu, ktory failowal.

## Public APIs / typy do dodania lub zmiany
1. `SwiftDataContainerFactory`:
- `bootstrap(...) -> ModelContainerBootstrapResult` zwraca rozszerzony wynik (`bootstrapState`, `diagnostics`).
- `cleanupStoreArtifacts(...)` zostaje publiczne internal.
2. Nowe typy:
- `StartupBootstrapState`
- `BootstrapDiagnostics`
- `StartupSentinel` (`@Model`)
3. `FamilyTodoApp`:
- nowy stan launch gating (`ready` vs `emergency`) i separacja flow taskow startupowych.

## Testy i scenariusze akceptacyjne

### Unit
1. `test_bootstrap_success_returnsReadyNormal`
2. `test_bootstrap_persistentRetry_returnsStoreResetReady`
3. `test_bootstrap_fullInMemoryFail_returnsEmergencyNotCrash`
4. `test_probeModelsIndividually_collectsFailingModels`
5. `test_cleanup_removes_store_and_support_artifacts`
6. `test_pendingStoreReset_forces_cleanup_before_bootstrap`

### UI
1. Launch normal: app idzie do `RootView` (brak emergency view).
2. Launch z wymuszonym bootstrap failure (launch arg testowy): pojawia sie `StartupRecoveryView`.
3. `StartupRecoveryView` nie uruchamia taskow cloud/scheduler.
4. `Copy Diagnostics` dziala i nie crashuje.

### Manual / TestFlight
1. Build z fixem na `appleid-login`.
2. Uruchomienie na urzadzeniu, ktore crashowalo build `309`.
3. Oczekiwane:
- brak SIGTRAP,
- jesli bootstrap nadal failuje: emergency screen + diagnostyka zapisana w `UserDefaults`,
- jesli bootstrap dziala: normalny onboarding/main app.

## Rollout i operacje
1. Commit scope tylko:
- `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`
- `FamilyTodo/FamilyTodoApp.swift`
- `FamilyTodo/Views/StartupRecoveryView.swift`
- `FamilyTodo/Models/StartupSentinel.swift`
- `FamilyTodoTests/SwiftDataContainerFactoryTests.swift`
- `FamilyTodo.xcodeproj/project.pbxproj`
2. Nie commitowac `crash/*` (PII).
3. Push `appleid-login`.
4. Monitoring GHA co 2 min:
- `gh run list --limit 5`
- `gh run view <run_id> --json status,conclusion,jobs`
- przy failure: `gh run view <run_id> --log-failed`.

## Zalozenia i domyslne decyzje
1. Priorytet: zero crashy przy starcie ponad pelna funkcjonalnosc przy uszkodzonym store.
2. Emergency mode jest tymczasowy, ale produkcyjnie bezpieczny.
3. Automatyczny reset cache jest dozwolony.
4. Diagnostyka lokalna (`UserDefaults` + log) wystarczy do identyfikacji modelu winnego w P1.

## Uwagi po porownaniu z claude-crash-plan.md
1. Trafna obserwacja Claude:
- crash point w build `309` jest poprawnie zidentyfikowany (`fatalError` w fallbacku in-memory).

2. Ryzyko wysokie w planie Claude:
- propozycja usuniecia `CachedArea` i `CachedRecurringChore` z `appSchema` jest niebezpieczna bez dodatkowych zmian, bo modele sa nadal uzywane przez `RecurringChoreStore`, scheduler i `RepetitiveTasksView`.

3. Ryzyko wysokie w planie Claude:
- samo dodanie alertu dla `schemaFailure` nie wystarczy; bez launch gatingu aplikacja dalej uruchomi startup taski (store/sync/scheduler) i moze ponownie crashowac.

4. Co warto zachowac z planu Claude:
- rozszerzone logowanie bledow bootstrapu (`NSError.domain`, `code`, pelny opis) i utrwalenie diagnostyki w `UserDefaults`.

5. Decyzja do implementacji:
- trzymamy strategia z tego planu (`emergency mode` + `StartupRecoveryView` + `probeModelsIndividually`),
- elementy telemetryczne Claude dolaczamy jako uzupelnienie, ale bez usuwania modeli ze schema na slepo.
