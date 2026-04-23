# HousePulse — App Store Launch Strategy

> Research 2026-02-15 · Źródła: RevenueCat, Adapty, Apple HIG, ASO benchmarks

---

## 1. Audyt obecnego onboardingu

### Co mamy teraz

`OnboardingView.swift` — **pojedynczy ekran**:
- Ikona `house.fill` (SF Symbol, 60pt)
- Tekst "Welcome to Family To-Do"
- Teksty "Create a household..." / "Guest mode..."
- 2 buttony: **Create Household** / **Join Household**
- Zero animacji, zero prezentacji wartości, zero personalizacji

### Ocena: ❌ Brak efektu wow

| Kryterium | Stan | Ocena |
|-----------|------|-------|
| Prezentacja wartości (value proposition) | ❌ Brak — user nie widzi co app robi | 1/10 |
| Animacje / micro-interactions | ❌ Zero | 0/10 |
| Personalizacja | ❌ Brak pytań o potrzeby usera | 0/10 |
| Aha! moment | ❌ User od razu musi tworzyć household | 1/10 |
| Social proof | ❌ Brak | 0/10 |
| Branding / premium feel | ⚠️ Prosty SF Symbol + borderedProminent | 3/10 |
| Czas do pierwszej wartości | ❌ ~5 tapów do zobaczenia czegokolwiek | 2/10 |

**Wniosek**: Obecny onboarding to **formularz rejestracyjny**, nie prezentacja aplikacji. 25% użytkowników odinstaluje app po jednym użyciu z powodu złego pierwszego wrażenia.

---

## 2. Rekomendowany onboarding — "Wow Flow"

### 2.1 Architektura flow (5 ekranów + 1 opcjonalny)

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  SPLASH       │───▶│  VALUE 1     │───▶│  VALUE 2     │───▶│  VALUE 3     │───▶│  PERSONALIZE │
│  Logo anim    │    │  Tasks       │    │  Shopping     │    │  Together    │    │  "How many?" │
│  3s auto      │    │  "3 tasks"   │    │  "Smart list" │    │  "Family"    │    │  household   │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                                                                                        │
                                                                                        ▼
                                                                               ┌──────────────┐
                                                                               │  CTA         │
                                                                               │  Sign Up /   │
                                                                               │  Try Free    │
                                                                               └──────────────┘
```

### 2.2 Szczegóły każdego ekranu

#### Ekran 1: Animated Splash (auto, 2-3s)
- Logo HousePulse z animacją (np. house icon → rozpuszcza się w pulse wave)
- Czyste, premium tło (gradient lub dark)
- Zero interakcji — auto-przejście
- **Cel**: Branding, "this is polished"

#### Ekran 2: Value — "Focus on What Matters" (Tasks)
- **Hero image**: Mockup Tasks view z 3 taskami w NEXT
- Headline: **"Only 3 active tasks. No overwhelm."**
- Subheadline: "Focus on what matters today. The rest waits in your backlog."
- **Animacja**: Tasks pojawiają się jeden po drugim z fade-in
- Progress dots: ○ ● ○ ○ (swipe)

#### Ekran 3: Value — "Shopping Made Easy" (Shopping List)
- **Hero image**: Mockup Shopping z rapid entry + "Recently Purchased"
- Headline: **"Type, tap, done. The smartest shopping list."**
- Subheadline: "Auto-suggestions, restock in one tap, shared with family."
- **Animacja**: Items wpisywane rapid-fire (simulated typing)

#### Ekran 4: Value — "Better Together" (Family/Sharing)
- **Hero image**: Avatar stack (2-4 member avatars) + shared task list
- Headline: **"Your whole household, in sync."**
- Subheadline: "Assign tasks, share lists, see who did what. No nagging."
- **Animacja**: Avatars pojawiają się z bounce, taski przydzielają się do osób

#### Ekran 5: Personalization — Quick Setup
- **Pytanie 1**: "How big is your household?" → [Solo] [Couple] [Family 3-4] [Big family 5+]
- **Pytanie 2**: "What matters most?" → [Tasks] [Shopping] [Both equally]
- Odpowiedzi wpływają na:
  - Default tab po onboardingu (Shopping vs Tasks)
  - Seed data (np. sample categories w Backlog)
  - Wersja CTA (solo = "Get Started", family = "Invite Your Family")
- **Animacja**: Karty z opcjami flip/scale na tap

#### Ekran 6: CTA — Sign Up / Try Free
- **Headline**: "Start your free 14-day trial"
- **Subheadline**: "No credit card required. Cancel anytime."
- [Sign in with Apple] — primary, duży
- [Continue as Guest] — secondary, mniejszy tekst
- Social proof: "★★★★★ Loved by 10,000+ families" (gdy będzie applicable)
- Privacy note: "Your data stays on your device. We never sell personal info."

### 2.3 Techniczne wymagania

```swift
// Nowy plik: WelcomeCarouselView.swift
// Zastąpi obecny OnboardingView.swift

struct WelcomeCarouselView: View {
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            AnimatedSplashPage().tag(0)
            ValuePage_Tasks().tag(1)
            ValuePage_Shopping().tag(2)
            ValuePage_Family().tag(3)
            PersonalizationPage().tag(4)
            CTAPage().tag(5)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Custom page indicator dots
    }
}
```

**Nowe pliki potrzebne**:
- `WelcomeCarouselView.swift` — główny carousel
- `WelcomePageModels.swift` — modele danych + personalization state
- `WelcomeAnimations.swift` — custom animacje (Lottie lub native SwiftUI)
- Assets: illustrations lub screenshots do mockupów

**Effort**: 2-3 dni (z animacjami), 1 dzień (bez animacji, statyczne strony)

---

## 3. Strategia monetyzacji

### 3.1 Analiza konkurencji

| App | Model | Free tier | Paid tier | Cena |
|-----|-------|-----------|-----------|------|
| **Todoist** | Freemium + Sub | 5 projektów, basic | Pro: 300 projects, AI, reminders | $5-7/mo ($60/yr) |
| **Cozi** | Freemium + Sub | Calendar (30 dni), ads | Gold: no ads, full calendar | $40/yr |
| **Cozi Max** | Freemium + Sub | j.w. | + AI Meal Planner | $60/yr |
| **OurHome** | Freemium | Chores, basic | Premium (unknown pricing) | ? |
| **Any.do** | Freemium + Sub | Basic tasks | Pro: recurring, colors, widgets | $3-6/mo |
| **Tody** | One-time purchase | — | Full app | $14.99 |
| **Apple Reminders** | Free (Apple ecosystem) | Full | — | Free |

### 3.2 Rekomendowany model: **Freemium + Subscription**

> ⚠️ **NIE** hard paywall. Nie rekomendujemy blokowania dostępu do core features.

#### Dlaczego freemium + sub, a nie:
- **Paid upfront**: Ryzyko — nikt nie kupi app za $5 bez wypróbowania. Conversion rate: 0.5-2% z App Store page
- **Free trial only (hard paywall)**: Ryzyko — 78% trial starts to Day 0, ale po trialu churn >60%. Agresywne i generuje negatywne reviews
- **Ads**: ❌ Absolutnie nie — app produktywnościowa z reklamami traci trust. Reddit community jednoznacznie: "no ads in productivity apps"
- **One-time purchase**: Brak ciągłego revenue = brak motywacji do development. Działa dla małych utility apps, nie dla app z sync

#### Rekomendowany tier structure:

```
┌─────────────────────────────────────────────────────────────────┐
│                    HousePulse FREE                              │
│                                                                 │
│  ✅ Tasks (3 active NEXT, unlimited backlog)                    │
│  ✅ Shopping list (basic — add/buy/delete)                      │
│  ✅ 1 household, up to 2 members                                │
│  ✅ Backlog (3 categories)                                      │
│  ✅ Basic themes (Light/Dark)                                   │
│  ❌ No recurring tasks                                          │
│  ❌ No shopping suggestions                                     │
│  ❌ No daily digest notifications                               │
│  ❌ No custom themes                                            │
│  ❌ No unlimited categories                                     │
│  ❌ Max 2 household members                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    HousePulse PRO                               │
│                    $2.99/mo  ·  $24.99/yr (~$2.08/mo)           │
│                                                                 │
│  Everything in FREE, plus:                                      │
│  ✅ Unlimited household members                                 │
│  ✅ Unlimited backlog categories                                │
│  ✅ Recurring tasks + ChoreScheduler                            │
│  ✅ Shopping suggestions + auto-restock                         │
│  ✅ Daily digest / smart notifications                          │
│  ✅ All themes (Journal, Pastel, Soft, Night)                   │
│  ✅ Task notes & due dates                                      │
│  ✅ Household stats dashboard (future)                          │
│  ✅ Widgets (future)                                            │
│  ✅ Priority support                                            │
└─────────────────────────────────────────────────────────────────┘
```

#### Pricing rationale:
- **$2.99/mo / $24.99/yr** — celowo tańszy niż Todoist ($5-7) i Cozi ($40-60)
- Family app = price-sensitive audience (rodziny, budżet domowy)
- Roczny plan z 30% zniżką zachęca do commitment
- **Benchmarki**: productivity apps w tej kategorii mają sweet spot $2-4/mo

### 3.3 Trial strategy

#### Rekomendacja: **14-dniowy free trial z soft paywall**

| Parameter | Wartość | Uzasadnienie |
|-----------|---------|-------------|
| **Trial length** | 14 dni | 7 dni za krótko na nawyk (habit loop = 7-21 dni). 30 dni = za długo, user zapomina dlaczego płaci. 14 = sweet spot |
| **Paywall type** | Soft | Core features dostępne free, paywall na premium. Nie blokujemy app! |
| **Paywall timing** | Po onboardingu + 1 dzień użycia | User musi NAJPIERW doświadczyć value, POTEM zobaczyć paywall |
| **Credit card upfront** | ❌ NIE | Apple StoreKit handles — brak CC w onboarding. "No credit card required" w CTA |
| **Trial reminder** | Dzień 11/14 | Push: "Your trial ends in 3 days. Keep your household organized!" |

#### Paywall flow:

```
User pobiera app
    │
    ▼
Onboarding carousel (5 ekranów)
    │
    ▼
Sign in / Guest → Create household
    │
    ▼
14 dni pełnego dostępu (PRO features unlocked)
    │
    ├── Day 3: Soft nudge — "Did you know? Recurring tasks save 2h/week"
    ├── Day 7: Feature highlight — "Your shopping suggestions are getting smarter"
    ├── Day 11: Reminder — "3 days left in your trial"
    └── Day 14: Paywall screen
              │
              ├── [Subscribe $2.99/mo] — primary CTA
              ├── [Annual $24.99/yr — Save 30%] — secondary
              └── [Continue with Free] — tertiary, clearly visible
```

### 3.4 Paywall design

#### Co powinien zawierać ekran paywall:
1. **Headline**: "Keep your household running smoothly"
2. **Feature comparison**: FREE vs PRO side-by-side (checkmarks)
3. **Social proof**: Rating stars + "Trusted by X families"
4. **Pricing**: Obydwa plany (monthly + annual) z wyraźnym savings badge
5. **Trial info**: "Start your 14-day free trial" (jeśli nowy user)
6. **CTA**: Duży, accessible button
7. **Fine print**: "Cancel anytime. No commitment."
8. **X (close)**: ZAWSZE widoczny — Apple rejects apps bez opcji zamknięcia

#### Benchmark conversion rates:
| Metric | Nasza sytuacja | Benchmark |
|--------|---------------|-----------|
| Trial start rate | Target: 15-20% | Industry avg: 8-11% |
| Trial→Paid conversion | Target: 25-35% | Top apps: 20%+ |
| Install→Paid (no trial) | Target: 5-8% | High-perf: 4-10% |
| Day 0 trial starts | Expected: 80%+ | Industry: 80%+ |

### 3.5 Technologia: StoreKit 2 + RevenueCat

**Rekomendacja**: Użyć **RevenueCat SDK** zamiast raw StoreKit 2:
- ✅ Remote paywall config (A/B testing bez resubmisji)
- ✅ Analytics (MRR, churn, LTV)
- ✅ Entitlements management
- ✅ Cross-platform (jeśli w przyszłości Android)
- ✅ Free tier do 2,500 MTR (monthly tracked revenue = $2,500 — wystarczający na start)
- ✅ Webhook integrations (Firebase, Amplitude)

Alternatywnie: natywny StoreKit 2 z `SubscriptionStoreView` (iOS 17+) — prostsze, ale brak A/B i analytics.

**Nowe pliki**:
- `SubscriptionManager.swift` — zarządzanie entitlements
- `PaywallView.swift` — ekran paywall
- `ProFeatureGate.swift` — wrapper do sprawdzania czy feature jest unlocked

---

## 4. App Store Page — optymalizacja

### 4.1 Nazwa i subtitle

```
Nazwa:     HousePulse — Family Organizer
Subtitle:  Tasks, Shopping Lists & Household Management
```

- Nazwa zawiera keyword "Family Organizer" (ASO)
- Subtitle zawiera 3 key features (tasks, shopping, household)
- Łącznie <60 znaków (limit Apple)

### 4.2 Screenshots (10 slotów)

App Store screenshots to **60-70% decyzji o pobraniu**. Pierwsze 3 widoczne w search results.

#### Rekomendowana kolejność:

| # | Ekran | Headline na screenshot | Cel |
|---|-------|----------------------|-----|
| 1 | Tasks view (3 aktywne) | **"Only 3 tasks. Zero overwhelm."** | Hero — USP |
| 2 | Shopping list | **"The fastest shopping list ever."** | Quick value |
| 3 | Family sharing (avatars) | **"Your whole family, in sync."** | Social/sharing |
| 4 | Backlog view | **"Never forget an idea."** | Completeness |
| 5 | Recurring tasks | **"It remembers so you don't have to."** | Smart features |
| 6 | Dark mode / themes | **"Beautiful. Day and night."** | Visual appeal |
| 7 | Widgets (future) | **"Glance, don't launch."** | Convenience |
| 8 | Notifications | **"Gentle reminders. Not spam."** | Trust |
| 9 | Settings / Personalization | **"Your household, your rules."** | Customization |
| 10 | Social proof / rating | **"★★★★★ See why families love it."** | Credibility |

#### Specyfikacje techniczne:
- Format: PNG, RGB, 72dpi, no transparency
- Rozmiar: 1290×2796px (iPhone 6.7") — scales for smaller
- **Apple indexuje tekst na screenshots** od 2024 → keywords w headlines!

### 4.3 Video Preview (do 3 slotów)

| # | Treść | Czas |
|---|-------|------|
| 1 | **Hero clip**: Tasks → complete → celebration → Shopping → rapid entry | 20s |
| 2 | **Sharing clip**: Invite family → assign tasks → see progress | 15s |
| 3 | **Dark mode / customization**: Theme switching + widgets | 15s |

- H.264 lub ProRes 422, max 500MB
- 15-30s każdy
- **Muted by default** → add text overlays!
- Autoplay w App Store → pierwsze 3s muszą przyciągnąć

### 4.4 Description + Keywords

#### Keywords (100 znaków):
```
family,todo,household,chore,task,shopping,list,grocery,organizer,home,shared,family tasks
```

#### Opis (first paragraph = most important):
```
HousePulse keeps your entire household organized — without the stress.

Focus on just 3 active tasks. No infinite to-do lists, no guilt.
Your backlog captures ideas until you're ready.

🛒 Shopping list with smart suggestions and one-tap restock
✅ Shared tasks with gentle WIP limits — no micromanagement
👨‍👩‍👧‍👦 Real-time sync for the whole family via iCloud
🔄 Recurring chores that schedule themselves
🎨 Beautiful themes for every mood
```

---

## 5. Marketing pre-launch checklist

### 5.1 Przed submisją

- [ ] Onboarding carousel (5 ekranów) zaimplementowany
- [ ] Paywall / subscription flow (StoreKit 2 lub RevenueCat)
- [ ] Free vs Pro tier gating logic
- [ ] App Store screenshots (min 5, ideal 10)
- [ ] Video preview (min 1, ideal 2-3)
- [ ] App Store description + keywords
- [ ] Privacy policy URL (wymagane przez Apple)
- [ ] Support URL
- [ ] App icon finalized (1024×1024, no transparency)
- [ ] TestFlight beta (min 10 testerów, zbierz feedback)
- [ ] Apple App Review compliance check (paywall X button, restore purchases, etc.)

### 5.2 Post-launch (first 30 days)

- [ ] Monitor conversion funnel: Install → Onboarding → Trial → Paid
- [ ] A/B test paywall (pricing, features, copy)
- [ ] Respond to ALL App Store reviews (zwłaszcza negatywne)
- [ ] Share on: Product Hunt, Reddit (r/productivity, r/apple), Twitter/X
- [ ] Email list / newsletter setup
- [ ] Press kit (screenshots + description template)
- [ ] Monitor RevenueCat/Adapty analytics daily

### 5.3 Kluczowe metryki do śledzenia

| Metryka | Target | Alert if below |
|---------|--------|---------------|
| Onboarding completion rate | >80% | <60% |
| Trial start rate | >15% | <8% |
| Trial→Paid conversion | >25% | <15% |
| Day 1 retention | >40% | <25% |
| Day 7 retention | >20% | <10% |
| Day 30 retention | >10% | <5% |
| Average rating | >4.5★ | <4.0★ |
| Revenue per install | >$0.30 | <$0.10 |

---

## 6. Podsumowanie — co zrobić i kiedy

### Must-have przed launch (P0, ~5 dni)

| # | Task | Effort |
|---|------|--------|
| 1 | Onboarding carousel (5 ekranów z animacjami) | 2-3 dni |
| 2 | PaywallView + subscription logic (RevenueCat/StoreKit) | 2 dni |
| 3 | Free/Pro tier gating (`ProFeatureGate`) | 0.5 dnia |
| 4 | App Store screenshots (5-10) | 0.5 dnia |

### Nice-to-have przed launch (P1, ~3 dni)

| # | Task | Effort |
|---|------|--------|
| 5 | Video preview (1-2 clips) | 1 dzień |
| 6 | A/B test framework dla paywall | 1 dzień |
| 7 | In-app review prompt (`SKStoreReviewController`) | 0.5 dnia |
| 8 | Celebrations (confetti, micro-animations) | 0.5 dnia |

### Post-launch optimization (P2)

| # | Task | Effort |
|---|------|--------|
| 9 | RevenueCat analytics dashboard | 1 dzień |
| 10 | Paywall A/B testing | ongoing |
| 11 | ASO optimization (keywords, screenshots) | ongoing |
| 12 | Referral program ("Invite friends, get 1 mo free") | 2 dni |

---

## 7. Najważniejsze wnioski

> **TLDR**:
> 1. Obecny onboarding to formularz, nie prezentacja — wymaga **pełnej przebudowy** na carousel z animacjami
> 2. **Freemium + subscription** to jedyny sensowny model (nie hard paywall, nie reklamy)
> 3. **14-dniowy trial** z soft paywall → daj userowi polubić app, potem pokaż wartość Pro
> 4. **$2.99/mo / $24.99/yr** — tańszy niż konkurencja, ale premium feel
> 5. **App Store page** to twoje CV — pierwszy screenshot decyduje o 60% pobrań
> 6. **RevenueCat** zamiast raw StoreKit — A/B testing i analytics od dnia 1
