# Plan v9 — Tab Bar Parity z GitHub/Clock + Ocena `claude-PLAN.md`

## Summary
Po analizie `claude-PLAN.md`, aktualnego kodu i nagrania `ScreenRecording_02-16-2026 09-31-30_1.mp4`:
1. Plan Claude jest trafny kierunkowo dla efektu UX (droplet motion + brak blur całej treści).
2. Część diagnozy w Claude jest już nieaktualna względem repo.
3. Najlepsza ścieżka dla tego projektu to dalsze dopracowanie **custom `FloatingTabBar`**, nie pełna migracja do `TabView`.

## Ocena planu Claude (co bierzemy / co korygujemy)
1. Przyjmujemy:
- `ContentView`: brak blur/scale transition dla całej treści, przełączanie ma być instant.
- Tab bar na iOS 26: ograniczyć warstwy powodujące white-wash.
- Większa separacja aktywnej ikony (rozmiar + waga) jak w GitHub/Clock.
2. Korygujemy:
- W repo blur transition w `ContentView` jest już usunięty, ale nadal jest `.animation(..., value: activeTab)`; trzeba to wyciąć dla pełnego “instant swap”.
- Obecny tab bar ma już single-indicator positioning, ale nie używa `glassEffectID`/`glassEffectTransition`; to osłabia efekt “liquid morph”.
- Nie przechodzimy teraz na pełny `TabView`, bo obecna architektura opiera wiele ekranów o `AppChromeMetrics`, custom keyboard handling i floating CTA.

## Important API / Interface Changes
1. `FamilyTodo/Views/Components/FloatingTabBar.swift`
- Przywrócenie iOS26 morph transition:
  - `@Namespace private var glassNamespace`
  - aktywny droplet renderowany per-slot (centrowanie 1:1 na tabie) z:
    - `.glassEffectID("activeTabIndicator", in: glassNamespace)`
    - `.glassEffectTransition(.matchedGeometry)`
- iOS26 base bar:
  - `GlassEffectContainer`
  - `.glassEffect(.regular.interactive(), in: .capsule)` na powierzchni paska
  - bez ciężkich, kryjących overlayów/tintów.
- iOS17-25 fallback:
  - `matchedGeometryEffect` + material capsule
  - obniżony `fallbackTint` (light: ~0.12–0.16).
- Ikony:
  - `activeIcon`/`inactiveIcon` (filled vs regular)
  - rozmiar np. 24 aktywny, 20 nieaktywny.
2. `FamilyTodo/ContentView.swift`
- Usunięcie `.animation(.easeInOut(duration: 0.3), value: activeTab)` z `tabContent`.
- Zostaje natychmiastowy switch ekranu; animuje się tylko tab droplet.
3. Brak zmian modeli/store dla tego scope.

## Implementation Plan

## P0 — Efekt “jak GitHub/Clock” na iOS26
1. Refactor `FloatingTabBar`:
- iOS26 path oparty o `GlassEffectContainer`.
- Aktywny owal przeniesiony na per-slot conditional view z `glassEffectID` + `glassEffectTransition`.
- Utrzymanie równej geometrii slotów (`HStack(spacing: 0)` + pełne `frame(maxWidth: .infinity)`).
2. Uproszczenie base glass:
- Usunąć elementy tłumiące kontrast (manualne, zbyt kryjące warstwy).
- Zachować minimalny stroke tylko jeśli nie psuje clarity.
3. Wzmocnienie sygnału aktywnego taba:
- aktywna ikona większa i semibold,
- nieaktywne ikony neutralne, mniejsze.

## P0 — Zachowanie przełączania treści
1. `ContentView`:
- brak animacji całej treści przy zmianie zakładki.
- Utrzymanie obecnego `switch activeTab` bez transition/fade.

## P1 — Fallback i stabilność interakcji
1. iOS17-25 fallback:
- subtelniejszy tint fallback bar (`~0.15` light).
- zachowanie istniejącego hit-testing.
2. Polish:
- sprawdzić centrowanie owalu na każdym tabie (Shopping/Tasks/Backlog/More),
- potwierdzić brak “rozmycia wszystkiego” w light i dark.

## Delivery Gate
1. `PRE_COMMIT_HOME=/tmp/pre-commit-cache pre-commit run -a`
2. Jeśli hooki zmienią pliki, rerun do pełnego `Passed`.
3. Selektywny commit tylko plików z tego taska.
4. Commit:
- `fix: match tab bar liquid transition with iOS clock/github behavior`
5. Push:
- `git push origin feature/continue-mvp`

## Test Cases and Scenarios
1. `TabBar_DropletMorph_iOS26`
- widoczny płynny glass morph między wszystkimi tabami.
2. `TabBar_NoWhiteWash_LightAndDark`
- bar nie wybiela treści i nie wygląda jak mleczna plama.
3. `TabBar_CenteredIndicator_AllTabs`
- owal zawsze centralnie względem ikony/label.
4. `ContentSwitch_Instant_NoBlurFlash`
- brak blur/scale/fade całego ekranu przy przełączaniu.
5. `TabBar_HitTesting_Stable`
- 20 szybkich tapów między tabami bez gubienia kliknięć.
6. `Fallback_iOS17_25_Stable`
- ruch aktywnego wskaźnika i czytelność bez Liquid Glass API.

## Assumptions and Defaults
1. Priorytet UX: iOS26 (efekt jak Clock/GitHub), fallback dla iOS17-25.
2. Zostajemy przy custom tab bar architecture (bez pełnej migracji do `TabView`).
3. Przełączanie treści ma być instant; animujemy tylko tab chrome.
4. Nie ruszamy obecnych feature flow (Shopping/Backlog/Tasks), tylko warstwę tab bar transitions i rendering.
