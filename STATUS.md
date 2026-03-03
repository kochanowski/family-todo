# STATUS

Last updated: 2026-02-27

## Current state

### App flow and UX
- Native 4-tab shell działa stabilnie: Shopping, Tasks, Ideas, More.
- Onboarding/Auth/Household routing jest spięty pod launch state.
- Guest fallback działa równolegle do cloud-first (Sign in with Apple).

### CloudKit / sharing
- Invite flow jest domknięty: link + QR + paste + deferred deep link.
- `createShare`/`acceptShare` mają stage-level diagnostics.
- Scope handling (owner/participant) i zone context zostały utwardzone.

### Regression recovery (this session)
- Naprawiono ścieżkę schema gate pod systemowy typ `cloudkit.share`.
- CI skrypty schema są odporne na managed record types.
- Pipeline zakończony green: schema gate + deploy TestFlight.

## Completed in the latest series
- Hardened CKShare create/accept flow.
- Dodany i dopracowany diagnostyczny flow błędów CloudKit.
- CloudKit schema gate:
- Development apply + Production verify,
- jawny check `cloudkit.share`,
- czytelne logi przy brakach Dev/Prod.
- Branch policy CI/TestFlight rozszerzona o branch testowy.

## Known operational constraint
- Bez Xcode pierwszy bootstrap `cloudkit.share` wymaga ręcznej akcji w CloudKit Console:
- Development -> Private DB -> Act As -> custom zone -> save `Household` -> Share Record,
- następnie Stop Acting As i Deploy Schema Changes Dev -> Prod.
- Po tym bootstrapie dalsza walidacja i blokada release są pilnowane przez GHA.

## Current CI policy snapshot
- PR/push lane: build + SwiftLint.
- Release/testing lane: build + SwiftLint + CloudKit schema gate + TestFlight deploy.
- Przy failu schema gate deploy do TestFlight jest blokowany.
