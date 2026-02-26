# Plan: Fix SwiftData Startup Crash (build 309)

## Context

Aplikacja HousePulse crashuje natychmiast po uruchomieniu (221ms od launch) na TestFlight build 309 (iPhone 15, iOS 26.2.1). Crash to `fatalError` w `SwiftDataContainerFactory.bootstrapForRuntime:143` — **wszystkie trzy** proby stworzenia ModelContainer zawiodly:

1. Persistent container (`HousePulse.store`) -> FAIL
2. Cleanup artefaktow + retry persistent -> FAIL
3. **In-memory fallback** -> FAIL -> `fatalError()`

Fakt, ze nawet in-memory container nie moze byc stworzony, wskazuje na **problem ze Schema**, nie z persistent store.

Commit `b193ec9` wprowadzil SwiftDataContainerFactory z triple-fallback, ale nie zmienil zadnych modeli — wiec root cause nadal istnieje.

## Root Cause Analysis

Schema zawiera 8 modeli, z czego 2 sa nieuzywanymi stubami:

| Model | Uzywany? | Sync metadata? |
|-------|----------|----------------|
| CachedTask | TAK | TAK |
| CachedMember | TAK | TAK |
| CachedShoppingItem | TAK | TAK |
| CachedBacklogCategory | TAK | TAK |
| CachedBacklogItem | TAK | TAK |
| CachedHousehold | TAK | **NIE** |
| CachedArea | **NIE (stub)** | **NIE** |
| CachedRecurringChore | **NIE (stub)** | **NIE** |

**Hipoteza glowna**: Modele legacy (CachedArea, CachedRecurringChore) lub niespojnosc schematu powoduje, ze SwiftData odrzuca Schema na poziomie walidacji — jeszcze przed dotknieciem jakichkolwiek danych. Aktualny blad jest tracony w `fatalError` — nie wiemy co dokladnie SwiftData mowi.

**Hipoteza dodatkowa**: Poprzedni build mogl miec inny schemat (np. zmienione properties w modelach), co powoduje migration failure. Ale to nie tlumaczy dlaczego in-memory tez failuje — chyba ze iOS 26.2.1 ma bug w SwiftData schema validation.

## Plan naprawy

### Krok 1: Zastap fatalError graceful fallback + diagnostyka

**Plik**: `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`

Zamiast `fatalError()` w linii 143:
- Zapisz dokladny error do `UserDefaults` (domena, kod, userInfo, opis)
- Zaloguj error via `print()` (widoczny w Xcode Organizer)
- Stworz **pusty container** z minimalnym schematem zamiast crasha
- Zwroc `ModelContainerBootstrapResult` z nowym recovery mode `.schemaFailure`
- Ustaw diagnosticMessage informujacy uzytkownika o krytycznym bledzie

Doda nowy case do `StoreRecoveryMode`:
```
case schemaFailure  // All container creation failed including in-memory
```

### Krok 2: Usun legacy modele z Schema

**Plik**: `FamilyTodo/FamilyTodoApp.swift` (linie 19-28)

Usun `CachedArea.self` i `CachedRecurringChore.self` z `appSchema`:
```swift
private static let appSchema = Schema([
    CachedTask.self,
    CachedMember.self,
    CachedShoppingItem.self,
    CachedBacklogCategory.self,
    CachedBacklogItem.self,
    CachedHousehold.self,
])
```

Te modele:
- Nie sa uzywane przez zaden Store ani View
- Nie maja sync metadata (niespojne z reszta)
- Planowane na Phase 5-6 (future)
- Klasy zostaja w `LegacyStubs.swift` — tylko wyrejestrowane ze Schema

### Krok 3: Cleanup UITestHelper

**Plik**: `FamilyTodo/FamilyTodoApp.swift` (linie 277-278)

Usun referencje do CachedArea i CachedRecurringChore z `clearAllData()`:
```swift
// Usun te dwie linie:
try context.delete(model: CachedArea.self)
try context.delete(model: CachedRecurringChore.self)
```

### Krok 4: Rozszerz error logging w recovery path

**Plik**: `FamilyTodo/Utilities/SwiftDataContainerFactory.swift`

W metodzie `persistRecoveryEvent`:
- Dodaj `NSError.domain`, `NSError.code`, `NSError.userInfo` do payload
- Dodaj schemat info (liczba modeli, nazwy)
- Dodaj wersje iOS

W kazdym `catch` bloku `bootstrapForRuntime` — loguj pelny error (nie skrocony).

### Krok 5: Dodaj recovery UI dla schemaFailure

**Plik**: `FamilyTodo/FamilyTodoApp.swift`

Rozszerz istniejacy `.alert("Recovery Complete", ...)` o obsluge nowego `.schemaFailure` mode:
- Pokaz alert z informacja o krytycznym bledzie
- Dodaj przycisk "Report Issue" (kopiuje diagnostyke do clipboard)
- Dodaj przycisk "Try Reset" (czysci store i restartuje)

## Pliki do modyfikacji

1. **`FamilyTodo/Utilities/SwiftDataContainerFactory.swift`** — zastap fatalError, rozszerz logging, nowy recovery mode
2. **`FamilyTodo/FamilyTodoApp.swift`** — usun legacy modele z schema, cleanup UITestHelper, recovery UI
3. **`FamilyTodo/Models/LegacyStubs.swift`** — BEZ ZMIAN (klasy zostaja, tylko nie sa w Schema)

## Bezpieczenstwo danych

- CloudKit jest source of truth — SwiftData to tylko cache (ADR-002)
- CachedArea/CachedRecurringChore nigdy nie mialy danych (puste stuby)
- Istniejace tabele w SQLite beda ignorowane (SwiftData nie kasuje tabel nie-w-schema)
- Najgorszy przypadek: utrata lokalnego cache -> CloudKit resync przy nastepnym uruchomieniu

## Weryfikacja

1. `pre-commit run --all-files` — musi przejsc
2. GitHub Actions CI — build + testy
3. TestFlight deploy -> cold start na urzadzeniu
4. Sprawdz ze guest mode dziala (seeding)
5. Sprawdz ze cloud mode dziala (Sign in with Apple -> sync)
6. Monitoruj crash reports w App Store Connect

---

## Porownanie z planem Codex (`codex-crash-plan.md`)

### Co Codex robi lepiej

1. **`probeModelsIndividually()`** — iteruje po kazdym modelu z schema, probuje stworzyc in-memory container dla kazdego z osobna, raportuje ktore modele failuja. Daje twarda diagnostyke zamiast zgadywania. Warto adoptowac.

2. **`StartupSentinel` model** — minimalny `@Model` z jednym polem UUID jako baza emergency containera. Bezpieczniejsze niz puste `Schema([])`, ktore moze miec edge-case'y w SwiftData.

3. **`pendingStoreReset` flag** — dobrze przemyslany flow: user tapuje "Reset" -> flaga w UserDefaults -> przy nastepnym starcie cleanup PRZED bootstrapem. Lepsze niz moje ogolne "Try Reset".

4. **Separacja P0/P1** — najpierw zagwarantuj ze app nie crashuje (P0), potem napraw root cause na podstawie twardych danych (P1). Metodologicznie czyste.

5. **Scenariusze testowe** — 6 unit testow + 4 UI scenariusze, dobrze zdefiniowane i konkretne.

### Czego brakuje w planie Codex

1. **Nie probuje naprawic root cause** — Codex traktuje problem jako "nie wiemy co zlamane, zbierzmy dane". Ale CachedArea i CachedRecurringChore to nieuzywane stuby bez sync metadata, niespojne z reszta schema. Ich usuniecie ze Schema jest bezpieczne i prawdopodobnie naprawi problem od razu. Codex tego w ogole nie proponuje.

2. **Nie czysci UITestHelper** — `clearAllData()` w `FamilyTodoApp.swift:277-278` referencjonuje `CachedArea.self` i `CachedRecurringChore.self`. Po wyrejestrowaniu ze schema te wywolania beda powodowac bledy w UI testach. Moj plan to adresuje.

3. **Overengineering** — 4 nowe typy (`StartupBootstrapState`, `BootstrapDiagnostics`, `StartupSentinel`, `StartupRecoveryView`) + nowy plik widoku to duzo nowego kodu na problem, ktory prawdopodobnie zniknie po usunieciu legacy modeli ze schema. Dodaje zlozonosc bez pewnosci ze bedzie potrzebna.

### Odpowiedz na uwagi Codexa (codex-crash-plan.md, sekcja "Uwagi")

**Uwaga 2 — "CachedArea/CachedRecurringChore sa uzywane"**: Codex ma racje. Zweryfikowalem kod:
- `RecurringChoreStore` (LegacyStubs.swift:357-470) to pelna implementacja z CRUD + CloudKit sync + FetchDescriptor<CachedRecurringChore>
- `ChoreScheduler` (LegacyStubs.swift:517-590) wywolywany przy kazdym starcie (FamilyTodoApp.swift:96) odpytuje CachedRecurringChore
- `AreaStore` (LegacyStubs.swift) uzywa FetchDescriptor<CachedArea>
- CLAUDE.md mowi "stub" ale kod to pelne implementacje (~200 linii)
- **Wycofuje Krok 2 i 3** z oryginalnego planu. Modele musza zostac w schema.

**Uwaga 3 — "launch gating potrzebny"**: Codex ma racje. Sam alert nie wystarczy. Bez gatingu `.task{}` blok odpali ChoreScheduler, CloudKit sync itd. na zlamanym containerze -> kolejne crashe. Adoptuje `StartupRecoveryView` + launch gating z planu Codex.

**Uwaga 5 — "overengineering"**: Wycofuje ten zarzut. Skoro modeli nie mozna usunac ze schema, crash-proof emergency mode z probeModelsIndividually() jest wlasciwym podejsciem.

### Optymalny plan (po korekcie)

Finalna strategia bazuje na planie Codex z uzupelnieniami telemetrycznymi Claude:
1. Zastap fatalError emergency containerem (StartupSentinel)
2. probeModelsIndividually() — zidentyfikuj zlamany model
3. Rozszerzone logowanie NSError (domain, code, userInfo) + persist do UserDefaults
4. Launch gating: ready -> RootView, emergency -> StartupRecoveryView (bez store'ow/schedulera)
5. pendingStoreReset flow: user tapuje Reset -> flaga -> cleanup przy nastepnym starcie
6. Schema pozostaje bez zmian (wszystkie 8 modeli)
