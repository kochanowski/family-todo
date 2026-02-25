# CLOUD_SYNC_PROFILES

Last updated: 2026-02-25

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
