# TODO (Unified Roadmap)

**Last Updated:** 2026-01-18
**Purpose:** Single source of truth for all LLM agents on what is done, what is next, and where to start.

## Current Focus (Start Here)
- [ ] Fix GitHub Actions `Build and Test` failure: CoreAudioTypes linker error in `FamilyTodoTests`
- [ ] Re-run CI after the fix and confirm green build

## Completed (Implemented or in codebase)
- [x] Xcode project scaffold and SwiftUI app shell
- [x] Core models: Household, Member, Area, Task, RecurringChore
- [x] TaskStore with optimistic UI + WIP limit logic
- [x] SwiftData offline cache (`CachedTask`)
- [x] TaskListView (Next/Backlog/Done) and TaskDetailView (create/edit)
- [x] Areas and Recurring Chores views/stores (UI scaffolding)
- [x] Settings view + sign-out
- [x] Sign in with Apple flow (AuthenticationService, UserSession, SignInView)
- [x] GitHub Actions CI + Fastlane pipeline wiring
- [x] Core docs + MVP wireframes + shared shopping list spec

## Planned Work (Prioritized)

### Priority 1 — MVP Must‑Haves
- [ ] Household onboarding + invitations (CKShare share/accept flow)
- [ ] Member management UI + roles (Owner/Member)
- [ ] Full CloudKit CRUD for Household/Member/Area/RecurringChore/Task
- [ ] Offline‑first sync engine per ADR‑002 (sync states, LWW merge, retries)
- [ ] SwiftData local storage for all models (not only tasks)
- [ ] WIP limit enforcement in UI (prevent adding 4th “Next”)
- [ ] Basic notifications (daily digest + real deadlines)
- [ ] Household overview screen (areas summary + members)
- [ ] Settings for notifications + celebrations

### Priority 2 — Shared Shopping List (Household‑wide)
- [ ] ShoppingItem + ShoppingListEntry models (quantity value + unit)
- [ ] CloudKit schema + SwiftData cache for shopping list
- [ ] Shopping tab UI with `To Buy` / `Bought`
- [ ] Add/edit/delete items + mark bought flow
- [ ] Suggestions from `Bought` (sort by count + recency, limit 5–50)
- [ ] Settings: suggestion limit + “Clear To Buy”

### Priority 3 — Quality & Infrastructure
- [ ] Unit tests for critical logic (recurrence, WIP, task transitions)
- [ ] CloudKitManager tests/mocks
- [ ] Resolve SwiftLint warnings in tests (force unwraps)
- [ ] Add new docs to `docs/README.md` index as they’re created
- [ ] Add App Store Connect secrets + verify TestFlight deploy job

### Priority 4 — Post‑MVP / Future Features
- [ ] Templates, activity feed, attachments, advanced projects
- [ ] Analytics (App Store Connect)
- [ ] Monetization (StoreKit 2 + paywall)
- [ ] Localization (PL/DE/IT/ES/others)
- [ ] Marketing / ASO launch plan
