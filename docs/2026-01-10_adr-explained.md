# ADR - Architecture Decision Record (wyjaśnienie)

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie czym są ADRy i jak ich używać

---

## Czym jest ADR?

**Architecture Decision Record (ADR)** to dokument opisujący **ważną decyzję architektoniczną** w projekcie.

### Prosta analogia:

Wyobraź sobie, że budujesz dom:
- ❓ **Pytanie:** "Z czego zbudować ściany?"
- 🤔 **Opcje:** Cegła, drewno, beton
- ✅ **Decyzja:** "Wybieramy cegłę"
- 📝 **ADR:** Dokument wyjaśniający **dlaczego** wybraliśmy cegłę

**ADR to zapisana historia decyzji:**
- Dlaczego coś wybraliśmy?
- Jakie były alternatywy?
- Co wzięliśmy pod uwagę?
- Jakie są konsekwencje?

---

## Po co pisać ADRy?

### 1. **Pamięć zespołu**
Za 6 miesięcy zapomnisz dlaczego wybrałeś CloudKit zamiast Firebase.

**Bez ADR:**
```
"Czemu używamy CloudKit?"
"Hmm... nie pamiętam, chyba bo było łatwiejsze?"
```

**Z ADR:**
```
"Czemu używamy CloudKit?"
"Przeczytaj ADR-001, tam jest pełne uzasadnienie"
```

### 2. **Onboarding nowych developerów**
Nowy programista może szybko zrozumieć kluczowe decyzje projektu.

### 3. **Unikanie ponownych dyskusji**
Gdy ktoś powie "może lepiej Firebase?", możesz odpowiedzieć:
"Już to rozważaliśmy w ADR-001, przeczytaj argumenty"

### 4. **Historia projektu**
ADRy to dziennik rozwoju architektury:
- Co działało?
- Co się nie sprawdziło?
- Co zmieniliśmy i dlaczego?

---

## Kiedy pisać ADR?

Pisz ADR dla **ważnych decyzji**, które:
- ✅ Dotyczą całej architektury projektu
- ✅ Są trudne do zmiany później
- ✅ Mają znaczący wpływ na koszty/czas/wydajność
- ✅ Są przedmiotem dyskusji w zespole

### Przykłady kiedy PISAĆ ADR:
- Wybór backendu (CloudKit vs Firebase vs własny serwer)
- Wybór architektury (MVC vs MVVM vs VIPER)
- Wybór bazy danych (Core Data vs SwiftData vs Realm)
- Wybór platformy (iOS-only vs multiplatform)
- Wybór języka programowania (Swift vs Objective-C)

### Przykłady kiedy NIE PISAĆ ADR:
- ❌ Wybór nazwy zmiennej
- ❌ Małe refactoring
- ❌ Zmiana koloru buttona
- ❌ Dodanie pojedynczej funkcji

**Zasada:** Jeśli decyzja będzie miała wpływ na projekt za 6 miesięcy - napisz ADR.

---

## Struktura ADR

Standardowy ADR ma kilka sekcji:

### 1. **Tytuł**
Krótki, opisowy tytuł decyzji:
```
ADR-001: Use CloudKit as Backend for Family To-Do App
```

### 2. **Status**
Aktualny status decyzji:
- **Proposed** - propozycja, jeszcze nie zatwierdzona
- **Accepted** - zatwierdzona, wdrażamy
- **Deprecated** - przestarzała, ale jeszcze używana
- **Superseded** - zastąpiona inną decyzją
- **Rejected** - odrzucona

### 3. **Context** (Kontekst)
Opisuje sytuację i problem:
- Jaki problem rozwiązujemy?
- Jakie są wymagania?
- Jakie ograniczenia mamy?

**Przykład:**
```
Family To-Do App potrzebuje backendu do:
- Synchronizacji danych między urządzeniami
- Udostępniania tasków między członkami rodziny
- Offline-first architektury

Wymagania:
- Niski koszt dla MVP (2 użytkowników)
- Łatwa integracja z iOS
- Bezpieczeństwo danych
```

### 4. **Decision** (Decyzja)
Opisuje co zdecydowaliśmy:

**Przykład:**
```
Wybieramy CloudKit jako backend dla Family To-Do App.
```

### 5. **Consequences** (Konsekwencje)
Opisuje pozytywne i negatywne skutki decyzji:

**Przykład:**
```
Pozytywne:
+ Darmowy dla MVP (1GB storage, 10GB transfer)
+ Natywna integracja z iOS
+ Automatyczna synchronizacja
+ Bezpieczeństwo przez Apple

Negatywne:
- Tylko dla iOS/macOS (brak Androida)
- Wymaga Apple Developer Account ($99/rok)
- Ograniczone opcje queryingu
- Uzależnienie od Apple'a
```

### 6. **Alternatives Considered** (Rozważane alternatywy)
Lista innych opcji i dlaczego je odrzuciliśmy:

**Przykład:**
```
Firebase:
+ Multiplatform (iOS, Android, Web)
+ Więcej funkcji (auth, analytics, push)
- Droższe dla większej skali
- Więcej konfiguracji
- Uzależnienie od Google

Własny backend:
+ Pełna kontrola
+ Brak vendor lock-in
- Wysoki koszt developmentu
- Konieczność utrzymania serwera
- Wolniejsze wdrożenie MVP
```

---

## Przykładowy ADR dla Family To-Do

Utworzyłem pełny ADR w pliku:
**`docs/2026-01-10_adr-001-cloudkit-backend.md`**

Przeczytaj go jako przykład dobrego ADR.

---

## Numeracja ADRów

ADRy są numerowane sekwencyjnie:
- **ADR-001**: Pierwsza decyzja
- **ADR-002**: Druga decyzja
- **ADR-003**: Trzecia decyzja
- itd.

**Format nazwy pliku:**
```
adr-NNN-short-title.md
```

**Przykłady:**
```
adr-001-cloudkit-backend.md
adr-002-swiftui-architecture.md
adr-003-swiftdata-local-storage.md
```

---

## Gdzie przechowywać ADRy?

**W repozytorium kodu!**

Typowa struktura:
```
project/
├── docs/
│   ├── adr/
│   │   ├── README.md
│   │   ├── adr-001-cloudkit-backend.md
│   │   ├── adr-002-swiftui-architecture.md
│   │   └── adr-003-swiftdata-local-storage.md
│   └── other-docs.md
├── src/
└── README.md
```

**Dlaczego w repozytorium?**
- ✅ Wersjonowane razem z kodem
- ✅ Łatwo dostępne dla całego zespołu
- ✅ Można linkować w Pull Requestach
- ✅ Historia zmian w git

---

## Jak używać ADRów w praktyce?

### Scenario 1: Nowa decyzja architektoniczna

1. **Pojawia się pytanie:** "Jakiego backendu użyć?"
2. **Zbierz informacje:** Jakie są opcje? Wymagania?
3. **Napisz propozycję ADR** ze statusem "Proposed"
4. **Dyskutuj z zespołem** (jeśli masz zespół)
5. **Zmień status na "Accepted"** po podjęciu decyzji
6. **Commituj ADR** do repozytorium

### Scenario 2: Zmiana decyzji

1. **Okazuje się że CloudKit nie wystarcza**
2. **Napisz nowy ADR-004:** "Migrate from CloudKit to Firebase"
3. **W nowym ADR dodaj:** "Supersedes ADR-001"
4. **W starym ADR-001 zmień status** na "Superseded by ADR-004"
5. **NIE USUWAJ** starego ADR - to historia projektu!

### Scenario 3: Nowy developer w projekcie

1. **Nowy developer:** "Dlaczego używamy CloudKit?"
2. **Ty:** "Przeczytaj docs/adr/README.md i ADR-001"
3. **Developer szybko rozumie** kontekst i uzasadnienie

---

## Narzędzia do ADRów

### Prosty sposób (rekomendowany dla MVP):
- Zwykłe pliki Markdown w repozytorium
- Edytor tekstu (VS Code, Neovim, itp.)
- Numeracja ręczna

### Zaawansowane narzędzia:
- **adr-tools** - CLI do zarządzania ADRami
  ```bash
  brew install adr-tools
  adr new "Use CloudKit as Backend"
  ```
- **adr-log** - Generuje spis ADRów
- **Confluence/Notion** - Dla większych organizacji

**Dla Family To-Do:** Zwykłe Markdown pliki wystarczą!

---

## Szablony ADR

### Minimalny szablon:
```markdown
# ADR-NNN: [Tytuł decyzji]

**Status:** [Proposed/Accepted/Deprecated/Superseded/Rejected]
**Date:** YYYY-MM-DD
**Deciders:** [Kto podejmuje decyzję]

## Context
[Opis problemu i kontekstu]

## Decision
[Co zdecydowaliśmy]

## Consequences
[Pozytywne i negatywne skutki]
```

### Rozszerzony szablon (z alternatywami):
```markdown
# ADR-NNN: [Tytuł decyzji]

**Status:** [Status]
**Date:** YYYY-MM-DD
**Deciders:** [Kto]

## Context and Problem Statement
[Szczegółowy opis problemu]

## Decision Drivers
[Co wpływa na decyzję? Wymagania, ograniczenia]

## Considered Options
- Option 1
- Option 2
- Option 3

## Decision Outcome
[Co wybraliśmy i dlaczego]

### Positive Consequences
- [Pozytywne skutki]

### Negative Consequences
- [Negatywne skutki]

## Alternatives Considered

### Option 1: [Nazwa]
[Opis opcji]
**Pros:**
- [Zalety]
**Cons:**
- [Wady]
**Why not chosen:** [Uzasadnienie]

### Option 2: [Nazwa]
[Podobnie jak powyżej]

## Links
- [Link do dokumentacji]
- [Link do dyskusji]
```

---

## Praktyczne wskazówki

### DO ✅:
- ✅ Pisz jasno i konkretnie
- ✅ Uzasadnij każdą decyzję
- ✅ Uwzględnij kontekst biznesowy (czas, koszt)
- ✅ Zapisuj konsekwencje (pozytywne i negatywne)
- ✅ Datuj ADRy
- ✅ Commituj ADRy razem z kodem

### DON'T ❌:
- ❌ Nie usuwaj starych ADRów (nawet jeśli nieaktualne)
- ❌ Nie edytuj starych ADRów (dodaj nowy ADR zamiast tego)
- ❌ Nie pisz ADRów dla drobnych decyzji
- ❌ Nie używaj buzzwordów bez wyjaśnienia
- ❌ Nie pomijaj alternatyw

---

## Przykład: ADR dla Family To-Do

Utworzyłem pełny przykład ADR w osobnym pliku:

**`docs/2026-01-10_adr-001-cloudkit-backend.md`**

Przeczytaj go, żeby zobaczyć jak wygląda dobry ADR w praktyce.

---

## Podsumowanie

**ADR to:**
- 📝 Dokument opisujący ważną decyzję architektoniczną
- 🧠 Pamięć zespołu - dlaczego wybraliśmy X zamiast Y
- 📚 Historia projektu - jak ewoluowała architektura
- 🚀 Narzędzie onboardingowe dla nowych developerów

**Dla Family To-Do App:**
Będziemy pisać ADRy dla decyzji takich jak:
- Wybór backendu (CloudKit)
- Wybór architektury UI (SwiftUI + MVVM)
- Wybór local storage (SwiftData)
- Wybór strategii synchronizacji

**Pamiętaj:**
ADRy to nie biurokracja - to inwestycja w przyszłość projektu!

---

## Przydatne linki

- [ADR GitHub Organization](https://adr.github.io/) - Standardy i narzędzia
- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) - Oryginalny artykuł o ADRach
- [ADR Tools](https://github.com/npryce/adr-tools) - CLI do zarządzania ADRami
- [ADR Examples](https://github.com/joelparkerhenderson/architecture-decision-record) - Przykłady ADRów

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
