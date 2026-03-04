# HousePulse CloudKit Sharing: Bulletproof Architecture Plan

## Summary
After reviewing your current implementation in [CloudKitManager.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Managers/CloudKitManager.swift), [HouseholdStore.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Stores/HouseholdStore.swift), [ShareAcceptanceCoordinator.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Services/ShareAcceptanceCoordinator.swift), [AppDelegateBridge.swift](/home/wkochanowski/code/family-todo/FamilyTodo/Services/AppDelegateBridge.swift), and [FamilyTodoApp.swift](/home/wkochanowski/code/family-todo/FamilyTodo/FamilyTodoApp.swift), the core architecture is close, but one root flaw is still likely causing false `shareNotCreated`: `CKModifyRecordsOperation` per-record failures are not treated as hard failures in share creation.
That can produce exactly your TestFlight symptom: `operation=createShare` + `shareNotCreated` without the real CKError.

---

## 1. CKShare & Zone Creation Sequence (mandatory, deterministic)

### Required order (owner-side)
1. Set scope to owner private DB.
2. Ensure custom zone exists on server (`modifyRecordZones`) before any root/share write.
3. Ensure household root record exists in that exact custom zone.
4. Fetch root record from exact `CKRecord.ID(recordName: householdId, zoneID: ownerZoneID)`.
5. If root already has a share reference, fetch and return existing `CKShare` (idempotent path).
6. If not shared, create `CKShare(rootRecord: rootRecord)`.
7. Save `rootRecord` and `share` in one `CKModifyRecordsOperation`.
8. Only after a successful save, expose/share the URL.

### CKModifyRecordsOperation configuration
1. `recordsToSave = [rootRecord, share]`.
2. `savePolicy = .ifServerRecordUnchanged` for first try.
3. `isAtomic = true` (same zone, prevents partial success behavior).
4. `qualityOfService = .userInitiated`.
5. Capture and fail on any per-record failure, especially for the `CKShare` record.
6. Retry once on `serverRecordChanged` with refetch + recreate share.
7. Keep fallback poll for eventual consistency, but only after confirming there was no per-record failure.

### Common “Failed to create share” causes
1. Root record is in default zone, not custom zone.
2. Zone not created/saved before record/share write.
3. Share attempted in wrong DB scope (not owner private).
4. Missing CloudKit Sharing entitlement/capability.
5. Production schema mismatch (record types not deployed).
6. `serverRecordChanged` not retried correctly.
7. Partial failure hidden because per-record errors are ignored.

---

## 2. QR Code & Invite Link Structure

### Recommended payload format
1. QR should encode native `CKShare.url.absoluteString` directly.
2. Manual input should accept raw iCloud share URL.
3. Custom deep link is optional compatibility layer only.

### If using custom deep link
1. Use wrapper only as transport, for example `housepulse://join?u=<percent-encoded-ckshare-url>`.
2. Decode and validate to a real iCloud share URL before any CloudKit calls.
3. Never serialize or pass `CKShare.Metadata` in URL payload.
4. Never uppercase or transform invite token.

### Why this is safest
1. Native `CKShare.URL` is the canonical share token CloudKit expects.
2. Metadata is short-lived/runtime-resolved and should come from `CKContainer.shareMetadata(for:)`.
3. Wrapper links increase parsing risk and should stay secondary.

---

## 3. Intercepting and Accepting Invitations (programmatic, custom onboarding-safe)

### Invite acceptance mechanism
1. For invitees, use `CKAcceptSharesOperation` (not `UICloudSharingController`).
2. `UICloudSharingController` should remain owner-side for managing/sending shares.
3. On universal-link accept, rely on `application(_:userDidAcceptCloudKitShareWith:)` as primary source of metadata.
4. For pasted/scanned URL, fetch metadata via `CKContainer.shareMetadata(for:)`, then accept with `CKAcceptSharesOperation`.

### Deferred Deep Link pattern (must-have)
1. If app state is onboarding/auth/set-name, store pending invite (metadata preferred, URL fallback).
2. Do not attempt join while user is guest/signed-out or display name is not confirmed.
3. After auth + display name complete, process pending invite exactly once.
4. Persist pending invite across cold start in `UserDefaults` to avoid losing invite.
5. Clear pending invite only after successful acceptance + household resolution.

### Post-accept sequence
1. Set scope to participant shared DB.
2. Persist shared zone context from `metadata.rootRecordID.zoneID`.
3. Fetch root household record from shared DB using metadata root ID.
4. Upsert membership for current user.
5. Set current household and route to main app.

---

## Important API / Interface / Type changes
1. `CloudKitManager.createShare` must return real CKError stage when per-record share save fails, not generic `shareNotCreated`.
2. Add explicit internal result model for share-save stage: operation error vs per-record error vs eventual-consistency timeout.
3. Add persistent pending invite storage in `ShareAcceptanceCoordinator` (`pendingMetadataURLString`, timestamp, source).
4. Keep `UICloudSharingController` for owner invitation UI, but make `CKAcceptSharesOperation` the only invitee acceptance engine.

---

## Test cases and acceptance scenarios

### Unit/integration
1. Share create success when zone exists and root is in custom zone.
2. Share create fails with surfaced per-record CKError when share record fails.
3. Existing share path returns existing share without recreating.
4. Deferred invite does not process in onboarding/auth/set-name states.
5. Deferred invite processes after sign-in + display name confirmation.
6. Pending invite survives app relaunch.

### Manual TestFlight
1. New household owner: create share, get URL, QR opens and joins.
2. Legacy household migrated from default zone: share works after migration.
3. Invite by tap link from outside app: auto-join after auth flow.
4. Invite by paste/scanned QR inside app: join succeeds without system share UI.
5. Guest receives invite: no early error; invite executes after Apple sign-in.
6. Any failure shows exact stage + CKError domain/code (not only `shareNotCreated`).

---

## Assumptions and defaults
1. One active household per session remains product rule.
2. Canonical owner zone naming remains `HouseholdZone-<householdUUID>`.
3. Native `CKShare.URL` is the canonical invite token.
4. Production/TestFlight is the target environment, so schema/capabilities must already be deployed.
5. `shareNotCreated` should only be used after exhausting deterministic checks and polling, never when a concrete CKError exists.
