# TODO (Unified Roadmap)

**Last Updated:** 2026-01-24
**Purpose:** Single source of truth for all LLM agents on what is done, what is next, and where to start.

## Current Focus (Start Here)
- [x] Household onboarding + invitations (CKShare share/accept flow) ✅
- [x] Member management UI + roles (Owner/Member) ✅
- [x] CloudKit CRUD for all core models ✅
- [x] SwiftData local storage for all models ✅
- [x] Basic offline support (cache + optimistic updates) ✅
- [x] Basic notifications (daily digest + real deadlines) ✅
- [x] Settings for notifications + celebrations ✅

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
- [x] Member management UI (edit/delete members + role management)
- [x] SwiftData cache for all models (Task, Household, Member, Area, RecurringChore, ShoppingItem)
- [x] Offline-first foundation (cache-first load + optimistic updates)
- [x] CloudKit error categorization (network, auth, quota, conflicts)
- [x] Shopping list enhancements (suggestion limit + clear to buy)

## Planned Work (Prioritized)

### Priority 1 — MVP Must-Haves (Cards-first)
- [x] Household onboarding + invitations (CKShare share/accept flow)
- [x] Member management UI + roles (Owner/Member)
- [x] Full CloudKit CRUD for Household/Member/Area/RecurringChore/Task/ShoppingItem
- [x] SwiftData local storage for all models
- [x] Basic offline support (cache-first load + optimistic updates)
- [x] Basic notifications (daily digest + real deadlines)
- [x] Settings for notifications + celebrations

### Priority 2 — Shared Shopping List (Enhancements) ✅
- [x] Suggestions from `Bought` (sort by count + recency, limit 5–50)
- [x] Settings: suggestion limit + "Clear To Buy"

### Priority 3 — Quality & Infrastructure
- [ ] Unit tests for critical logic (recurrence, WIP, task transitions)
- [ ] CloudKitManager tests/mocks
- [ ] Resolve SwiftLint warnings in tests (force unwraps)
- [ ] Add new docs to `docs/README.md` index as they're created
- [ ] Add App Store Connect secrets + verify TestFlight deploy job

### Priority 4 — Advanced Sync (Deferred to Post-MVP)

**Rationale:** Basic offline support (cache + optimistic updates) is sufficient for MVP. Advanced conflict resolution needed only when 2+ users edit same item simultaneously (rare in family context). Can be added post-launch based on user feedback.

- [ ] Retry queue with exponential backoff (~2-3h)
- [ ] Last-Write-Wins conflict resolution (~2-3h)
- [ ] Sync status UI indicators (Synced ✅ / Syncing 🔄 / Offline 📴) (~1-2h)
- [ ] Background sync triggers (network state monitoring) (~1-2h)
- [ ] CloudKit system fields for change tracking (~1h)

**ADR-002 Implementation Status:**
- ✅ SwiftData cache with sync metadata
- ✅ Optimistic UI updates
- ✅ Error categorization
- ❌ Retry queue (deferred)
- ❌ LWW merge logic (deferred)
- ❌ Sync status indicators (deferred)

### Priority 5 — Post-MVP / Future Features
- [ ] Templates, activity feed, attachments, advanced projects
- [ ] Analytics (App Store Connect)
- [ ] Monetization (StoreKit 2 + paywall)
- [ ] Localization (PL/DE/IT/ES/others)
- [ ] Marketing / ASO launch plan
