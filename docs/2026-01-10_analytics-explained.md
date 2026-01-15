# Analytics & Metrics - wyjaśnienie

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie jak zbierać statystyki instalacji i użytkowania aplikacji

---

## Czym są analytics (metryki aplikacji)?

**Analytics (analityka aplikacji)** to zbieranie danych o tym jak użytkownicy korzystają z Twojej aplikacji.

### Podstawowe pytania na które odpowiada analytics:

1. **Ile osób pobrało aplikację?** (downloads)
2. **Ile osób aktywnie używa?** (active users)
3. **Jak często wracają?** (retention)
4. **Które funkcje są używane?** (feature usage)
5. **Gdzie aplikacja się crashuje?** (crashes)
6. **Jak szybko działa?** (performance)

### Prosta analogia:

Wyobraź sobie że masz sklep:
- **Analytics** = kamera nad drzwiami licząca klientów
- **Downloads** = ile osób weszło do sklepu
- **Active users** = ile osób coś kupiło
- **Retention** = ile osób wraca następnego tygodnia
- **Feature usage** = które półki są najpopularniejsze

---

## Po co zbierać analytics?

### 1. **Zrozumienie użytkowników**
Dowiesz się:
- Które funkcje są używane (a które ignorowane)
- Gdzie użytkownicy rezygnują (drop-off points)
- Czy nowa funkcja jest popularna

**Przykład:**
```
Analytics pokazuje:
"95% użytkowników używa recurring chores"
"Tylko 10% używa projekty"

→ Decyzja: Rozwijaj recurring chores, upraszczaj projekty
```

### 2. **Optymalizacja konwersji**
Jeśli masz płatną wersję:
- Ile osób przechodzi z free → paid?
- Na którym ekranie rezygnują z zakupu?
- Która cena działa najlepiej?

### 3. **Znajdowanie bugów**
Widzisz gdzie aplikacja się crashuje:
- "20% crashy na ekranie dodawania recurring chore"
- → Naprawiasz bug → crash rate spada do 0%

### 4. **Pomiar sukcesu**
Czy aplikacja rośnie?
- Tygodniowy wzrost: +15% active users
- Retention rate: 60% wraca po 7 dniach
- → Aplikacja rozwija się dobrze!

---

## Rodzaje analytics

### 1. **Podstawowe (App Store Connect)** - DARMOWE ✅
Apple automatycznie zbiera:
- Downloads (instalacje)
- Active devices (aktywne urządzenia)
- Sessions (sesje użycia)
- Crashes (awarie)
- Uninstalls (odinstalowania)

**Zalety:**
- ✅ Darmowe
- ✅ Automatyczne (zero konfiguracji)
- ✅ Privacy-first (dane anonimowe)
- ✅ Wystarczające dla MVP

**Wady:**
- ❌ Brak szczegółów (nie wiesz KTÓRE ekrany)
- ❌ Opóźnienie (dane co 24h)
- ❌ Brak custom events

### 2. **Zaawansowane (Firebase, TelemetryDeck)** - PŁATNE/DARMOWE
Dodatkowe narzędzia zbierają:
- Screen views (które ekrany są oglądane)
- Custom events (np. "task_completed", "chore_added")
- User flows (jaką ścieżką przeszedł użytkownik)
- A/B testing (testowanie wersji)
- Funnels (konwersja krok po kroku)

**Zalety:**
- ✅ Szczegółowe dane
- ✅ Real-time (dane natychmiastowe)
- ✅ Custom events
- ✅ Segmentacja użytkowników

**Wady:**
- ❌ Wymaga konfiguracji (kod + privacy)
- ❌ Może być płatne
- ❌ Privacy concerns (GDPR compliance)

---

## Rekomendacja dla Family To-Do MVP

**Użyj App Store Connect Analytics (FREE)**

Dlaczego?
1. ✅ **$0 kosztów** - całkowicie darmowe
2. ✅ **Zero kodu** - działa automatycznie
3. ✅ **Privacy-friendly** - nie zbiera danych osobowych
4. ✅ **Wystarczające dla MVP** - pokrywa podstawowe potrzeby

**Czego NIE dostaniesz (ale nie potrzebujesz na start):**
- ❌ "Który ekran jest najpopularniejszy?"
- ❌ "Ile razy użyto funkcji X?"
- ❌ "Jaki jest funnel konwersji?"

**Kiedy dodać zaawansowane analytics?**
- Gdy masz 100+ active users
- Gdy planujesz monetyzację (potrzebujesz funnel analytics)
- Gdy chcesz A/B testować features

---

## App Store Connect Analytics - przewodnik

### Czym jest App Store Connect?

**App Store Connect** to panel kontrolny Apple dla developerów. Tutaj:
- Wgrywasz aplikację do App Store
- Zarządzasz wersjami
- Widzisz recenzje użytkowników
- **Widzisz analytics**

### Jak uzyskać dostęp?

**Krok 1: Apple Developer Account**
1. Musisz mieć Apple Developer Account ($99/rok)
2. Zaloguj się na [appstoreconnect.apple.com](https://appstoreconnect.apple.com)

**Krok 2: Wgraj aplikację do App Store**
1. Build aplikacji w Xcode
2. Upload do App Store Connect (via Xcode lub Transporter)
3. Poczekaj na review Apple (~24-48h)
4. Aplikacja w App Store → analytics dostępne

**Krok 3: Włącz analytics (automatyczne)**
- App Store automatycznie zbiera dane
- Nie musisz nic konfigurować w kodzie
- Dane dostępne 24h po pierwszym downloadu

---

## App Store Connect Analytics - jakie metryki dostaniesz?

### 1. **App Units** - Instalacje
Ile razy aplikacja została pobrana.

**Metryki:**
- **First-time downloads** - nowi użytkownicy
- **Redownloads** - użytkownicy instalujący ponownie
- **Total downloads** - suma wszystkich

**Przykład:**
```
Styczeń 2026:
- First-time: 150 pobrań
- Redownloads: 20
- Total: 170

→ Przyrost: +150 nowych użytkowników
```

### 2. **Installations** - Aktywne instalacje
Ile urządzeń ma aplikację zainstalowaną (obecnie).

**Różnica:**
- Downloads: kumulatywna liczba (rośnie zawsze)
- Installations: aktualna (może spadać jeśli odinstalują)

**Przykład:**
```
Downloads: 500
Installations: 300

→ 200 osób odinstalowało aplikację (40% churn)
```

### 3. **Active Devices** - Aktywne urządzenia
Ile urządzeń używało aplikacji w danym okresie.

**Periods:**
- **Last 30 days** - ile używało w ostatnim miesiącu
- **Last 7 days** - tydzień
- **Last 1 day** - dzień

**Przykład:**
```
Active devices (30 days): 250
Active devices (7 days): 180
Active devices (1 day): 50

→ DAU (Daily Active Users): 50
→ WAU (Weekly Active Users): 180
→ MAU (Monthly Active Users): 250
```

### 4. **Sessions** - Sesje użycia
Ile razy użytkownicy otworzyli aplikację.

**Session** = otwarcie aplikacji → użycie → zamknięcie

**Metryki:**
- Total sessions
- Sessions per active device (średnia)

**Przykład:**
```
Sessions (7 days): 600
Active devices (7 days): 150

→ Sessions per device: 600/150 = 4
→ Średnio użytkownik otwiera app 4 razy w tygodniu
```

### 5. **Crashes** - Awarie
Ile razy aplikacja się crashowała.

**Metryki:**
- **Crash rate** - % sesji które się crashowały
- **Crash-free sessions** - % sesji bez crashy

**Przykład:**
```
Sessions: 1000
Crashes: 20

→ Crash rate: 2%
→ Crash-free: 98%

Cel: <1% crash rate (high quality app)
```

### 6. **Retention** - Retencja
Czy użytkownicy wracają do aplikacji?

**Retention rates:**
- **Day 1** - ile wraca następnego dnia
- **Day 7** - ile wraca po tygodniu
- **Day 30** - ile wraca po miesiącu

**Przykład:**
```
100 użytkowników pobrało app w poniedziałek
- Day 1 retention: 60% (60 osób wróciło we wtorek)
- Day 7 retention: 40% (40 osób wróciło za tydzień)
- Day 30 retention: 25% (25 osób wróciło za miesiąc)

Benchmark dla productivity apps:
- Day 1: 40-60%
- Day 7: 20-40%
- Day 30: 10-20%

Family To-Do ma powyżej średniej! ✅
```

### 7. **App Store Views** - Wyświetlenia strony
Ile razy ludzie zobaczyli Twoją aplikację w App Store.

**Metryki:**
- Product page views
- Conversion rate (views → downloads)

**Przykład:**
```
Page views: 500
Downloads: 100

→ Conversion rate: 20%

Benchmark: 15-30% (zależy od kategorii)
```

---

## Jak czytać App Store Connect Analytics?

### Krok 1: Zaloguj się
1. Idź na [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Zaloguj się Apple ID (Developer Account)
3. Kliknij **"My Apps"**
4. Wybierz **"Family To-Do"**

### Krok 2: Otwórz Analytics
1. W menu po lewej kliknij **"Analytics"**
2. Wybierz **"Metrics"**

### Krok 3: Wybierz zakres dat
```
Opcje:
- Last 7 days
- Last 30 days
- Last 90 days
- Custom range
```

### Krok 4: Wybierz metryki
```
Dostępne:
- App Units (downloads)
- Impressions (page views)
- Sessions
- Active Devices
- Crashes
- Retention
```

### Krok 5: Filtruj dane
```
Filtry:
- Platform (iPhone, iPad)
- Device type (iPhone 15, iPhone 14)
- iOS version (iOS 17, iOS 18)
- Territory (Poland, Germany, USA)
- Source (App Store Search, Browse, Web Referrer)
```

---

## Przykładowy analytics dashboard dla Family To-Do

### Tydzień 1 (po launch):
```
┌─────────────────────────────────────┐
│ Week 1 Analytics (Jan 10-16, 2026) │
├─────────────────────────────────────┤
│ Downloads: 50                       │
│ Active devices (7d): 45             │
│ Sessions: 180                       │
│ Crash rate: 0.5%                    │
│                                     │
│ Day 1 retention: 80%                │
│ Day 7 retention: N/A (too early)    │
├─────────────────────────────────────┤
│ Analiza:                            │
│ ✅ Wysoka retencja D1 (80%)         │
│ ✅ Niski crash rate (<1%)           │
│ ✅ 3.6 sessions/device (dobre!)     │
│                                     │
│ Akcje:                              │
│ • Zbierz feedback od 45 users       │
│ • Napraw 1 crash (0.5% = ~1 bug)   │
│ • Promuj app w social media         │
└─────────────────────────────────────┘
```

### Miesiąc 1:
```
┌─────────────────────────────────────┐
│ Month 1 Analytics (Jan 2026)       │
├─────────────────────────────────────┤
│ Downloads: 200                      │
│ Active devices (30d): 150           │
│ Sessions: 900                       │
│ Crash rate: 0.8%                    │
│                                     │
│ Day 1 retention: 70%                │
│ Day 7 retention: 50%                │
│ Day 30 retention: 30%               │
├─────────────────────────────────────┤
│ Analiza:                            │
│ ✅ Retention powyżej benchmarku     │
│ ✅ 6 sessions/device (very engaged!)│
│ ⚠️  Installations: 150 (50 churn)  │
│                                     │
│ Akcje:                              │
│ • Zbadaj czemu 50 osób odinstalowało│
│ • Dodaj onboarding (improve D1)     │
│ • Rozważ monetyzację (30% D30)      │
└─────────────────────────────────────┘
```

---

## Privacy & GDPR Compliance

### App Store Connect Analytics są privacy-friendly! ✅

**Co zbiera:**
- ✅ Anonimowe dane (bez imion, emaili, danych osobowych)
- ✅ Aggregated metrics (suma, nie indywidualni użytkownicy)
- ✅ Zgodne z GDPR out-of-the-box

**Czego NIE zbiera:**
- ❌ Dane osobowe (imię, email, adres)
- ❌ Treść tasków użytkownika
- ❌ CloudKit data
- ❌ Lokalizacja (bez Twojej zgody)

**Privacy Policy:**
Musisz mieć Privacy Policy mówiącą:
```
"Używamy App Store Connect Analytics do zbierania
anonimowych danych o instalacjach i użyciu aplikacji."
```

---

## Zaawansowane Analytics - kiedy i które?

### Kiedy dodać zaawansowane analytics?

**Sygnały że potrzebujesz:**
- ✅ Masz 100+ active users
- ✅ Planujesz monetyzację
- ✅ Chcesz zrozumieć user flows
- ✅ Testujesz A/B features
- ✅ Potrzebujesz real-time data

**Dla Family To-Do:**
- **MVP (0-100 users):** App Store Connect wystarczy
- **Growth (100-1000 users):** Rozważ zaawansowane analytics
- **Scale (1000+ users):** Definitywnie potrzebujesz

---

## Porównanie narzędzi analytics

| | App Store Connect | Firebase | TelemetryDeck | Mixpanel |
|---|---|---|---|---|
| **Koszt (MVP)** | FREE | FREE | $10-49/mo | FREE |
| **Setup** | Zero code | Moderate | Easy | Moderate |
| **Privacy** | Excellent | Moderate | Excellent | Low |
| **Real-time** | No (24h delay) | Yes | Yes | Yes |
| **Custom events** | No | Yes | Yes | Yes |
| **User flows** | No | Yes | Limited | Yes |
| **A/B testing** | No | Yes | No | Yes |
| **GDPR compliance** | Yes | Manual | Yes | Manual |

### Firebase Analytics (Google)

**Pros:**
- ✅ Free tier (unlimited events)
- ✅ Rich feature set
- ✅ Integrates with Firebase suite

**Cons:**
- ❌ Google tracking (privacy concerns)
- ❌ Requires code integration
- ❌ GDPR compliance manual

**Cost:**
- FREE for analytics
- $25-200/mo if using other Firebase features

**Setup time:** 2-4 hours

---

### TelemetryDeck (Privacy-first)

**Pros:**
- ✅ Privacy-focused (no user tracking)
- ✅ GDPR compliant out-of-box
- ✅ Made for indie devs
- ✅ Beautiful UI

**Cons:**
- ❌ Paid ($10-49/mo)
- ❌ Less features than Firebase
- ❌ Smaller ecosystem

**Cost:**
- Indie: $10/mo (10K events)
- Pro: $49/mo (100K events)

**Setup time:** 1-2 hours

**Recommended for:** Privacy-conscious apps (Family To-Do perfect fit!)

---

### Mixpanel (Advanced)

**Pros:**
- ✅ Powerful segmentation
- ✅ Funnels and cohorts
- ✅ A/B testing

**Cons:**
- ❌ Expensive at scale
- ❌ Complex setup
- ❌ Overkill for MVP

**Cost:**
- FREE: 100K events/mo
- Growth: $25-100/mo
- Enterprise: $1000+/mo

**Setup time:** 4-8 hours

---

## Implementation - Dodawanie zaawansowanych analytics

### Przykład: TelemetryDeck (rekomendacja)

**Krok 1: Signup**
```
1. Idź na telemetrydeck.com
2. Utwórz konto
3. Utwórz nową aplikację
4. Skopiuj App ID
```

**Krok 2: Dodaj SDK**
```swift
// W Package.swift
dependencies: [
    .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0")
]
```

**Krok 3: Inicjalizacja**
```swift
// W App file
import TelemetryDeck

@main
struct FamilyTodoApp: App {
    init() {
        let config = TelemetryDeck.Config(appID: "YOUR-APP-ID")
        TelemetryDeck.initialize(config: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Krok 4: Track events**
```swift
// Gdy użytkownik dodaje task
TelemetryDeck.signal("task_created", parameters: [
    "area": area.name,
    "priority": priority
])

// Gdy task jest completed
TelemetryDeck.signal("task_completed", parameters: [
    "time_to_complete_hours": timeSinceCreation
])

// Gdy użytkownik dodaje recurring chore
TelemetryDeck.signal("recurring_chore_created", parameters: [
    "frequency": recurrence.rawValue
])
```

**Krok 5: Zobacz dane**
```
Dashboard → Events → Zobacz
- Które eventy są najczęstsze
- Trend użycia features
- Retention per feature
```

---

## Key Performance Indicators (KPIs) dla Family To-Do

### Metryki sukcesu:

**1. Activation (Aktywacja)**
- ✅ User dodał przynajmniej 1 task
- ✅ User dodał przynajmniej 1 recurring chore
- Target: 80% użytkowników w ciągu 24h

**2. Engagement (Zaangażowanie)**
- ✅ DAU/MAU ratio (daily/monthly active)
- Target: >20% (użytkownicy wracają często)

**3. Retention (Retencja)**
- ✅ Day 7 retention: >40%
- ✅ Day 30 retention: >20%

**4. Stickiness (Lepkość)**
- ✅ Sessions per user per week: >3
- ✅ Tasks completed per week: >5

**5. Quality (Jakość)**
- ✅ Crash rate: <1%
- ✅ App Store rating: >4.5 stars

### Jak mierzyć KPIs z App Store Connect:

```
1. Activation:
   Nie możesz zmierzyć bezpośrednio (potrzeba custom events)
   Workaround: Day 1 retention jako proxy

2. Engagement:
   DAU = Active devices (1 day)
   MAU = Active devices (30 days)
   DAU/MAU = engagement ratio

3. Retention:
   App Store Connect → Retention tab → Day 7, Day 30

4. Stickiness:
   Sessions / Active devices = sessions per user

5. Quality:
   App Store Connect → Crashes tab
   App Store Connect → Ratings tab
```

---

## Co zrobić z danymi analytics?

### Przykładowe decyzje bazowane na danych:

**Scenario 1: Niskie Day 1 retention (30%)**
```
Problem: Tylko 30% wraca następnego dnia

Możliwe przyczyny:
- Słaby onboarding
- Bugs/crashes
- Brak value proposition

Akcje:
1. Sprawdź crash rate (może to bug?)
2. Dodaj onboarding tutorial
3. Wyślij welcome email
4. Zbierz feedback od churned users
```

**Scenario 2: Wysokie sessions/user (10+/tydzień)**
```
Problem: To dobry problem! :)

Znaczy że:
- App jest sticky
- Użytkownicy są engaged
- Feature set jest dobry

Akcje:
1. Rozważ monetyzację (mają wartość)
2. Zbierz testimonials/reviews
3. Dodaj referral program
4. Inwestuj w growth
```

**Scenario 3: 50% instalacji z Polski**
```
Obserwacja: Połowa użytkowników z PL

Akcje:
1. Priorytetuj polską lokalizację
2. Marketing w Polsce
3. Cena w PLN (jeśli paid)
4. Polski support
```

---

## Podsumowanie

### Dla Family To-Do MVP:

**Rekomendacja:**
1. ✅ **Start:** App Store Connect (FREE, zero setup)
2. ✅ **100+ users:** Dodaj TelemetryDeck ($10/mo, privacy-first)
3. ✅ **1000+ users:** Rozważ Firebase (more features)

### Kluczowe metryki do śledzenia:
- Downloads (wzrost użytkowników)
- Active devices (actual usage)
- Retention (czy wracają?)
- Crash rate (jakość)
- Sessions per user (engagement)

### Privacy-first approach:
- App Store Connect: anonimowe
- TelemetryDeck: privacy-focused
- NIE: Mixpanel, Google Analytics (overkill + privacy)

### Koszt:
- **MVP:** $0 (App Store Connect)
- **Growth:** $10-49/mo (TelemetryDeck)
- **Scale:** $25-200/mo (Firebase/Mixpanel)

---

## Przydatne linki

- [App Store Connect](https://appstoreconnect.apple.com)
- [App Store Connect Analytics Guide](https://developer.apple.com/app-store-connect/analytics/)
- [TelemetryDeck](https://telemetrydeck.com)
- [Firebase Analytics](https://firebase.google.com/products/analytics)
- [iOS Privacy Guidelines](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [GDPR Compliance for Apps](https://gdpr.eu/)

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
**Status:** Planned for post-MVP implementation
