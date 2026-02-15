# CLOUD_SYNC_PROFILES

Last updated: 2026-02-15

## Profiles

### 1. `preview-local` (default)
- `HPCloudKitEnabled = NO`
- Purpose: fast UI iteration on phone/simulator without CloudKit side effects.
- This is the default behavior in project build settings.

### 2. `sync-enabled`
- `HPCloudKitEnabled = YES`
- Purpose: verify CloudKit login/share/sync behavior.
- Use in manual CI runs or dedicated sync checks.

## How to switch
- In CI/manual build commands, override Info.plist key via build setting:
  - `INFOPLIST_KEY_HPCloudKitEnabled=YES` for sync-enabled,
  - `INFOPLIST_KEY_HPCloudKitEnabled=NO` for preview-local.

## Recommendation
- Keep day-to-day UI tests on `preview-local`.
- Run `sync-enabled` before validating sharing flows or CloudKit regressions.
