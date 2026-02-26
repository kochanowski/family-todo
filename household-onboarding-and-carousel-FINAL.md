# Household Onboarding + Carousel — Plan FINAL

## Summary
Wdrażamy spójny flow `onboarding -> auth -> householdSetup/mainApp` zgodny ze specyfikacją, bez duplikacji routera i bez regresji startup recovery.  
Kluczowe decyzje: guest po auth idzie bezpośrednio do `mainApp`; Apple Sign-In idzie do `householdSetup` jeśli brak household; `syncChoice` znika z aktywnego flow.

## Decyzje Zamknięte
1. Guest: `Continue without account` -> `mainApp` (nie `householdSetup`).
2. Apple Sign-In success: jeśli brak household -> `householdSetup`, jeśli household jest -> `mainApp`.
3. `LaunchState`: `onboarding`, `auth`, `householdSetup`, `mainApp`.
4. `SyncSelectionView` zostaje tylko jako legacy (nieużywany w routingu).
5. Startup emergency gating (`StartupRecoveryView`) pozostaje bez zmian.
6. `SignInView` debug diagnostics zostają aktywne.

## Zakres Implementacji

### 1. Router i stan aplikacji
1. W `OnboardingState.swift` usunąć `syncChoice` z `LaunchState`, dodać `auth`.
2. Dodać kompatybilną migrację `hasCompletedOnboarding` -> `hasSeenOnboarding` (fallback read starego klucza).
3. Zmienić przejścia:
4. `completeOnboarding()` -> `auth`.
5. Nowa metoda `completeAuth(syncMethod:isGuest:hasHousehold:)` ustawiająca `syncMethod` i docelowy stan.
6. Zmienić `determineInitialState()` tak, aby legacy `syncChoice` mapować do `auth`.
7. W `FamilyTodoApp.swift` (`RootView`) zostawić jedyne źródło prawdy dla routingu.
8. W `ContentView.swift` usunąć auth/household gating; ma renderować tylko `MainAppView` (bootstrap household zostaje tylko w `MainAppView`).

### 2. Auth flow i ustawianie sync mode
1. W `SignInView.swift` po Apple success wywołać `completeAuth(syncMethod: .iCloud, isGuest: false, hasHousehold: ...)`.
2. W `SignInView.swift` po guest start wywołać `completeAuth(syncMethod: .local, isGuest: true, hasHousehold: false)`.
3. Anulowanie SIWA pozostawić neutralne (bez czerwonego błędu).
4. Błędy CloudKit zostawić jako user-friendly + `Open diagnostics`.

### 3. Onboarding carousel (premium)
1. W `OnboardingCarouselView.swift` dodać 4. slajd (`Better Together`, `person.2.fill`).
2. Dodać `Skip` (top trailing), aktywny na każdym slajdzie.
3. Dodać dolny CTA: `Next` na slajdach 1-3, `Get Started` na 4.
4. `Skip` i `Get Started` ustawiają onboarding zakończony i przejście do `auth`.
5. Zachować obecne tło/aurora i animacje.

### 4. Household setup + join
1. `CreateHouseholdView.swift`: utrzymać Create/Join jako dwie główne akcje.
2. `Join` ma wspierać 3 kanały: QR, paste/manual input, deep link.
3. `InviteInputNormalizer.swift`: obsługa `icloud` URL, short code, `housepulse://join/<payload>`, bez uppercasing.
4. Dla `housepulse://join/...` pokazać confirm alert „Join this household?” przed dołączeniem.

### 5. Deep links i invite acceptance
1. W `FamilyTodoApp.swift` rozszerzyć `.onOpenURL`:
2. `icloud.com` -> obecny `ShareAcceptanceCoordinator`.
3. `housepulse://join/...` -> pending invite input do procesu join.
4. W `ShareAcceptanceCoordinator.swift` dodać obsługę pending raw invite input (obok metadata/url), finalizowaną po gotowej sesji.
5. W `project.pbxproj` dodać URL scheme `housepulse`.

### 6. Guest upgrade banner
1. W `MoreView.swift` dodać banner widoczny tylko dla `userSession.isGuest`.
2. CTA: „Unlock syncing & sharing. Sign in with Apple.”
3. Po sukcesie upgrade: jeśli brak household -> przejście do `householdSetup`.

## Public API / Interfejsy / Typy
1. `LaunchState`: usuwa `syncChoice`, dodaje `auth`.
2. `OnboardingState`:
3. nowy klucz `hasSeenOnboarding` + migracja legacy.
4. nowa metoda `completeAuth(syncMethod:isGuest:hasHousehold:)`.
5. `InviteInputNormalizer`:
6. nowy parser dla `housepulse://join/...`.
7. `ShareAcceptanceCoordinator`:
8. nowy pending typ dla raw invite input (poza CKShare metadata/url).

## Testy i Scenariusze Akceptacyjne

### Unit tests
1. `OnboardingStateTests`: onboarding -> auth; legacy migration; guest -> mainApp; cloud/no-household -> householdSetup; cloud/with-household -> mainApp.
2. `InviteInputNormalizerTests`: icloud URL, short code, `housepulse://join/...`, invalid input.
3. `ShareAcceptanceCoordinatorTests`: pending invite przed sesją, finalizacja po auth.
4. `SignInFlowTests`: ustawianie `syncMethod` dla Apple i guest.

### UI tests
1. First launch: `Skip` -> `auth`.
2. First launch: `Next` x3 + `Get Started` -> `auth`.
3. Guest path: `Continue without account` -> `mainApp`.
4. Apple path: sign-in success bez household -> `householdSetup`.
5. Guest banner widoczny tylko dla guest; po upgrade idzie do `householdSetup`.
6. Join by paste, join by QR, join by deep link confirm.

### Manual QA
1. Update istniejącego usera nie cofa do onboarding.
2. Sign out wraca do `auth`.
3. Pending invite przy signed-out finalizuje się po loginie.
4. Emergency startup path działa niezależnie od routingu onboarding/auth.

## Rollout
1. Commit 1: `OnboardingState` + `RootView/ContentView` routing.
2. Commit 2: carousel (`Skip`, `Next`, 4th slide).
3. Commit 3: auth sync-mode + guest/mainApp behavior.
4. Commit 4: invite deep link `housepulse://join/...`.
5. Commit 5: guest upgrade banner + testy.
6. Smoke test lokalny, potem TestFlight.
7. Monitorować drop-off: onboarding completion, auth failure rate, join conversion.

## Assumptions i Defaulty
1. Jedno aktywne household per sesja pozostaje.
2. Guest to local-only i wchodzi do `mainApp` bez household setup.
3. CloudKit sharing dalej idzie przez istniejący `CloudKitManager`/`ShareAcceptanceCoordinator`.
4. Diagnostyka auth/store pozostaje manualnie kopiowana z aplikacji (bez auto-upload).
