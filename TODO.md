# TODO (Unified Roadmap)

**Last Updated:** 2026-01-19
**Purpose:** Single source of truth for all LLM agents on what is done, what is next, and where to start.

## Current Focus (Start Here)
- [x] Household onboarding + invitations (CKShare share/accept flow) ✅
- [ ] Member management UI + roles (Owner/Member)
- [ ] CloudKit CRUD for all core models (Household/Member/Area/Task/RecurringChore/ShoppingItem)
- [ ] Offline-first sync engine per ADR-002 (sync states, LWW merge, retries)
- [ ] SwiftData local storage for all models (not only tasks)
- [ ] Basic notifications (daily digest + real deadlines)
- [ ] Settings for notifications + celebrations

## Completed (Implemented or in codebase)
- [x] Xcode project scaffold and SwiftUI app shell
- [x] Core models: Household, Member, Area, Task, RecurringChore
- [x] TaskStore with optimistic UI + WIP limit logic
- [x] SwiftData offline cache (`CachedTask`)
- [x] Book-style cards home screen (glass morphism + shimmer + confetti)
- [x] Cards wired to live data (tasks, shopping list, recurring, household)
- [x] Shopping list model + CloudKit store
- [x] Household card lists areas + members
- [x] TaskListView + TaskDetailView (legacy tabs retained)
- [x] Areas and Recurring Chores views/stores (UI scaffolding)
- [x] Settings view + sign-out
- [x] Sign in with Apple flow (AuthenticationService, UserSession, SignInView)
- [x] GitHub Actions CI + Fastlane pipeline wiring
- [x] Core docs + MVP wireframes + shared shopping list spec
- [x] CardsPagerView added to Xcode project
- [x] TestFlight deploy disabled until credentials exist
- [x] Unified roadmap in TODO.md

## Planned Work (Prioritized)

### Priority 1 — MVP Must-Haves (Cards-first)
- [x] Household onboarding + invitations (CKShare share/accept flow)
- [ ] Member management UI + roles (Owner/Member)
- [ ] Full CloudKit CRUD for Household/Member/Area/RecurringChore/Task/ShoppingItem
- [ ] Offline-first sync engine per ADR-002 (sync states, LWW merge, retries)
- [ ] SwiftData local storage for all models (not only tasks)
- [ ] Basic notifications (daily digest + real deadlines)
- [ ] Settings for notifications + celebrations

### Priority 2 — Shared Shopping List (Enhancements)
- [ ] Suggestions from `Bought` (sort by count + recency, limit 5–50)
- [ ] Settings: suggestion limit + “Clear To Buy”

### Priority 3 — Quality & Infrastructure
- [ ] Unit tests for critical logic (recurrence, WIP, task transitions)
- [ ] CloudKitManager tests/mocks
- [ ] Resolve SwiftLint warnings in tests (force unwraps)
- [ ] Add new docs to `docs/README.md` index as they’re created
- [ ] Add App Store Connect secrets + verify TestFlight deploy job

### Priority 4 — Post-MVP / Future Features
- [ ] Templates, activity feed, attachments, advanced projects
- [ ] Analytics (App Store Connect)
- [ ] Monetization (StoreKit 2 + paywall)
- [ ] Localization (PL/DE/IT/ES/others)
- [ ] Marketing / ASO launch plan
