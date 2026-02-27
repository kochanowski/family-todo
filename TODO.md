# TODO

Last updated: 2026-02-27

## Completed recently
- CloudKit diagnostics UI dla błędów auth/share (debug banner + copy/clear).
- Hardened invite flow:
- create share w custom zone ownera,
- accept share z retry/backoff,
- deferred invite przez `ShareAcceptanceCoordinator`.
- Schema gate rozszerzony o kontrolę systemowego `cloudkit.share`.
- Stabilizacja skryptów schema CI:
- obsługa managed types (`cloudkit.share`) w apply,
- normalizacja nazw typów z eksportu.
- Stabilizacja branch policy CI/TestFlight dla gałęzi testowych.

## Active now
1. Manual smoke na 2 Apple ID po ostatnim buildzie TestFlight:
- create household,
- invite (QR, link, paste),
- accept invite,
- cross-device sync CRUD.
2. Posprzątać bootstrap testowe dane CloudKit (opcjonalnie):
- household/zone utworzone tylko do bootstrapu `cloudkit.share`.
3. Potwierdzić brak regresji w household actions:
- rename,
- leave (owner/non-owner),
- delete household.

## Next priorities
1. Uzupełnić testy unit/UI dla invite acceptance i scope transitions.
2. Dokończyć hard enforcement WIP=3 we wszystkich ścieżkach (nie tylko guidance).
3. Domknąć remaining UX polish:
- sign-out overlap w niektórych konfiguracjach,
- drobne dopracowanie motywów retro/paper.

## Deferred / nice to have
1. Rozszerzyć observability o agregowane metryki invite-flow (lokalnie, bez PII).
2. Przygotować checklistę release readiness pod App Store Launch.
