# Analiza planu: Household Onboarding & Carousel

## Wniosek glowny

**Plan jest w ~95% juz zaimplementowany.** Prawie kazdy komponent opisany w `household-onboarding-and-carousel.md` istnieje w kodzie i jest produkcyjnie gotowy. Ponizej szczegolowa mapa: plan vs rzeczywistosc.

---

## Status implementacji: Plan vs Kod

### Part 1: Onboarding Carousel — ZAIMPLEMENTOWANE

| Element z planu | Status | Plik |
|----------------|--------|------|
| TabView z `.page` style | JEST | `OnboardingCarouselView.swift` |
| Slide 1: "Smart Shopping" | JEST (inna tresc: "Sync your home") | j.w. |
| Slide 2: "Clear Your Mind" | JEST (inna tresc: "Never forget the milk") | j.w. |
| Slide 3: "Make It Yours" | JEST (inna tresc: "Dream together") | j.w. |
| Slide 4: "Better Together" | **BRAK** — carousel ma 3 slajdy, nie 4 | j.w. |
| SF Symbol ikony | JEST (cloud.fill, basket.fill, square.3.layers.3d) | j.w. |
| Przycisk "Skip" | **BRAK** — nie ma przycisku Skip | j.w. |
| Przycisk "Next" / "Get Started" | JEST — "Get Started" na ostatnim slajdzie | j.w. |
| `@AppStorage("hasSeenOnboarding")` | JEST — w `OnboardingState.swift` (`hasCompletedOnboarding`) | `OnboardingState.swift` |
| Animowane tlo | JEST — Aurora z 3 paletami, orby, material overlay | `AuroraBackground.swift` (173 linii) |

**Roznice**: Tresci slajdow sa inne niz w planie (bardziej dopasowane do produktu). Brak 4. slajdu i przycisku "Skip".

### Part 2: Authentication & Guest Mode — ZAIMPLEMENTOWANE

| Element z planu | Status | Plik |
|----------------|--------|------|
| "Sign in with Apple" przycisk | JEST — natywny `ASAuthorizationAppleIDButton` | `SignInView.swift` (140 linii) |
| "Try without account" przycisk | JEST — "Continue without account" | j.w. |
| Guest → mainApp transition | JEST — przez `SyncSelectionView` | `SyncSelectionView.swift` (149 linii) |
| Guest upgrade banner w "More" | JEST — w `MoreView.swift` | `MoreView.swift` |
| Stany auth (loading, error, success) | JEST — switch po `authenticationState` | `SignInView.swift` |
| CloudKit user identity | JEST — `CKUserIdentity` fetch po auth | `AuthenticationService.swift` |

**Roznica architektoniczna**: Plan proponuje bezposrednia sciezke Auth → Guest → mainApp. Implementacja dodaje posredni krok `SyncSelectionView` (iCloud vs Guest), co jest lepsze UX-owo — user swiadomie wybiera tryb synchronizacji.

### Part 3: Household Setup — ZAIMPLEMENTOWANE

| Element z planu | Status | Plik |
|----------------|--------|------|
| Ekran "Let's set up your space" | JEST — `CreateHouseholdView` | `CreateHouseholdView.swift` (338 linii) |
| Karta "Create a Household" | JEST — TextField + przycisk Create | j.w. |
| Karta "Join a Household" | JEST — otwiera `CreateJoinSheet` | j.w. |
| Walidacja nazwy | JEST — disabled button gdy puste | j.w. |
| Guest mode support | JEST — pelne tworzenie lokalne | j.w. |

**Status**: Kompletne, wlacznie z obsuga guest mode i cloud mode.

### Part 4: Join Household — ZAIMPLEMENTOWANE

| Element z planu | Status | Plik |
|----------------|--------|------|
| QR Code scanner | JEST — AVFoundation, obsluga permisji | `QRCodeScannerView.swift` (135 linii) |
| TextField na invite code | JEST — w `CreateJoinSheet` | `CreateHouseholdView.swift` |
| Przycisk "Paste" | JEST — paste z clipboard | j.w. |
| `.onOpenURL` deep link | JEST — w `FamilyTodoApp.swift:131` | `FamilyTodoApp.swift` |
| Universal link handling | JEST — `ShareAcceptanceCoordinator` z kolejka | `ShareAcceptanceCoordinator.swift` (126 linii) |
| Normalizacja URL | JEST — `InviteInputNormalizer` + testy | `InviteInputNormalizer.swift` (59 linii) |
| CloudKit share acceptance | JEST — `AppDelegateBridge` delegate | `AppDelegateBridge.swift` (23 linii) |

**Status**: Kompletne. Implementacja jest nawet bogatsza niz plan — dodaje normalizacje URL, kolejke acceptance, i obsluge CloudKit metadata.

---

## Routing / State Machine — ZAIMPLEMENTOWANE

Plan proponuje `AppState` enum z 4 stanami. Implementacja ma dokladnie to:

```
OnboardingState.LaunchState:
  .onboarding    → OnboardingCarouselView
  .syncChoice    → SyncSelectionView (dodatkowy krok vs plan)
  .householdSetup → CreateHouseholdView / SignInView
  .mainApp       → ContentView → MainAppView
```

Dodatkowe feature'y ponad plan:
- **Persystencja stanu** — `@AppStorage` z resume logic (user moze wyjsc w polowie flow)
- **Haptic feedback** na tranzycjach
- **Animacje** `.transition(.opacity)` miedzy ekranami
- **ShareAcceptanceCoordinator** — kolejkuje zaproszenia i przetwarza gdy sesja gotowa

---

## Co jest do zrobienia (gap analysis)

### Drobne braki (nice-to-have, nie blokujace):

1. **4. slajd carouselu** — plan mowi o "Better Together" (person.2.fill). Implementacja ma 3 slajdy. Decyzja: dodac czy zostawic 3?

2. **Przycisk "Skip" w carouselu** — plan wymaga, implementacja go nie ma. Uzytkownik musi przejsc do ostatniego slajdu.

3. **Legacy `OnboardingView.swift`** — 244 linie nieuzywany plik (stary flow bez carouselu). Bezpieczny do usuniecia.

### Potencjalne ulepszenia:

4. **Error recovery w Join flow** — jesli join failuje, user musi zamknac sheet i otworzyc ponownie
5. **QR scan feedback** — brak haptycznego feedbacku po zeskanowaniu kodu
6. **Household preview** — przed dolaczeniem mozna by pokazac nazwe/liczbe czlonkow

---

## Podsumowanie

| Komponent | Plan | Implementacja | Delta |
|-----------|------|---------------|-------|
| Carousel (3-4 slajdy) | 4 slajdy + Skip | 3 slajdy, brak Skip | Drobna roznica |
| Auth (Apple + Guest) | 2 przyciski | 2 przyciski + stany error | Kompletne |
| Sync Selection | Brak w planie | Dodatkowy ekran (lepszy UX) | Bonus |
| Household Create | TextField + Create | TextField + Create + Guest | Kompletne |
| Join (QR + Code + Link) | 3 metody | 3 metody + normalizacja + kolejka | Kompletne+ |
| State Machine | 4 stany | 4 stany + persystencja + resume | Kompletne+ |
| Deep Links | `.onOpenURL` | `.onOpenURL` + `AppDelegateBridge` + `ShareAcceptanceCoordinator` | Kompletne+ |

**Verdict**: Plan jest zrealizowany. Jedyne otwarte pytania to: czy dodac 4. slajd i przycisk Skip do carouselu. Reszta jest produkcyjnie gotowa i w wielu miejscach bogatsza niz plan zakladal.

---

# Uwagi Claude do planu Codex (`household-onboarding-and-carousel-codex.md`)

## Ogolna ocena

Plan Codex jest solidnym dokumentem implementacyjnym — konkretny, plik-po-pliku, z testami i rollout planem. Rozpoznaje istniejacy kod ("adaptacja, nie przepisywanie od zera"). Ponizej uwagi i korekty ktore poprawiaja dokladnosc i bezpieczenstwo zmian.

---

## Co Codex robi dobrze (vs moja analiza powyzej)

1. **Konkretny plan akcji** — zmiana po zmianie, plik po pliku, z testami. Moja analiza tylko identyfikowala luki, nie proponowala jak je naprawic.
2. **Architektoniczna decyzja o `syncChoice`** — proponuje usuniecie stanu `syncChoice` i zastapienie jawnym `auth`. Sluszne uproszczenie, bo `SyncSelectionView` de facto pelni role ekranu auth (iCloud = Apple Sign In, Guest = local).
3. **Guest upgrade banner** — wykryty brak w `MoreView` (potwierdzam — grep na MoreView nie znalazl zadnego bannera). Moja analiza blednie twierdzila "JEST".
4. **`housepulse://join/...` URL scheme** — nowy deep link dla invite bez iCloud. Moja analiza nie identyfikowala tego jako luke.
5. **Migracja `hasCompletedOnboarding` → `hasSeenOnboarding`** — Codex mysli o istniejacych uzytkownikach po update. Wazny edge case.
6. **Scenariusze testowe** — 5 unit testow + 8 UI testow + 4 manual QA.

---

## 1. Guest flow: odejscie od specyfikacji (ryzyko srednie)

**Plan Codex mowi**: Guest → `householdSetup` (sekcja 2, punkt 2).

**Oryginalny spec mowi** (`household-onboarding-and-carousel.md:29`):
> "Try without an account" → Sets user as a Guest and transitions directly to `mainApp`.

**Stan kodu**: `SyncSelectionView.swift:93` — guest wybiera "Continue as Guest", `startGuestSession()` + `selectSyncMethod(.local)` → bezposrednio `mainApp`. Household tworzy sie automatycznie w `HouseholdStore` przy seeding.

**Uwaga**: Wymuszenie householdSetup na gosciu zmienia UX. Guest traci benefit natychmiastowego wejscia do aplikacji z seedowanymi danymi. Jesli to celowa decyzja — wymaga jawnego uzasadnienia w planie. Jesli nie — guest powinien isc do `mainApp` jak w obecnym kodzie i oryginalnym spec.

**Rekomendacja**: Zachowac obecny flow guest → `mainApp` z auto-seedingiem. Alternatywnie: jesli chcemy wymusic nazwanie household, dodac lekki krok (just name input, nie pelny `CreateHouseholdView`).

---

## 2. Routing zyje w RootView, nie ContentView (blad w planie)

**Plan Codex mowi** (sekcja 3.1): zmiany w `ContentView.swift` — "Uproszczenie `ContentView` do roli shell `MainAppView` (bez routing decision)".

**Stan kodu**: Routing oparty o `onboardingState.currentState` jest w `RootView` (`FamilyTodoApp.swift:163-186`), NIE w `ContentView`. `ContentView` jest juz shell'em wyswietlajacym `MainAppView`.

```
RootView (FamilyTodoApp.swift:157-219):
  switch onboardingState.currentState
    .onboarding    -> OnboardingCarouselView
    .syncChoice    -> SyncSelectionView
    .householdSetup -> CreateHouseholdView / SignInView
    .mainApp       -> ContentView
```

Linia 175 ma dodatkowy warunek: `if userSession.hasActiveSession` decyduje czy pokazac `CreateHouseholdView` vs `SignInView` w stanie `.householdSetup`.

**Korekta**: Zmiany routingowe powinny byc w `RootView` (w `FamilyTodoApp.swift`), nie w `ContentView`. `ContentView` nie wymaga zmian.

---

## 3. Brak szczegolowej migracji OnboardingState transitions (ryzyko wysokie)

Plan mowi "usunac `syncChoice`" i "dodac `auth`", ale nie opisuje konkretnych zmian w metodach `OnboardingState`:

**Aktualny kod** (`OnboardingState.swift`):
- `completeOnboarding()` (linia 81): przechodzi do `.syncChoice` — musi przejsc do `.auth`
- `selectSyncMethod()` (linia 87): ustawia `hasCompletedOnboarding = true` i idzie do `.mainApp` — ta metoda odpada lub zmienia sie radykalnie
- `determineInitialState()` (linia 60): resume logic hardkoduje `.syncChoice` i `.householdSetup` — trzeba zaktualizowac
- `LaunchState` enum (linia 5): musi dodac `.auth` i usunac `.syncChoice`

**Wymagane zmiany**:
1. `LaunchState`: dodac `auth`, usunac `syncChoice`
2. `completeOnboarding()`: `.syncChoice` -> `.auth`
3. Nowa metoda: `completeAuth(isGuest: Bool)` — jesli guest: `mainApp` (z auto-seed), jesli cloud: `householdSetup`
4. `selectSyncMethod()`: usunac lub przeksztalcic w wewnetrzna logike `completeAuth`
5. `determineInitialState()`: resume z `.auth` zamiast `.syncChoice`
6. `@AppStorage` migracja: `hasCompletedOnboarding` -> `hasSeenOnboarding` (z backward compat)

---

## 4. SignInView nie ustawia sync mode (brakujaca logika)

Po usunieciu `SyncSelectionView`, kto ustawia sync mode?

**Aktualny flow**:
- `SyncSelectionView` wola `onboardingState.selectSyncMethod(.iCloud)` lub `selectSyncMethod(.local)`
- To ustawia `@AppStorage("syncMethod")` i `hasCompletedOnboarding = true`

**SignInView** (`SignInView.swift:99`): wola `userSession.signIn()` — ale nie ustawia sync method.
**SignInView** (`SignInView.swift:129`): wola `userSession.startGuestSession()` — ale nie ustawia sync method.

**Korekta**: `SignInView` (lub nowa warstwa w `OnboardingState`) musi ustawiac sync mode:
- Apple Sign In success → `syncMethod = .iCloud`
- Guest → `syncMethod = .local`

Bez tego po usunieciu `SyncSelectionView` sync mode zostanie `.none` i app nie bedzie wiedziec jak synchronizowac.

---

## 5. Tresci carousela: plan vs obecne (decyzja produktowa)

**Plan Codex** (sekcja 3.2): 4 slajdy z tresciami z oryginalnego spec'a:
- Smart Shopping (`cart.fill`)
- Clear Your Mind (`lightbulb.fill`)
- Make It Yours (`paintpalette.fill`)
- Better Together (`person.2.fill`)

**Aktualny kod** (`OnboardingCarouselView.swift:12-31`): 3 slajdy z innymi tresciami:
- "Sync your home" (`cloud.fill`) — fokus na sync
- "Never forget the milk" (`basket.fill`) — fokus na restock
- "Dream together" (`square.3.layers.3d`) — fokus na backlog

**Uwaga**: Obecne tresci sa lepiej dopasowane do faktycznej funkcjonalnosci MVP (sync, shopping restock, backlog). Tresci z planu mowia o features ktore jeszcze nie istnieja w pelni (themes ma 4 presety, recurring chores to stub). "Make It Yours" sugeruje customizacje ktora jest ograniczona.

**Rekomendacja**: Zachowac obecne 3 tresci, dodac 4. slajd "Better Together" (`person.2.fill`) bo sharing jest zaimplementowany. Dodac Skip i Next/Get Started.

---

## 6. `housepulse://join/...` URL scheme: nowy scope (ryzyko niskie)

Plan proponuje dodanie custom URL scheme. Aktualny kod obsluguje tylko iCloud CKShare URLs (`FamilyTodoApp.swift:131-135`).

**Uwaga**: To jest NOWY feature, nie naprawa braku. Wymaga:
- Info.plist: dodanie `housepulse` URL scheme
- `project.pbxproj`: aktualizacja URL types
- `.onOpenURL`: rozroznianie iCloud vs housepulse URLs
- `InviteInputNormalizer`: nowe sciezki normalizacji

**Rekomendacja**: Wydzielic jako osobny commit/task zeby nie blokowac reszty flow.

---

## 7. Interakcja z crash fix (StartupRecoveryView gating)

Po wdrozeniu crash fix planu, `FamilyTodoApp.swift` ma launch gating:
```
if startupBootstrapState == .emergency → StartupRecoveryView
else → RootView
```

Plan Codex nie wspomina o interakcji z tym gatingiem. Jesli routing sie zmieni, trzeba upewnic sie ze emergency path jest niezalezny od `OnboardingState`.

**Stan kodu**: Juz jest niezalezny (gating jest wyzej niz `RootView`). Brak ryzyka, ale warto odnotowac.

---

## 8. Korekta do mojej wlasnej analizy (powyzej)

Moja oryginalna analiza (sekcja "Part 2") blednie twierdzila ze "Guest upgrade banner w More" ma status "JEST". Grep na `MoreView.swift` nie zwraca zadnych wynikow dla "guest banner", "upgrade banner", "Unlock syncing" ani "Sign in with Apple". **Banner NIE istnieje** — Codex ma racje identyfikujac to jako luke.

---

## 9. Drobne korekty do planu Codex

1. **Sekcja 4, punkt 2**: "nowy klucz `hasSeenOnboarding`, migracja kompatybilna z `hasCompletedOnboarding`" — ale `hasCompletedOnboarding` jest uzywany w wielu miejscach (`determineInitialState`, `selectSyncMethod`, `completeHouseholdSetup`, `skipHouseholdSetup`). Migracja wymaga sprawdzenia kazdego uzycia.

2. **Sekcja 3.4, punkt 3**: `InviteInputNormalizer` "rozszerzyc o housepulse://join/" — obecny normalizer obsluguje iCloud share URLs i short codes. Trzeba rozszerzyc API, nie przepisac.

3. **Sekcja 6**: "commitami warstwowymi" — dobry pomysl. Proponowana kolejnosc:
   1. `OnboardingState` refactor (LaunchState enum + transitions) — **high risk, test first**
   2. Carousel UX (4 slajdy + Skip + Next)
   3. Auth flow (merge syncChoice into auth)
   4. Guest banner + deep link (nowe features)

---

## Podsumowanie porownania

| Aspekt | Codex | Claude korekta |
|--------|-------|----------------|
| Guest flow | Guest → householdSetup | Guest → mainApp (jak w spec) |
| Routing plik | ContentView | RootView (FamilyTodoApp.swift) |
| OnboardingState migracja | "usun syncChoice, dodaj auth" | 6 konkretnych zmian w metodach |
| Sync mode po auth | Nie adresuje | SignInView musi ustawic syncMethod |
| Tresci carousela | 1:1 z planem (4 nowe) | Zachowac 3 obecne + dodac "Better Together" |
| housepulse:// URL | W scope | Wydzielic jako osobny task |
| Guest banner w More | Zidentyfikowany brak | Potwierdzam — moja analiza blednie twierdzila ze istnieje |
