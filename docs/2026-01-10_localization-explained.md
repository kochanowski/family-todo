# Localization (Lokalizacja) - wyjaśnienie

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie jak dodać tłumaczenia na wiele języków (PL, DE, IT, ES, ZH, JA)

---

## Czym jest lokalizacja (i18n)?

**Localization (l10n)** = adaptacja aplikacji do różnych języków i regionów
**Internationalization (i18n)** = przygotowanie kodu do łatwej lokalizacji

### Prosta analogia:

Wyobraź sobie restaurację:
- **i18n** = menu z wymiennymi kartonami (struktura)
- **l10n** = kartony w różnych językach (polski, niemiecki, włoski)

### Dla Family To-Do:

Zamiast hardcoded:
```swift
Text("Add Task")  // ❌ Tylko angielski
```

Używamy:
```swift
Text("add_task")  // ✅ Klucz do tłumaczenia
→ Polski: "Dodaj zadanie"
→ Niemiecki: "Aufgabe hinzufügen"
→ Włoski: "Aggiungi attività"
```

---

## Dlaczego lokalizować Family To-Do?

### 1. **Większy rynek**
Każdy język = nowi użytkownicy:
```
Tylko angielski: ~400M native speakers
+ Polski: +40M
+ Niemiecki: +100M
+ Włoski: +65M
+ Hiszpański: +500M
+ Chiński: +900M
+ Japoński: +125M
────────────────────
TOTAL: ~2.1 miliarda potential users!
```

### 2. **Lepsze recenzje w App Store**
Users UWIELBIAJĄ apps w swoim języku:
```
App tylko po angielsku:
"Good app but needs Polish translation ⭐⭐⭐"

App po polsku:
"Świetna apka, wszystko po polsku! ⭐⭐⭐⭐⭐"
```

### 3. **Wyższe downloads w lokalnych App Store**
App Store w Polsce promuje polskie aplikacje!

### 4. **Competitive advantage**
Większość to-do apps to tylko angielski
→ Family To-Do w 7 językach = przewaga!

---

## Języki docelowe dla Family To-Do

| Język | Native Speakers | Target Region | Priority |
|---|---|---|---|
| **English** | 400M | USA, UK, Australia | ✅ Default |
| **Polish** | 40M | Poland | 🔥 HIGH |
| **German** | 100M | Germany, Austria, Switzerland | 🔥 HIGH |
| **Italian** | 65M | Italy | 🟡 MEDIUM |
| **Spanish** | 500M | Spain, LatAm | 🟡 MEDIUM |
| **Chinese (Simplified)** | 900M | China, Singapore | 🟢 LOW (MVP) |
| **Japanese** | 125M | Japan | 🟢 LOW (MVP) |

**MVP priorytet:**
1. English (default)
2. Polish (Ty i Twój rynek)
3. German (duży rynek, blisko Polski)
4. Pozostałe: post-MVP

---

## iOS Localization - jak to działa?

### Struktura plików:

```
FamilyTodo/
├── en.lproj/           ← Angielski
│   └── Localizable.strings
├── pl.lproj/           ← Polski
│   └── Localizable.strings
├── de.lproj/           ← Niemiecki
│   └── Localizable.strings
├── it.lproj/           ← Włoski
│   └── Localizable.strings
├── es.lproj/           ← Hiszpański
│   └── Localizable.strings
├── zh-Hans.lproj/      ← Chiński (uproszczony)
│   └── Localizable.strings
└── ja.lproj/           ← Japoński
    └── Localizable.strings
```

### Localizable.strings format:

```
/* Comment explaining the string */
"key" = "Translated value";
```

**Przykład (en.lproj/Localizable.strings):**
```
/* Main tab title */
"tab_tasks" = "Tasks";

/* Button to add new task */
"button_add_task" = "Add Task";

/* Recurring chore frequency */
"frequency_weekly" = "Every week";
```

**Przykład (pl.lproj/Localizable.strings):**
```
/* Main tab title */
"tab_tasks" = "Zadania";

/* Button to add new task */
"button_add_task" = "Dodaj zadanie";

/* Recurring chore frequency */
"frequency_weekly" = "Co tydzień";
```

---

## Krok 1: Przygotowanie kodu (i18n)

### 1.1 Oznacz stringi do tłumaczenia

**PRZED (hardcoded):**
```swift
Text("Add Task")
Button("Save") { }
.navigationTitle("My Tasks")
```

**PO (localized):**
```swift
Text(NSLocalizedString("button_add_task", comment: "Button to add new task"))
Button(NSLocalizedString("button_save", comment: "Save button")) { }
.navigationTitle(NSLocalizedString("nav_my_tasks", comment: "Navigation title"))
```

### 1.2 Uproszczony helper (recommended)

Stwórz helper żeby nie pisać `NSLocalizedString` za każdym razem:

```swift
// Localization.swift
import Foundation

extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}
```

**Użycie:**
```swift
Text("button_add_task".localized)
Button("button_save".localized) { }
.navigationTitle("nav_my_tasks".localized)

// Z parametrami:
Text("tasks_count".localized(5)) // "5 tasks"
```

### 1.3 Pluralization (liczba mnoga)

Polski ma TRZY formy liczby mnogiej (1, 2-4, 5+):
```
1 zadanie (singular)
2 zadania (few)
5 zadań (many)
```

**Użyj .stringsdict:**
```xml
<!-- en.lproj/Localizable.stringsdict -->
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>tasks_count</key>
    <dict>
        <key>NSStringLocalizedFormatKey</key>
        <string>%#@tasks@</string>
        <key>tasks</key>
        <dict>
            <key>NSStringFormatSpecTypeKey</key>
            <string>NSStringPluralRuleType</string>
            <key>NSStringFormatValueTypeKey</key>
            <string>d</string>
            <key>one</key>
            <string>%d task</string>
            <key>other</key>
            <string>%d tasks</string>
        </dict>
    </dict>
</dict>
</plist>
```

```xml
<!-- pl.lproj/Localizable.stringsdict -->
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>tasks_count</key>
    <dict>
        <key>NSStringLocalizedFormatKey</key>
        <string>%#@tasks@</string>
        <key>tasks</key>
        <dict>
            <key>NSStringFormatSpecTypeKey</key>
            <string>NSStringPluralRuleType</string>
            <key>NSStringFormatValueTypeKey</key>
            <string>d</string>
            <key>one</key>
            <string>%d zadanie</string>
            <key>few</key>
            <string>%d zadania</string>
            <key>many</key>
            <string>%d zadań</string>
            <key>other</key>
            <string>%d zadań</string>
        </dict>
    </dict>
</dict>
</plist>
```

**Użycie w kodzie:**
```swift
let count = 5
Text("tasks_count".localized(count)) // "5 zadań"
```

---

## Krok 2: Setup w Xcode

### 2.1 Dodaj języki do projektu

1. W Xcode, wybierz **projekt** (top level)
2. W sekcji **Info** znajdź **Localizations**
3. Kliknij **"+"** i dodaj języki:
   - Polish (pl)
   - German (de)
   - Italian (it)
   - Spanish (es)
   - Chinese, Simplified (zh-Hans)
   - Japanese (ja)

### 2.2 Utwórz Localizable.strings

1. **File → New → File**
2. Wybierz **Strings File**
3. Nazwij: `Localizable.strings`
4. **Save**

5. Wybierz `Localizable.strings` w navigatorze
6. W **File Inspector** (prawy panel):
   - Kliknij **"Localize..."**
   - Wybierz **Base**
   - Kliknij **Localize**

7. Teraz zaznacz checkboxy dla wszystkich języków:
   - ☑ English
   - ☑ Polish
   - ☑ German
   - ☑ Italian
   - ☑ Spanish
   - ☑ Chinese (Simplified)
   - ☑ Japanese

Xcode automatycznie utworzy foldery `*.lproj/`

---

## Krok 3: Tłumaczenie - DIY z AI

### 3.1 Przygotuj plik bazowy (English)

**en.lproj/Localizable.strings:**
```
/* Tab Titles */
"tab_tasks" = "Tasks";
"tab_household" = "Household";
"tab_settings" = "Settings";

/* Buttons */
"button_add_task" = "Add Task";
"button_add_chore" = "Add Chore";
"button_save" = "Save";
"button_cancel" = "Cancel";
"button_delete" = "Delete";

/* Task Status */
"status_backlog" = "Backlog";
"status_next" = "Next";
"status_done" = "Done";

/* Recurring Chores */
"frequency_daily" = "Every day";
"frequency_weekly" = "Every week";
"frequency_biweekly" = "Every 2 weeks";
"frequency_monthly" = "Every month";

/* Priority */
"priority_today" = "Today";
"priority_this_week" = "This Week";
"priority_someday" = "Someday";

/* Areas */
"area_kitchen" = "Kitchen";
"area_bathroom" = "Bathroom";
"area_living_room" = "Living Room";
"area_bedroom" = "Bedroom";
"area_garden" = "Garden";

/* Notifications */
"notification_task_due_today" = "Task due today";
"notification_chore_scheduled" = "Recurring chore scheduled";

/* Errors */
"error_generic" = "Something went wrong";
"error_network" = "Network error. Please try again.";
"error_icloud_not_signed_in" = "Please sign into iCloud in Settings";
```

### 3.2 Prompt do tłumaczenia z ChatGPT/Claude

**Template prompt:**
```
Przetłumacz poniższy plik lokalizacyjny iOS na [JĘZYK].

Kontekst: Family To-Do App - aplikacja do zarządzania zadaniami domowymi dla rodzin.

Zasady:
1. Zachowaj format: "key" = "value";
2. Tłumacz TYLKO wartości (po prawej), NIE klucze (po lewej)
3. Zachowaj komentarze /* */ w języku angielskim
4. Użyj naturalnego, codziennego języka (nie formalnego)
5. Tłumacz kontekstowo (np. "Next" w kontekście tasków to "Następne", nie "Dalej")

[WKLEJ PLIK en.lproj/Localizable.strings]

Zwróć gotowy plik pl.lproj/Localizable.strings do skopiowania.
```

**Przykład dla polskiego:**
```
Przetłumacz poniższy plik lokalizacyjny iOS na polski.

[... reszta promptu ...]

/* Tab Titles */
"tab_tasks" = "Tasks";
"tab_household" = "Household";
...
```

**Odpowiedź AI:**
```
/* Tab Titles */
"tab_tasks" = "Zadania";
"tab_household" = "Dom";
"tab_settings" = "Ustawienia";

/* Buttons */
"button_add_task" = "Dodaj zadanie";
"button_add_chore" = "Dodaj obowiązek";
"button_save" = "Zapisz";
"button_cancel" = "Anuluj";
"button_delete" = "Usuń";

/* Task Status */
"status_backlog" = "Zaległości";
"status_next" = "Następne";
"status_done" = "Zrobione";
...
```

### 3.3 Języki specjalne - uwagi

#### **Niemiecki (German)**
- Długie słowa złożone (Compoundwörter):
  ```
  "Recurring Chore" → "Wiederkehrende Aufgabe"
  ```
- UI może się rozciągnąć - testuj długie stringi!
- Formalne "Sie" vs nieformalne "du"
  - **Dla Family To-Do:** Użyj "du" (nieformalne, friendly)

#### **Włoski (Italian)**
- Rodzaje (masculine/feminine):
  ```
  "il compito" (task - masculine)
  "la routine" (chore - feminine)
  ```
- Wielokrotne formy liczby mnogiej

#### **Hiszpański (Spanish)**
- Dialekty: España vs LatAm
  - **Dla Family To-Do:** Użyj neutralnego hiszpańskiego (zrozumiałe wszędzie)
- "Vosotros" (España) vs "Ustedes" (LatAm)
  - Użyj "Ustedes" (bardziej uniwersalne)

#### **Chiński (Simplified)**
- **Brak spacji** między słowami:
  ```
  English: "Add Task"
  Chinese: "添加任务" (no space)
  ```
- **Krótki!** Chiński zajmuje mniej miejsca niż angielski
- **Tone:** Uprzejmy, nie zbyt formalny

#### **Japoński (Japanese)**
- **3 systemy pisma:** Kanji, Hiragana, Katakana
- **Grzeczność:** Casual vs formal
  - **Dla Family To-Do:** Casual (friendly app)
- **Przykład:**
  ```
  English: "Add Task"
  Japanese: "タスクを追加" (tasuku wo tsuika)
  ```

---

## Krok 4: Weryfikacja tłumaczeń

### 4.1 AI Review Prompt

Po otrzymaniu tłumaczenia, poproś AI o review:

```
Zweryfikuj poniższe tłumaczenie na [JĘZYK] pod kątem:
1. Poprawności gramatycznej
2. Naturalności (czy brzmi jak native speaker?)
3. Spójności terminów (czy "task" jest zawsze tłumaczone tak samo?)
4. Długości stringów (czy UI się zmieści?)

Kontekst: Family To-Do App dla rodzin.
Ton: Friendly, casual, helpful (nie formalny).

[WKLEJ TŁUMACZENIE]

Zwróć listę problemów + poprawione wersje.
```

### 4.2 Native Speaker Review (recommended)

**Gdzie znaleźć:**
- Fiverr ($5-20 per language)
- Upwork ($10-30/hour)
- Reddit (r/translator - darmowe, ale może być nierzetelne)
- Znajomi native speakers

**Checklist do reviewera:**
```
Proszę zweryfikuj tłumaczenia:
1. Czy wszystko brzmi naturalnie?
2. Czy ton jest friendly (nie zbyt formalny)?
3. Czy są błędy gramatyczne?
4. Czy jakieś stringi są zbyt długie dla UI?
5. Sugestie ulepszeń?
```

---

## Krok 5: Testowanie lokalizacji

### 5.1 Zmiana języka w Simulatorze

**Opcja A: Settings (jak real device):**
```
1. Simulator → Settings
2. General → Language & Region
3. Preferred Languages → Add Language → Polski
4. Uruchom app ponownie
```

**Opcja B: Xcode Scheme (faster):**
```
1. Product → Scheme → Edit Scheme
2. Run → Options
3. App Language → Polish
4. Uruchom app (Cmd+R)
```

### 5.2 Co testować?

**Checklist:**
- ✅ Wszystkie ekrany pokazują przetłumaczone texty
- ✅ Buttony się mieszczą (nie są obcięte)
- ✅ Navigationowe tytuły są OK
- ✅ Pluralization działa (1 task, 2 tasks, 5 tasks)
- ✅ Daty formatowane poprawnie (DD/MM/YYYY vs MM/DD/YYYY)
- ✅ Liczby formatowane poprawnie (1,000 vs 1.000)

### 5.3 Screenshot Testing

**Dla każdego języka zrób screenshots:**
```
1. Main screen (Tasks list)
2. Add Task screen
3. Recurring Chores screen
4. Settings screen
```

**Użyj do:**
- App Store screenshots (każdy język ma swoje screenshots!)
- Bug reporting (pokaz długie stringi)
- Marketing materials

---

## Krok 6: Formatowanie dat i liczb

### 6.1 Daty

**NIE rób tego:**
```swift
❌ "\\(day)/\\(month)/\\(year)" // Hardcoded format
```

**Rób to:**
```swift
✅ date.formatted(date: .long, time: .omitted)
```

**Rezultat:**
```
English: "January 15, 2026"
Polish: "15 stycznia 2026"
German: "15. Januar 2026"
Japanese: "2026年1月15日"
```

### 6.2 Liczby

**NIE rób tego:**
```swift
❌ String(format: "%.2f", 1234.56) // "1234.56"
```

**Rób to:**
```swift
✅ number.formatted(.number.precision(.fractionLength(2)))
```

**Rezultat:**
```
English: "1,234.56"
German: "1.234,56"
Polish: "1 234,56"
```

### 6.3 Waluty

```swift
let price = 4.99
Text(price, format: .currency(code: "USD"))
```

**Rezultat:**
```
English (US): "$4.99"
Polish: "4,99 USD"
German: "4,99 $"
```

---

## Krok 7: App Store Metadata Localization

### 7.1 Co trzeba przetłumaczyć w App Store?

**Dla każdego języka:**
1. **App Name** (opcjonalnie, może być ten sam)
2. **Subtitle** (30 znaków)
3. **Description** (4000 znaków)
4. **Keywords** (100 znaków, comma-separated)
5. **Screenshots** (z przetłumaczonym UI)
6. **Preview Video** (opcjonalne)
7. **What's New** (release notes)

### 7.2 Przykład - Polski

**App Name:**
```
Family To-Do
(lub: Rodzinne Zadania)
```

**Subtitle:**
```
Zadania domowe dla rodzin
```

**Description:**
```
Family To-Do to prosta aplikacja do zarządzania zadaniami domowymi, stworzona dla par i rodzin.

Kluczowe funkcje:
• Wspólne gospodarstwo domowe - współdzielcie zadania z partnerem
• Cykliczne obowiązki - automatycznie planuj cotygodniowe sprzątanie
• Limit 3 tasków - skup się na tym co ważne
• Delikatne przypomnienia - bez nacisków i presji
• Offline-first - działa bez internetu

Dlaczego Family To-Do?
✓ Zaprojektowane dla par, nie dla project managerów
✓ Proste, bez zbędnych funkcji
✓ Privacy-first - dane w Twoim iCloud
✓ Jedna wspólna lista - koniec z zapominaniem

Pobierz za darmo i zacznij organizować dom razem!
```

**Keywords:**
```
zadania,rodzina,dom,para,współdzielenie,sprzątanie,obowiązki,lista,to-do,household
```

### 7.3 App Store Connect Setup

```
1. App Store Connect → My Apps → Family To-Do
2. Lewe menu: App Store → [Version]
3. Prawy górny róg: Language dropdown
4. Wybierz język (np. Polish)
5. Wypełnij wszystkie pola
6. Upload screenshots (z polskim UI!)
7. Save
8. Powtórz dla każdego języka
```

---

## Koszt lokalizacji

### DIY z AI (Recommended dla MVP):

| Język | AI Translation | Native Review | Screenshots | Total |
|---|---|---|---|---|
| Polish | $0 (ChatGPT) | $15 (Fiverr) | 2h (self) | **~$15** |
| German | $0 | $20 | 2h | **~$20** |
| Italian | $0 | $20 | 2h | **~$20** |
| Spanish | $0 | $20 | 2h | **~$20** |
| Chinese | $0 | $25 | 2h | **~$25** |
| Japanese | $0 | $25 | 2h | **~$25** |

**Total dla 6 języków:** ~$125 + 12h czasu

### Profesjonalne tłumaczenie:

| | DIY + AI | Professional |
|---|---|---|
| **Koszt/język** | $15-25 | $100-300 |
| **Jakość** | 85-90% | 95-100% |
| **Czas** | 2-4h/język | 1-2 tygodnie |
| **Total (6 języków)** | **$125** | **$600-1,800** |

**Dla Family To-Do MVP:** DIY + AI + native review wystarczy!

---

## Maintenance (utrzymanie tłumaczeń)

### Problem:
Dodajesz nową funkcję → nowe stringi → trzeba tłumaczyć ponownie!

### Rozwiązanie:

**1. Komentuj nowe stringi:**
```
/* NEW in v1.1 - Export feature */
"button_export_csv" = "Export to CSV";
```

**2. Użyj diff tool:**
```bash
# Znajdź nowe klucze
diff en.lproj/Localizable.strings pl.lproj/Localizable.strings
```

**3. Przetłumacz tylko nowe:**
```
Prompt dla AI:
"Przetłumacz tylko te nowe stringi na polski:
[WKLEJ NOWE STRINGI]"
```

**4. Partial release:**
Możesz wypuścić feature tylko w niektórych językach:
```swift
if Locale.current.language.languageCode == "en" {
    // Show export feature
} else {
    // Coming soon message
}
```

---

## Troubleshooting

### Issue: "Stringi nie są przetłumaczone w app"

**Rozwiązanie:**
1. Sprawdź czy klucz w kodzie == klucz w .strings:
   ```swift
   "button_add_task".localized // Musi być dokładnie "button_add_task"
   ```
2. Clean build folder: Product → Clean Build Folder (Cmd+Shift+K)
3. Sprawdź czy `.lproj` foldery są w target membership

### Issue: "Polski nie pojawia się jako opcja w Simulator"

**Rozwiązanie:**
1. Sprawdź Project → Info → Localizations → czy Polish jest tam?
2. Rebuild app
3. Delete app z Simulator i zainstaluj ponownie

### Issue: "Długie stringi są obcięte w UI"

**Rozwiązanie:**
```swift
// Zamiast:
Text(longString)

// Użyj:
Text(longString)
    .lineLimit(nil) // Allow multiple lines
    .minimumScaleFactor(0.8) // Shrink if needed
```

---

## Podsumowanie

### Dla Family To-Do MVP:

**Języki (priorytet):**
1. ✅ English (default)
2. ✅ Polish (main market)
3. ✅ German (large market)
4. 🟡 Italian, Spanish, Chinese, Japanese (post-MVP)

**Implementacja:**
- Setup w Xcode: 2-3h
- Ekstrakcja stringów: 2-3h
- Tłumaczenie DIY + AI: 2h/język
- Native review: $15-25/język
- Testing: 1-2h/język
- App Store metadata: 1h/język

**Total effort (3 języki):** ~15-20h + ~$60

**Koszt:**
- DIY + AI: $0
- Native review: $15-25/język
- **Total:** ~$45-75 dla PL, DE, IT

**Tools:**
- ChatGPT/Claude dla tłumaczeń
- Fiverr dla native review
- Xcode dla testing

**Kiedy robić:**
- MVP: English + Polish
- V1.1: + German
- V1.2+: + Italian, Spanish
- V2.0: + Chinese, Japanese

---

## Przydatne linki

- [iOS Localization Guide](https://developer.apple.com/localization/)
- [NSLocalizedString Documentation](https://developer.apple.com/documentation/foundation/nslocalizedstring)
- [Stringsdict Format](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/StringsdictFileFormat/StringsdictFileFormat.html)
- [Fiverr Translation Services](https://www.fiverr.com/categories/writing-translation/translation-services)
- [Plural Rules (Unicode)](https://www.unicode.org/cldr/charts/43/supplemental/language_plural_rules.html)
- [ChatGPT](https://chat.openai.com) - dla tłumaczeń
- [Claude](https://claude.ai) - dla tłumaczeń

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
**Status:** Planned for post-MVP (v1.1 - Polish, v1.2 - German)
