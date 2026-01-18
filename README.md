# Family To-Do App 🏡

A **shared household task management app** for iOS, designed to help couples and families coordinate tasks and groceries without micromanagement or pressure.

**Core Philosophy:** Simple, shared-first architecture that reduces conflicts by providing a single source of truth for household tasks and a shared shopping list, with gentle reminders and clear assignments.

---

## ✨ Key Features

- 📱 **iOS-first** - Native SwiftUI app with offline-first architecture
- ☁️ **CloudKit sync** - Seamless synchronization across devices
- 👥 **Multi-user households** - Share tasks and a global shopping list with partner/family
- ♻️ **Recurring chores** - Auto-schedule weekly/monthly tasks
- 🎯 **WIP limit** - Max 3 tasks per person in "Next" (focus mechanism)
- 🔔 **Gentle notifications** - 1 daily digest max, no nagging
- ✨ **Micro-celebrations** - Duolingo-style positive reinforcement (optional)
- 🔐 **Sign in with Apple** - Secure, privacy-focused authentication

---

## 🎯 Product North Star

> "Does this decision make it easier for two people to live together and remember household tasks, without feeling controlled or pressured?"

If the answer isn't clearly "yes" - simplify or reject the decision.

---

## 🏗️ Architecture

### Tech Stack

- **Platform:** iOS 17+
- **UI Framework:** SwiftUI
- **Backend:** CloudKit (BaaS)
- **Local Storage:** SwiftData
- **Auth:** Sign in with Apple
- **CI/CD:** GitHub Actions

### Core Principles

1. **Shared-first** - Household collaboration is core, not an add-on
2. **Simplicity over power** - Max 3-5 concepts users need to understand
3. **No micromanagement** - No ratings, points, or pressure
4. **Gentle nudges** - Rare, predictable notifications
5. **One source of truth** - Clear status, owner, and history for every task

See [CLAUDE.md](CLAUDE.md) for detailed design principles.

---

## 📚 Documentation

All documentation is in the [docs/](docs/) directory:

### Quick Start

- **[CloudKit Setup Guide](docs/2026-01-10_cloudkit-setup-guide.md)** - Configure CloudKit backend
- **[GitHub Actions Setup](docs/2026-01-10_github-actions-setup.md)** - Setup CI/CD pipeline

### Concepts

- **[ADR Explained](docs/2026-01-10_adr-explained.md)** - Architecture Decision Records
- **[Wireframe Explained](docs/2026-01-10_wireframe-explained.md)** - UX design and wireframes

### Architecture Decisions

- **[ADR-001: CloudKit Backend](docs/2026-01-10_adr-001-cloudkit-backend.md)** - Why CloudKit?

---

## 🚀 Development

### Prerequisites

- macOS with Xcode 15.2+ (or use GitHub Actions for builds)
- Apple Developer Account ($99/year)
- Git

### Local Development (macOS)

```bash
# Clone repository
git clone https://github.com/yourusername/family-todo.git
cd family-todo

# Open in Xcode
open FamilyTodo.xcodeproj

# Add CloudKit capability
# 1. Select target → Signing & Capabilities
# 2. Add "iCloud" capability
# 3. Enable "CloudKit"

# Run on simulator
# Cmd+R in Xcode
```

### Development on Linux (e.g., Manjaro)

**⚠️ Xcode only works on macOS!**

For Linux developers:
1. Write Swift code in any editor (VS Code, Neovim)
2. Push to GitHub
3. GitHub Actions builds and tests automatically on macOS runners
4. View results in GitHub Actions tab

See [GitHub Actions Setup Guide](docs/2026-01-10_github-actions-setup.md) for details.

### CI/CD Pipeline

GitHub Actions automatically:
- ✅ Builds app on every commit
- ✅ Runs unit tests
- ✅ Checks code quality (SwiftLint)
- 🚀 Deploys to TestFlight (on `main` branch)

**Free tier:** 2000 minutes/month on macOS runners

---

## 📋 Project Status

**Current Phase:** MVP Planning & Architecture Setup

### ✅ Completed
- [x] Product requirements defined (instructions.md)
- [x] Core design principles documented (CLAUDE.md)
- [x] Backend choice (CloudKit) - see ADR-001
- [x] CI/CD pipeline configured (GitHub Actions)
- [x] Documentation structure created

### 🚧 In Progress
- [ ] Xcode project setup
- [ ] CloudKit schema implementation
- [ ] SwiftUI views (Home, Task List, Shopping List, Recurring Chores)
- [ ] SwiftData local storage

### 📅 Planned
- [ ] Sign in with Apple integration
- [ ] Household sharing (CKShare)
- [ ] Recurring chores auto-scheduling
- [ ] Gentle celebration animations
- [ ] TestFlight beta testing

---

## 🤝 Contributing

This is currently a solo project. Contributions may be accepted in the future.

If you're interested in similar projects or want to discuss household task management UX, feel free to open an issue!

---

## 📄 License

TBD (currently private development)

---

## 🧠 Design Philosophy

This app is **NOT**:
- ❌ A project management tool (Jira for home)
- ❌ A gamified productivity app (with points/leaderboards)
- ❌ A micromanagement tool (tracking every detail)

This app **IS**:
- ✅ A shared memory for household tasks and groceries
- ✅ A conflict-reduction tool (neutral assignments)
- ✅ A gentle reminder system (not nagging)
- ✅ A focus tool (WIP limit of 3 tasks per person)

**Target Audience:** Couples/families managing a household together, who value:
- Clear communication
- Shared responsibility
- Low cognitive overhead
- Relationship-friendly mechanics

---

## 📞 Contact

**Project Lead:** Wojtek Kochanowski

For questions, feedback, or collaboration inquiries, please open an issue.

---

**Last Updated:** 2026-01-18
