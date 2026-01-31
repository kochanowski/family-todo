# House Pulse - Complete Implementation Guide

**App Name:** House Pulse  
**Data utworzenia:** 2026-01-31  
**Wersja:** Pre-release (MVP)  
**Platforma:** iOS 17+

---

## 📋 Spis treści

1. [Przegląd aplikacji](#-przegląd-aplikacji)
2. [Global UI & Design Rules](#-global-ui--design-rules)
3. [Model danych](#-model-danych)
4. [Ekrany aplikacji](#-ekrany-aplikacji)
5. [Szczegółowa logika](#-szczegółowa-logika)
6. [Architektura techniczna](#-architektura-techniczna)
7. [Implementacja SwiftUI](#-implementacja-swiftui)
8. [Zalecenia dla iOS](#-zalecenia-dla-ios)
9. [Status implementacji](#-status-implementacji)
10. [Monetyzacja i marketing](#-monetyzacja-i-marketing)
11. [Roadmapa](#-roadmapa)

---

## 🏠 Przegląd aplikacji

### Cel i propozycja wartości

**House Pulse** to wysokiej jakości, współdzielona aplikacja do zarządzania domem zaprojektowana dla par i rodzin.

**Core Value Proposition:**
- Information density
- Speed of entry
- Clear separation of concerns (Shopping vs. Daily Tasks vs. Long-term Backlog)

### Docelowa grupa użytkowników

Pary i małe rodziny mieszkające razem, ceniące minimalizm i efektywność.

### Czym NIE jest ta aplikacja

- ❌ Narzędzie do zarządzania projektami (Jira dla domu)
- ❌ Aplikacja gamifikacyjna (punkty, rankingi, streaki)
- ❌ Narzędzie do mikrozarządzania
- ❌ Porównywarka członków rodziny

### Czym JEST ta aplikacja

- ✅ Wspólna pamięć dla zadań domowych i zakupów
- ✅ Narzędzie redukcji konfliktów (neutralne przypisania)
- ✅ Delikatny system przypomnień (bez nachalności)
- ✅ Narzędzie fokusowe (max 3 aktywne zadania)

---

## 🎨 Global UI & Design Rules

### Estetyka: "Premium Minimalist"

Używa natywnych konwencji iOS, ale podniesionych z custom spacing i subtelnym glassmorphism.

### Typografia

| Element | Font | Rozmiar | Styl |
|---------|------|---------|------|
| **Font** | Inter (lub San Francisco) | - | - |
| **Headers** | Bold | - | Tight tracking |
| **Body** | Regular | 14pt-15pt | Maksymalizacja widocznych wierszy |
| **Secondary Text** | Regular | 10pt-12pt | Muted colors (gray/secondary label) |

### Layout

- **Edge-to-Edge:** Content flows behind status bar i bottom navigation
- **Floating Tab Bar:** Custom pill-shaped container floating ~24pt above bottom safe area
- **Glassmorphism:** Na Tab Bar i Toast notifications (blur + translucency)

### Motion & Transitions

**Tab Switching Animation (WYMAGANE):**
Przejścia między tabami NIE mogą być natychmiastowe.

```swift
// Fade-In Animation przy zmianie tabów
Opacity: 0% → 100%
Scale: 99% → 100% (very slight zoom in)
Blur: 2px → 0px (comes into focus)
Duration: ~0.3s
Easing: cubic-bezier
```

### Dark Mode (Full Support)

| Mode | Background | Cards |
|------|------------|-------|
| **Light Mode** | Off-white (#F9F9F9) | White |
| **Dark Mode** | Pure black | Dark gray (#1C1C1E) |

---

## 💾 Model danych

### Encje (Conceptual)

#### ShoppingItem
```swift
struct ShoppingItem {
    let id: UUID
    var text: String           // Name of item
    var isCompleted: Bool
    var state: ItemState       // .active, .restockPool, .deleted
}
```

#### Task (TodoItem)
```swift
struct Task {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var assignee: Member?      // Optional
    var dueDate: Date?         // Optional
}
```

#### BacklogCategory (Section)
```swift
struct BacklogCategory {
    let id: UUID
    var title: String          // e.g., "Home Projects"
    var items: [Task]
}
```

#### User / Member
```swift
struct Member {
    var name: String           // e.g., "Anna", "Tom"
    var initials: String
    var color: Color           // Theme color for UI avatars
}
```

#### AppTheme
```swift
enum AppTheme {
    case light, dark, system
}
```

### Relacje CloudKit

```
Household (1) ←→ (N) Member
Household (1) ←→ (N) Task
Household (1) ←→ (N) BacklogCategory
Household (1) ←→ (N) ShoppingItem

Member (1) ←→ (N) Task (assigneeId)
BacklogCategory (1) ←→ (N) Task
```

### Sync Strategy (ADR-002)

1. **Local Database** - wszystkie dane w SwiftData
2. **Optimistic UI** - zmiany widoczne natychmiast
3. **Background Sync** - CloudKit w tle
4. **Last-Write-Wins** - najnowszy timestamp wygrywa

---

## 📱 Ekrany aplikacji

### Nawigacja (Floating Tab Bar)

**High-Level Structure:** Single-window application z persistent floating bottom navigation bar zawierającym 4 taby.

| Tab | Ikona | Funkcja |
|-----|-------|---------|
| **Shopping** | 🛒 | Lista zakupów |
| **Tasks** | ✓ | Aktywne zadania |
| **Backlog** | 📦 | Long-term storage |
| **More** | ⋯ | Settings, Profile, Categories |

---

### 4.1 Shopping List Tab

**Purpose:** Quick capture and management of groceries and household essentials.

#### Layout
- **Top:** Header z Title ("Shopping"), Item Count Badge, Action Buttons (Clear All, Restock)
- **Body:** Scrollable list of active items
- **Bottom:** Floating "Add Item" input row (above tab bar context)

#### Components
- **Row:** Minimalist row. Left: Circular Checkbox. Center: Text.
- **Input:** Text field that remains active after "Enter" to allow rapid-fire entry

#### Transitions
- Checking item → immediate animation → item disappears → moves to "Restock" pool

---

### 4.2 Tasks Tab (Todo List)

**Purpose:** Daily chores and immediate to-dos.

#### Layout
- **Top:** Header ("Tasks")
- **Banner:** "Focus Rule" info banner (Blue, rounded) - "Max 3 active tasks" philosophy
- **Body:** Split list: "Active" items at top, "Completed" items at bottom

#### Task Row Components
- **Left:** Checkbox (Square/Rounded Square)
- **Center:** Title + Metadata Row
- **Metadata:** Due date (Orange if Today) • Assignee Pill (Gray background)
- **Right:** None (Clean edge)

#### Behavior
- Tapping task → toggles state between Active and Completed
- Completed tasks move to bottom section with strikethrough text

---

### 4.3 Backlog Tab

**Purpose:** Long-term storage for ideas and projects, categorized.

#### Layout
- **Top:** Header ("Backlog")
- **Body:** List of Categories, NOT flat tasks
- **Empty State:** Prompt directing to "More" tab to manage categories

#### Components
- **Category Card:** Grouped inset list (rounded container)
  - **Header:** Category Title (small caps, gray)
  - **Rows:** List of items inside
  - **Footer:** "Add item" button specific to that category
- **Backlog Item Row:** Dot indicator, Text, Chevron

**WAŻNE:** Items cannot exist outside a Category. Items are for storage, not "active" daily tasks.

---

### 4.4 More Tab

**Purpose:** Hub for settings, profile management, and global data configuration.

#### Layout
- **Top:** Header ("More")
- **Body:** Grouped inset lists (Settings-style)

#### Menu Options
1. **Profile Card:** Shows "Anna & Tom", plan details. Tapping → Profile Detail
2. **Backlog Categories:** Opens Category Management
3. **Repetitive Tasks:** Opens Recurring Task manager
4. **Settings:** Opens App Settings

---

## ⚙️ Szczegółowa logika

### Shopping List - Cycle of Items

```
Active → User taps checkbox → Bought (Checked)
                                    ↓
                            Moves to RestockPool
                                    ↓
User taps "Refresh" icon → Modal slides up → "Recently Purchased"
                                    ↓
User taps "+" next to item → Item moves back to Active list
```

**Mental Model:** "I bought Milk (check). Next week, I need Milk again (Restock → Add)."

#### Clear All / Undo
- Tapping "Trash" clears visible list
- Toast notification appears with "Undo" button for 4 seconds
- If Undo pressed → state reverts

---

### Tasks Screen - Visual Hierarchy

| State | Contrast | Position |
|-------|----------|----------|
| **Active** | High (Black/White text) | Top |
| **Completed** | Low (Gray text, strikethrough) | Bottom under "Completed" header |

#### Assignee Logic
- Tasks assigned to "Me" or specific names ("Tom") show small pill badge
- "Today" dates highlighted in Orange/Red (urgency)

---

### Backlog - Category-First Architecture

- Items cannot exist outside a Category
- Items are for storage, not "active" daily tasks
- **Structure changes** (add/remove categories) → More tab
- **Content changes** (add items to category) → Backlog tab

---

### More Screen - Sub-screens

#### 8.1 Profile Screen
- Display household name ("Smith Family Home")
- Members list ("Anna", "Tom")
- Edit Mode: Members can be removed (Trash icon)

#### 8.2 Backlog Categories Management
- List of all categories
- Add: Input field at bottom
- Delete: Trash icon on rows
- **Validation:** If category has items → confirmation modal before deletion

#### 8.3 Settings
- **Appearance:** 3-way toggle (Light / Dark / System) - immediate UI update
- **Toggles:** "Celebrations" (confetti effects), "Suggestions"

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
HousePulse/
├── Models/
│   ├── ShoppingItem.swift
│   ├── Task.swift
│   ├── BacklogCategory.swift
│   ├── Member.swift
│   └── Cached*.swift         # SwiftData dla offline
│
├── Views/
│   ├── ShoppingListView.swift
│   ├── TasksView.swift
│   ├── BacklogView.swift
│   ├── MoreView.swift
│   ├── ProfileView.swift
│   ├── CategoriesView.swift
│   ├── SettingsView.swift
│   └── Components/
│       ├── FloatingTabBar.swift
│       ├── CustomStatusBar.swift
│       └── ToastView.swift
│
├── Stores/
│   ├── ShoppingStore.swift
│   ├── TaskStore.swift
│   ├── BacklogStore.swift
│   └── ThemeStore.swift
│
├── Managers/
│   └── CloudKitManager.swift
│
└── Utilities/
```

---

## 🛠️ Implementacja SwiftUI

### Shared State (@EnvironmentObject / @Observable)

```swift
// BacklogContext: Shared between BacklogScreen and MoreScreen → BacklogCategoriesView
@Observable
class BacklogStore {
    var categories: [BacklogCategory] = []
}

// ThemeContext: Must wrap root view
@Observable
class ThemeStore {
    var theme: AppTheme = .system
}
```

### Custom Components

#### Bottom Navigation (NIE używaj native TabView!)

```swift
struct ContentView: View {
    @State private var activeTab: Tab = .shopping
    
    var body: some View {
        ZStack {
            // Content views
            Group {
                switch activeTab {
                case .shopping: ShoppingView()
                case .tasks: TasksView()
                case .backlog: BacklogView()
                case .more: MoreView()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.99)))
            .animation(.easeInOut(duration: 0.3), value: activeTab)
            
            // Floating Tab Bar overlay
            VStack {
                Spacer()
                FloatingTabBar(activeTab: $activeTab)
                    .padding(.bottom, 24)
            }
        }
    }
}
```

#### Tab Switching Animation

```swift
.transition(.opacity.combined(with: .scale).combined(with: .blur))
.animation(.easeInOut(duration: 0.3), value: activeTab)
```

### Interaction Details

- **Haptics:** Required for "premium" feel on check actions
- **Default Profile:** "Anna & Tom" hardcoded as default state
- **Shopping List:** Quantity REMOVED from UI (name only)

---

## 📱 Zalecenia dla iOS

### 1. Lokalizacja Multi-language (i18n/l10n)

| Język | Priorytet | Uzasadnienie |
|-------|-----------|--------------|
| **English** | ✅ Default | Globalny rynek |
| **Polish** | 🔥 HIGH | Główny rynek (autor) |
| **German** | 🔥 HIGH | Duży rynek |
| **Italian** | 🟡 MEDIUM | Popularny w niszach family |
| **Spanish** | 🟡 MEDIUM | 500M+ native speakers |

#### Rollout Plan
- v1.0: English only (MVP)
- v1.1: + Polish
- v1.2: + German

---

### 2. Dostępność dla wszystkich modeli iPhone

| Model | Ekran | Klasa rozmiaru |
|-------|-------|----------------|
| iPhone SE (2nd/3rd) | 4.7" | Compact |
| iPhone 13 mini | 5.4" | Compact |
| iPhone 14/15 | 6.1" | Regular |
| iPhone 14/15 Pro Max | 6.7" | Regular |

#### Zalecenia
- Dynamic Type z semantycznymi fontami
- Safe Areas dla floating tab bar
- ScrollView dla overflow content

---

### 3. VoiceOver i Accessibility

```swift
Button(action: addItem) {
    Image(systemName: "plus")
}
.accessibilityLabel("Add new item")
.accessibilityHint("Double tap to add item to list")
```

---

### 4. Dark Mode

**Full support required** - zgodnie z Global UI Rules:
- Light Mode: Off-white backgrounds (#F9F9F9)
- Dark Mode: Pure black backgrounds, dark gray cards (#1C1C1E)

---

### 5. Performance Guidelines

```swift
// Lazy loading dla list
LazyVStack {
    ForEach(items) { item in
        ItemRow(item: item)
    }
}
```

- Target app size: < 30 MB
- Use SF Symbols
- Haptic feedback na akcjach

---

## ✅ Status implementacji

### Ukończone

- [x] Projekt Xcode + shell aplikacji SwiftUI
- [x] Modele: ShoppingItem, Task, BacklogCategory, Member
- [x] TaskStore z WIP limit + optimistic UI
- [x] SwiftData offline cache
- [x] Sign in with Apple flow
- [x] GitHub Actions CI + Fastlane
- [x] Podstawowa obsługa offline

### W toku

- [ ] Floating Tab Bar (custom, nie native TabView)
- [ ] Tab switching animations (fade/scale/blur)
- [ ] Glassmorphism na Tab Bar i Toast
- [ ] Shopping List Restock flow
- [ ] TestFlight deploy

### Planowane

- [ ] Advanced sync (retry queue, conflict UI)
- [ ] Monetyzacja (StoreKit 2)
- [ ] Lokalizacja (PL, DE)

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

---

## 🗺️ Roadmapa

### Phase 1: MVP Launch (Current)

- [ ] Core functionality
- [ ] CloudKit sync
- [ ] Offline support
- [ ] Premium UI (floating tab, animations)
- [ ] TestFlight beta

### Phase 2: Polish (v1.1)

- [ ] Polish localization
- [ ] Bug fixes from beta
- [ ] Performance optimization

### Phase 3: Growth (v1.2+)

- [ ] German localization
- [ ] Monetization (StoreKit 2)
- [ ] Marketing launch

---

## 📚 Dokumentacja referencyjna

| Plik | Opis |
|------|------|
| Product Specification: House Pulse.md | Specyfikacja UI/UX |
| NEW_VERSION.md | Dokumentacja techniczna |
| README.md | Główny README projektu |
| CLAUDE.md | Wytyczne dla agentów AI |
| docs/ | Pełna dokumentacja techniczna |

---

**Utworzono:** 2026-01-31  
**Źródła:** Product Specification: House Pulse.md (UI/UX) + NEW_VERSION.md (Technical)  
**Ostatnia aktualizacja:** 2026-01-31
