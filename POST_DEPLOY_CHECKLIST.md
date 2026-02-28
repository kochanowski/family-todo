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
- `_icloud`: `read/create`
- `_creator`: `read/write` (w nowym UI CloudKit często nie ma osobnego toggle `delete`).
3. Deploy schema changes Development -> Production (jeśli nie zrobił tego workflow).
4. TestFlight smoke:
- owner widzi 6-znakowy kod invite,
- invitee może dołączyć po wpisaniu kodu,
- link/QR nadal działają.

## Co musisz zrobić ręcznie po tym wdrożeniu (Category colors + Tasks reactivity + invite title cleanup)
1. Uruchom workflow `cloudkit-schema` (Development) i potwierdź, że przechodzi walidacja dla:
- `Member.colorHex`
- `BacklogCategory.colorHex`
2. CloudKit Console -> `Deploy Schema Changes...`:
- wypchnij zmiany Development -> Production (pole `BacklogCategory.colorHex`).
3. Nowy build TestFlight dopiero po kroku 2.
4. Smoke test:
- Ideas: tworzenie i edycja kategorii pozwala wybrać kolor, a kolor widać też w Tasks,
- Household Settings: edycja household po nazwie działa bez błędu `record to insert already exists`,
- Invite Member: UI nie pokazuje suffixu `(właściciel)` w tytule udostępniania.

## Notatka
`cloudkit.share` to typ systemowy CloudKit. Nie dodajemy go ręcznie do `housepulse-schema.json`.

## Guardrail CI (ważne)
Od teraz skrypty `scripts/cloudkit/apply_schema.sh` i `scripts/cloudkit/promote_schema.sh`
najpierw eksportują schemę z docelowego środowiska i dołączają istniejące bloki
`SECURITY ROLE` do ckdb przed `import-schema`.
To zapobiega przypadkowemu usuwaniu uprawnień (np. `InviteToken` w `_world/_icloud/_creator`)
przy kolejnych migracjach.
