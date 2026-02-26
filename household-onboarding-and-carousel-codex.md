# Plan Implementacji: Household Onboarding + Premium Carousel + Auth Router (repo-aware)

## Summary
Treść poniżej jest docelową zawartością `household-onboarding-and-carousel-codex.md`.
Po analizie obecnego kodu plan ogólny wymaga adaptacji, nie przepisywania od zera: mamy już `RootView`, `SignInView`, `CreateHouseholdView`, `ShareAcceptanceCoordinator`, QR scanner i deep-link dla CKShare.
Zamknięte decyzje:
1. Guest po wyborze „Continue without account” przechodzi do `householdSetup`.
2. Routing upraszczamy do `onboarding -> auth -> householdSetup -> mainApp` (usuwamy `syncChoice` z głównego flow).

## 1. Ground Truth (co już jest vs luki)
1. Routing istnieje, ale ma stan `syncChoice` i rozproszoną logikę wejścia do `SignInView`/`CreateHouseholdView` w `ContentView`.
2. Karuzela onboarding istnieje, ale ma 3 slajdy, brak `Skip`, brak `Next` (poza `Get Started` na końcu).
3. Sign-in screen istnieje i ma już debug diagnostics + actionable errors.
4. Household setup istnieje (`CreateHouseholdView`), join ma paste + scan QR.
5. Deep link CKShare istnieje (`AppDelegateBridge`, `ShareAcceptanceCoordinator`, `.onOpenURL`), ale join screen nie obsługuje jeszcze `housepulse://join/...` z potwierdzeniem.
6. Brakuje guest upgrade bannera w `More`.

## 2. Target UX i state machine (decision-complete)
1. `onboarding`:
- 4-slajdowy carousel, `Skip` (top trailing), `Next` dla slajdów 1-3, `Get Started` na 4.
- `Skip` i `Get Started` ustawiają `hasSeenOnboarding = true` i przejście do `auth`.
2. `auth`:
- `Sign in with Apple` (primary), `Continue without account` (secondary).
- Apple success: aktywna sesja cloud -> `householdSetup`.
- Guest start: sesja guest -> `householdSetup`.
3. `householdSetup`:
- Ekran „Let’s set up your space” z dwoma kartami: Create / Join.
- Create success -> `mainApp`.
- Join success -> `mainApp`.
4. `mainApp`:
- Zawiera taby jak dziś.
- Jeśli `isGuest == true`, pokazuje banner upgrade w `More`.
- Po upgrade (udany Apple Sign-In) i braku household -> automatyczne przejście do `householdSetup`.

## 3. Zakres zmian i pliki

1. Routing i stan aplikacji
- [OnboardingState.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Services/OnboardingState.swift)
- [FamilyTodoApp.swift](/home/wkochanowski/code/family-todo/FamilyTodo/FamilyTodoApp.swift)
- [ContentView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/ContentView.swift)

Zmiany:
1. `LaunchState`: `onboarding`, `auth`, `householdSetup`, `mainApp`.
2. Usunięcie `syncChoice` z aktywnej ścieżki.
3. Dodanie jednej metody wyliczającej docelowy stan na podstawie: `hasSeenOnboarding`, `userSession.hasActiveSession`, `currentHouseholdID`.
4. Uproszczenie `ContentView` do roli shell `MainAppView` (bez routing decision).
5. Guardrail: jeśli sesja znika w runtime -> przejście do `auth`.

2. Premium onboarding carousel
- [OnboardingCarouselView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/Onboarding/OnboardingCarouselView.swift)

Zmiany:
1. 4 slajdy z treściami:
- Smart Shopping (`cart.fill`)
- Clear Your Mind (`lightbulb.fill`)
- Make It Yours (`paintpalette.fill`)
- Better Together (`person.2.fill`)
2. Przyciski:
- `Skip` (zawsze)
- `Next` na slajdach 1-3
- `Get Started` na slajdzie 4
3. Zachowanie istniejącego stylu (aurora/tło) bez regresji.

3. Auth flow i migracja ze `syncChoice`
- [SignInView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/SignInView.swift)
- [SyncSelectionView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/Onboarding/SyncSelectionView.swift)

Zmiany:
1. `SignInView` pozostaje ekranem `auth` i zachowuje debug diagnostics.
2. Po Apple success/Guest start routing idzie do `householdSetup` (nie bezpośrednio do `mainApp`).
3. `SyncSelectionView` oznaczyć jako deprecated/usunąć z aktywnego routingu.
4. Teksty CTA zgodne z flow: Apple primary, guest secondary.

4. Household setup + join methods
- [CreateHouseholdView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/Onboarding/CreateHouseholdView.swift)
- [InviteInputNormalizer.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Utilities/InviteInputNormalizer.swift)
- [HouseholdStore.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Stores/HouseholdStore.swift)

Zmiany:
1. Przestrukturyzować wejście w `CreateHouseholdView` na dwa wyraźne akcje: Create / Join.
2. Join screen:
- Top: QR scanner section (obecny komponent zostaje).
- Bottom: ręczne pole kod/link + Join button.
3. `InviteInputNormalizer` rozszerzyć o:
- pełne URL,
- `housepulse://join/<code_or_link>`,
- krótki alfanumeryczny kod (bez uppercasing).
4. Dla deep linku z join ekranu pokazać confirm alert „Join this household?”.

5. Deep link transport
- [FamilyTodoApp.swift](/home/wkochanowski/code/family-todo/FamilyTodo/FamilyTodoApp.swift)
- [AppDelegateBridge.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Services/AppDelegateBridge.swift)
- [ShareAcceptanceCoordinator.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Services/ShareAcceptanceCoordinator.swift)
- [project.pbxproj](/home/wkochanowski/code/family-todo/FamilyTodo.xcodeproj/project.pbxproj)

Zmiany:
1. Dodać URL scheme dla `housepulse://`.
2. `.onOpenURL` rozróżnia:
- CKShare iCloud URL -> obecna ścieżka `ShareAcceptanceCoordinator`.
- `housepulse://join/...` -> enqueue jako pending invite/raw code.
3. Jeśli user nie ma aktywnej sesji, invite zostaje pending i finalizuje się po auth (obecny mechanizm zachować).
4. Join screen ma lokalny confirm UX; root-level path pozostaje fallbackiem.

6. Guest upgrade banner
- [MoreView.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Views/MoreView.swift)

Zmiany:
1. Dodać banner tylko dla `userSession.isGuest`.
2. CTA „Unlock syncing & sharing. Sign in with Apple.” uruchamia `userSession.signIn()`.
3. Po sukcesie auth routing automatycznie przenosi do `householdSetup`.
4. W przypadku błędu użyć istniejącego mechanizmu błędów z auth diagnostyką.

## 4. API / interfejsy / typy do zmiany
1. `LaunchState`:
- usunięcie `syncChoice`,
- dodanie/utrzymanie `auth` jako jawnego stanu.
2. `OnboardingState`:
- nowy klucz `hasSeenOnboarding`,
- migracja kompatybilna z dotychczasowym `hasCompletedOnboarding`.
3. `InviteInputNormalizer`:
- nowe publiczne ścieżki normalizacji dla `housepulse://join/...` i short code.
4. Brak zmian w publicznym API CloudKit managera dla CKShare acceptance.

## 5. Testy i scenariusze akceptacyjne

1. Unit tests
- [OnboardingStateTests.swift](/home/wkochanowski/code/family-todo/FamilyTodoTests/OnboardingStateTests.swift)
1. `test_firstLaunch_startsInOnboarding`
2. `test_onboardingCompleted_routesToAuthWhenSignedOut`
3. `test_authenticatedWithoutHousehold_routesToHouseholdSetup`
4. `test_sessionWithHousehold_routesToMainApp`
5. `test_legacyHasCompletedOnboarding_migratesToHasSeenOnboarding`
- Nowy test normalizacji invite:
1. `test_normalize_housepulseJoinURL`
2. `test_normalize_shortInviteCode`
3. `test_normalize_icloudShareURL`
4. `test_normalize_invalidInput_throws`

2. UI tests
1. First launch: onboarding `Skip` -> auth.
2. Onboarding `Next` x3 + `Get Started` -> auth.
3. Auth guest -> household setup.
4. Auth Apple success -> household setup.
5. Join flow: scan/paste/manual.
6. Deep link `housepulse://join/...` na join screen -> confirm -> join.
7. Guest banner w `More` widoczny tylko dla guest.
8. Guest upgrade -> po sukcesie auth przejście do household setup.

3. Manual QA
1. Existing user po update nie wraca do onboarding nieoczekiwanie.
2. Sign out z main app wraca do `auth`.
3. Pending invite przy starcie signed-out finalizuje się po logowaniu.
4. Continue without account nadal działa offline-first.

## 6. Rollout i bezpieczeństwo zmian
1. Wdrożenie w jednym PR, ale commitami warstwowymi:
1. routing/state migration,
2. carousel UX,
3. household setup/join/deeplink,
4. guest banner + testy.
2. Dodać krótką sekcję do `STATUS.md` z opisem nowej sekwencji stanów.
3. Monitorować TestFlight: onboarding completion, auth drop-off, join conversion.

## 7. Założenia i defaulty
1. Zachowujemy zasadę: jeden aktywny household na sesję.
2. Guest nie wchodzi od razu do `mainApp`; najpierw `householdSetup`.
3. CloudKit share acceptance pozostaje przez istniejący `ShareAcceptanceCoordinator`.
4. Diagnostyka auth w `SignInView` zostaje aktywna i dostępna dla QA.
5. Design karuzeli może zachować obecny styl wizualny, ale treści i nawigacja muszą odpowiadać planowi docelowemu.
