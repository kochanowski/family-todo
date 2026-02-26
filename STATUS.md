# STATUS

Last updated: 2026-02-26

## Implemented (current redesign branch)

### Core shell and session flow
- 4-tab app shell: Shopping, Tasks, Backlog/Ideas, More
- Onboarding flow now transitions to `mainApp` after sync choice
- Cloud-first with Guest fallback:
  - iCloud path shows Sign in with Apple
  - Guest path starts local-only session
- Household setup gate enforced after session activation:
  - active session + no household => `CreateHouseholdView`
  - cloud session auto-bootstraps existing household membership before showing gate

### CloudKit / Sharing
- CloudKitManager has explicit household DB scope (`ownerPrivate` / `participantShared`)
- Household join supports:
  - invite link paste
  - deep-link acceptance (`userDidAcceptCloudKitShareWith` via app delegate bridge)
  - pending invite processing after login (`ShareAcceptanceCoordinator`)
- Household membership join path now uses member upsert (prevents duplicate member records)

### Invite UX
- Owner can invite via existing `UICloudSharingController`
- Owner can also show invite QR (`InviteQRCodeView`)
- Join sheet accepts full iCloud share link, supports clipboard paste, and QR scanning
- Invite normalization utility added (`InviteInputNormalizer`)

### Project configuration
- Added app entitlements (`FamilyTodo/HousePulse.entitlements`) for:
  - CloudKit
  - CloudKit sharing
  - Sign in with Apple
- App target defaults to `HPCloudKitEnabled = YES`
- Added camera usage description + remote notification background mode
- Added CloudKit schema CI workflow (`.github/workflows/cloudkit-schema.yml`):
  - reusable + manual dispatch
  - schema contract validation from `cloudkit/schema/housepulse-schema.json`
  - Development apply + automatic Production promote
  - `ios-ci.yml` blocks TestFlight deploy until schema gate succeeds

## Tests added
- `InviteInputNormalizerTests`
- `OnboardingStateTests`

## Known constraints / follow-up
- CloudKit sharing behavior still requires on-device validation with two Apple IDs.
- Full XCTest/UI test lanes in PR CI remain disabled by policy; use nightly/manual runs.
