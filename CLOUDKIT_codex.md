# Plan Utwardzenia CloudKit i Sync (FamilyTodo)

## Summary
Celem jest doprowadzenie warstwy sieciowej i synchronizacji do stanu produkcyjnego: pelna poprawnos zapisu/odczytu CloudKit, spojny offline-first z retry, bezpieczny sharing/invite i stabilny push update.
Wybrany zakres: **Critical+High**, strategia konfliktow: **LWW + retry**, bezpieczenstwo invite: **harden codes**.

## Kluczowe ustalenia z analizy kodu
1. Brak paginacji CloudKit query (ignorowany cursor), co grozi utrata czesci danych przy wiekszych listach.
   Evidence: `FamilyTodo/Managers/CloudKitManager.swift` (`queryRecords`, `createInviteCode` query).
2. `pendingUpload`/`pendingDelete` nie maja realnego mechanizmu replay, wiec mutacje moga utknac na stale.
   Evidence: `TaskStore.loadTasks`, `ShoppingListStore.loadItems`, `BacklogStore.loadData`.
3. Globalny mutable `householdScope` w `CloudKitManager` jest ryzykowny przy wspolbieznych flow.
4. Cache dostepnosci CloudKit moze sie zakleszczyc (brak realnego reset/invalidation flow).
5. Push pipeline nie jest domkniety end-to-end (AppDelegate nie obsluguje remote notification callbackow dla subskrypcji).
6. InviteToken w Public DB ma `_world read`, a token zawiera `shareURL`; to zwieksza powierzchnie naduzyc.
7. W wielu miejscach sa `try? modelContext.save()`, czyli utrata bledow zapisu lokalnego.
8. Niespojnosc cache semantics: np. shopping `loadFromCache` nie filtruje `pendingDelete`.

## Zmiany API/interfejsow (publiczne i techniczne)
1. Dodac jawny kontekst scope do operacji CloudKit, zamiast polegania na globalnym stanie.
   Nowy typ: `CloudScopeContext { scope, householdId }`.
2. Dodac paginowane helpery query w `CloudKitManager`.
   Nowe API: `queryAllRecords(...)` i `queryAllRecords(inZoneWith:...)`.
3. Dodac replay outbox.
   Nowy model SwiftData: `CachedSyncMutation` (`id`, `entityType`, `entityId`, `operation`, `payload`, `attemptCount`, `nextAttemptAt`, `createdAt`).
4. Dodac bezpieczny zapis lokalny.
   Wspolny helper: `saveContextOrSetError(...)` dla wszystkich store.
5. Dodac callbacki push do `AppDelegateBridge` i forwarding do `CloudKitSubscriptionManager`.
6. Invite hardening: schema role update (`InviteToken` bez `_world read`), code length 8, `maxUses` + retry przy `serverRecordChanged`.

## Plan implementacji (decision-complete)
1. **Etap 0: Artifact i baseline**
   Utworzyc dokument planu w pliku `CLOUDKIT_codex.md` z ta specyfikacja i checklista rollout.

2. **Etap 1: Paginacja CloudKit (Critical)**
   Zaimplementowac paginowane query helpery i podmienic wszystkie miejsca `records(matching:)` ignorujace cursor.
   Dotyczy glownie:
   - `CloudKitManager.queryRecords(...)`
   - query `InviteToken` w `createInviteCode`.

3. **Etap 2: Replay outbox + retry/backoff (Critical)**
   Wprowadzic `CachedSyncMutation` + `SyncOutboxActor`; kazdy create/update/delete dodaje mutacje, `load*()` uruchamia `flushPendingMutations()`.
   Dotyczy store'ow:
   - `TaskStore`
   - `ShoppingListStore`
   - `BacklogStore`
   - `MemberStore`

4. **Etap 3: Scope safety (Critical)**
   Wyeliminowac zaleznosc od globalnego `householdScope` w sciezkach CRUD/query; scope przekazywany jawnie z aktywnego household/session.
   Zachowac kompatybilny wrapper tymczasowy i oznaczyc stary mechanizm jako deprecated.

5. **Etap 4: Push E2E + availability hardening (High)**
   Dodac AppDelegate callbacki dla remote notification i token registration; forwarding do managera subskrypcji.
   Dodac invalidacje cache dostepnosci CloudKit (TTL + reset na zmiane konta).

6. **Etap 5: Invite hardening (High)**
   Zmienic schema role dla `InviteToken`: brak `_world read`, tylko `_icloud` i `_creator`.
   Podniesc entropy kodu do 8 znakow, dodac `maxUses`, retry-safe increment uzycia.
   Utrzymac UX: link + QR + krotki kod.

7. **Etap 6: Spojnosc cache i bledy lokalne (High)**
   Zastapic `try? modelContext.save()` helperem z telemetry/error propagation.
   Naprawic shopping cache filter dla `pendingDelete`.
   Dodac cache reconciliation dla usunietych members.

8. **Etap 7: Regression safety i CI**
   Rozszerzyc testy i schema gate o nowe kontrakty.
   Zaktualizowac `scripts/cloudkit/validate_schema.sh` pod nowe role `InviteToken`.

## Test cases i scenariusze akceptacyjne
1. Query >100 rekordow zwraca pelny zbior dla Task/Shopping/Backlog (owner + participant).
2. Offline create/update/delete przechodza do outbox, po reconnect sa wysylane i oznaczane jako `synced`.
3. `pendingDelete` nigdy nie wraca do UI po restarcie offline.
4. Konflikt `serverRecordChanged` rozwiazuje sie LWW + retry bez duplikacji.
5. Rownolegle flow (np. createShare + loadTasks) nie mieszaja scope baz.
6. Push z CloudKit powoduje odswiezenie/bannery po stronie app (foreground/background).
7. Invite code dziala po hardeningu; `_world` nie ma odczytu `InviteToken`.
8. create/join household, QR, deep-link deferred acceptance dzialaja jak dotad.
9. Delete household nie zostawia orphan records/cache.
10. Wszystkie store'y raportuja blad save local (brak silent fail).

## Zalozenia i domyslne decyzje
1. Pozostaje model **1 aktywny household per session**.
2. iCloud login pozostaje wymagany do dolaczenia przez invite.
3. Strategia konfliktow: **LWW + retry**, bez manualnego conflict UI.
4. Zakres tej iteracji: **Critical + High**, bez pelnego refactoru architektury na osobny backend.
5. Plan jest gotowy do implementacji bez dodatkowych decyzji produktowych.
