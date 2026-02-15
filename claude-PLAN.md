# Plan poprawek po implementacji Codex — uwagi Antigravity

## Kontekst
Codex wdrożył bazowy plan. User przetestował na iPhone 15 z iOS 26.2.1 przez TestFlight.
**Recently Purchased działa ✅** — pozycje pojawiają się poprawnie po zaznaczeniu.

---

## Issue 1: Done button — za nisko, styka się z klawiaturą

### Status: ✅ ZAIMPLEMENTOWANE (Antigravity)

Zamieniono `UIToolbar` na custom `UIView` (56pt) z niebieską capsulą "Done" pill button.

#### Zmieniony plik: `FamilyTodo/Views/ShoppingListView.swift`

`RapidEntryTextField.Coordinator.makeAccessoryToolbar()` — zmieniono z:

```swift
func makeAccessoryToolbar() -> UIToolbar {
    let toolbar = UIToolbar()
    toolbar.sizeToFit()
    let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
    let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
    toolbar.items = [spacer, done]
    return toolbar
}
```

na:

```swift
func makeAccessoryToolbar() -> UIView {
    let containerHeight: CGFloat = 56
    let container = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: containerHeight))
    container.backgroundColor = .clear

    let button = UIButton(type: .system)
    button.setTitle("Done", for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = UIColor.systemBlue
    button.layer.cornerRadius = 20
    button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
    button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

    button.layer.shadowColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
    button.layer.shadowRadius = 8
    button.layer.shadowOffset = CGSize(width: 0, height: 4)
    button.layer.shadowOpacity = 1.0

    button.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(button)
    NSLayoutConstraint.activate([
        button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    return container
}
```

---

## Issue 2: Recently Purchased — brak clear all i usuwania pojedynczych itemów

### Status: ✅ ZAIMPLEMENTOWANE (Antigravity)

#### Zmieniony plik: `FamilyTodo/Stores/ShoppingListStore.swift`

Dodano 2 nowe metody:

```swift
/// Deletes a single recent item (all bought duplicates matching the same title).
func deleteRecentItem(_ item: ShoppingItem) async {
    let key = normalizedRecentKey(item.title)
    let matchingBought = items.filter { $0.isBought && normalizedRecentKey($0.title) == key }
    for match in matchingBought {
        await deleteItem(match)
    }
}

/// Clears all recently purchased items.
func clearRecentItems() async {
    let boughtItems = items.filter(\.isBought)
    guard !boughtItems.isEmpty else { return }

    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
        items.removeAll(where: \.isBought)
    }

    for item in boughtItems {
        if let context = modelContext {
            let itemId = item.id
            let descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.id == itemId }
            )
            if let cached = try? context.fetch(descriptor).first {
                context.delete(cached)
            }
        }
        if isCloudSyncEnabled {
            do { try await cloudKit.deleteShoppingItem(id: item.id) }
            catch { self.error = error }
        }
    }
    try? modelContext?.save()
}
```

#### Zmieniony plik: `FamilyTodo/Views/ShoppingListView.swift`

**RestockSheet** — zamieniony z `ScrollView`+`LazyVStack` na `List`+`ForEach`+`.onDelete`:

```swift
struct RestockSheet: View {
    @ObservedObject var store: ShoppingListStore
    let onRestore: (ShoppingItem) -> Void
    let onDeleteItem: (ShoppingItem) -> Void     // ← NOWE
    let onClearAll: () -> Void                    // ← NOWE
    @State private var showClearAllConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if store.recentItems.isEmpty {
                    ContentUnavailableView(...)
                } else {
                    List {
                        ForEach(store.recentItems) { item in
                            RestockItemRow(item: item, onRestore: { onRestore(item) })
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparator(.hidden)
                        }
                        .onDelete { offsets in                    // ← SWIPE DELETE
                            let items = store.recentItems
                            for index in offsets {
                                onDeleteItem(items[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {           // ← CLEAR ALL
                    if !store.recentItems.isEmpty {
                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Text("Clear All").foregroundStyle(.red)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Clear all recently purchased?", isPresented: $showClearAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) { onClearAll() }
            } message: {
                Text("This permanently removes all items from the recently purchased list.")
            }
        }
    }
}
```

**Call site** w `ShoppingListContent`:

```swift
.sheet(isPresented: $showRestock) {
    RestockSheet(
        store: store,
        onRestore: restoreRecentItem,
        onDeleteItem: deleteRecentItem,
        onClearAll: clearRecentItems
    )
}
```

**Nowe helper methods** w `ShoppingListContent`:

```swift
private func deleteRecentItem(_ item: ShoppingItem) {
    _Concurrency.Task { await store.deleteRecentItem(item) }
    HapticManager.lightTap()
}

private func clearRecentItems() {
    _Concurrency.Task { await store.clearRecentItems() }
    HapticManager.success()
}
```

---

## Issue 3: Glass effect nadal nie działa (iOS 26.2.1, iPhone 15)

### Status: 🔴 DO NAPRAWY — potrzebna restrukturyzacja

### Diagnoza

User potwierdził: iPhone 15, iOS 26.2.1, glass działa w natywnych appach (Zegar, GitHub). Kod `#available(iOS 26)` odpala się prawidłowo, ale efekt nie renderuje.

### Root cause: modyfikatory po `GlassEffectContainer` blokują compositing

Aktualny kod:

```swift
var body: some View {
    Group {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                tabBarContent
                    .glassEffect(.regular.tint(liquidGlassTint), in: .capsule)
            }
        } else { ... }
    }
    .overlay {                                    // ← PROBLEM 1
        Capsule()
            .strokeBorder(borderColor, lineWidth: 0.5)
            .allowsHitTesting(false)
    }
    .shadow(color: ..., radius: 12, x: 0, y: 5)  // ← PROBLEM 2
    .padding(...)
}
```

**Problem 1:** `.overlay { Capsule().strokeBorder() }` jest **POZA** `GlassEffectContainer`. Na iOS 26 to rysuje dodatkowy `Capsule` **na wierzchu** glass surface, co blokuje efekt wizualny przezroczystości.

**Problem 2:** `.shadow()` po overlay dodaje warstwę cienia nad glass compositing pipeline.

**Problem 3:** W `activeTabIndicator`:
```swift
Color.clear
    .glassEffect(.regular.tint(dropletTint).interactive(), in: .capsule)
    .glassEffectID(...)
    .glassEffectTransition(.matchedGeometry)
    .overlay { Capsule().strokeBorder(...) }  // ← blokuje glass
    .shadow(...)                              // ← blokuje glass
```
Apple docs: *"`.glassEffect()` should be the last modifier. Modifiers applied after glass (overlay, shadow, clipShape) prevent the glass system from correctly compositing."*

### Proponowany fix

```swift
var body: some View {
    if #available(iOS 26.0, *) {
        // iOS 26: glass handles its own shape, border, and shadow
        GlassEffectContainer(spacing: 0) {
            tabBarContent
                .glassEffect(.regular.tint(liquidGlassTint), in: .capsule)
        }
        // NO overlay, NO shadow — glass renders its own chrome
        .padding(.horizontal, AppChromeMetrics.horizontalInset)
    } else {
        // iOS 17-25: manual material + border + shadow
        tabBarContent
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(fallbackTint)
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 12, x: 0, y: 5)
            .padding(.horizontal, AppChromeMetrics.horizontalInset)
    }
}
```

**Kluczowe zasady iOS 26 Liquid Glass:**
1. **Żadnych modyfikatorów po `.glassEffect()`** — glass sam rysuje border, shadow, blur
2. **`GlassEffectContainer` musi być top-level** — nie wewnątrz `Group` z shared modifiers
3. **Active droplet** — usunąć `.overlay` i `.shadow` z `activeTabIndicator` na iOS 26:

```swift
@ViewBuilder
private var activeTabIndicator: some View {
    if #available(iOS 26.0, *) {
        Color.clear
            .glassEffect(.regular.tint(dropletTint).interactive(), in: .capsule)
            .glassEffectID("tabActiveIndicator", in: glassNamespace)
            .glassEffectTransition(.matchedGeometry)
            // NO overlay, NO shadow on iOS 26
    } else {
        Capsule()
            .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.88))
            .overlay {
                Capsule().strokeBorder(...)
            }
            .shadow(...)
            .matchedGeometryEffect(id: "tabActiveIndicatorFallback", in: fallbackNamespace)
    }
}
```

> [!IMPORTANT]
> To jedyna zmiana, która naprawdę ma szansę naprawić glass. Shared modifiers (overlay, shadow) powinny istnieć **TYLKO** na fallback path, a na iOS 26 glass sam zarządza swoim wyglądem.

---

## Podsumowanie

| Issue | File | Status |
|-------|------|--------|
| Done button height | `ShoppingListView.swift` | ✅ Zaimplementowane |
| Recently Purchased clear/delete | `ShoppingListView.swift` + `ShoppingListStore.swift` | ✅ Zaimplementowane |
| Glass effect | `FloatingTabBar.swift` | 🔴 Do naprawy — usunąć shared overlay/shadow na iOS 26 path |
