# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Family To-Do App** - An iOS application designed for shared household task management. The core value proposition is providing a single source of truth for household tasks with natural sharing, minimal cognitive overhead, and conflict reduction through clear assignments and gentle reminders.

**Critical Principle**: This is NOT a project management tool like Jira. It's "home Agile lite" - designed to help people remember and plan without micromanagement, scoring, or pressure.

## Product North Star

Before implementing any feature, ask: **"Does this decision make it easier for two people to live together and remember household tasks, without feeling controlled or pressured?"**

If the answer isn't clearly "yes" - simplify or reject the decision.

## Core Design Principles (DO NOT VIOLATE)

1. **Shared-first**: Sharing is core, not an add-on. Household (shared space) exists from the start.
2. **Simplicity over power**: Max 3-5 concepts users need to understand. If a feature complicates onboarding/UX, simplify or remove it.
3. **No micromanagement**: No ratings, points, penalties, or pressure.
4. **Gentle nudges, not nagging**: Notifications are rare, predictable, and configurable.
5. **One source of truth**: Every task has clear status, owner, and change history.

## Domain Model

### Core Entities

**Household**
- Shared data space containing members, tasks, projects, and recurring chores
- Single source of truth for the family

**Members**
- Users assigned to Household
- Minimal roles: Owner, Member
- Each member has "My Tasks" perspective

**Areas/Boards**
- Logical areas of home/life (Kitchen, Bathroom, Garden, Repairs)
- For organization, not control

**Projects**
- Larger goals/initiatives (e.g., "Build a bench")
- Always composed of small, checkable steps
- Must have one clear "Next action"

**Tasks**
- Minimal fields:
  - `title` (verb + effect)
  - `assignee` (who does it)
  - `status`
  - `due_date` (optional)
  - `area/project`
  - `type`: one-off or recurring

**Recurring Chores**
- Cyclical tasks (e.g., weekly)
- Auto-scheduled after completion

## Workflow Patterns

### Minimal Kanban
Statuses only:
- Backlog
- Next (Now)
- Done

### WIP Limit
**CRITICAL**: Each user can have max 3 tasks in "Next". This is a key focus mechanism.

### Definition of Done
Tasks must be formulated to be unambiguously checkable. Always promote precise naming.

### Priorities (No Numbers)
Only use:
- Today
- This Week
- Someday

## Relational Mechanics

**Proposal vs Assignment**
- Tasks can be added as "proposals"
- Other person can accept them to their "Next"
- No automatic assignment without consent (unless user explicitly sets it)

**Neutrality**
- App doesn't "judge" or compare users

## Gentle Celebration (Not Gamification)

**CRITICAL**: Traditional gamification (points, leaderboards, streaks) creates competition and pressure - exactly what we're avoiding.

**What we DON'T do:**
- ❌ Points, badges, or scores
- ❌ Leaderboards or comparisons between members
- ❌ Streak counters that create pressure
- ❌ "You vs Partner" competition mechanics

**What we DO (Duolingo-style gentle rewards):**
- ✨ **Micro-celebrations**: Simple, playful acknowledgment when completing tasks
  - "Nice! Kitchen is sparkling ✨"
  - "Bathroom sorted! 🧼"
  - Emoji based on area/task type
- 🎉 **Milestone moments**: Celebrate shared achievements (non-comparative)
  - "10 tasks done this week! Home is happy 🏡"
  - "First full week with empty Next! Take a break ☕"
- 📊 **Neutral progress**: Show household progress, not individual scores
  - "8/12 weekly tasks done"
  - "Living room: all sorted ✓"
- 🌟 **Occasional surprises**: Rare, delightful moments (not predictable rewards)
  - After completing all recurring chores: "Weekend earned! 🎈"
  - Random positive messages (max once per week)

**Design principles:**
1. Celebrations are **private** (shown to person who completed task, not broadcast to partner)
2. **No pressure**: Optional, can be disabled in settings
3. **Relationship-first**: Never create competition between partners
4. **Genuinely helpful**: Reinforces good habits without manipulation

**Examples:**
```
✓ Task completed: "Dishes done"
  → Show: "✨ Clean kitchen! Next: Take out trash"

✓ All recurring chores this week done
  → Show: "🎉 Weekly chores complete! Home looks great"

✓ Partner completed their Next 3
  → Show to other: "💙 [Partner] cleared their Next!"
```

## Notification Policy

- 1 daily digest max
- Deadline notifications only for real deadlines
- No hourly reminders
- Complete silence option available

## MVP Scope

### In MVP:
- Household + invitations
- Areas/Boards
- Tasks with assignee and status
- Recurring chores (weekly)
- "Next 3" for each user
- Basic notifications

### Out of MVP (optional):
- Templates
- Activity feed
- Attachments
- Advanced projects

## Future Features (Post-MVP)

These features are documented and planned for implementation after MVP launch. Each has dedicated documentation in `docs/` with implementation guides, cost estimates, and trade-offs.

### Analytics & Metrics
- **What:** App Store Connect analytics (downloads, active users, retention, crashes)
- **Documentation:** [Analytics Guide](docs/2026-01-10_analytics-explained.md)
- **Status:** Not implemented
- **Priority:** Medium (after MVP launch with 10+ users)
- **Effort:** 0h (App Store Connect is automatic)
- **Cost:** $0 (free with Apple Developer Account)
- **When:** Post-MVP, when you want to measure growth

### Monetization
- **What:** In-app purchases / subscriptions (StoreKit 2)
- **Model:** Freemium recommended (free: 2 members, paid: 3+ members)
- **Pricing:** $4.99/mo or $39.99/yr
- **Documentation:** [Monetization Guide](docs/2026-01-10_monetization-explained.md)
- **Status:** Not implemented
- **Priority:** High (required for sustainability after product-market fit)
- **Effort:** 8-12h (App Store Connect setup + StoreKit 2 code + PaywallUI)
- **Revenue estimate:** $5,000-10,000 year 1 (conservative)
- **When:** After MVP validation (100+ active users, positive feedback)

### Localization (i18n)
- **What:** Multi-language support (Polish, German, Italian, Spanish, Chinese, Japanese)
- **Approach:** DIY with AI assistance (ChatGPT/Claude) + native review
- **Documentation:** [Localization Guide](docs/2026-01-10_localization-explained.md)
- **Status:** English only
- **Priority:** Medium (expand user base internationally)
- **Effort:** ~15-20h for 3 languages (PL, DE, IT)
- **Cost:** $45-75 (native review per language: $15-25)
- **Rollout plan:**
  - v1.0: English only (MVP)
  - v1.1: + Polish (main market)
  - v1.2: + German (large market)
  - v2.0: + Italian, Spanish, Chinese, Japanese
- **When:** v1.1 (after MVP in English is stable)

### Automated Testing
- **What:** Unit tests, UI tests, integration tests
- **Framework:** XCTest (built-in)
- **Documentation:** [Testing Strategy](docs/2026-01-10_testing-strategy.md)
- **Status:** Partially implemented (GitHub Actions CI configured, no tests yet)
- **Priority:** High (code quality, refactoring confidence)
- **Recommended approach:** Level 1 (Unit tests only) for MVP
- **Effort:**
  - Level 1 (Unit only): 10-15h initial + 30min/feature
  - Level 2 (Unit + UI): 20-30h initial + 1.5h/feature
  - Level 3 (Full): 40-60h initial + 3h/feature
- **Coverage target:** 60-70% for MVP
- **When:** Start with MVP (unit tests for critical logic)

### Marketing & Growth Strategy
- **What:** App Store Optimization (ASO), paid advertising, launch strategy, organic growth
- **Target market:** Global English-speaking (USA, UK primarily)
- **Budget:** $50-200/month (bootstrap phase)
- **Channels:**
  - **Primary:** Apple Search Ads ($100-150/month recommended)
  - **Secondary:** Facebook/Instagram Ads ($50-100/month)
  - **Organic:** Product Hunt launch, Reddit engagement, X/Twitter #BuildInPublic
- **Launch strategy:** Aggressive Day 1 post-MVP
- **Documentation:** [Marketing Strategy Guide](docs/2026-01-11_marketing-strategy-explained.md)
- **Status:** Planned (execute post-MVP)
- **Priority:** High (user acquisition critical for validation)
- **Effort:** 5-10h/week (monitoring ads, content creation, community engagement)
- **Expected results (Month 1):** 160-425 downloads, 3-10 paying users, $15-50 revenue
- **Break-even timeline:** 6-12 months realistic
- **When:** Day 1 after MVP approval (ASO setup), Week 1 (paid ads start)
- **Key metrics:** CPI <$3, conversion to paid >2%, 4.5+ star rating
- **ASO priorities:** Keywords, screenshots with value props, first 3 lines of description

### Implementation Prerequisites
- **Getting Started:** See [Getting Started Checklist](docs/2026-01-10_getting-started-checklist.md)
- **Required:** Xcode project setup, CloudKit capability, GitHub repo
- **Estimated first working prototype:** 2-3 weeks (4-6 sessions × 4h)

## Technical Stack

- **Platform**: iOS-first
- **UI Framework**: SwiftUI
- **Architecture**: Offline-first with background sync
- **Auth**: Sign in with Apple
- **Backend**: CloudKit (see ADR-001 in docs/)
- **Local Storage**: SwiftData (for offline caching)
- **CI/CD**: GitHub Actions

## User Mental Model

Users think in terms of:
- "what needs to be done at home"
- "who will do it"
- "is this for now or later"
- "is this one-time or recurring"

Design UI language, structures, and flows to match this thinking.

## Development Guidelines

When implementing features:
1. Prioritize simplicity and human relationships
2. Avoid feature creep
3. If multiple options exist, choose the simplest as default, describe others as alternatives
4. Keep UX language aligned with user mental model (see above)
5. Always consider offline-first architecture
6. Ensure all decisions support the "two people living together" use case

## Agent Permissions

When working in this repository, the agent (Claude/Gemini) is allowed to:

1. **Git operations**: Run `git add` and `git commit` autonomously after completing work
2. **GitHub Actions**: Use `gh` CLI to check CI build status and fix failures
3. **Pre-commit**: Always run `pre-commit run --all-files` after implementation and fix any errors
4. **Command approval**: If a command is approved once, it's approved for all future uses

**Workflow after implementation:**
1. Run `pre-commit run --all-files`
2. Fix any linting/formatting errors
3. Run pre-commit again until it passes
4. `git add -A && git commit -m "..."`
5. User will do `git push`

## Language

- Product requirements document (instructions.md) is in Polish
- Code, comments, and documentation should be in English
