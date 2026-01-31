# Family To-Do App - Kompletna Dokumentacja Techniczna

**Data utworzenia:** 2026-01-29  
**Wersja aplikacji:** Pre-release (MVP)  
**Platforma:** iOS 17+

---

## 📋 Spis treści

1. [Przegląd aplikacji](#-przegląd-aplikacji)
2. [Architektura techniczna](#-architektura-techniczna)
3. [Kluczowe funkcjonalności](#-kluczowe-funkcjonalności)
4. [Model danych](#-model-danych)
5. [Status implementacji](#-status-implementacji)
6. [Zalecenia dla iOS](#-zalecenia-dla-ios)
7. [Monetyzacja i marketing](#-monetyzacja-i-marketing)
8. [Roadmapa](#-roadmapa)

---

## 🏠 Przegląd aplikacji

### Cel i filozofia

**Family To-Do App** to aplikacja iOS zaprojektowana do wspólnego zarządzania zadaniami domowymi dla par i rodzin. Główna propozycja wartości:

> *„Czy ta decyzja sprawia, że dwóm osobom łatwiej jest żyć razem i pamiętać o sprawach domowych, bez poczucia kontroli lub presji?"*

### Czym NIE jest ta aplikacja

- ❌ Narzędzie do zarządzania projektami (Jira dla domu)
- ❌ Aplikacja gamifikacyjna (punkty, rankingi, streaki)
- ❌ Narzędzie do mikrozarządzania
- ❌ Porównywarka członków rodziny

### Czym JEST ta aplikacja

- ✅ Wspólna pamięć dla zadań domowych i zakupów
- ✅ Narzędzie redukcji konfliktów (neutralne przypisania)
- ✅ Delikatny system przypomnień (bez nachalności)
- ✅ Narzędzie fokusowe (WIP limit 3 zadań)

### Docelowa grupa użytkowników

Pary i rodziny zarządzające wspólnym gospodarstwem domowym, ceniące:
- Jasną komunikację
- Współdzieloną odpowiedzialność
- Niski narzut poznawczy
- Mechaniki przyjazne relacjom

---

## 🏗️ Architektura techniczna

### Stos technologiczny

| Komponent | Technologia | Wersja |
|-----------|-------------|--------|
| **Platforma** | iOS | 17.0+ |
| **Framework UI** | SwiftUI | Latest |
| **Backend** | CloudKit (BaaS) | CKCloud |
| **Lokalna baza** | SwiftData | iOS 17+ |
| **Autentykacja** | Sign in with Apple | OAuth2 |
| **CI/CD** | GitHub Actions | macOS runners |

### Zasady architektoniczne

1. **Shared-first** - Współdzielenie to rdzeń, nie dodatek
2. **Offline-first** - Aplikacja działa bez internetu
3. **Optymistyczny UI** - Zmiany widoczne natychmiast
4. **Last-Write-Wins** - Rozwiązywanie konfliktów przez najnowszy timestamp
5. **One source of truth** - Każde zadanie ma jasny status i właściciela

### Struktura projektu

```
FamilyTodo/
├── Models/                 # Modele danych (Entity + Cache)
│   ├── Household.swift
│   ├── Member.swift
│   ├── Task.swift
│   ├── Area.swift
│   ├── RecurringChore.swift
│   ├── ShoppingItem.swift
│   └── Cached*.swift       # Modele SwiftData dla offline
│
├── Views/                  # Widoki SwiftUI
│   ├── ShoppingListView.swift     # Lista zakupów (Tab: Shopping)
│   ├── TaskListView.swift         # Lista zadań (Tab: Tasks)
│   ├── BacklogView.swift          # Zaległe zadania (Tab: Backlog)
│   ├── SettingsView.swift         # Ustawienia (Tab: More)
│   ├── TaskDetailView.swift       # Szczegóły zadania
│   ├── RecurringChoresView.swift  # Obowiązki cykliczne
│   ├── OnboardingView.swift       # Onboarding
│   ├── SignInView.swift           # Logowanie
│   ├── ShareInviteView.swift      # Zapraszanie członków
│   └── MemberManagementView.swift # Zarządzanie członkami
│
├── Stores/                 # State management
│   ├── TaskStore.swift            # Zarządzanie zadaniami
│   └── ...other stores
│
├── Managers/               # Logika biznesowa
│   └── CloudKitManager.swift      # Synchronizacja CloudKit
│
├── Services/               # Usługi pomocnicze
│   └── AuthenticationService.swift
│
└── Utilities/              # Narzędzia pomocnicze
```

---

## ⭐ Kluczowe funkcjonalności

### Nawigacja (Tab Bar)

Aplikacja używa prostej nawigacji Tab Bar z 4 zakładkami:

| Tab | Ikona | Funkcja |
|-----|-------|---------|
| **Shopping** | 🛒 | Lista zakupów |
| **Tasks** | ✓ | Aktywne zadania (Next) |
| **Backlog** | 📦 | Zaplanowane zadania |
| **More** | ⋯ | Ustawienia, Household, Chores |

### 1. Gospodarstwo domowe (Household)

- **Wspólna przestrzeń danych** dla wszystkich członków
- **Zapraszanie przez CKShare** (link SMS/email)
- **Role:** Owner, Member
- **Minimum:** 1 członek (właściciel)

### 2. Zadania (Tasks)

**Statusy (Minimal Kanban):**
- `Backlog` - zaplanowane
- `Next` - aktualne (max 3 per osoba - WIP limit)
- `Done` - ukończone

**Priorytety (bez liczb):**
- Dziś
- W tym tygodniu
- Kiedyś

**Pola zadania:**
- Tytuł (verb + efekt)
- Przypisanie (kto robi)
- Status
- Opcjonalny termin
- Obszar/projekt
- Typ: jednorazowe lub cykliczne

### 3. Obowiązki cykliczne (Recurring Chores)

Automatyczne planowanie zadań:
- **Dzienna** - codziennie
- **Tygodniowa** - w określony dzień tygodnia
- **Co 2 tygodnie** - biweekly
- **Miesięczna** - w określony dzień miesiąca

### 4. Obszary (Areas/Boards)

Logiczne strefy domu:
- Kuchnia
- Łazienka
- Salon
- Sypialnia
- Ogród
- Naprawy

### 5. Lista zakupów (Shopping List) - Tab: Shopping 🛒

**Główny ekran (Tab: Shopping):**
- **Lista** z nagłówkiem i licznikiem pozycji
- Przycisk "+" do dodawania nowych produktów
- Produkty z emoji, nazwą, ilością i jednostką
- Inicjały osoby która dodała (A, T)
- Sekcja "Do uzupełnienia" z sugestiami

**Dwie sekcje:**
- **To Buy** - aktywna lista do zakupu
- **Bought** - biblioteka wcześniej kupionych (sugestie)

**Funkcje:**
- Sugestie z historii zakupów
- Ilość + opcjonalna jednostka (np. "2 l", "1 kg", "10 szt")
- Brak kategorii (prostota)

### 6. Powiadomienia

**Zasady:**
- Max 1 dzienny digest
- Powiadomienia terminowe tylko dla realnych deadlines
- Brak przypomnień "co godzinę"
- Możliwość całkowitego wyciszenia

### 7. Delikatne celebracje (nie gamifikacja!)

**Co robimy:**
- ✨ Mikro-celebracje: "Kuchnia błyszczy! ✨"
- 🎉 Milestone'y: "10 zadań zrobionych!"
- 📊 Neutralny postęp: "8/12 tygodniowych zadań"

**Czego NIE robimy:**
- ❌ Punkty, odznaki, rankingi
- ❌ Porównania między członkami
- ❌ Streaki tworzące presję

---

## 💾 Model danych

### Encje CloudKit

```
Household (1) ←→ (N) Member
Household (1) ←→ (N) Area
Household (1) ←→ (N) Task
Household (1) ←→ (N) RecurringChore
Household (1) ←→ (N) ShoppingItem

Member (1) ←→ (N) Task (assigneeId)
Area (1) ←→ (N) Task (areaId)
RecurringChore (1) ←→ (N) Task (recurringChoreId)
```

### Sync Strategy (ADR-002)

1. **Local Database** - wszystkie dane w SwiftData
2. **Optimistic UI** - zmiany widoczne natychmiast
3. **Background Sync** - CloudKit w tle
4. **Last-Write-Wins** - najnowszy timestamp wygrywa
5. **Exponential Backoff** - retry w przypadku błędów sieci

---

## ✅ Status implementacji

### Ukończone (Implemented)

- [x] Projekt Xcode + shell aplikacji SwiftUI
- [x] Modele: Household, Member, Area, Task, RecurringChore, ShoppingItem
- [x] TaskStore z WIP limit + optimistic UI
- [x] SwiftData offline cache dla wszystkich modeli
- [x] Tab-based navigation (Shopping, Tasks, Backlog, More)
- [x] Lista zakupów z sugestiami i sekcją "Do uzupełnienia"
- [x] Sign in with Apple flow
- [x] GitHub Actions CI + Fastlane
- [x] Podstawowa obsługa offline (cache + optimistic updates)
- [x] Kategoryzacja błędów CloudKit
- [x] Zarządzanie członkami (edit/delete/role)
- [x] Powiadomienia (daily digest + deadlines)
- [x] Ustawienia dla powiadomień + celebracji

### W toku (Current Focus)

- [ ] Sekwencje TestFlight deploy (credentials setup)
- [ ] Unit testy dla krytycznej logiki

### Planowane (Priority 3+)

- [ ] Advanced sync (retry queue, conflict UI, sync status indicators)
- [ ] Monetyzacja (StoreKit 2 + paywall)
- [ ] Lokalizacja (PL, DE, IT, ES, ZH, JA)
- [ ] Marketing / ASO launch

---

## 📱 Zalecenia dla iOS

### 1. Lokalizacja Multi-language (i18n/l10n)

#### Wymagania

Aplikacja powinna wspierać przynajmniej:

| Język | Priorytet | Uzasadnienie |
|-------|-----------|--------------|
| **English** | ✅ Default | Globalny rynek |
| **Polish** | 🔥 HIGH | Główny rynek (autor) |
| **German** | 🔥 HIGH | Duży rynek, blisko Polski |
| **Italian** | 🟡 MEDIUM | Popularny w niszach family |
| **Spanish** | 🟡 MEDIUM | 500M+ native speakers |
| **Chinese (Simplified)** | 🟢 LOW | Ogromny rynek |
| **Japanese** | 🟢 LOW | Premium market |

#### Implementacja

1. **Struktura plików:**
```
FamilyTodo/
├── en.lproj/Localizable.strings
├── pl.lproj/Localizable.strings
├── de.lproj/Localizable.strings
└── ...
```

2. **Użycie w kodzie:**
```swift
// Helper extension
extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}

// Użycie
Text("button_add_task".localized)
```

3. **Pluralizacja (ważne dla polskiego!):**
```
1 zadanie (singular)
2 zadania (few)
5 zadań (many)
```

4. **Formatowanie dat i liczb:**
```swift
// NIE: "\\(day)/\\(month)/\\(year)"
// TAK:
date.formatted(date: .long, time: .omitted)
number.formatted(.number.precision(.fractionLength(2)))
```

#### Koszty i czas

- **DIY + AI + native review:** ~$15-25/język
- **Czas:** ~2h/język (tłumaczenie) + 1h (testowanie)
- **Total dla PL, DE, IT:** ~$60 + 15-20h

#### Rollout Plan

- v1.0: English only (MVP)
- v1.1: + Polish
- v1.2: + German
- v2.0: + Italian, Spanish, Chinese, Japanese

---

### 2. Dostępność dla wszystkich modeli iPhone (Accessibility)

#### Rozmiary ekranu

| Model | Ekran | Klasa rozmiaru |
|-------|-------|----------------|
| iPhone SE (2nd/3rd) | 4.7" | Compact |
| iPhone 13 mini | 5.4" | Compact |
| iPhone 14/15 | 6.1" | Regular |
| iPhone 14/15 Plus | 6.7" | Regular |
| iPhone 14/15 Pro Max | 6.7" | Regular |

#### Zalecenia implementacyjne

1. **Dynamic Type:**
```swift
Text("Task Title")
    .font(.headline)  // Używaj semantycznych fontów
    .minimumScaleFactor(0.75)  // Dla długich tekstów
```

2. **Safe Areas:**
```swift
.padding(.horizontal)
.safeAreaInset(edge: .bottom) {
    // Footer content
}
```

3. **Adaptive Layout:**
```swift
@Environment(\.horizontalSizeClass) var sizeClass

var body: some View {
    if sizeClass == .compact {
        // Layout dla iPhone SE/mini
    } else {
        // Layout dla większych ekranów
    }
}
```

4. **ScrollView dla małych ekranów:**
```swift
ScrollView {
    VStack {
        // Content that might overflow
    }
}
```

---

### 3. VoiceOver i Accessibility

#### Wymagania Apple

1. **Accessibility Labels:**
```swift
Button(action: addTask) {
    Image(systemName: "plus")
}
.accessibilityLabel("Dodaj nowe zadanie")
```

2. **Accessibility Hints:**
```swift
.accessibilityHint("Stuknij dwukrotnie, aby utworzyć nowe zadanie")
```

3. **Accessibility Identifiers (dla testów):**
```swift
.accessibilityIdentifier("addTaskButton")
```

4. **Grouped Elements:**
```swift
VStack {
    Text(task.title)
    Text(task.dueDate.formatted())
}
.accessibilityElement(children: .combine)
```

5. **Reduce Motion:**
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

withAnimation(reduceMotion ? nil : .spring()) {
    // Animation
}
```

---

### 4. Dark Mode

#### Implementacja

```swift
// Kolory systemowe (automatyczne)
Text("Title").foregroundStyle(.primary)
Text("Subtitle").foregroundStyle(.secondary)

// Custom kolory (wymagają Assets)
Color("AccentColor")  // Zdefiniuj w Assets.xcassets
```

#### Zalecenia

- ✅ Używaj `Color.primary`, `Color.secondary`
- ✅ Definiuj custom kolory w Assets z wariantami Light/Dark
- ❌ NIE używaj hardcoded `Color.black` / `Color.white`

---

### 5. Wsparcie iPad (przyszłość)

#### Zalecenia dla przyszłej kompatybilności

1. **Multitasking:**
```swift
.windowResizability(.contentSize)
```

2. **Sidebar Navigation (iPadOS):**
```swift
NavigationSplitView {
    // Sidebar
} content: {
    // Detail
} detail: {
    // Secondary detail
}
```

3. **Keyboard Shortcuts:**
```swift
.keyboardShortcut("n", modifiers: .command)  // ⌘N
```

---

### 6. Wsparcie iOS 17+ Features

#### Wymagane (iOS 17+)

1. **SwiftData:**
```swift
@Model
class CachedTask {
    @Attribute(.unique) var id: UUID
    // ...
}
```

2. **Observable Macro:**
```swift
@Observable
class TaskStore {
    var tasks: [Task] = []
}
```

3. **TipKit (dla onboardingu):**
```swift
struct AddTaskTip: Tip {
    var title: Text { Text("Dodaj pierwsze zadanie") }
    var message: Text? { Text("Stuknij +, aby dodać zadanie") }
}
```

---

### 7. Bezpieczeństwo i prywatność

#### App Privacy (App Store)

Deklaracja użycia danych w App Store Connect:

| Typ danych | Użycie | Linked to Identity |
|------------|--------|-------------------|
| User ID | iCloud sync | ❌ No |
| Email | Apple Sign In | ❌ No (proxy) |
| Task Data | App functionality | ❌ No |

#### CloudKit Security

- ✅ Dane przechowywane w prywatnym CloudKit użytkownika
- ✅ Szyfrowanie at rest i in transit
- ✅ Współdzielenie tylko przez CKShare (explicit consent)

---

### 8. Performance Guidelines

#### Memory Management

```swift
// Lazy loading dla dużych list
LazyVStack {
    ForEach(tasks) { task in
        TaskRow(task: task)
    }
}
```

#### Background Tasks

```swift
// Background refresh
BGAppRefreshTaskRequest(identifier: "sync")
```

#### App Size

- Target: < 30 MB
- Używaj SF Symbols zamiast custom assets
- Kompresuj obrazy z @2x i @3x

---

### 9. App Store Guidelines Checklist

| Wymaganie | Status |
|-----------|--------|
| ✅ iOS 17.0+ deployment target | Implemented |
| ✅ SwiftUI + SwiftData | Implemented |
| ✅ Sign in with Apple | Implemented |
| ✅ Privacy Policy URL | Needed |
| ✅ App Review Guidelines 4.2 (functionality) | OK |
| ⚠️ Screenshots dla wszystkich rozmiarów | Needed |
| ⚠️ App Preview video | Optional |
| ⚠️ Lokalizacja App Store metadata | Needed |

---

### 10. Testowanie przed release

#### Required Testing

1. **Unit Tests:**
   - RecurringChore scheduling logic
   - WIP limit enforcement
   - Task state transitions

2. **UI Tests:**
   - Add task flow
   - Complete task flow
   - Navigation

3. **Device Testing:**
   - iPhone SE (smallest)
   - iPhone 15 Pro Max (largest)
   - Różne wersje iOS (17.0, 17.1, 17.2+)

4. **Network Testing:**
   - Offline mode
   - Slow network (Network Link Conditioner)
   - Sync conflicts

---

## 💰 Monetyzacja i marketing

### Model biznesowy (proponowany)

**Freemium:**
- **Free:** 2 członków gospodarstwa
- **Premium:** 3+ członków, $4.99/miesiąc lub $39.99/rok

### Marketing Budget (bootstrap)

- **Apple Search Ads:** $100-150/miesiąc
- **Facebook/Instagram:** $50-100/miesiąc
- **Organic:** Product Hunt, Reddit, #BuildInPublic

### Expected Results (Month 1)

- Downloads: 160-425
- Paying users: 3-10
- Revenue: $15-50

---

## 🗺️ Roadmapa

### Phase 1: MVP Launch (Current)

- [x] Core functionality
- [x] CloudKit sync
- [x] Offline support
- [ ] TestFlight beta
- [ ] App Store submission

### Phase 2: Polish (v1.1)

- [ ] Polish localization
- [ ] Bug fixes from beta
- [ ] Performance optimization

### Phase 3: Growth (v1.2+)

- [ ] German localization
- [ ] Monetization (StoreKit 2)
- [ ] Marketing launch

### Phase 4: Expansion (v2.0+)

- [ ] Additional languages
- [ ] iPad support
- [ ] Widget support
- [ ] Watch app (potential)

---

## 📚 Dokumentacja referencyjna

### Pliki w repozytorium

| Plik | Opis |
|------|------|
| [README.md](README.md) | Główny README projektu |
| [CLAUDE.md](CLAUDE.md) | Wytyczne dla agentów AI |
| [TODO.md](TODO.md) | Unified roadmap |
| [instructions.md](instructions.md) | Wymagania produktowe (PL) |
| [docs/](docs/) | Pełna dokumentacja techniczna |

### Kluczowe ADRs

- **ADR-001:** CloudKit Backend - dlaczego CloudKit
- **ADR-002:** Offline-First Strategy - architektura sync

---

**Utworzono:** 2026-01-29  
**Autor:** Gemini Agent  
**Ostatnia aktualizacja:** 2026-01-29
