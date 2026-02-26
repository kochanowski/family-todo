# CLOUD_SYNC_PROFILES

Last updated: 2026-02-26

## Profiles

### 1. `sync-enabled` (app default)
- `HPCloudKitEnabled = YES`
- Purpose: production-like behavior for Apple login, CloudKit households, sharing/invites.
- App target now defaults to this profile.

### 2. `preview-local` (override profile)
- `HPCloudKitEnabled = NO`
- Purpose: fast UI iteration without CloudKit side effects.
- Use explicitly in CI/manual runs.

## How to switch
- In CI/manual build commands, override Info.plist key via build setting:
  - `INFOPLIST_KEY_HPCloudKitEnabled=YES` for sync-enabled,
  - `INFOPLIST_KEY_HPCloudKitEnabled=NO` for preview-local.

## Recommendation
- Keep day-to-day UI checks that touch auth/share on `sync-enabled`.
- Use `preview-local` only for isolated visual or non-sync development.

## CloudKit Schema CI Gate
- TestFlight deploy flow now runs a reusable schema workflow first:
  - `.github/workflows/cloudkit-schema.yml`
  - validates `cloudkit/schema/housepulse-schema.json`
  - applies schema to CloudKit Development
  - verifies Production schema has required record types
- If production schema is missing required record types, workflow fails with manual action:
  - CloudKit Console (Production) -> `Deploy Schema Changes...`
- Required secret for schema operations:
  - `CLOUDKIT_MANAGEMENT_TOKEN` (CloudKit management token)
- Existing `TEAM_ID` secret is reused.
- `CONTAINER_ID` is fixed to `iCloud.com.kochanowski.housepulse`.

## Manual Trigger
- You can run schema gate manually via `workflow_dispatch`:
  - `promote_to_production=true|false`
  - `dry_run=true|false`
  - `schema_source=cloudkit/schema/housepulse-schema.json`
