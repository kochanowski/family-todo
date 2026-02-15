# HousePulse (Family Todo)

iOS household app for shared shopping, tasks, and backlog management. Built with SwiftUI + CloudKit + SwiftData.

## What it does

A shared household hub where family members manage daily tasks, shopping lists, and long-term backlog — with offline-first sync, gentle nudges (not nagging), and a WIP limit of 3 tasks per person.

**4 tabs:** Shopping 🛒 · Tasks ✓ · Backlog 📦 · More ⋯

## Tech stack

- **iOS 17+** (iOS 26+ for Liquid Glass effects)
- **SwiftUI** + custom floating tab bar
- **SwiftData** for offline-first cache
- **CloudKit** for sync + household sharing (CKShare)
- **Sign in with Apple** + guest mode
- **GitHub Actions** CI (build + lint)
- **Branch:** `rebuild/swiftui-clean-impl`

## Status (2026-02-15)

**✅ Working:** Shopping (rapid entry, buy/unbuy, restock), Tasks (CRUD, WIP limit, completion), Backlog (categories + items), Auth (Apple + guest), CloudKit sync, Notifications, Onboarding, 4 Themes, Member management, Household sharing.

**⚠️ Stubs:** Task detail/edit, recurring chores, areas/rooms, sign out, join household flow, notification settings, backlog→task promotion.

**See:** `claude-codex-TODO.md` for the full merged roadmap (Phases 0-9).

## Key documentation

| File | Purpose |
|------|---------|
| [`CLAUDE.md`](CLAUDE.md) | Agent guidance + full project context |
| [`claude-codex-TODO.md`](claude-codex-TODO.md) | **Merged implementation roadmap** (source of truth for next steps) |
| [`STATUS.md`](STATUS.md) | Current implementation status |
| [`docs/current/ROADMAP.md`](docs/current/ROADMAP.md) | Prioritized roadmap (Now / Next / Later) |
| [`docs/current/TESTING_CI_POLICY.md`](docs/current/TESTING_CI_POLICY.md) | CI and testing policy |
| [`docs/current/CLOUD_SYNC_PROFILES.md`](docs/current/CLOUD_SYNC_PROFILES.md) | Cloud sync profile switching |

## Architecture docs

| File | Purpose |
|------|---------|
| [`Product Specification: House Pulse.md`](<Product Specification: House Pulse.md>) | Product spec |
| [`Product Specification: First Launch.md`](<Product Specification: First Launch.md>) | First launch / onboarding spec |
| [`docs/2026-01-10_adr-001-cloudkit-backend.md`](docs/2026-01-10_adr-001-cloudkit-backend.md) | ADR: CloudKit as backend |
| [`docs/2026-01-12_adr-002-error-handling-offline-first.md`](docs/2026-01-12_adr-002-error-handling-offline-first.md) | ADR: Error handling + offline-first |
| [`docs/2026-01-11_cloudkit-schema.md`](docs/2026-01-11_cloudkit-schema.md) | CloudKit record types schema |

## CI

- **PR/push:** build + SwiftLint (`.github/workflows/ios-ci.yml`)
- **Nightly/manual:** full regression tests (`.github/workflows/nightly.yml`)
- Cloud sync tests require `HPCloudKitEnabled=YES` profile — see [`CLOUD_SYNC_PROFILES.md`](docs/current/CLOUD_SYNC_PROFILES.md)

## Development

Dev on Linux → GitHub Actions for build/test → iPhone 15 (iOS 26.2.1) for physical testing.

```bash
# Pre-commit checks
pre-commit run --all-files

# Check CI
gh run list --limit 5
```
