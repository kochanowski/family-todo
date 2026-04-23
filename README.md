# HousePulse

HousePulse is a shared-first iOS household organizer built in the `FamilyTodo` Xcode project.
The product focuses on shared shopping, assigned tasks, backlog planning, and low-friction
household coordination without pressure mechanics.

## Source of Truth

Start here when you open the repo:

- [`AGENTS.md`](AGENTS.md): product rules, architecture constraints, and repo workflow rules
- [`STATUS.md`](STATUS.md): current implementation state and known issues
- [`TODO.md`](TODO.md): active roadmap and priority order
- [`TODO_DETAILS.md`](TODO_DETAILS.md): implementation notes and likely touch points
- [`docs/README.md`](docs/README.md): reference docs, setup guides, ADRs, and archive index
- [`CONTRIBUTING.md`](CONTRIBUTING.md): local commands, checks, scripts, and contribution workflow

## Stack

- iOS 17+
- SwiftUI with a custom floating tab bar shell
- SwiftData for local cache and offline-first UI responsiveness
- CloudKit for sync and household sharing
- Sign in with Apple plus Guest mode
- GitHub Actions for CI, schema gate, and TestFlight delivery

## App Areas

- Shopping
- Tasks
- Backlog
- More

## Quick Local Checks

```bash
pre-commit run --all-files
```

Optional CI inspection:

```bash
gh run list --limit 5
gh run view <run_id> --json status,conclusion,jobs
gh run view <run_id> --log-failed
```

## Repo Layout

- `FamilyTodo/`: app code
- `FamilyTodoTests/`: unit and integration-style tests
- `FamilyTodoUITests/`: UI tests
- `docs/active/`: active product, engineering, and release docs
- `docs/setup/`: setup and environment guides
- `docs/adr/`: architectural decision records
- `docs/archive/`: historical notes, legacy docs, and migrated material
- `scripts/`: CI, CloudKit, and legacy Xcode helper scripts
