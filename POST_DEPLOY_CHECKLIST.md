# POST_DEPLOY_CHECKLIST

## Zasada
Po każdym wdrożeniu dostajesz ode mnie sekcję:
- `Co musisz zrobić ręcznie`

Ten plik jest źródłem prawdy dla kroków po deployu i będzie aktualizowany przy kolejnych zmianach.

## Kolejność działań (standard)
1. Push kodu na branch.
2. CI/GHA (build + schema gate) musi przejść.
3. Jeśli schema gate wymaga manuala: CloudKit Console (schema/security roles).
4. TestFlight build.
5. Smoke test manualny na urządzeniu.

## CloudKit (ogólnie)
1. Upewnij się, że schema jest wdrożona Development -> Production.
2. Sprawdź Record Types/Indexes wymagane przez nowe feature.
3. Sprawdź Security Roles (szczególnie Public DB dla flow invite/redeem).

## Co musisz zrobić ręcznie po ostatnim wdrożeniu (Invite Code fallback)
1. CloudKit Console -> Public Database -> Record Types:
- potwierdź, że istnieje `InviteToken` z polami:
  - `code`, `householdId`, `shareURL`, `createdAt`, `expiresAt`, `isRevoked`, `usesCount`, `lastRedeemedAt`
2. CloudKit Console -> Public Database -> Security Roles dla `InviteToken`:
- `_world`: `read`
- `_icloud`: `create`
- `_creator`: `read/write/delete`
3. Deploy schema changes Development -> Production (jeśli nie zrobił tego workflow).
4. TestFlight smoke:
- owner widzi 6-znakowy kod invite,
- invitee może dołączyć po wpisaniu kodu,
- link/QR nadal działają.

## Notatka
`cloudkit.share` to typ systemowy CloudKit. Nie dodajemy go ręcznie do `housepulse-schema.json`.
