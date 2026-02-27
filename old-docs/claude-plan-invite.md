# Plan: CloudKit Sharing Architecture Review & Fix

## Context

Sharing via QR codes i invite links nie dziala. Uzytkownik podejrzewa fundamentalny blad w architekturze CKShare. Po deep-dive w kod zidentyfikowalem **2 showstoppery**, **5 bugow** i **4 problemy architektoniczne**.

---

## Odpowiedzi na pytania architektoniczne

### Q1: CKShare & Zone Creation Sequence

**Wymagana kolejnosc operacji (mandatory):**
1. Stworz custom zone via `db.modifyRecordZones(saving:deleting:)` — MUSI byc na serwerze ZANIM cokolwiek sie w niej zapisze
2. Zapisz root record (Household) w tej zone
3. Stworz `CKShare(rootRecord:)` z root recordem ktory juz jest w custom zone
4. Zapisz root record + CKShare **atomowo** w jednym `CKModifyRecordsOperation` z `savePolicy = .ifServerRecordUnchanged`

**Aktualny kod** (`CloudKitManager.swift:1283-1355`) robi to w 5 etapach: ensureZone → migrate → fetchRoot → modifyRecords → fallbackPoll. Kolejnosc jest poprawna.

**Typowe przyczyny "Failed to create share":**
- Root record nie w target zone (stale migration)
- Stale changeTag (serverRecordChanged)
- Share juz istnieje dla tego root record
- Zone nie istnieje na serwerze

### Q2: QR Code & Link Generation

**QR powinien kodowac surowy `CKShare.url` bezposrednio** (np. `https://www.icloud.com/share/0aBcDeFg`). Obecny kod to robi poprawnie w `InviteQRCodeView`. NIE opakowywac w custom scheme (`housepulse://`) — traci sie native system routing.

Custom scheme (`housepulse://join/...`) moze byc dodatkowym mechanizmem, ale nie glownym.

### Q3: Accepting the Share

- **`UICloudSharingController`**: Do TWORZENIA i ZARZADZANIA share (strona ownera). NIE do akceptowania.
- **`CKAcceptSharesOperation`**: Do AKCEPTOWANIA share (strona joiner'a). Programmatic path.
- **System callback** (`userDidAcceptCloudKitShareWith`): Najlepsza sciezka — iOS dostarcza gotowe `CKShare.Metadata`. Wymaga `CKSharingSupported = YES` w Info.plist.

**Pros/cons:**

| Metoda | Pros | Cons |
|--------|------|------|
| `UICloudSharingController` | Native UI, handles all edge cases, manages participants | Owner-side only, can't customize UI |
| `CKAcceptSharesOperation` | Full control, programmatic, custom UI | Must handle metadata fetching, retry, scope switching |
| System callback (`userDidAcceptCloudKitShareWith`) | Best UX — metadata delivered ready-made by iOS | Requires `CKSharingSupported = YES` in Info.plist |

**Deferred acceptance for guests:** Obecny `ShareAcceptanceCoordinator` juz poprawnie buforuje zaproszenia i czeka na autentykacje. Pattern jest solidny — kolejkuje metadata/invite code i procesuje gdy: mainApp state + authenticated + cloud mode + displayName confirmed.

---

## Zidentyfikowane bugi (priorytet)

### P0 — SHOWSTOPPER 1: `publicPermission = .none` bez participant management

**Plik**: `CloudKitManager.swift:1242`
```swift
share.publicPermission = .none  // ← BLAD
```

Share jest prywatny — tylko jawnie zaproszeni uczestnicy moga go zaakceptowac. Ale app **NIGDZIE** nie uzywa `CKShare.Participant` API (`addParticipant`, `fetchParticipant`). Czyli: share tworzony, URL generowany, ale **nikt nie moze go zaakceptowac** bo nikt nie jest zaproszony jako participant.

Zweryfikowano grepem: zero wynikow dla `CKShare.Participant`, `addParticipant`, `fetchParticipant` w calym codebase.

**Fix**: Zmienic na `.readWrite` — kazdy z URL moze dolaczyc (jak Apple Notes, Shortcuts, shared iCloud folders).

**Ryzyko**: Kazdy kto uzyska URL moze dolaczyc. Akceptowalne dla family app — URL jest wspoldzielony celowo (QR, wiadomosc, AirDrop).

### P0 — SHOWSTOPPER 2: Brak `CKSharingSupported = YES` w Info.plist

**Plik**: `FamilyTodo.xcodeproj/project.pbxproj`

Grep potwierdza: **zero wynikow** dla `CKSharingSupported` w project.pbxproj i w calym projekcie (poza docs). Bez tego:
- iOS **NIE** routuje `https://www.icloud.com/share/...` do `userDidAcceptCloudKitShareWith`
- `AppDelegateBridge.swift` jest **dead code** — callback nigdy nie jest wywolywany
- Share linki otwieraja Safari/iCloud web page zamiast aplikacji
- Joiner musi reczne kopiowac/wklejac URL zamiast tapnac i dolaczyc

**Fix**: Dodac `INFOPLIST_KEY_CKSharingSupported = YES` w build settings (Debug + Release).

### P1 — Bug 3: `perShareResultBlock` zamiast `acceptSharesResultBlock`

**Plik**: `CloudKitManager.swift:1384`

`perShareResultBlock` odpala sie PER SHARE **przed** zakonczeniem calej operacji `CKAcceptSharesOperation`. Continuation jest wznawiana zanim operacja sie zakonczy, co moze powodowac race condition z natychmiastowym fetch na liniach 1399-1400.

**Fix**: Uzyc `acceptSharesResultBlock` dla overall completion. Alternatywnie — uzyc nowego async/await API jesli target iOS 16+.

### P1 — Bug 4: Brak retry po acceptance fetch

**Plik**: `CloudKitManager.swift:1399-1400`
```swift
let record = try await db.record(for: metadata.rootRecordID)
```

Shared database ma **eventual consistency**. Natychmiastowy fetch po `CKAcceptSharesOperation` moze failowac z `.unknownItem` bo record jeszcze nie jest widoczny w shared DB.

**Fix**: Retry z exponential backoff (5 prob, 500ms → 4s). Failuje tylko jesli wszystkie 5 prob sie nie uda.

### P2 — Bug 5: `.onOpenURL` przechwytuje iCloud URLs przed system routing

**Plik**: `FamilyTodoApp.swift:134-140`

`.onOpenURL` lapie `icloud.com` URLs i procesuje je programmatycznie (invite code path → `container.shareMetadata(for:)` → `CKAcceptSharesOperation`). To pomija natywny system routing `userDidAcceptCloudKitShareWith` ktory dostarcza gotowe `CKShare.Metadata` — prostsze i bardziej niezawodne.

**Fix**: Po dodaniu `CKSharingSupported`, priorytetowo obslugiwac custom scheme. iCloud URLs traktowac jako fallback (na wypadek gdyby system routing nie zadzialal).

### P2 — Bug 6: Dual share-creation paths moga kolidowac

**Pliki**: `ShareInviteView.swift:28-38` + `HouseholdStore.fetchInviteURL()`

Dwie niezalezne sciezki tworzenia share:
- **Path A**: `UICloudSharingController` z preparation handler (linia 30-38) — tworzy share jesli nie istnieje
- **Path B**: `HouseholdStore.fetchInviteURL()` → `CloudKitManager.createShare()` — tworzy share programmatycznie

Jesli user triggeruje obie sciezki, moga race'owac i spowodowac `serverRecordChanged` lub duplikat.

**Fix**: `UICloudSharingController` **ZAWSZE** dostaje pre-existing share. Caller musi zapewnic ze share istnieje przed prezentacja `ShareInviteView`. Usunac preparation handler.

### P3 — Bug 7: `recordID(for:)` tworzy ID w default zone

**Plik**: `CloudKitManager+Mapping.swift:9-11`
```swift
func recordID(for id: UUID) -> CKRecord.ID {
    CKRecord.ID(recordName: id.uuidString)  // ← default zone
}
```

Wszystkie record ID tworzone w default zone. `saveRecordWithZoneRecovery` potem je koryguje, ale to fragile i wymaga dodatkowego round-trip.

**Fix**: Dodac zone-aware wariant `recordID(for:in:)`.

---

## Plan implementacji (krok po kroku)

### Krok 1: Fix P0 — publicPermission (1 linia)

**Plik**: `CloudKitManager.swift:1242`

Zmiana:
```swift
// BEFORE:
share.publicPermission = .none

// AFTER:
share.publicPermission = .readWrite
```

**UWAGA**: Istniejace share'y z `.none` nie beda automatycznie zaktualizowane. Jesli share juz istnieje, trzeba go usunac i stworzyc nowy. Alternatywnie — dodac migration step ktory aktualizuje `publicPermission` na istniejacych share'ach.

### Krok 2: Fix P0 — CKSharingSupported

**Plik**: `FamilyTodo.xcodeproj/project.pbxproj`

Dodac w obu blokach build settings (Debug + Release):
```
INFOPLIST_KEY_CKSharingSupported = YES;
```

Szukaj `buildSettings` bloków z `INFOPLIST_KEY_` entries i dodaj tam.

### Krok 3: Fix P1 — acceptShare completion + retry

**Plik**: `CloudKitManager.swift:1378-1407`

Zastapic `perShareResultBlock` na `acceptSharesResultBlock` i dodac retry loop:

```swift
func acceptShare(metadata: CKShare.Metadata) async throws -> Household {
    let ckContainer = await container
    let acceptOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
    acceptOperation.qualityOfService = .userInitiated

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        acceptOperation.acceptSharesResultBlock = { result in
            switch result {
            case .success:
                continuation.resume()
            case let .failure(error):
                continuation.resume(throwing: self.categorizeError(error))
            }
        }
        ckContainer.add(acceptOperation)
    }

    setHouseholdScope(.participantShared)
    if let householdId = UUID(uuidString: metadata.rootRecordID.recordName) {
        setSharedZoneContext(householdId: householdId, zoneID: metadata.rootRecordID.zoneID)
    }
    let db = await sharedDatabase

    // Retry with exponential backoff — shared DB has eventual consistency
    var fetchedRecord: CKRecord?
    for attempt in 0..<5 {
        do {
            fetchedRecord = try await db.record(for: metadata.rootRecordID)
            break
        } catch let error as CKError where error.code == .unknownItem && attempt < 4 {
            let delayNs = UInt64(pow(2.0, Double(attempt))) * 500_000_000
            try await _Concurrency.Task.sleep(nanoseconds: delayNs)
        }
    }

    guard let record = fetchedRecord else {
        throw CloudKitManagerError.unknownError(CKError(.unknownItem))
    }

    if let householdId = UUID(uuidString: metadata.rootRecordID.recordName) {
        rememberRecordZone(record, explicitHouseholdId: householdId)
    } else {
        rememberRecordZone(record, explicitHouseholdId: nil)
    }
    return try household(from: record)
}
```

### Krok 4: Fix P2 — .onOpenURL routing

**Plik**: `FamilyTodoApp.swift:134-150`

Zmienic kolejnosc: custom scheme first, iCloud URLs jako fallback:
```swift
.onOpenURL { url in
    // 1. Custom deep links (housepulse://join/...)
    if url.scheme?.lowercased() == "housepulse" {
        do {
            let normalized = try InviteInputNormalizer.normalizeInput(url.absoluteString)
            shareAcceptanceCoordinator.enqueue(rawInviteCode: normalized.inviteCode)
        } catch {
            shareAcceptanceCoordinator.lastErrorMessage = "Invalid invite link format."
        }
        return
    }

    // 2. Fallback: iCloud URLs that weren't caught by CKSharingSupported routing
    if let host = url.host?.lowercased(), host.contains("icloud.com") {
        shareAcceptanceCoordinator.enqueue(inviteURL: url)
    }
}
```

### Krok 5: Fix P2 — Unify share creation

**Plik**: `ShareInviteView.swift`

Usunac preparation handler (linie 28-38). `UICloudSharingController` ZAWSZE dostaje gotowy share:

```swift
func makeUIViewController(context: Context) -> UICloudSharingController {
    guard let share = householdStore.share,
          let container = householdStore.activeContainer
    else {
        // Caller must ensure share exists before presenting
        preconditionFailure("ShareInviteView presented without an active share. Call createShare() first.")
    }
    let controller = UICloudSharingController(share: share, container: container)
    controller.delegate = context.coordinator
    controller.availablePermissions = [.allowReadWrite, .allowPrivate]
    return controller
}
```

Caller (np. MemberManagementView) musi najpierw stworzyc share:
```swift
Button {
    Task {
        do {
            _ = try await householdStore.createShare()
            showShareInvite = true
        } catch {
            // handle error
        }
    }
} label: {
    Label("Invite Member", systemImage: "person.badge.plus")
}
```

### Krok 6: Fix P3 — zone-aware recordID

**Plik**: `CloudKitManager+Mapping.swift`

Dodac overload:
```swift
func recordID(for id: UUID, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
}
```

---

## Pliki do modyfikacji

| Plik | Zmiana | Priorytet | Effort |
|------|--------|-----------|--------|
| `CloudKitManager.swift:1242` | `publicPermission = .readWrite` | P0 | 1 line |
| `project.pbxproj` (2 bloki) | `INFOPLIST_KEY_CKSharingSupported = YES` | P0 | 2 lines |
| `CloudKitManager.swift:1378-1407` | `acceptSharesResultBlock` + retry fetch | P1 | ~30 lines |
| `FamilyTodoApp.swift:134-150` | Reorder .onOpenURL (custom scheme first) | P2 | ~10 lines |
| `ShareInviteView.swift:28-38` | Remove preparation handler | P2 | ~15 lines |
| `CloudKitManager+Mapping.swift:9-11` | Add zone-aware `recordID(for:in:)` | P3 | 5 lines |

## Weryfikacja

### Manual testing (2 urzadzenia, 2 rozne Apple ID):
1. **Owner tworzy share**: Members → Invite → UICloudSharingController → wyslij link via iMessage
2. **Joiner tapuje link (native)**: iOS otwiera app → `userDidAcceptCloudKitShareWith` fires → household loaded
3. **QR scan**: Owner pokazuje QR → Joiner skanuje → `acceptShare(inviteCode:)` → household loaded
4. **Paste**: Joiner wkleja URL → Join → household loaded
5. **Deferred**: Joiner niezalogowany → tapuje link → loguje sie → share automatycznie accepted
6. **Error recovery**: Airplane mode → accept fails → wlacz siec → retry succeeds

### CI: `pre-commit run --all-files` + GitHub Actions build

### Edge cases do przetestowania:
- Owner tworzy share, joiner akceptuje na innym urzadzeniu (iPhone vs iPad)
- Owner tworzy share, zamyka app, joiner akceptuje — czy share jest trwaly?
- Dwa joiners akceptuja ten sam share — czy obaj widza household?
- Guest mode joiner tapuje link — czy deferred acceptance dziala po Sign In?
- Istniejacy share z `.none` permission — czy wymaga recreation?
