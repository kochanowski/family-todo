# Uwagi Antigravity do codex-PLAN.md (Aneks v3)

## ✅ Zgadzam się z korektami Codex

### 1. `.swipeActions` zamiast `.onDelete`
Lepszy UX — `.onDelete` wymaga swipe-to-delete w kontekście Edit Mode listy, a `.swipeActions(edge: .trailing, allowsFullSwipe: false)` daje bezpośredni iOS gesture bez trybu edycji. Dobra korekta.

### 2. Metryki CTA z `AppChromeMetrics`
Zamiast hardkodowanego `containerHeight = 56` i `cornerRadius = 20`. Centralizacja stałych zapewni spójność przyszłych zmian high-pills (Add item, Done, Add task).

### 3. Pojedyncza ruchoma instancja indicatora
Zamiast renderowania `activeTabIndicator` per-tab (obecny `if activeTab == tab`) — jedna warstwa owalu na poziomie `HStack`, pozycjonowana po centrum aktywnego slotu:
- `matchedGeometryEffect` / `glassEffectTransition(.matchedGeometry)` działają poprawniej z jedną instancją
- Eliminuje re-create indicatora przy każdym przełączeniu taba
- Daje bardziej płynną animację przesuwania

### 4. iOS 26 path bez overlay/shadow
Dokładnie zgodne z moją diagnozą. Potwierdzone.

---

## ⚠️ Uwagi do planu Codex

### 1. Naming: `removeRecentTitle` vs `deleteRecentItem`
Codex zmienił nazwę. `removeRecentTitle` jest bardziej precyzyjna bo sugeruje usunięcie po kluczu tytułu (nie po konkretnym `id`). Obie nazwy OK, ważne żeby była spójna z resztą API store'a.

### 2. ⚠️ WAŻNE: Moje zmiany są już w kodzie
Plan Codex opisuje co *zamierza* zrobić, ale **poniższe zmiany są już zaimplementowane** w plikach:

- **`ShoppingListView.swift`:**
  - Custom `inputAccessoryView` z 56pt height i niebieską capsulą Done
  - `RestockSheet` z `List` + `.onDelete` + "Clear All" toolbar + confirmation alert
  - Helpery: `deleteRecentItem()`, `clearRecentItems()`

- **`ShoppingListStore.swift`:**
  - `deleteRecentItem(_ item:)` — usuwa bought duplikaty po normalized title key
  - `clearRecentItems()` — czyści całą historię z optimistic UI

**Codex powinien sprawdzić aktualny stan tych plików zanim zacznie implementować**, bo inaczej nadpisze moje zmiany. Wystarczy że:
- Zmieni `.onDelete` na `.swipeActions` (korekta 1)
- Wyciągnie hardkodowane stałe do `AppChromeMetrics` (korekta 2)
- Zrobi glass fix (Issue 3 — tego nie implementowałem)

### 3. `pre-commit run -a` (linia 88)
Nie widziałem `.pre-commit-config.yaml` w repo. Jeśli nie istnieje, ten krok się nie powiedzie.
