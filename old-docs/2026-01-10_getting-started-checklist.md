# Getting Started Checklist - Jak zacząć kodowanie

**Data:** 2026-01-10
**Projekt:** Family To-Do App
**Cel:** Wyjaśnienie jakie kroki podjąć ZANIM Claude zacznie pisać kod

---

## Pytanie: Jakie kroki muszę podjąć, abyś (Claude) mógł zacząć pisać kod?

Odpowiadam szczegółowo z dwoma ścieżkami: **Opcja A (macOS)** i **Opcja B (Linux/Manjaro)**.

---

## Opcja A: Masz dostęp do macOS (Recommended)

### Krok 1: Zainstaluj Xcode

**1.1 Pobierz Xcode:**
```
Mac App Store → Xcode → Pobierz (FREE, ~15GB)
lub
https://developer.apple.com/xcode/
```

**1.2 Zainstaluj Command Line Tools:**
```bash
xcode-select --install
```

**1.3 Zweryfikuj instalację:**
```bash
xcode-select -p
# Output: /Applications/Xcode.app/Contents/Developer

xcodebuild -version
# Output: Xcode 15.2
#         Build version 15C500b
```

**Czas:** ~30-60 minut (w zależności od internetu)

---

### Krok 2: Zarejestruj się w Apple Developer Program

**2.1 Dlaczego potrzebne?**
- CloudKit wymaga Apple Developer Account
- TestFlight wymaga Apple Developer Account
- App Store wymaga Apple Developer Account

**2.2 Jak się zarejestrować:**
```
1. Idź na https://developer.apple.com/programs/
2. Kliknij "Enroll"
3. Zaloguj się Apple ID
4. Wypełnij formularz
5. Zapłać $99/rok
6. Czekaj ~24-48h na aktywację
```

**Koszt:** $99/rok (recurring)
**Czas:** 24-48h na aktywację

**⚠️ WAŻNE:** To jest WYMAGANE, nie opcjonalne!

---

### Krok 3: Utwórz projekt w Xcode

**3.1 Nowy projekt:**
```
1. Otwórz Xcode
2. File → New → Project
3. Wybierz "App" (iOS)
4. Kliknij "Next"
```

**3.2 Konfiguracja projektu:**
```
Product Name: FamilyTodo
Team: [Twój Apple Developer Team]
Organization Identifier: com.yourname
Bundle Identifier: com.yourname.familytodo (auto-generated)
Interface: SwiftUI
Language: Swift
Storage: None (użyjemy CloudKit)
Include Tests: ☑ YES
```

**3.3 Wybierz lokalizację:**
```
~/code/family-todo/
```

**3.4 Zweryfikuj strukturę:**
```
family-todo/
├── FamilyTodo.xcodeproj
├── FamilyTodo/
│   ├── FamilyTodoApp.swift
│   ├── ContentView.swift
│   ├── Assets.xcassets/
│   └── Preview Content/
├── FamilyTodoTests/
└── FamilyTodoUITests/
```

**Czas:** ~5 minut

---

### Krok 4: Dodaj CloudKit Capability

**4.1 Włącz iCloud:**
```
1. W Xcode, wybierz projekt (top level)
2. Wybierz target "FamilyTodo"
3. Zakładka "Signing & Capabilities"
4. Kliknij "+ Capability"
5. Wyszukaj "iCloud"
6. Kliknij "iCloud"
```

**4.2 Włącz CloudKit:**
```
W sekcji iCloud:
☑ CloudKit
Container: iCloud.com.yourname.familytodo (auto-created)
```

**4.3 Włącz Background Modes (dla sync):**
```
1. "+ Capability" → "Background Modes"
2. ☑ Remote notifications
```

**4.4 Zweryfikuj:**
Plik `FamilyTodo.entitlements` powinien zawierać:
```xml
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.yourname.familytodo</string>
</array>
```

**Czas:** ~5 minut

---

### Krok 5: Test Build

**5.1 Wybierz Simulator:**
```
Top bar → iPhone 15 (lub inny)
```

**5.2 Build and Run:**
```
Cmd+R
lub
Product → Run
```

**5.3 Powinieneś zobaczyć:**
```
- Simulator uruchamia się
- App otwiera się
- Widzisz "Hello, World!" (default SwiftUI)
```

**Jeśli build fails:**
- Sprawdź czy wybrałeś Team w Signing & Capabilities
- Sprawdź czy Bundle ID jest unique
- Clean Build Folder (Cmd+Shift+K) i spróbuj ponownie

**Czas:** ~2 minuty

---

### Krok 6: Utwórz Git Repository

**6.1 Inicjalizuj git (jeśli jeszcze nie):**
```bash
cd ~/code/family-todo
git init
```

**6.2 Skopiuj .gitignore (już utworzony):**
```bash
# .gitignore already exists from our setup!
# Verify it includes:
cat .gitignore | grep -E "xcuserdata|DerivedData"
```

**6.3 First commit:**
```bash
git add .
git commit -m "Initial Xcode project setup

- Created iOS app with SwiftUI
- Added CloudKit capability
- Enabled iCloud
- Added Background Modes for sync"
```

**6.4 Utwórz GitHub repo:**
```
1. GitHub.com → New repository
2. Name: family-todo
3. Description: Family household task management app
4. Private (lub Public)
5. DON'T initialize with README (już mamy lokalnie)
6. Create repository
```

**6.5 Push do GitHub:**
```bash
git remote add origin https://github.com/yourusername/family-todo.git
git branch -M main
git push -u origin main
```

**Czas:** ~10 minut

---

### Krok 7: Przekaż dostęp Claude

**7.1 Udostępnij repository:**
- **Jeśli private:** Dodaj collaboratora lub make public
- **Jeśli public:** Podaj URL

**7.2 Commit i push wszystkie zmiany:**
```bash
git add -A
git commit -m "Project ready for development"
git push
```

**7.3 Powiadom Claude:**
```
"Projekt gotowy! Możesz zacząć kodować.
Repo: https://github.com/yourusername/family-todo"
```

**🎉 GOTOWE! Claude może zacząć pisać kod!**

---

## Opcja B: Tylko Linux/Manjaro (bez macOS)

⚠️ **UWAGA:** Xcode NIE działa na Linuxie. Będziesz pisał kod lokalnie, ale buildy będą w chmurze (GitHub Actions).

### Krok 1: Zainstaluj podstawowe narzędzia

```bash
# Git (jeśli nie masz)
sudo pacman -S git

# Edytor (VS Code recommended dla Swift)
sudo pacman -S code

# Swift language server (optional, dla syntax highlighting)
yay -S sourcekit-lsp
```

---

### Krok 2: Utwórz strukturę projektu ręcznie

**2.1 Utwórz foldery:**
```bash
mkdir -p ~/code/family-todo
cd ~/code/family-todo

mkdir -p FamilyTodo/Models
mkdir -p FamilyTodo/Views
mkdir -p FamilyTodo/ViewModels
mkdir -p FamilyTodo/Managers
mkdir -p FamilyTodo/Utils
mkdir -p FamilyTodoTests
```

**2.2 Utwórz podstawowe pliki:**

**FamilyTodo/FamilyTodoApp.swift:**
```swift
import SwiftUI

@main
struct FamilyTodoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**FamilyTodo/ContentView.swift:**
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, World!")
            .padding()
    }
}
```

**2.3 Utwórz `project.pbxproj` (skeleton):**

⚠️ **PROBLEM:** `.xcodeproj` file format jest bardzo skomplikowany!

**LEPSZE ROZWIĄZANIE:** Poproś kogoś z macOS o:
1. Utworzenie projektu w Xcode
2. Push initial setup do GitHub
3. Ty pull'ujesz i pracujesz dalej

---

### Krok 3: Setup GitHub Actions (już zrobione!)

**Dobra wiadomość:** GitHub Actions config już istnieje!

**`.github/workflows/ios-ci.yml` automatycznie:**
- Buduje projekt na macOS runners
- Uruchamia testy
- Raportuje błędy

**Workflow:**
```
1. Edytujesz kod lokalnie w VS Code (Manjaro)
2. git commit + push
3. GitHub Actions buduje i testuje
4. Sprawdzasz logi w GitHub Actions tab
5. Jeśli build fails → poprawiasz i push again
```

---

### Krok 4: Pierwszy build na GitHub Actions

**4.1 Push placeholder code:**
```bash
cd ~/code/family-todo
git init
git add .
git commit -m "Initial project structure for GitHub Actions"
```

**4.2 Utwórz GitHub repo:**
```
(Same jak Opcja A, krok 6.4)
```

**4.3 Push:**
```bash
git remote add origin https://github.com/yourusername/family-todo.git
git push -u origin main
```

**4.4 Sprawdź GitHub Actions:**
```
1. GitHub repo → Actions tab
2. Zobacz workflow run
3. Jeśli fail - sprawdź logi
```

**⚠️ WAŻNE:** Pierwszy build prawdopodobnie FAIL (brak .xcodeproj).

**Rozwiązanie:**
- Poproś Claude o utworzenie plików projektu
- Lub poproś kogoś z macOS o initial setup

---

### Krok 5: Iteracyjne fixowanie przez GitHub Actions

**Workflow:**
```
1. Claude pisze kod → commit
2. Push do GitHub
3. GitHub Actions buduje
4. Build fails z błędem
5. Claude poprawia → commit
6. Push
7. Repeat aż build passes
```

**To jest WOLNIEJSZE niż local development, ale działa!**

**Czas na pierwszy successful build:** 2-5 iteracji (~1-2 godziny)

---

### Krok 6: Testing na prawdziwym urządzeniu

**Problem:** Nie masz Simulatora na Linuxie!

**Rozwiązania:**
1. **TestFlight** (gdy app już działa):
   - GitHub Actions → build IPA → upload to TestFlight
   - Testujesz na swoim iPhonie

2. **Pożycz/ wynajmij Maca:**
   - Mac Mini M1 used: ~$400
   - MacStadium cloud Mac: $20-50/mo
   - Kolega z Makiem: priceless 😄

3. **Xcode Cloud** (Apple's CI/CD):
   - $15-50/mo
   - Buduje i testuje w chmurze
   - Alternative do GitHub Actions

---

## Co Claude potrzebuje żeby zacząć kodować?

### Minimum Required:

✅ **1. GitHub Repository URL**
```
https://github.com/yourusername/family-todo
```

✅ **2. Dostęp do repo**
- Public repo: Claude ma dostęp automatycznie
- Private repo: Dodaj Claude jako collaborator (jeśli możliwe) lub make public

✅ **3. Xcode project structure**
- `.xcodeproj` file EXISTS (utworzony w Xcode lub ręcznie)
- Basic Swift files exist (App.swift, ContentView.swift)

✅ **4. CloudKit capability configured**
- `FamilyTodo.entitlements` file z iCloud settings
- Bundle ID: `com.yourname.familytodo`

### Nice to Have (przyspieszą development):

🟡 **5. Git hooks configured** (opcjonalne)
🟡 **6. Issue tracking** (GitHub Issues dla bug reportów)
🟡 **7. Project board** (GitHub Projects dla planning)

---

## Pierwszy Coding Session - czego się spodziewać?

### Sesja 1: Setup & Models (2-4h)

**Claude utworzy:**
1. **Data Models** (Household, Member, Task, RecurringChore, Area)
   ```
   FamilyTodo/Models/
   ├── Household.swift
   ├── Member.swift
   ├── Task.swift
   ├── RecurringChore.swift
   └── Area.swift
   ```

2. **CloudKitManager**
   ```
   FamilyTodo/Managers/
   └── CloudKitManager.swift
   ```

3. **Basic Tests**
   ```
   FamilyTodoTests/
   ├── TaskTests.swift
   └── RecurringChoreTests.swift
   ```

**Ty robisz:**
- Review kodu (pull request lub direct commit review)
- Test lokalnie (build + run w Simulatorze)
- Report bugs/issues

---

### Sesja 2: Views & Navigation (3-5h)

**Claude utworzy:**
1. **Main Views**
   ```
   FamilyTodo/Views/
   ├── HomeView.swift
   ├── TaskListView.swift
   ├── TaskDetailView.swift
   ├── RecurringChoresView.swift
   └── SettingsView.swift
   ```

2. **Navigation**
   ```
   FamilyTodo/
   └── MainTabView.swift
   ```

**Ty robisz:**
- Test user flows
- Feedback na UI/UX
- Request changes

---

### Sesja 3: Logic & Integration (4-6h)

**Claude utworzy:**
1. **ViewModels**
   ```
   FamilyTodo/ViewModels/
   ├── TaskViewModel.swift
   ├── RecurringChoreViewModel.swift
   └── HouseholdViewModel.swift
   ```

2. **CloudKit Integration**
   - CRUD operations
   - Sync logic
   - Error handling

**Ty robisz:**
- Test offline mode (Airplane Mode)
- Test CloudKit sync
- Report edge cases

---

### Sesja 4: Polish & Testing (2-3h)

**Claude robi:**
- Bug fixes z Twojego feedback
- Additional tests
- Code cleanup
- Documentation

**Ty robisz:**
- Final testing
- Prepare for TestFlight
- Write release notes

---

## Troubleshooting

### Issue: "Nie mam Maca, nie mogę utworzyć .xcodeproj"

**Rozwiązanie:**
1. **Opcja A:** Poproś kogoś z Makiem o utworzenie projektu i push do GitHub
2. **Opcja B:** Użyj template .xcodeproj (Claude może dostarczyć)
3. **Opcja C:** Kup/wypożycz Maca na weekend ($0 od kolegi lub $400 Mac Mini used)

### Issue: "CloudKit wymaga Apple Developer Account, a ja nie mam"

**Rozwiązanie:**
1. Musisz zarejestrować ($99/rok) - to jest **wymagane** dla CloudKit
2. Alternative: Użyj Firebase zamiast CloudKit (zmiana architektury)
3. Alternative: Develop lokalnie bez backendu (tylko local storage)

### Issue: "GitHub Actions fails: 'No such file or directory: FamilyTodo.xcodeproj'"

**Rozwiązanie:**
1. Upewnij się że `.xcodeproj` jest committed do git
2. Sprawdź `.gitignore` - czy nie ignoruje `.xcodeproj`?
3. Push ponownie z flagą force (jeśli potrzeba):
   ```bash
   git add -f FamilyTodo.xcodeproj
   git commit -m "Add Xcode project"
   git push
   ```

---

## Checklist - Czy jestem gotowy?

### Przed pierwszym coding session:

**Opcja A (macOS):**
- [ ] Xcode zainstalowany
- [ ] Apple Developer Account aktywny ($99/rok paid)
- [ ] Projekt utworzony w Xcode
- [ ] CloudKit capability dodana
- [ ] Test build successful (Cmd+R działa)
- [ ] Git repo utworzone
- [ ] Pushed do GitHub
- [ ] Claude ma dostęp do repo

**Opcja B (Manjaro/Linux):**
- [ ] Git zainstalowany
- [ ] VS Code (lub inny edytor) zainstalowany
- [ ] Basic project structure utworzona
- [ ] GitHub repo utworzone
- [ ] GitHub Actions skonfigurowane (już zrobione!)
- [ ] Kolega z Makiem może pomóc (optional ale helpful!)
- [ ] Claude ma dostęp do repo

**Universal:**
- [ ] Przeczytałeś `CLAUDE.md`
- [ ] Przeczytałeś `instructions.md`
- [ ] Masz ~4-8h czasu na pierwszy sprint
- [ ] Jesteś gotowy na iteracyjny development

---

## Timeline Estimate

### Opcja A (macOS):

| Krok | Czas |
|---|---|
| Install Xcode | 30-60min |
| Apple Developer signup | 24-48h (czekanie) |
| Create project | 5min |
| Add CloudKit | 5min |
| Test build | 2min |
| Git setup | 10min |
| **TOTAL** | **~1-2h + 24-48h czekania** |

### Opcja B (Manjaro):

| Krok | Czas |
|---|---|
| Install tools | 10min |
| Create structure | 30min |
| GitHub setup | 10min |
| First GitHub Actions build | 1-2h (iteracje) |
| **TOTAL** | **~2-4h** |

---

## Podsumowanie

### Pytanie: "Jakie kroki muszę podjąć, abyś (Claude) mógł zacząć pisać kod?"

**Odpowiedź (Opcja A - macOS):**
1. ✅ Zainstaluj Xcode
2. ✅ Zarejestruj Apple Developer Account ($99/rok)
3. ✅ Utwórz projekt w Xcode
4. ✅ Dodaj CloudKit capability
5. ✅ Test build (Cmd+R)
6. ✅ Push do GitHub
7. ✅ Powiadom Claude: "Gotowe, możesz zacząć!"

**Odpowiedź (Opcja B - Manjaro):**
1. ✅ Zainstaluj Git + VS Code
2. ✅ Poproś kolegę z Makiem o initial Xcode project setup
   (lub użyj template)
3. ✅ Pull projekt lokalnie
4. ✅ Push changes do GitHub
5. ✅ GitHub Actions buduje automatycznie
6. ✅ Powiadom Claude: "Gotowe, możesz zacząć!"

**Co Claude utworzy (pierwsza sesja):**
- Data models (Household, Task, RecurringChore, etc.)
- CloudKitManager
- Basic Views (HomeView, TaskListView)
- Unit tests
- SwiftUI navigation

**Kiedy możesz testować:**
- Opcja A: Od razu (local Simulator)
- Opcja B: Po deploymencie do TestFlight (~1-2 tygodnie)

**Realnie ile czasu na pierwszy working prototype:**
- Opcja A: 2-3 tygodnie (4-6 sesji po 4h)
- Opcja B: 3-4 tygodnie (więcej iteracji przez GitHub Actions)

---

## Przydatne linki

- [Xcode Download](https://developer.apple.com/xcode/)
- [Apple Developer Program](https://developer.apple.com/programs/)
- [GitHub](https://github.com)
- [VS Code](https://code.visualstudio.com/)
- [SwiftUI Tutorial](https://developer.apple.com/tutorials/swiftui)
- [CloudKit Setup Guide](2026-01-10_cloudkit-setup-guide.md)
- [GitHub Actions Setup](2026-01-10_github-actions-setup.md)

---

**Data aktualizacji:** 2026-01-10
**Autor:** Claude Code Assistant
**Status:** Ready to start - waiting for user setup completion
