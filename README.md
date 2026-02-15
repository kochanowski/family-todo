# Family Todo

iOS household app for shared shopping, tasks, and backlog workflows.

## Current source of truth
- Product principles: `CLAUDE.md`
- Implementation status: `STATUS.md`
- Active roadmap: `docs/current/ROADMAP.md`
- CI/test policy: `docs/current/TESTING_CI_POLICY.md`
- Cloud sync profiles: `docs/current/CLOUD_SYNC_PROFILES.md`
- Doc migration map: `docs/current/DOCS_MIGRATION_INDEX.md`

## Core technical specs still active
- `Product Specification: House Pulse.md`
- `Product Specification: First Launch.md`
- `docs/2026-01-10_adr-001-cloudkit-backend.md`
- `docs/2026-01-12_adr-002-error-handling-offline-first.md`
- `docs/2026-01-11_cloudkit-schema.md`

## CI overview
- PR/push: build + SwiftLint (`.github/workflows/ios-ci.yml`)
- Nightly/manual regression tests: `.github/workflows/nightly.yml`
