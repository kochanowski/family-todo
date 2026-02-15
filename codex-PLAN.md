# Aneks v3 Po Analizie `claude-PLAN.md`

## Summary
Po porownaniu `claude-PLAN.md` z naszym planem:
1. Przyjmuje 3 kierunki Claude jako trafne:
- customowy `Done` jako pill nad klawiatura,
- zarzadzanie `Recently Purchased` (single delete + clear all),
- diagnoze braku widocznego glass na iOS 26.
2. Koryguje 4 elementy wykonawcze:
- zamiast `.onDelete` przechodzimy na jawne `.swipeActions`,
- nie hardcodujemy stylu `Done` (wysokosc i paddings z `AppChromeMetrics`),
- nie trzymamy per-tab aktywnego owalu; robimy jedna ruchoma warstwe indicatora,
- iOS 26 path bez globalnych overlay/shadow po `.glassEffect`, fallback (iOS 17-25) zostaje materialowy z border/shadow.

## Co bierzemy od Claude 1:1
1. `Done`:
- `UIToolbar` do wymiany na custom `inputAccessoryView` z przyciskiem typu capsule.
2. `Recently Purchased`:
- dodanie kasowania pojedynczego wpisu i `Clear all` z potwierdzeniem.
3. Glass:
- usuniecie warstw, ktore tlumia kompozycje glass na iOS 26.

## Co poprawiamy wzgledem planu Claude
1. `Recently Purchased` single delete:
- zamiast `.onDelete` (edit-list semantics) stosujemy `.swipeActions(edge: .trailing, allowsFullSwipe: false)` na wierszu.
- powod: to jest dokladnie oczekiwany UX i nie wymaga trybu edycji listy.
2. `Done` button layout:
- zamiast stalego `containerHeight = 56` i sztywnego `cornerRadius = 20`, bierzemy metryki z `AppChromeMetrics`.
- powod: gwarancja tej samej wysokosci co `Add item` teraz i po przyszlych zmianach.
3. Glass transition architecture:
- nie zostawiamy aktywnego owalu renderowanego per-tab.
- jedna instancja indicatora na poziomie calego HStack, pozycjonowana po centrum aktywnego slotu.
- powod: bardziej deterministyczny ruch i lepsza czytelnosc animacji.
4. iOS 26 path:
- brak globalnych `.overlay`/`.shadow` nad warstwa glass.
- fallback path (iOS 17-25) zachowuje obecny border/shadow/material.

## Important API / Interface Changes
1. `FamilyTodo/Views/Components/FloatingTabBar.swift`
- nowa architektura indicatora: pojedynczy, ruchomy aktywny owal.
- iOS 26: glass tylko na indicatorze (i opcjonalnie neutralnej bazie bez post-glass overlay/shadow).
- iOS 17-25: material fallback bez zmian semantycznych.
- dodanie metryk CTA:
  - `compactCTAHeight`
  - `compactCTAHorizontalPadding`
  - `compactCTAVerticalPadding`

2. `FamilyTodo/Views/ShoppingListView.swift`
- `RapidEntryTextField`:
  - custom `inputAccessoryView` z `Done` capsule i odstepem od klawiatury.
  - `Done` wywoluje `onDone`.
- `RestockSheet`:
  - `List` + per-row `swipeActions` Delete.
  - toolbar: `Clear all` + `Done`.
  - potwierdzenie dla `Clear all`.

3. `FamilyTodo/Stores/ShoppingListStore.swift`
- dodane:
  - `removeRecentTitle(_ item: ShoppingItem)` (usuwa wszystkie bought rekordy normalized key),
  - `clearRecentHistory()` (usuwa wszystkie bought rekordy).
- bez zmian kierunku:
  - `recentItems` dedupe po normalized title,
  - `restoreRecentItem(_:)` usuwa wpis z Recent po restore.

## Plan implementacji (final)
1. P0: Finalny `Done` nad klawiatura.
- w `AppChromeMetrics` dodac wspolne stale CTA.
- zbudowac custom accessory view z trailing capsule `Done` o tej samej wysokosci co `Add item`.
- dodac dolny inset 8-10 pt nad klawiatura.

2. P0: `Recently Purchased` management.
- `RestockSheet` przepiac na `List`.
- wiersz: restore `+` + trailing `swipeActions` Delete.
- toolbar: `Clear all` (destructive) + confirm alert.
- dodac helpery store: `removeRecentTitle`, `clearRecentHistory`.

3. P1: Glass transition fix (iOS 26+).
- usunac globalne overlay/shadow z iOS 26 glass path.
- przebudowac active indicator na pojedyncza ruchoma warstwe.
- iOS 26 indicator: `.glassEffect(...).interactive()` + `glassEffectID` + `glassEffectTransition(.matchedGeometry)`.
- iOS 17-25 indicator: dotychczasowy material + `matchedGeometryEffect`.

4. P1: Spojnosc CTA.
- `Add item` i keyboard `Done` korzystaja z tych samych metryk.
- (opcjonalnie) `Add task` migruje na te same metryki dla pelnej spojnosci chrome.

5. Delivery gate.
- `PRE_COMMIT_HOME=/tmp/pre-commit-cache pre-commit run -a`
- poprawki po hookach
- ponowny `pre-commit` do pelnego `Passed`
- selektywny commit tylko plikow taska
- push na `rebuild/swiftui-clean-impl`

## Test Cases and Scenarios
1. `DoneAccessoryLayout`
- `Done` ma ta sama wysokosc co `Add item`,
- ma odstep nad klawiatura,
- nie styka sie z klawiatura.

2. `RecentSingleDeleteByTitle`
- swipe delete na wpisie usuwa cala nazwe z Recent (wszystkie bought duplicates).

3. `RecentClearAll`
- `Clear all` wymaga potwierdzenia,
- `Cancel` nic nie zmienia,
- `Clear` usuwa cala historie Recent.

4. `RecentRestoreStillWorks`
- restore jednym kliknieciem:
  - pozycja wraca do `To Buy`,
  - wpis znika z Recent.

5. `TabGlassTransitionIOS26`
- przy zmianie taba widoczny ruch aktywnego glass droplet.

6. `TabFallbackIOS17_25`
- brak regresji fallbacku material.

7. `InteractionSmoke`
- 20 szybkich przelaczen tabow bez utraty tapow.

## Assumptions and Defaults
1. Priorytet wizualny glass: iOS 26+.
2. Single delete w Recent usuwa cala nazwe (dedupe key).
3. `Clear all` usuwa historie trwale (po potwierdzeniu).
4. `Done` ma identyczny kontrakt rozmiaru co `Add item`.
5. iOS target zostaje 17.
