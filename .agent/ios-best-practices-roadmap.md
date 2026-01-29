# iOS Best Practices Roadmap

Plan implementacji dobrych praktyk dla aplikacji FamilyTodo.

---

## ✅ Zaimplementowane

- [x] SwiftData - persistencja lokalna
- [x] CloudKit sync - synchronizacja między urządzeniami
- [x] Pre-commit hooks (SwiftLint, SwiftFormat)
- [x] CI/CD z GitHub Actions
- [x] Theming system (ThemeStore, AppColors)
- [x] UI rebuild z nowym designem (2026-01-29)

---

## 🔜 Priorytet 1: Lokalizacja (i18n)

**Cel:** Aplikacja domyślnie po angielsku, automatycznie po polsku w PL, po niemiecku w DE, itd.

### Kroki:
- [ ] Utworzyć strukturę folderów lokalizacji:
  - `en.lproj/Localizable.strings` (base/default)
  - `pl.lproj/Localizable.strings` (polski)
  - `de.lproj/Localizable.strings` (opcjonalnie niemiecki)
- [ ] Zamienić wszystkie hardcoded polskie stringi na `String(localized:)`
- [ ] Utworzyć extension dla wygodniejszego dostępu do lokalizacji
- [ ] Dodać lokalizację dla:
  - Tytuły ekranów (Zadania, Backlog, Lista, Więcej, etc.)
  - Przyciski i akcje
  - Komunikaty błędów i alerty
  - Placeholdery (Dodaj zadanie..., Dodaj pomysł..., etc.)
  - Info bannery

### Pliki do zmiany:
- `CardComponents.swift` - CardKind titles, subtitles
- `CardsPagerView.swift` - TodoCardView, BacklogCardView, RecurringCardView, ShoppingListCardView
- `MoreMenuView` - menu items

---

## 🔜 Priorytet 2: Accessibility (a11y)

**Cel:** Wsparcie dla VoiceOver i innych technologii asystujących.

### Kroki:
- [ ] Dodać `.accessibilityLabel()` dla wszystkich interaktywnych elementów
- [ ] Dodać `.accessibilityHint()` dla akcji
- [ ] Użyć `.accessibilityValue()` dla stanów (np. checkbox)
- [ ] Przetestować z VoiceOver
- [ ] Wsparcie Dynamic Type (skalowalne fonty)
- [ ] Sprawdzić kontrast kolorów (WCAG 2.1)

### Elementy do oznaczenia:
- Checkboxy zadań
- Przyciski dodawania (+)
- Tab bar items
- Karty zadań/pomysłów
- Avatary użytkowników
- Priority badges

---

## 🔜 Priorytet 3: Dark Mode

**Cel:** Poprawne wyświetlanie w trybie ciemnym.

### Kroki:
- [ ] Audit wszystkich hardcoded kolorów (Color(hex:))
- [ ] Zamienić na semantic colors lub asset colors z dark variant
- [ ] Dodać warianty ciemne do ThemeStore/AppColors
- [ ] Przetestować wszystkie ekrany w Dark Mode
- [ ] Dodać screenshots do App Store dla obu trybów

---

## 📋 Priorytet 4: Responsywność

**Cel:** Obsługa wszystkich rozmiarów iPhone i opcjonalnie iPad.

### Kroki:
- [ ] Przetestować na iPhone SE (mały ekran)
- [ ] Przetestować na iPhone Pro Max (duży ekran)
- [ ] Sprawdzić safe area insets
- [ ] Opcjonalnie: iPad layout z split view
- [ ] Opcjonalnie: Landscape orientation

---

## 🔒 Priorytet 5: Bezpieczeństwo

**Cel:** Bezpieczne przechowywanie danych.

### Kroki:
- [ ] Przenieść wrażliwe dane z UserDefaults do Keychain
- [ ] Audit App Transport Security
- [ ] Opcjonalnie: Biometric lock (Face ID/Touch ID)

---

## 🧪 Priorytet 6: Testowanie

**Cel:** Zwiększenie pokrycia testami.

### Kroki:
- [ ] Dodać unit tests dla nowych komponentów UI
- [ ] Dodać UI tests dla krytycznych flows:
  - Dodawanie zadania
  - Oznaczanie jako done
  - Nawigacja między tabami
- [ ] Snapshot tests dla głównych ekranów

---

## 📊 Priorytet 7: Performance

**Cel:** Płynne działanie przy dużej ilości danych.

### Kroki:
- [ ] Lazy loading dla długich list
- [ ] Pagination dla zadań
- [ ] Profiling z Instruments
- [ ] Optymalizacja animacji

---

## Notatki

- Screenshoty designu dostępne w: `.gemini/antigravity/brain/.../uploaded_media_*.png`
- Commit z UI rebuild: `3b71edb`
- Obecny język UI: Polski (hardcoded)
