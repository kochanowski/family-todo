# Wireframe - wyjaśnienie i przykłady

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie czym są wireframe'y i jak ich używać

---

## Czym jest Wireframe?

**Wireframe** to **szkic interfejsu użytkownika** - prosty, czarno-biały rysunek pokazujący:
- Gdzie są elementy na ekranie (przyciski, teksty, listy)
- Jak elementy są ułożone (layout)
- Jaka jest hierarchia informacji

### Prosta analogia:

Wyobraź sobie, że budujesz dom:
- 🏗️ **Plan architektoniczny** (wireframe) → Pokazuje rozmieszczenie pokoi, drzwi, okien
- 🎨 **Projekt wnętrz** (mockup) → Pokazuje kolory, meble, dekoracje
- 🏡 **Gotowy dom** (aplikacja) → Gotowy produkt do użycia

**Wireframe to "plan architektoniczny" dla aplikacji.**

---

## Po co robić wireframe'y?

### 1. **Przemyślenie UX przed kodowaniem**
Łatwiej zmienić prostą kreskę na papierze niż 200 linii kodu SwiftUI.

**Bez wireframe:**
```
"Napiszę kod... hmm, to tu przycisk... a może lepiej tam?
Ok, przepiszę... a może jednak inaczej? Przepiszę znowu..."
→ Zmarnowane 2 dni
```

**Z wireframe:**
```
"Narysuję 3 wersje na papierze w 30 minut... ta wygląda najlepiej!
Teraz piszę kod tylko raz."
→ Oszczędzone 1.5 dnia
```

### 2. **Komunikacja z innymi**
Jeśli pracujesz z kimś (żona, designer, inny dev), wireframe pokazuje jak ma wyglądać ekran.

### 3. **Walidacja pomysłu**
Możesz pokazać wireframe żonie i zapytać: "Czy tak będzie Ci wygodnie?"
Bez kodowania ani linijki.

### 4. **Dokumentacja projektu**
Za 6 miesięcy będziesz wiedzieć "jak to miało wyglądać".

---

## Rodzaje wireframe'ów

### 1. **Low-fidelity (niska jakość)**
- Prosty szkic ręczny lub w narzędziu
- Czarno-białe prostokąty i tekst
- Brak kolorów, zdjęć, precyzyjnych fontów
- **Cel:** Szybkie sprawdzenie layoutu i flow

**Przykład:**
```
┌─────────────────────┐
│  < Back    Tasks    │
├─────────────────────┤
│                     │
│ ☐ Wipe dust         │
│   Every Monday      │
│   Next: Jan 15      │
│                     │
│ ☐ Clean bathroom   │
│   Every Friday      │
│   Next: Jan 12      │
│                     │
│ [+ Add Chore]       │
│                     │
└─────────────────────┘
```

### 2. **High-fidelity (wysoka jakość)**
- Bardziej szczegółowy, bliski finalnemu wyglądowi
- Może zawierać kolory, ikony, prawdziwe texty
- **Cel:** Finalna wersja przed kodowaniem

**Dla MVP starczy low-fidelity!**

---

## Narzędzia do wireframe'ów

### ✏️ Papier i długopis (NAJLEPSZE dla MVP!)
- **Koszt:** 0 zł
- **Czas:** 5-30 minut
- **Zalety:** Najszybsza iteracja, zero barier
- **Wady:** Trzeba sfotografować żeby zapisać

### 📱 Excalidraw (rekomendowane dla cyfrowego)
- **Koszt:** Darmowe
- **Link:** [excalidraw.com](https://excalidraw.com)
- **Zalety:** Szybkie, proste, ręcznie rysowane style
- **Wady:** Brak dedykowanych komponentów iOS

### 🎨 Figma (profesjonalne)
- **Koszt:** Darmowe dla 1 osoby
- **Link:** [figma.com](https://figma.com)
- **Zalety:** Profesjonalne narzędzie, biblioteki iOS komponentów, współpraca
- **Wady:** Stroma krzywa uczenia, overkill dla prostych wireframe'ów

### 📐 Inne narzędzia:
- **Balsamiq** - specjalizuje się w wireframe'ach (płatne)
- **Sketch** - tylko macOS (płatne)
- **Adobe XD** - profesjonalne (płatne)
- **draw.io** - darmowe, dobre do diagramów

**Dla Family To-Do:** Papier + długopis lub Excalidraw wystarczą!

---

## Jak stworzyć dobry wireframe?

### ✅ DO:
1. **Zacznij od listy elementów:** Co musi być na ekranie?
   - Tytuł ekranu
   - Lista tasków
   - Przyciski akcji
   - Informacje dodatkowe

2. **Używaj prostokątów i etykiet:**
   ```
   [Button]
   ┌──────┐
   │ Text │
   └──────┘
   ```

3. **Pokazuj hierarchię:** Co jest najważniejsze? (większy font, bold)

4. **Opisuj interakcje:**
   - "Tap → otwiera ekran szczegółów"
   - "Swipe left → usuwa task"

5. **Rysuj kilka wersji:** Porównaj 2-3 layouty i wybierz najlepszy

### ❌ DON'T:
1. ❌ Nie spędzaj godzin na perfekcji - to szkic!
2. ❌ Nie dodawaj kolorów na tym etapie
3. ❌ Nie projektuj pixel-perfect - zostaw to dla mockupu
4. ❌ Nie rysuj każdego ekranu - skup się na kluczowych

---

## Wireframe dla Recurring Chores (Family To-Do)

Poniżej znajdują się wireframe'y dla funkcjonalności recurring chores w aplikacji Family To-Do.

### Ekran 1: Lista Recurring Chores

```
╔═══════════════════════════════════════╗
║  < Household    Recurring Chores   +  ║  ← Top bar
╠═══════════════════════════════════════╣
║                                       ║
║  🧹 Kitchen                           ║  ← Area section
║  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ║
║                                       ║
║  ☐ Wipe counters                     ║  ← Chore item
║     Every Monday                      ║     Frequency
║     👤 Wojtek                         ║     Assignee
║     Next: Jan 15 (6 days)            ║     Next occurrence
║                                       ║
║  ☐ Empty dishwasher                  ║
║     Every 2 days                      ║
║     👤 Partner                        ║
║     Next: Tomorrow                    ║
║                                       ║
║  🚽 Bathroom                          ║  ← Area section
║  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ║
║                                       ║
║  ☐ Clean toilet                      ║
║     Every Friday                      ║
║     👤 Wojtek                         ║
║     Next: Jan 12 (3 days)            ║
║                                       ║
║  ☐ Wipe mirror                       ║
║     Every week                        ║
║     👤 Partner                        ║
║     Next: Jan 14 (5 days)            ║
║                                       ║
╚═══════════════════════════════════════╝

Interactions:
- Tap chore → Open detail view
- Swipe right → Mark as done (reschedules automatically)
- Swipe left → Edit or delete
- Tap "+" → Add new recurring chore
```

**Kluczowe elementy:**
- ✅ **Checkbox** - pokazuje status (to be done)
- 📅 **Frequency** - jasno pokazane "Every Monday"
- 👤 **Assignee** - kto jest odpowiedzialny
- ⏰ **Next occurrence** - kiedy następne wykonanie
- 🏠 **Area grouping** - pogrupowane po obszarach (Kitchen, Bathroom)

---

### Ekran 2: Dodawanie Recurring Chore

```
╔═══════════════════════════════════════╗
║  < Cancel    New Chore         Done   ║  ← Top bar
╠═══════════════════════════════════════╣
║                                       ║
║  Title                                ║  ← Text field
║  ┌───────────────────────────────────┐║
║  │ Clean toilet                      │║
║  └───────────────────────────────────┘║
║                                       ║
║  Frequency                            ║  ← Picker
║  ┌───────────────────────────────────┐║
║  │ Every week               ▼       │║
║  └───────────────────────────────────┘║
║    Options:                           ║
║    • Every day                        ║
║    • Every week                       ║
║    • Every 2 weeks                    ║
║    • Every month                      ║
║                                       ║
║  Day                                  ║  ← Day picker (if weekly)
║  ┌───────────────────────────────────┐║
║  │ M  T  W  T  F  S  S              │║
║  │         ✓                         │║  (Friday selected)
║  └───────────────────────────────────┘║
║                                       ║
║  Assigned to                          ║  ← Member picker
║  ┌───────────────────────────────────┐║
║  │ 👤 Wojtek                ▼       │║
║  └───────────────────────────────────┘║
║                                       ║
║  Area                                 ║  ← Area picker
║  ┌───────────────────────────────────┐║
║  │ 🚽 Bathroom              ▼       │║
║  └───────────────────────────────────┘║
║                                       ║
║  First occurrence                     ║  ← Date picker
║  ┌───────────────────────────────────┐║
║  │ Jan 12, 2026                     │║
║  └───────────────────────────────────┘║
║                                       ║
╚═══════════════════════════════════════╝

Interactions:
- Tap "Done" → Save chore and return to list
- Tap "Cancel" → Discard and return
- Frequency changes day picker visibility
  (e.g., monthly shows day of month, weekly shows weekday)
```

**Kluczowe decyzje UX:**
- ✅ **Simple frequency picker** - nie "cron expressions", tylko naturalne opcje
- ✅ **Visual day picker** - kliknij dzień tygodnia (M T W T F S S)
- ✅ **Auto-calculate first occurrence** - inteligentnie wybiera najbliższy dzień
- ✅ **Area optional** - można zostawić puste

---

### Ekran 3: Szczegóły Recurring Chore

```
╔═══════════════════════════════════════╗
║  < Back            Edit               ║  ← Top bar
╠═══════════════════════════════════════╣
║                                       ║
║  Clean toilet                         ║  ← Title (large)
║                                       ║
║  ┌─────────────────────────────────┐ ║
║  │ 📅 Every Friday                 │ ║  ← Info card
║  │ 👤 Wojtek                       │ ║
║  │ 🚽 Bathroom                     │ ║
║  └─────────────────────────────────┘ ║
║                                       ║
║  Next Occurrence                      ║  ← Section header
║  ┌─────────────────────────────────┐ ║
║  │ Friday, Jan 12                  │ ║
║  │ In 3 days                       │ ║
║  │                                 │ ║
║  │     [✓ Mark as Done]            │ ║  ← Primary action
║  └─────────────────────────────────┘ ║
║                                       ║
║  History                              ║  ← Section header
║  ┌─────────────────────────────────┐ ║
║  │ ✓ Jan 5  (Completed by Wojtek) │ ║
║  │ ✓ Dec 29 (Completed by Partner)│ ║
║  │ ✓ Dec 22 (Completed by Wojtek) │ ║
║  │ ✓ Dec 15 (Completed by Wojtek) │ ║
║  └─────────────────────────────────┘ ║
║                                       ║
║  [Delete Chore]                       ║  ← Destructive action
║                                       ║
╚═══════════════════════════════════════╝

Interactions:
- Tap "Mark as Done" → Chore marked complete, auto-schedules next occurrence
- Tap "Edit" → Open edit form
- Tap "Delete Chore" → Confirmation alert
- Tap history item → (optional) Show who did it and when
```

**Kluczowe elementy:**
- ✅ **Clear next occurrence** - jasno widoczne kiedy następne
- ✅ **One-tap completion** - duży przycisk "Mark as Done"
- ✅ **History** - pokazuje kto i kiedy wykonywał (transparency)
- ✅ **Delete at bottom** - destructive action na końcu ekranu

---

### Flow: Oznaczanie jako Done

```
Step 1: User taps "Mark as Done"
   ↓
Step 2: System shows gentle celebration
   ┌─────────────────────────────────┐
   │  ✨ Nice work!                  │
   │  Bathroom is clean              │
   │                                 │
   │  Next: Friday, Jan 19           │
   └─────────────────────────────────┘
   (Auto-dismiss after 2 seconds)
   ↓
Step 3: Chore auto-scheduled for next occurrence
   - Creates new task in Backlog with status "Scheduled"
   - Updates "lastCompletedAt" timestamp
   - Updates "nextScheduledAt" to next Friday
   ↓
Step 4: User sees updated list
   - "Next: Jan 19" instead of "Next: Jan 12"
   - History shows new completion entry
```

---

### Flow: Gdy recurring chore jest gotowe do wykonania

```
System checks daily at 6 AM:
   ↓
If today = nextScheduledAt:
   ↓
   Create new Task in Backlog:
   - Title: "Clean toilet"
   - Assignee: Wojtek
   - Area: Bathroom
   - Priority: "This Week"
   - isRecurring: true
   - linkedChoreID: [recurring chore ID]
   ↓
   User opens app:
   ┌─────────────────────────────────┐
   │ 💭 Gentle Reminder              │
   │                                 │
   │ 1 new task for this week:       │
   │ • Clean toilet (Bathroom)       │
   │                                 │
   │    [View Tasks]    [Dismiss]    │
   └─────────────────────────────────┘
   (Notification - dismissible)
```

**UX decision:**
- ✅ Nie "na siłę" dodawać do Next (limit 3 tasków!)
- ✅ Zamiast tego - dodaj do Backlog z priority "This Week"
- ✅ User sam decyduje kiedy przesunąć do Next

---

## Wireframe dla całego flow aplikacji

### Mapa ekranów:

```
[Launch Screen]
       ↓
[Sign in with Apple]
       ↓
┌─────────────────────┐
│   Home (My Tasks)   │ ← Main screen
└─────────────────────┘
       ↓
   ┌───┴───┬──────────┬─────────────┐
   ↓       ↓          ↓             ↓
[Next]  [Backlog]  [Done]  [Household Settings]
   ↓
[Task Detail] ← Can edit, complete, delete
   ↓
[Edit Task]


[Household Settings]
   ↓
   ├─ [Recurring Chores] ← Focus screen
   │    ↓
   │    ├─ [Add Chore]
   │    └─ [Chore Detail]
   │         ↓
   │         └─ [Edit Chore]
   │
   ├─ [Areas]
   ├─ [Members]
   └─ [Share Household]
```

**Kluczowe ekrany dla MVP:**
1. ✅ **Home (My Tasks)** - główny ekran z trzema tabami (Next, Backlog, Done)
2. ✅ **Task Detail** - szczegóły taska + edit
3. ✅ **Recurring Chores** - lista recurring chores
4. ✅ **Add/Edit Chore** - formularz
5. ✅ **Household Settings** - zaproszenia, członkowie, obszary

---

## Wireframe best practices dla iOS

### 1. Navigation Patterns

**iOS ma standardowe wzorce:**
```
┌─────────────────────────────────┐
│ < Back        Title       Edit  │ ← Navigation Bar
├─────────────────────────────────┤
│                                 │
│         Content                 │
│                                 │
│                                 │
├─────────────────────────────────┤
│   [Home] [Tasks] [Settings]    │ ← Tab Bar (optional)
└─────────────────────────────────┘
```

**Dla Family To-Do używamy:**
- **Navigation Bar** - tytuł ekranu, przycisk wstecz, action button (Edit, +, Done)
- **Tab Bar** - dla głównych sekcji (My Tasks, Household, Settings)
- **Modals** - dla formularzy (Add Task, Add Chore)

### 2. Touch Targets

**Minimum 44x44 points** dla wszystkich elementów dotykowych:
```
❌ Too small:
[✓]  (20x20) - trudno trafić palcem

✅ Good:
[ ✓ ]  (44x44) - łatwo trafić
```

### 3. Spacing & Padding

**iOS Human Interface Guidelines:**
- 16px padding od krawędzi ekranu
- 8-12px spacing między elementami
- 20-24px spacing między sekcjami

```
╔═══════════════════════════════╗
║←16px                     16px→║
║  ┌─────────────────────────┐ ║
║  │ Element                 │ ║
║  └─────────────────────────┘ ║
║  ↕ 12px spacing             ║
║  ┌─────────────────────────┐ ║
║  │ Element                 │ ║
║  └─────────────────────────┘ ║
╚═══════════════════════════════╝
```

### 4. Typography Hierarchy

**iOS dynamiczne fonty:**
- **Large Title** - 34pt (main screen title)
- **Title** - 28pt (section headers)
- **Headline** - 17pt bold (list items)
- **Body** - 17pt (content text)
- **Footnote** - 13pt (secondary info)
- **Caption** - 11pt (timestamps)

### 5. iOS Gestures w wireframe

Zaznaczaj standardowe gesty iOS:
- **Tap** - otwórz/zamknij/akcja
- **Swipe** - usuń, zaznacz jako done
- **Long press** - kontekstowe menu
- **Pull to refresh** - odśwież listę
- **Pinch** - zoom (jeśli applicable)

---

## Podsumowanie

**Wireframe to:**
- 📝 Szkic interfejsu przed kodowaniem
- ⚡ Szybka walidacja UX (30 min vs 2 dni przepisywania kodu)
- 🗣️ Narzędzie komunikacji w zespole
- 📚 Dokumentacja projektu

**Dla Family To-Do MVP:**
- ✅ Używaj low-fidelity wireframe'ów (papier lub Excalidraw)
- ✅ Skup się na kluczowych ekranach (Home, Task Detail, Recurring Chores)
- ✅ Pokaż żonie wireframe'y i zbierz feedback PRZED kodowaniem
- ✅ Iteruj szybko - rysuj, testuj, poprawiaj

**Pamiętaj:**
Wireframe to nie sztuka - to narzędzie do przemyślenia UX!
Lepiej brzydki wireframe niż przepisywanie 1000 linii kodu.

---

## Przydatne linki

- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Excalidraw](https://excalidraw.com) - Darmowe narzędzie do wireframe'ów
- [Figma iOS UI Kit](https://www.figma.com/community/file/768726574016795759) - Gotowe komponenty iOS
- [Mobile UI Patterns](https://mobbin.com) - Inspiracje z realnych aplikacji

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
