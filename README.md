# HousePulse (FamilyTodo)

iOS app do współdzielenia obowiązków domowych: Shopping, Tasks, Ideas i Household management.

## Stack
- iOS 17+ (iOS 26+ dla części efektów systemowych)
- SwiftUI (`TabView` shell)
- SwiftData (cache/offline-first)
- CloudKit (sync + household sharing przez `CKShare`)
- Sign in with Apple + Guest mode
- GitHub Actions (build, lint, schema gate, TestFlight deploy)

## Current app modules
- Shopping: rapid entry, buy/unbuy, Recently Purchased, restock flow.
- Tasks: active/completed, assignment, transitions z Ideas.
- Ideas (Backlog): categories, assign, promote do task.
- More: profile/household, member management, settings.

## CloudKit/TestFlight notes
- App target domyślnie działa z `HPCloudKitEnabled=YES`.
- CI schema gate:
- waliduje kontrakt schemy (`cloudkit/schema/housepulse-schema.json`),
- aplikuje Development,
- weryfikuje Production, w tym systemowy `cloudkit.share`.
- TestFlight deploy jest blokowany, jeśli schema gate nie przejdzie.
- Jednorazowy bootstrap `cloudkit.share` bez Xcode wymaga CloudKit Console:
- Development Private DB -> `Act As iCloud Account` -> custom zone -> save `Household` -> `Share Record` -> `Deploy Schema Changes` Dev -> Prod.

## Documentation
- [`AGENTS.md`](AGENTS.md) - decyzje produktowe/techniczne i runbook sesji.
- [`STATUS.md`](STATUS.md) - aktualny stan wdrożenia.
- [`TODO.md`](TODO.md) - aktywne i domknięte zadania.
- [`docs/current/CLOUD_SYNC_PROFILES.md`](docs/current/CLOUD_SYNC_PROFILES.md) - profile sync i schema gate.
- [`docs/current/TESTING_CI_POLICY.md`](docs/current/TESTING_CI_POLICY.md) - polityka CI/testów.
- [`docs/current/ROADMAP.md`](docs/current/ROADMAP.md) - roadmap.

## CI quick checks
```bash
gh run list --limit 5
gh run view <run_id> --json status,conclusion,jobs
gh run view <run_id> --log-failed
```
