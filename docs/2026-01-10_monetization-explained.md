# Monetization (Monetyzacja) - wyjaśnienie

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie jak zarabiać na aplikacji iOS (subskrypcje, płatności)

---

## Czym jest monetyzacja aplikacji?

**Monetyzacja** = sposób w jaki Twoja aplikacja zarabia pieniądze.

### Podstawowe pytania:

1. **Czy aplikacja będzie darmowa czy płatna?**
2. **Czy będą subskrypcje (np. 10 zł/miesiąc)?**
3. **Czy część funkcji będzie premium?**
4. **Czy będą reklamy?**

### Prosta analogia:

Wyobraź sobie że masz gym:
- **Paid Upfront** = karnety roczne (płacisz raz, wchodzisz rok)
- **Subscription** = karnet miesięczny (płacisz co miesiąc)
- **Freemium** = siłownia darmowa, osobisty trener płatny
- **Trial** = pierwszy tydzień gratis, potem płatny

---

## Modele monetyzacji na iOS

### Model 1: Paid Upfront (Jednorazowa opłata)

**Jak działa:**
- Użytkownik płaci PRZED pobraniem aplikacji
- Jednorazowa opłata (np. 19.99 zł)
- Aplikacja unlockowana na zawsze

**Przykłady:**
- Things 3 (task manager): $49.99
- Procreate (drawing app): $12.99
- GoodNotes (note-taking): $7.99

**Pros:**
- ✅ Proste (jedna cena, brak komplikacji)
- ✅ Brak recurring billing headaches
- ✅ Users lubią "own it forever"
- ✅ Łatwa implementacja (zero kodu)

**Cons:**
- ❌ Wysoka bariera wejścia (users nie próbują przed zakupem)
- ❌ Trudny refund policy (złe pierwsze wrażenie = refund)
- ❌ Brak recurring revenue (mniej stabilny przychód)
- ❌ Trudniej się promuje (nie ma free trial)
- ❌ Update revenue = $0 (musisz wypuścić "app 2.0" żeby znów zarobić)

**Revenue potential:**
```
Scenario:
- Cena: $4.99
- Downloads: 500/miesiąc
- Conversion: 2% (typowe dla paid upfront)

Revenue/miesiąc:
500 × 2% × $4.99 = $49.90/mo
Minus Apple cut (30%): $34.93/mo

Rok 1: ~$420
```

**Kiedy używać:**
- Niche productivity apps
- Professional tools
- Jeśli masz już brand/following
- Jeśli NIE potrzebujesz recurring revenue

---

### Model 2: Freemium (Darmowa + Premium Features)

**Jak działa:**
- Podstawowa wersja: DARMOWA
- Zaawansowane funkcje: PŁATNE (one-time lub subscription)
- User może używać free forever

**Przykłady freemium dla to-do apps:**
```
FREE tier (Family To-Do):
- Max 2 członków household
- Max 5 recurring chores
- Max 20 tasków w Backlog
- Podstawowe areas (Kitchen, Bathroom, Living Room)

PREMIUM tier ($4.99/mo lub $39.99/rok):
- Unlimited członków
- Unlimited recurring chores
- Unlimited tasks
- Custom areas
- Priority support
- Advanced analytics
- Export data
```

**Pros:**
- ✅ Łatwo ściągnąć users (free = low barrier)
- ✅ Users mogą przetestować przed zakupem
- ✅ Virality (users polecają bo free)
- ✅ Duża baza users (marketing opportunity)
- ✅ Flexible pricing (monthly lub annual)

**Cons:**
- ❌ Większość nie kupi (typowo 2-5% conversion)
- ❌ Konieczność balansowania free vs paid
- ❌ Free users kosztują (server costs, support)
- ❌ Trudniej projektować "gdzie paywall?"

**Revenue potential:**
```
Scenario:
- Downloads: 1000/miesiąc (free!)
- Conversion free→paid: 5%
- Cena: $4.99/mo

Revenue/miesiąc:
1000 × 5% × $4.99 = $249.50/mo
Minus Apple cut (15-30%): $174.65-212.07/mo

Rok 1: ~$2,000-2,500
```

**Kiedy używać:**
- Chcesz dużej bazy users
- Masz koszty serwerowe (CloudKit = free, więc OK)
- Chcesz virality
- Product ma clear "premium" features
- **RECOMMENDED dla Family To-Do!**

---

### Model 3: Trial + Subscription (Trial + obowiązkowa subskrypcja)

**Jak działa:**
- 7-14 dni darmowego trialu
- Potem MUSISZ płacić (np. $9.99/mo)
- Brak darmowej wersji na stałe

**Przykłady:**
- Headspace (meditation): 7-day trial → $12.99/mo
- Calm (meditation): 7-day trial → $14.99/mo
- Grammarly Premium: 7-day trial → $12/mo

**Pros:**
- ✅ Wysoki ARPU (Average Revenue Per User)
- ✅ Predictable recurring revenue
- ✅ Users get hooked w trial → convert
- ✅ Mniej "freeloader" users

**Cons:**
- ❌ Wysoki churn (users rezygnują po trial)
- ❌ Wymaga constant value delivery
- ❌ Trudniej get initial traction
- ❌ Subscription fatigue (users mają wiele subscriptions)

**Revenue potential:**
```
Scenario:
- Trial sign-ups: 500/miesiąc
- Trial→Paid conversion: 40%
- Cena: $9.99/mo
- Churn rate: 10%/mo

Miesiąc 1: 500 × 40% × $9.99 = $1,998
Miesiąc 2: 200 × 0.9 (retain) + 200 (new) = 380 × $9.99 = $3,796
... (stabilizuje się po ~6 mies)

Stabilny revenue (rok 1): ~$5,000-7,000/mo
```

**Kiedy używać:**
- Masz bardzo strong value proposition
- App jest "habit-forming" (daily use)
- Można szybko pokazać wartość w 7 dni
- Konkurencja używa tego modelu
- **MOŻLIWE dla Family To-Do** (jeśli masz strong onboarding)

---

### Model 4: Subscription Only (bez trialu, bez free)

**Jak działa:**
- Płacisz OD RAZU (np. $4.99/mo)
- Brak free tier, brak trialu
- Monthly lub annual

**Przykłady:**
- Niektóre niche professional tools
- B2B SaaS apps

**Pros:**
- ✅ Immediate revenue
- ✅ Only serious users download

**Cons:**
- ❌ Bardzo wysoka bariera (nikt nie próbuje)
- ❌ Trudno get initial users
- ❌ Conversion rate <1%

**Revenue potential:**
```
Bardzo niski initial uptake

Downloads: 100/miesiąc (mało!)
Immediate conversion: 10% (ci którzy płacą OD RAZU)
Revenue: 10 × $4.99 = $49.90/mo

Rok 1: ~$600

NOT recommended dla Family To-Do
```

**Kiedy używać:**
- Niche B2B tools
- Professional software z dedicated audience
- NIE dla consumer apps

---

## Porównanie modeli - które wybrać?

| Model | Bariera wejścia | Conversion | Revenue Rok 1 | Effort | Recommended? |
|---|---|---|---|---|---|
| **Paid Upfront** | Wysoka | 1-3% | $400-800 | Niski | ❌ Nie |
| **Freemium** | Niska | 3-7% | $2,000-3,000 | Średni | ✅ TAK |
| **Trial + Sub** | Średnia | 30-50% | $5,000-10,000 | Wysoki | ✅ Możliwe |
| **Sub Only** | Bardzo wysoka | <1% | $500-1,000 | Niski | ❌ Nie |

### Rekomendacja dla Family To-Do:

**🏆 Freemium (Recommended)**

**Dlaczego:**
1. ✅ Łatwo ściągnąć users (free = no barrier)
2. ✅ CloudKit jest darmowy (free tier nie kosztuje)
3. ✅ Natural paywall: "invite 3rd household member → upgrade"
4. ✅ Relationship-friendly (free tier wystarczy dla większości)
5. ✅ Viral growth (users polecają bo free)

**Free tier:**
```
- 2 household members (partner + Ty)
- Unlimited tasks
- Unlimited recurring chores
- All areas
- Basic notifications
```

**Premium tier ($4.99/mo lub $39.99/rok):**
```
- 3+ household members (np. + dziecko, + współlokator)
- Advanced analytics (task completion rates)
- Priority support
- Custom themes (optional)
- Export data to CSV
```

**Paywall trigger:**
"Chcesz dodać 3. członka? Upgrade to Premium!"

---

## StoreKit 2 - iOS In-App Purchases

**StoreKit** to framework Apple do handling płatności w aplikacjach.

**StoreKit 2** (nowa wersja) = lepsze API, łatwiejsze w użyciu, async/await.

### Typy produktów w StoreKit:

#### 1. **Auto-Renewable Subscription** (Subskrypcja odnaw-ialna)
- Odnawia się automatycznie co miesiąc/rok
- Użytkownik płaci rekurencyjnie
- **Use case:** Premium features w Family To-Do

**Przykład:**
```
Family To-Do Premium
- $4.99/miesiąc
- $39.99/rok (save 33%)
- Auto-renews
- Cancel anytime
```

#### 2. **Non-Renewable Subscription** (Subskrypcja bez auto-odnowienia)
- Trwa określony czas (np. 1 rok)
- Nie odnawia się automatycznie
- **Use case:** Rzadko używane

#### 3. **Consumable** (Zużywalne)
- Można kupić wielokrotnie
- "Zużywa się" po użyciu
- **Use case:** Coins w grach, boosts

**NIE dla Family To-Do**

#### 4. **Non-Consumable** (Niezużywalne)
- Kupujesz raz, masz na zawsze
- **Use case:** Unlock premium version

**Przykład:**
```
Family To-Do Premium Lifetime
- $49.99 one-time
- Unlock premium na zawsze
- No recurring fee
```

### Rekomendacja dla Family To-Do:

**Auto-Renewable Subscription** + opcjonalny **Non-Consumable lifetime**

---

## StoreKit 2 Implementation - Krok po kroku

### Krok 1: Utwórz produkty w App Store Connect

**1.1 Zaloguj się**
```
https://appstoreconnect.apple.com
→ My Apps
→ Family To-Do
→ Subscriptions (lewe menu)
```

**1.2 Utwórz Subscription Group**
```
Kliknij "+" → Create Subscription Group
Nazwa: "Family To-Do Premium"
```

**1.3 Utwórz subskrypcję miesięczną**
```
Kliknij "+" w grupie
Product ID: com.yourname.familytodo.premium.monthly
Reference Name: Premium Monthly
Duration: 1 month
Price: $4.99 (Tier 5)
```

**1.4 Utwórz subskrypcję roczną**
```
Product ID: com.yourname.familytodo.premium.yearly
Reference Name: Premium Yearly
Duration: 1 year
Price: $39.99 (Tier 40)
```

**1.5 Dodaj lokalizacje**
```
Dla każdego produktu dodaj:
- English (US): "Premium Monthly"
- Polish: "Premium miesięcznie"
- Opis features
```

**1.6 Dodaj screenshoty (jeśli wymagane)**

**1.7 Submit for review**
```
Status: Ready to Submit
Kliknij "Submit"
Czekaj ~24-48h na approval
```

---

### Krok 2: Implementacja StoreKit 2 w Swift

**2.1 Import StoreKit**
```swift
import StoreKit
```

**2.2 Utwórz StoreManager**
```swift
// StoreManager.swift
import StoreKit
import Foundation

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // Product IDs
    private let monthlyProductID = "com.yourname.familytodo.premium.monthly"
    private let yearlyProductID = "com.yourname.familytodo.premium.yearly"

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []

    private var updates: Task<Void, Never>? = nil

    init() {
        // Listen for transaction updates
        updates = observeTransactionUpdates()
    }

    deinit {
        updates?.cancel()
    }

    // Load products from App Store
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: [monthlyProductID, yearlyProductID])
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \\(error)")
        }
    }

    // Purchase a product
    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // Verify purchase
            let transaction = try checkVerified(verification)

            // Deliver content to user
            await transaction.finish()

            // Update purchased products
            await updatePurchasedProducts()

            return transaction

        case .userCancelled, .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    // Restore purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            print("Restore failed: \\(error)")
        }
    }

    // Check if user has premium
    var hasPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    // MARK: - Private helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await transaction.finish()
                    await updatePurchasedProducts()
                } catch {
                    print("Transaction failed verification: \\(error)")
                }
            }
        }
    }

    @MainActor
    private func updatePurchasedProducts() async {
        var purchasedIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            if transaction.revocationDate == nil {
                purchasedIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchasedIDs
    }
}

enum StoreError: Error {
    case failedVerification
}
```

**2.3 Utwórz Paywall UI**
```swift
// PaywallView.swift
import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var store = StoreManager.shared
    @Environment(\\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)

                    Text("Unlock Premium")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Add unlimited household members and more")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Features
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "person.3.fill", title: "Unlimited Members", description: "Add as many household members as you need")
                    FeatureRow(icon: "chart.bar.fill", title: "Advanced Analytics", description: "Track completion rates and trends")
                    FeatureRow(icon: "arrow.down.doc.fill", title: "Export Data", description: "Export tasks to CSV anytime")
                    FeatureRow(icon: "envelope.fill", title: "Priority Support", description: "Get help when you need it")
                }
                .padding(.horizontal)

                Spacer()

                // Products
                if store.products.isEmpty {
                    ProgressView("Loading...")
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.products, id: \\.id) { product in
                            ProductButton(product: product) {
                                await purchaseProduct(product)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Restore button
                Button("Restore Purchases") {
                    Task {
                        await store.restorePurchases()
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)

                // Legal
                Text("Cancel anytime. Terms & Privacy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await store.loadProducts()
        }
    }

    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil

        do {
            if let transaction = try await store.purchase(product) {
                // Success!
                dismiss()
            }
        } catch {
            errorMessage = "Purchase failed: \\(error.localizedDescription)"
        }

        isPurchasing = false
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ProductButton: View {
    let product: Product
    let action: () async -> Void

    @State private var isPurchasing = false

    var body: some View {
        Button {
            Task {
                isPurchasing = true
                await action()
                isPurchasing = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(product.displayName)
                        .fontWeight(.semibold)

                    if let description = product.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isPurchasing {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .fontWeight(.bold)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .disabled(isPurchasing)
    }
}
```

**2.4 Show paywall when needed**
```swift
// W ViewModel gdy user próbuje dodać 3. członka
@Published var showPaywall = false

func addMember(_ member: Member) {
    if members.count >= 2 && !StoreManager.shared.hasPremium {
        // Show paywall
        showPaywall = true
    } else {
        // Allow adding
        members.append(member)
    }
}

// W View
.sheet(isPresented: $viewModel.showPaywall) {
    PaywallView()
}
```

---

### Krok 3: Testowanie zakupów (Sandbox)

**3.1 Utwórz Sandbox Tester Account**
```
App Store Connect
→ Users and Access
→ Sandbox Testers
→ "+" Create New Sandbox Tester

Email: test@example.com (nie musi istnieć)
Password: Test1234!
Country: Poland
```

**3.2 Zaloguj się na urządzeniu**
```
Settings → App Store
→ Sandbox Account
→ Sign in with test@example.com
```

**3.3 Testuj zakupy**
```
1. Uruchom app
2. Kliknij "Unlock Premium"
3. Wybierz subskrypcję
4. Touch ID/Face ID → Confirm
5. Sandbox prompt: "Confirm sandbox purchase?"
6. ✅ Purchase successful!
```

**WAŻNE:**
- Sandbox purchases są DARMOWE (nie płacisz prawdziwych pieniędzy)
- Subskrypcje odnaw-iają się szybciej (1 month = 5 minut w sandbox)
- Możesz testować różne scenariusze (success, cancel, expired)

---

## Apple Revenue Share

**Apple bierze prowizję od każdej sprzedaży!**

### Small Business Program (do $1M rocznie)

**Jeśli zarabiasz <$1,000,000/rok:**
- Apple bierze **15%**
- Ty dostajesz **85%**

**Przykład:**
```
User płaci: $4.99
Apple dostaje: $0.75 (15%)
Ty dostajesz: $4.24 (85%)
```

### Standardowa prowizja (powyżej $1M rocznie)

**Jeśli zarabiasz >$1,000,000/rok:**
- Apple bierze **30%**
- Ty dostajesz **70%**

**Przykład:**
```
User płaci: $4.99
Apple dostaje: $1.50 (30%)
Ty dostajesz: $3.49 (70%)
```

### Po 1 roku subskrypcji (retention bonus)

**Jeśli user płaci subskrypcję >1 rok:**
- Apple bierze **15%** (nawet jeśli >$1M revenue)
- Ty dostajesz **85%**

**To zachęca do retention!**

---

## Pricing Strategy dla Family To-Do

### Rekomendowane ceny:

**Monthly subscription:**
- **$4.99/mo** (Tier 5)
- Sweet spot dla productivity apps
- Psychologically "under $5"

**Annual subscription:**
- **$39.99/rok** (Tier 40)
- Save 33% vs monthly
- $3.33/mo effective rate
- Incentivize annual (better for cash flow)

**Lifetime (optional):**
- **$49.99** one-time
- Dla users którzy NIE lubią subscriptions
- ~12.5 months payback (vs monthly)

### Porównanie z konkurencją:

| App | Model | Price | Features |
|---|---|---|---|
| **Todoist** | Freemium | $4/mo, $36/yr | Collaborative task management |
| **Things 3** | Paid | $49.99 | One-time, iOS only |
| **Notion** | Freemium | $10/mo, $96/yr | All-in-one workspace |
| **Any.do** | Freemium | $3/mo, $27/yr | Task + calendar |
| **Family To-Do** | Freemium | $4.99/mo, $39.99/yr | Household-focused, simple |

**Family To-Do jest competitively priced!**

---

## Revenue Calculator

### Scenariusz 1: Freemium (Conservative)

```
Assumptions:
- 500 downloads/month (year 1)
- Free-to-Paid conversion: 5%
- Monthly: $4.99
- Annual: $39.99
- Monthly/Annual split: 70%/30%
- Apple cut: 15%

Miesiąc 1:
- Paid users: 500 × 5% = 25
  - Monthly: 25 × 70% = 17.5 ≈ 18 users × $4.99 × 85% = $76
  - Annual: 25 × 30% = 7.5 ≈ 7 users × $39.99 × 85% = $238
- Total: $314/mo

Miesiąc 6 (assuming 10% monthly churn):
- Accumulated users: ~120 paid
- Monthly revenue: ~$500/mo

Rok 1 total revenue: ~$3,500-5,000
```

### Scenariusz 2: Freemium (Optimistic)

```
Assumptions:
- 1,000 downloads/month
- Conversion: 7%
- Lower churn (5%/mo)

Miesiąc 12:
- Paid users: ~300
- Monthly revenue: ~$1,200/mo

Rok 1 total revenue: ~$8,000-10,000
```

### Scenariusz 3: Trial + Subscription (Aggressive)

```
Assumptions:
- 300 trial signups/month
- Trial conversion: 40%
- Price: $9.99/mo
- Churn: 8%/mo

Miesiąc 12:
- Paid users: ~400
- Monthly revenue: ~$3,400/mo

Rok 1 total revenue: ~$18,000-25,000
```

**Family To-Do realistic target (rok 1):** $5,000-10,000

---

## Legal Requirements

### 1. Privacy Policy (WYMAGANE!)

**Musisz mieć Privacy Policy** mówiącą:
- Jakie dane zbierasz
- Jak używasz danych
- Czy udostępniasz dane third-party
- Jak users mogą usunąć dane

**Dla Family To-Do:**
```
- CloudKit data (tasks, chores)
- Sign in with Apple (email, name)
- NIE zbieramy analytics (bez user zgody)
- NIE sprzedajemy danych
```

**Generator (free):**
- [App Privacy Policy Generator](https://app-privacy-policy-generator.firebaseapp.com/)
- [TermsFeed](https://www.termsfeed.com/privacy-policy-generator/)

### 2. Terms of Service

**Opcjonalne, ale zalecane**

Zawiera:
- Co users mogą/nie mogą robić
- Twoje odpowiedzialności
- Refund policy
- Termination clause

### 3. Subscription Info (WYMAGANE w App Store)

Apple wymaga że pokażesz:
- Cena i okres (month/year)
- Auto-renewal info
- Jak anulować
- Privacy policy link
- Terms link

**To pokazujemy w PaywallView:**
```swift
Text("Cancel anytime. Terms & Privacy.")
    .font(.caption2)
```

---

## Best Practices

### 1. **Value First, Paywall Second**

❌ BAD:
```
User opens app → Immediate paywall
"Unlock Premium to use app!"
```

✅ GOOD:
```
User adds tasks, tries features for free
Tries to add 3rd member → Paywall
"Unlock Premium to add more members"
```

### 2. **Clear Value Proposition**

Paywall musi pokazywać **CO user dostaje**:
```
✅ "Add unlimited members"
✅ "Export data to CSV"
✅ "Priority support"

❌ "Premium features"
❌ "Unlock everything"
```

### 3. **Promotional Offers**

StoreKit 2 pozwala na:
- **Intro pricing:** "First month $0.99"
- **Free trial:** "7 days free, then $4.99/mo"
- **Pay-as-you-go:** "Try 1 month for $1"

**Setup w App Store Connect:**
```
Subscription → Subscription Prices → Introductory Offers
- Free trial: 7 days
- Intro price: $0.99 for 1 month
- Pay-as-you-go: $1 for 1 month
```

**Rekomendacja dla Family To-Do:**
- Month 1-3: Free trial (7 dni)
- Month 4-12: Intro price ($1.99 first month)
- Year 2+: Standard pricing

### 4. **Win-back Offers**

Jeśli user anulował subskrypcję:
```
"Come back! 50% off for 3 months"
```

StoreKit 2 to obsługuje automatycznie.

### 5. **Family Sharing**

Włącz Family Sharing w App Store Connect:
```
Subscription → Edit → Family Sharing: ON
```

**Korzyści:**
- User kupuje, cała rodzina korzysta (max 6 osób)
- Zwiększa value proposition
- Perfect dla Family To-Do! (literally family app)

---

## Troubleshooting

### Issue: "Products not loading"

**Rozwiązanie:**
1. Sprawdź czy Product IDs są poprawne
2. Sprawdź czy produkty są "Ready to Submit" w App Store Connect
3. Poczekaj 24h po utworzeniu produktów
4. Sprawdź czy Agreements w App Store Connect są signed

### Issue: "Purchase failed"

**Rozwiązanie:**
1. Sprawdź czy sandbox account jest zalogowany
2. Sprawdź czy StoreKit configuration file jest poprawny
3. Sprawdź logi: `print(error.localizedDescription)`

### Issue: "Subscription not renewing"

**Rozwiązanie:**
1. W sandbox subskrypcje expire szybciej (testowe)
2. Sprawdź `Transaction.updates` listener
3. Verify transaction: `checkVerified()`

---

## Podsumowanie

### Dla Family To-Do MVP:

**Rekomendowany model:** Freemium
- Free: 2 members, unlimited tasks/chores
- Premium: 3+ members, analytics, export ($4.99/mo lub $39.99/yr)

**Implementation effort:** ~8-12 hours
- App Store Connect setup: 2h
- StoreKit code: 4-6h
- UI/UX (paywall): 2-3h
- Testing: 2h

**Expected revenue (rok 1):** $5,000-10,000
- Conservative: 500 downloads/mo, 5% conversion
- Optimistic: 1000 downloads/mo, 7% conversion

**Apple revenue share:**
- Small Business Program: 15% (zarabiasz <$1M/rok)
- Standardowa: 30% (zarabiasz >$1M/rok)

**Legal:**
- Privacy Policy (WYMAGANE)
- Terms of Service (zalecane)
- Subscription info w app

**Best practices:**
- Value first, paywall second
- Clear value proposition
- Enable Family Sharing
- Offer intro pricing (7-day trial)

---

## Przydatne linki

- [App Store Connect](https://appstoreconnect.apple.com)
- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [In-App Purchase Guide](https://developer.apple.com/in-app-purchase/)
- [Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Subscription Best Practices](https://developer.apple.com/app-store/subscriptions/)
- [Privacy Policy Generator](https://app-privacy-policy-generator.firebaseapp.com/)
- [Revenue Calculator](https://www.revenuecat.com/calculator/)

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
**Status:** Planned for post-MVP implementation (consider for v1.1)
