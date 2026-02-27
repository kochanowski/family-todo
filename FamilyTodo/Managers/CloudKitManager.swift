import CloudKit
import Foundation

// swiftlint:disable type_body_length
actor CloudKitManager {
    static let shared = CloudKitManager()

    enum HouseholdDatabaseScope: Sendable {
        case ownerPrivate
        case participantShared
    }

    private struct SharedZoneContext {
        var zoneByHouseholdId: [UUID: CKRecordZone.ID] = [:]
        var zoneByRecordName: [String: CKRecordZone.ID] = [:]
        var lastResolvedSharedZones: [CKRecordZone.ID] = []
    }

    // CloudKit container identifier - matches the app's iCloud container
    #if CI
        private static let containerIdentifier = "iCloud.com.example.familytodo"
    #else
        private static let containerIdentifier = "iCloud.com.kochanowski.housepulse"
    #endif

    /// Container created on main thread during ensureReady().
    /// Using MainActor isolation for container to ensure it's created on main thread.
    @MainActor private static var _sharedContainer: CKContainer?

    private var isAvailable: Bool?
    private var isReady = false
    private var householdScope: HouseholdDatabaseScope = .participantShared
    private var sharedZoneContext = SharedZoneContext()

    private static let sharedZoneContextDefaultsKey = "CloudKit.sharedZoneByHouseholdId"
    private static let ownerHouseholdZonePrefix = "HouseholdZone-"

    /// Gets the shared container, must call ensureReady() first
    private var container: CKContainer {
        get async {
            // Container should be created by ensureReady() on main thread
            await MainActor.run {
                if Self._sharedContainer == nil {
                    Self._sharedContainer = CKContainer(identifier: Self.containerIdentifier)
                }
                return Self._sharedContainer!
            }
        }
    }

    private var privateDatabase: CKDatabase {
        get async {
            await container.privateCloudDatabase
        }
    }

    private var sharedDatabase: CKDatabase {
        get async {
            await container.sharedCloudDatabase
        }
    }

    private var activeHouseholdDatabase: CKDatabase {
        get async {
            switch householdScope {
            case .ownerPrivate:
                await privateDatabase
            case .participantShared:
                await sharedDatabase
            }
        }
    }

    init() {
        // Container is lazily initialized on first use via ensureReady()
        sharedZoneContext.zoneByHouseholdId = Self.loadStoredZoneByHouseholdId()
    }

    // MARK: - Readiness

    /// Call this after app launch to ensure CloudKit is ready.
    /// This prevents crashes when CloudKit is accessed too early during app initialization.
    /// CKContainer is created on the main thread to avoid crashes.
    func ensureReady() async {
        guard !isReady else { return }

        // Yield to let the main run loop complete initialization
        await _Concurrency.Task.yield()

        // Delay to ensure app is fully launched before accessing CloudKit.
        // CloudKit can crash with SIGTRAP if accessed during early app startup on iOS 26+.
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Create container on main thread to avoid CloudKit crashes.
        // CKContainer init crashes on background threads during early app startup.
        await MainActor.run {
            if Self._sharedContainer == nil {
                Self._sharedContainer = CKContainer(identifier: Self.containerIdentifier)
            }
        }

        isReady = true
    }

    // MARK: - Availability Check

    /// Check if CloudKit is available before performing operations
    func checkAvailability() async throws {
        // Ensure we're ready first
        await ensureReady()

        // Return cached result if available
        if let isAvailable = self.isAvailable {
            if !isAvailable {
                let error = CloudKitManagerError.notAuthenticated
                recordCloudKitFailure(error, operation: "checkAvailability.cached")
                throw error
            }
            return
        }

        do {
            let ckContainer = await container
            let status = try await ckContainer.accountStatus()
            let isAvailable = status == .available
            self.isAvailable = isAvailable

            if !isAvailable {
                let error = CloudKitManagerError.notAuthenticated
                recordCloudKitFailure(error, operation: "checkAvailability.status")
                throw error
            }
        } catch {
            recordCloudKitFailure(error, operation: "checkAvailability.accountStatus")
            throw error
        }
    }

    /// Reset availability cache (call when user signs in/out)
    func resetAvailabilityCache() {
        isAvailable = nil
    }

    /// Get the CloudKit container (for use with UICloudSharingController)
    func getContainer() async -> CKContainer {
        await container
    }

    func setHouseholdScope(_ scope: HouseholdDatabaseScope) {
        householdScope = scope
    }

    func getHouseholdScope() -> HouseholdDatabaseScope {
        householdScope
    }

    // MARK: - Shared Zone Context

    func setSharedZoneContext(householdId: UUID, zoneID: CKRecordZone.ID) {
        sharedZoneContext.zoneByHouseholdId[householdId] = zoneID
        persistSharedZoneContext()
        print("CloudKitScope: mapped household \(householdId) to zone \(zoneID.zoneName)")
    }

    private func persistSharedZoneContext() {
        let encoded = sharedZoneContext.zoneByHouseholdId.reduce(into: [String: String]()) { output, element in
            let householdId = element.key.uuidString
            let zoneID = element.value
            output[householdId] = Self.encodedZoneID(zoneID)
        }
        UserDefaults.standard.set(encoded, forKey: Self.sharedZoneContextDefaultsKey)
    }

    private static func loadStoredZoneByHouseholdId() -> [UUID: CKRecordZone.ID] {
        guard
            let raw = UserDefaults.standard.dictionary(forKey: sharedZoneContextDefaultsKey) as? [String: String]
        else {
            return [:]
        }

        var output: [UUID: CKRecordZone.ID] = [:]
        for (householdRaw, encodedZone) in raw {
            guard
                let householdId = UUID(uuidString: householdRaw),
                let zoneID = decodedZoneID(encodedZone)
            else {
                continue
            }
            output[householdId] = zoneID
        }
        return output
    }

    private static func encodedZoneID(_ zoneID: CKRecordZone.ID) -> String {
        "\(zoneID.zoneName)|\(zoneID.ownerName)"
    }

    private static func decodedZoneID(_ raw: String) -> CKRecordZone.ID? {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return CKRecordZone.ID(zoneName: String(parts[0]), ownerName: String(parts[1]))
    }

    private func rememberRecordZone(_ record: CKRecord, explicitHouseholdId: UUID?) {
        let zoneID = record.recordID.zoneID
        sharedZoneContext.zoneByRecordName[record.recordID.recordName] = zoneID

        if let explicitHouseholdId {
            sharedZoneContext.zoneByHouseholdId[explicitHouseholdId] = zoneID
            persistSharedZoneContext()
            return
        }

        if record.recordType == "Household",
           let householdRaw = record["id"] as? String,
           let householdId = UUID(uuidString: householdRaw)
        {
            sharedZoneContext.zoneByHouseholdId[householdId] = zoneID
            persistSharedZoneContext()
            return
        }

        if let householdRef = record["householdId"] as? CKRecord.Reference,
           let householdId = UUID(uuidString: householdRef.recordID.recordName)
        {
            sharedZoneContext.zoneByHouseholdId[householdId] = zoneID
            persistSharedZoneContext()
        }
    }

    private func resolveZoneForRecordName(_ recordName: String) -> CKRecordZone.ID? {
        sharedZoneContext.zoneByRecordName[recordName]
    }

    private func resolveCachedZone(for householdId: UUID?) -> CKRecordZone.ID? {
        guard let householdId else { return nil }
        return sharedZoneContext.zoneByHouseholdId[householdId]
    }

    private func clearCachedZone(for householdId: UUID?) {
        guard let householdId else { return }
        sharedZoneContext.zoneByHouseholdId.removeValue(forKey: householdId)
        persistSharedZoneContext()
        print("CloudKitScope: cleared cached zone for household \(householdId)")
    }

    nonisolated private func recordCloudKitFailure(_ error: Error, operation: String) {
        Task { @MainActor in
            CloudKitDiagnosticsState.shared.record(error: error, operation: operation)
        }
    }

    nonisolated private func clearCloudKitFailure() {
        Task { @MainActor in
            CloudKitDiagnosticsState.shared.clear()
        }
    }

    private func ownerZoneID(for householdId: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "\(Self.ownerHouseholdZonePrefix)\(householdId.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    @discardableResult
    func ensureHouseholdOwnerZone(householdId: UUID) async throws -> CKRecordZone.ID {
        let zoneID = ownerZoneID(for: householdId)
        if resolveCachedZone(for: householdId) == zoneID {
            return zoneID
        }

        let db = await privateDatabase
        let existingZones = try await db.allRecordZones()
        if existingZones.contains(where: { $0.zoneID == zoneID }) {
            setSharedZoneContext(householdId: householdId, zoneID: zoneID)
            return zoneID
        }

        print("CloudKitScope: creating owner household zone \(zoneID.zoneName)")
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])
        setSharedZoneContext(householdId: householdId, zoneID: zoneID)
        return zoneID
    }

    func migrateHouseholdToCustomZoneIfNeeded(householdId: UUID) async throws {
        guard householdScope == .ownerPrivate else { return }
        do {
            let targetZoneID = try await ensureHouseholdOwnerZone(householdId: householdId)
            let householdRecord = try await fetchRecord(id: householdId, householdId: householdId)
            let db = await privateDatabase
            var authoritativeRecord = householdRecord

            if householdRecord.recordID.zoneID != targetZoneID {
                print(
                    "CloudKitScope: migrating household \(householdId) from zone \(householdRecord.recordID.zoneID.zoneName) to \(targetZoneID.zoneName)"
                )

                let targetRecordID = CKRecord.ID(
                    recordName: householdRecord.recordID.recordName,
                    zoneID: targetZoneID
                )
                let migratedRecord = CKRecord(recordType: householdRecord.recordType, recordID: targetRecordID)
                for key in householdRecord.allKeys() {
                    migratedRecord[key] = householdRecord[key]
                }

                do {
                    authoritativeRecord = try await db.save(migratedRecord)
                } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                    authoritativeRecord = try await db.record(for: targetRecordID)
                }

                do {
                    _ = try await db.deleteRecord(withID: householdRecord.recordID)
                } catch let ckError as CKError where ckError.code == .unknownItem {
                    // Source may be already removed by concurrent migration.
                }
            }

            let defaultRecordID = CKRecord.ID(
                recordName: householdId.uuidString,
                zoneID: CKRecordZone.default().zoneID
            )
            if authoritativeRecord.recordID != defaultRecordID {
                do {
                    _ = try await db.deleteRecord(withID: defaultRecordID)
                } catch let ckError as CKError where ckError.code == .unknownItem {
                    // No legacy default-zone duplicate.
                }
            }

            setSharedZoneContext(householdId: householdId, zoneID: authoritativeRecord.recordID.zoneID)
            rememberRecordZone(authoritativeRecord, explicitHouseholdId: householdId)
        } catch {
            recordCloudKitFailure(error, operation: "migrateHouseholdToCustomZoneIfNeeded")
            throw error
        }
    }

    private func allSharedZoneIDs() async throws -> [CKRecordZone.ID] {
        let zones = try await sharedDatabase.allRecordZones()
        let zoneIDs = zones.map(\.zoneID)
        sharedZoneContext.lastResolvedSharedZones = zoneIDs
        if !zoneIDs.isEmpty {
            let names = zoneIDs.map(\.zoneName).joined(separator: ",")
            print("CloudKitScope: resolved shared zones [\(names)]")
        }
        return zoneIDs
    }

    private func allPrivateZoneIDs() async throws -> [CKRecordZone.ID] {
        let zones = try await privateDatabase.allRecordZones()
        let zoneIDs = zones.map(\.zoneID)
        if !zoneIDs.isEmpty {
            let names = zoneIDs.map(\.zoneName).joined(separator: ",")
            print("CloudKitScope: resolved private zones [\(names)]")
        }
        return zoneIDs
    }

    private func zoneCacheKey(_ zoneID: CKRecordZone.ID) -> String {
        "\(zoneID.zoneName)|\(zoneID.ownerName)"
    }

    private func removeCachedRecordZones(_ zoneID: CKRecordZone.ID) {
        let target = zoneCacheKey(zoneID)
        sharedZoneContext.zoneByRecordName = sharedZoneContext.zoneByRecordName.filter { _, value in
            zoneCacheKey(value) != target
        }
    }

    private func isRetryableZoneResolutionError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }

        switch ckError.code {
        case .zoneNotFound, .unknownItem, .permissionFailure:
            return true
        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                return partialErrors.values.contains { isRetryableZoneResolutionError($0) }
            }
            return true
        default:
            return false
        }
    }

    private func resolveHouseholdZone(for householdId: UUID) async throws -> CKRecordZone.ID? {
        if let cachedZone = resolveCachedZone(for: householdId) {
            return cachedZone
        }

        let householdPredicate = NSPredicate(format: "id == %@", householdId.uuidString)
        let householdQuery = CKQuery(recordType: "Household", predicate: householdPredicate)
        _ = try await queryRecords(householdQuery, householdId: householdId)
        return resolveCachedZone(for: householdId)
    }

    private func candidateZoneIDs(
        recordName: String,
        householdId: UUID?
    ) async throws -> [CKRecordZone.ID] {
        var ordered: [CKRecordZone.ID] = []
        var seen = Set<String>()

        func appendUnique(_ zoneID: CKRecordZone.ID?) {
            guard let zoneID else { return }
            let key = zoneCacheKey(zoneID)
            guard !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(zoneID)
        }

        appendUnique(resolveZoneForRecordName(recordName))
        appendUnique(resolveCachedZone(for: householdId))

        if let householdId {
            appendUnique(try await resolveHouseholdZone(for: householdId))
        }

        switch householdScope {
        case .ownerPrivate:
            appendUnique(CKRecordZone.default().zoneID)
            for zoneID in try await allPrivateZoneIDs() {
                appendUnique(zoneID)
            }
        case .participantShared:
            for zoneID in try await allSharedZoneIDs() {
                appendUnique(zoneID)
            }
        }

        return ordered
    }

    private func queryRecords(
        _ query: CKQuery,
        householdId: UUID? = nil
    ) async throws -> [CKRecord] {
        let db = await activeHouseholdDatabase

        switch householdScope {
        case .ownerPrivate:
            print("CloudKitScope: query ownerPrivate \(query.recordType)")
            let (results, _) = try await db.records(matching: query)
            let records = results.compactMap { _, result -> CKRecord? in
                guard case let .success(record) = result else { return nil }
                return record
            }
            records.forEach { rememberRecordZone($0, explicitHouseholdId: householdId) }
            return records

        case .participantShared:
            let cachedZone = resolveCachedZone(for: householdId)
            let initialZoneIDs: [CKRecordZone.ID]
            if let cachedZone {
                initialZoneIDs = [cachedZone]
            } else {
                initialZoneIDs = try await allSharedZoneIDs()
            }

            var aggregatedByRecordName: [String: CKRecord] = [:]
            var needsZoneRefresh = false

            for zoneID in initialZoneIDs {
                print("CloudKitScope: query participantShared \(query.recordType) in zone \(zoneID.zoneName)")
                do {
                    let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
                    for (_, result) in results {
                        guard case let .success(record) = result else { continue }
                        aggregatedByRecordName[record.recordID.recordName] = record
                    }
                } catch {
                    if isRetryableZoneResolutionError(error) {
                        needsZoneRefresh = true
                        print(
                            "CloudKitScope: query failed in zone \(zoneID.zoneName). scheduling shared-zone refresh"
                        )
                        continue
                    }
                    throw error
                }
            }

            var records = Array(aggregatedByRecordName.values)

            if let cachedZone, (records.isEmpty || needsZoneRefresh) {
                clearCachedZone(for: householdId)
                var fallbackZones = try await allSharedZoneIDs()
                fallbackZones.removeAll(where: { $0 == cachedZone })

                if !fallbackZones.isEmpty {
                    print("CloudKitScope: retrying participantShared query across refreshed zones")
                    var fallbackByRecordName: [String: CKRecord] = [:]
                    for zoneID in fallbackZones {
                        print(
                            "CloudKitScope: query participantShared \(query.recordType) fallback zone \(zoneID.zoneName)"
                        )
                        do {
                            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
                            for (_, result) in results {
                                guard case let .success(record) = result else { continue }
                                fallbackByRecordName[record.recordID.recordName] = record
                            }
                        } catch {
                            if isRetryableZoneResolutionError(error) {
                                continue
                            }
                            throw error
                        }
                    }
                    if !fallbackByRecordName.isEmpty {
                        records = Array(fallbackByRecordName.values)
                    }
                }
            }

            records.forEach { rememberRecordZone($0, explicitHouseholdId: householdId) }
            return records
        }
    }

    private func fetchRecord(
        id: UUID,
        householdId: UUID? = nil
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase
        let recordName = id.uuidString

        let scopeName = householdScope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        let zoneIDs = try await candidateZoneIDs(recordName: recordName, householdId: householdId)

        for zoneID in zoneIDs {
            do {
                print("CloudKitScope: fetch \(recordName) in \(scopeName) zone \(zoneID.zoneName)")
                let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
                let record = try await db.record(for: recordID)
                rememberRecordZone(record, explicitHouseholdId: householdId)
                return record
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue
            } catch {
                if isRetryableZoneResolutionError(error) {
                    continue
                }
                throw error
            }
        }

        throw CKError(.unknownItem)
    }

    private func deleteRecord(
        id: UUID,
        householdId: UUID? = nil
    ) async throws {
        let db = await activeHouseholdDatabase
        let recordName = id.uuidString

        let scopeName = householdScope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        let zoneIDs = try await candidateZoneIDs(recordName: recordName, householdId: householdId)

        for zoneID in zoneIDs {
            do {
                print("CloudKitScope: delete \(recordName) in \(scopeName) zone \(zoneID.zoneName)")
                let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
                _ = try await db.deleteRecord(withID: recordID)
                return
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue
            } catch {
                if isRetryableZoneResolutionError(error) {
                    continue
                }
                throw error
            }
        }

        throw CKError(.unknownItem)
    }

    private func recordForSave(
        _ record: CKRecord,
        householdId: UUID?
    ) async throws -> CKRecord {
        var zoneID = resolveCachedZone(for: householdId)
        if zoneID == nil {
            zoneID = resolveZoneForRecordName(record.recordID.recordName)
        }
        if zoneID == nil, let householdId {
            zoneID = try await resolveHouseholdZone(for: householdId)
        }

        guard let zoneID else { return record }
        let currentID = record.recordID
        if currentID.zoneID == zoneID {
            return record
        }

        let newRecordID = CKRecord.ID(recordName: currentID.recordName, zoneID: zoneID)
        let rewritten = CKRecord(recordType: record.recordType, recordID: newRecordID)
        for key in record.allKeys() {
            rewritten[key] = record[key]
        }
        return rewritten
    }

    private func saveRecordWithZoneRecovery(
        _ record: CKRecord,
        householdId: UUID?
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase
        let scopeName = householdScope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        let scopedRecord = try await recordForSave(record, householdId: householdId)
        do {
            print(
                "CloudKitScope: save \(record.recordType) in \(scopeName) zone \(scopedRecord.recordID.zoneID.zoneName)"
            )
            let saved = try await db.save(scopedRecord)
            rememberRecordZone(saved, explicitHouseholdId: householdId)
            return saved
        } catch {
            guard isRetryableZoneResolutionError(error) else {
                recordCloudKitFailure(error, operation: "saveRecordWithZoneRecovery.initial.\(record.recordType)")
                throw error
            }

            print(
                "CloudKitScope: save \(record.recordType) failed in \(scopeName), retrying with refreshed zone context"
            )
            sharedZoneContext.zoneByRecordName.removeValue(forKey: record.recordID.recordName)
            clearCachedZone(for: householdId)
            if let householdId {
                _ = try await resolveHouseholdZone(for: householdId)
            }

            let retryRecord = try await recordForSave(record, householdId: householdId)
            print(
                "CloudKitScope: retry save \(record.recordType) in \(scopeName) zone \(retryRecord.recordID.zoneID.zoneName)"
            )
            do {
                let saved = try await db.save(retryRecord)
                rememberRecordZone(saved, explicitHouseholdId: householdId)
                return saved
            } catch {
                recordCloudKitFailure(error, operation: "saveRecordWithZoneRecovery.retry.\(record.recordType)")
                throw error
            }
        }
    }

    private func saveRecordWithChangedKeys(
        _ record: CKRecord,
        database: CKDatabase
    ) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            var savedRecord: CKRecord?
            operation.perRecordSaveBlock = { _, result in
                if case let .success(record) = result {
                    savedRecord = record
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: savedRecord ?? record)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    enum CloudKitManagerError: LocalizedError {
        case invalidRecord
        case shareNotCreated
        case networkUnavailable
        case notAuthenticated
        case quotaExceeded
        case serverRecordChanged
        case unknownError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidRecord:
                "Invalid record data"
            case .shareNotCreated:
                "Failed to create share"
            case .networkUnavailable:
                "No internet connection. Changes will sync when online."
            case .notAuthenticated:
                "Please sign in to iCloud in Settings."
            case .quotaExceeded:
                "iCloud storage is full. Please free up space."
            case .serverRecordChanged:
                "This item was modified elsewhere. Refreshing..."
            case let .unknownError(error):
                "An error occurred: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Household

    func saveHousehold(_ household: Household) async throws -> CKRecord {
        if householdScope == .ownerPrivate {
            _ = try await ensureHouseholdOwnerZone(householdId: household.id)
        }
        let record = householdRecord(from: household)
        let saved = try await saveRecordWithZoneRecovery(record, householdId: household.id)
        clearCloudKitFailure()
        return saved
    }

    func fetchHousehold(id: UUID) async throws -> Household {
        let record = try await fetchRecord(id: id, householdId: id)
        return try household(from: record)
    }

    func deleteHousehold(id: UUID) async throws {
        try await deleteRecord(id: id, householdId: id)
    }

    /// Delete owner private zone for household when using a custom zone.
    /// Returns true when cascade delete via zone was performed (or zone was already gone).
    func deleteHouseholdZoneIfCustom(id householdId: UUID) async throws -> Bool {
        guard householdScope == .ownerPrivate else { return false }
        guard let zoneID = try await resolveHouseholdZone(for: householdId) else { return false }

        let defaultZone = CKRecordZone.default().zoneID
        guard zoneID != defaultZone else { return false }

        print("CloudKitScope: deleting owner custom zone \(zoneID.zoneName) for household cleanup")

        do {
            _ = try await privateDatabase.deleteRecordZone(withID: zoneID)
            clearCachedZone(for: householdId)
            removeCachedRecordZones(zoneID)
            return true
        } catch let ckError as CKError where ckError.code == .unknownItem {
            clearCachedZone(for: householdId)
            removeCachedRecordZones(zoneID)
            return true
        }
    }

    // MARK: - Member

    func saveMember(_ member: Member) async throws -> CKRecord {
        let record = memberRecord(from: member)
        return try await saveRecordWithZoneRecovery(record, householdId: member.householdId)
    }

    private func updateMemberRecord(
        memberId: UUID,
        householdId: UUID,
        operationName: String,
        mutate: (CKRecord) -> Void
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase
        let scopeName = householdScope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        var retryCount = 0

        while true {
            let existingRecord = try await fetchRecord(id: memberId, householdId: householdId)
            mutate(existingRecord)

            do {
                print(
                    "CloudKitScope: patch Member (\(operationName)) in \(scopeName) zone \(existingRecord.recordID.zoneID.zoneName)"
                )
                let saved = try await saveRecordWithChangedKeys(existingRecord, database: db)
                rememberRecordZone(saved, explicitHouseholdId: householdId)
                clearCloudKitFailure()
                return saved
            } catch let ckError as CKError where ckError.code == .serverRecordChanged && retryCount == 0 {
                retryCount += 1
                print("CloudKitScope: Member patch (\(operationName)) conflicted, retrying after refetch")
                continue
            } catch {
                guard retryCount == 0, isRetryableZoneResolutionError(error) else {
                    recordCloudKitFailure(error, operation: "updateMemberRecord.\(operationName)")
                    throw error
                }

                retryCount += 1
                print("CloudKitScope: Member patch (\(operationName)) failed, refreshing zone context and retrying")
                sharedZoneContext.zoneByRecordName.removeValue(forKey: memberId.uuidString)
                clearCachedZone(for: householdId)
                _ = try await resolveHouseholdZone(for: householdId)
            }
        }
    }

    func updateMemberDisplayName(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "displayName"
        ) { record in
            record["displayName"] = newDisplayName as CKRecordValue
        }
    }

    func updateMemberRole(
        memberId: UUID,
        householdId: UUID,
        newRole: Member.MemberRole
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "role"
        ) { record in
            record["role"] = newRole.rawValue as CKRecordValue
        }
    }

    func fetchMember(id: UUID) async throws -> Member {
        let record = try await fetchRecord(id: id)
        return try member(from: record)
    }

    func deleteMember(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteMember(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Find active member by Apple user ID in active database scope.
    func fetchMemberByUserId(_ userId: String, householdId: UUID? = nil) async throws -> Member? {
        let predicate = if let householdId {
            NSPredicate(
                format: "userId == %@ AND householdId == %@",
                userId,
                CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
            )
        } else {
            NSPredicate(format: "userId == %@", userId)
        }
        let query = CKQuery(recordType: "Member", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: false)]

        let records = try await queryRecords(query, householdId: householdId)
        let members = try records.map(member(from:))

        return members.first(where: { $0.isActive })
    }

    /// Fetch all members for a household
    func fetchMembers(householdId: UUID) async throws -> [Member] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "Member", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(member(from:))
    }

    // MARK: - Area

    func saveArea(_ area: Area) async throws -> CKRecord {
        let record = areaRecord(from: area)
        return try await saveRecordWithZoneRecovery(record, householdId: area.householdId)
    }

    func fetchArea(id: UUID) async throws -> Area {
        let record = try await fetchRecord(id: id)
        return try area(from: record)
    }

    func deleteArea(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteArea(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Fetch all areas for a household
    func fetchAreas(householdId: UUID) async throws -> [Area] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "Area", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(area(from:))
    }

    // MARK: - Task

    func saveTask(_ task: Task) async throws -> CKRecord {
        let record = taskRecord(from: task)
        return try await saveRecordWithZoneRecovery(record, householdId: task.householdId)
    }

    func fetchTask(id: UUID) async throws -> Task {
        let record = try await fetchRecord(id: id)
        return try task(from: record)
    }

    func deleteTask(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteTask(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Fetch all tasks for a household
    func fetchTasks(householdId: UUID) async throws -> [Task] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "Task", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(task(from:))
    }

    /// Fetch tasks filtered by status
    func fetchTasks(householdId: UUID, status: Task.TaskStatus) async throws -> [Task] {
        let predicate = NSPredicate(
            format: "householdId == %@ AND status == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none),
            status.rawValue
        )
        let query = CKQuery(recordType: "Task", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(task(from:))
    }

    /// Fetch tasks assigned to a specific member in "next" status (for WIP limit check)
    func fetchNextTasks(assigneeId: UUID) async throws -> [Task] {
        let predicate = NSPredicate(
            format: "assigneeId == %@ AND status == %@",
            CKRecord.Reference(recordID: recordID(for: assigneeId), action: .none),
            Task.TaskStatus.next.rawValue
        )
        let query = CKQuery(recordType: "Task", predicate: predicate)

        let records = try await queryRecords(query)
        return try records.map(task(from:))
    }

    /// Count tasks in "next" for a member (WIP limit = 3)
    func countNextTasks(assigneeId: UUID) async throws -> Int {
        try await fetchNextTasks(assigneeId: assigneeId).count
    }

    // MARK: - Recurring Chore

    func saveRecurringChore(_ chore: RecurringChore) async throws -> CKRecord {
        let record = recurringChoreRecord(from: chore)
        return try await saveRecordWithZoneRecovery(record, householdId: chore.householdId)
    }

    func fetchRecurringChore(id: UUID) async throws -> RecurringChore {
        let record = try await fetchRecord(id: id)
        return try recurringChore(from: record)
    }

    func deleteRecurringChore(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteRecurringChore(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Fetch all recurring chores for a household
    func fetchRecurringChores(householdId: UUID) async throws -> [RecurringChore] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "RecurringChore", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(recurringChore(from:))
    }

    // MARK: - Shopping Item

    func saveShoppingItem(_ item: ShoppingItem) async throws -> CKRecord {
        let record = shoppingItemRecord(from: item)
        return try await saveRecordWithZoneRecovery(record, householdId: item.householdId)
    }

    func fetchShoppingItem(id: UUID) async throws -> ShoppingItem {
        let record = try await fetchRecord(id: id)
        return try shoppingItem(from: record)
    }

    func deleteShoppingItem(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteShoppingItem(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Fetch all shopping items for a household
    func fetchShoppingItems(householdId: UUID) async throws -> [ShoppingItem] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "ShoppingItem", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(shoppingItem(from:))
    }

    // MARK: - Backlog Category

    func saveBacklogCategory(_ category: BacklogCategory) async throws -> CKRecord {
        let record = backlogCategoryRecord(from: category)
        return try await saveRecordWithZoneRecovery(record, householdId: category.householdId)
    }

    func fetchBacklogCategory(id: UUID) async throws -> BacklogCategory {
        let record = try await fetchRecord(id: id)
        return try backlogCategory(from: record)
    }

    func deleteBacklogCategory(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteBacklogCategory(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Fetch all backlog categories for a household
    func fetchBacklogCategories(householdId: UUID) async throws -> [BacklogCategory] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "BacklogCategory", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(backlogCategory(from:))
    }

    // MARK: - Backlog Item

    func saveBacklogItem(_ item: BacklogItem) async throws -> CKRecord {
        let record = backlogItemRecord(from: item)
        return try await saveRecordWithZoneRecovery(record, householdId: item.householdId)
    }

    func fetchBacklogItem(id: UUID) async throws -> BacklogItem {
        let record = try await fetchRecord(id: id)
        return try backlogItem(from: record)
    }

    func deleteBacklogItem(id: UUID) async throws {
        try await deleteRecord(id: id)
    }

    func deleteBacklogItem(id: UUID, householdId: UUID) async throws {
        try await deleteRecord(id: id, householdId: householdId)
    }

    /// Fetch all backlog items for a category
    func fetchBacklogItems(categoryId: UUID) async throws -> [BacklogItem] {
        let predicate = NSPredicate(
            format: "categoryId == %@",
            CKRecord.Reference(recordID: recordID(for: categoryId), action: .none)
        )
        let query = CKQuery(recordType: "BacklogItem", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let records = try await queryRecords(query)
        return try records.map(backlogItem(from:))
    }

    /// Fetch all backlog items for a household
    func fetchBacklogItems(householdId: UUID) async throws -> [BacklogItem] {
        let predicate = NSPredicate(
            format: "householdId == %@",
            CKRecord.Reference(recordID: recordID(for: householdId), action: .none)
        )
        let query = CKQuery(recordType: "BacklogItem", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let records = try await queryRecords(query, householdId: householdId)
        return try records.map(backlogItem(from:))
    }

    // MARK: - Mapping

    // MARK: - Sharing

    /// Fetch raw CKRecord for household (needed for CKShare)
    func fetchHouseholdRecord(id: UUID) async throws -> CKRecord {
        try await fetchRecord(id: id, householdId: id)
    }

    /// Create a CKShare for a household
    func createShare(for household: Household) async throws -> CKShare {
        do {
            if householdScope == .ownerPrivate {
                _ = try await ensureHouseholdOwnerZone(householdId: household.id)
                try await migrateHouseholdToCustomZoneIfNeeded(householdId: household.id)
            }

            let householdRecord = try await fetchHouseholdRecord(id: household.id)
            guard householdRecord.recordID.zoneID != CKRecordZone.default().zoneID else {
                throw CloudKitManagerError.shareNotCreated
            }
            let db = await activeHouseholdDatabase

            let share = CKShare(rootRecord: householdRecord)
            share[CKShare.SystemFieldKey.title] = household.name as CKRecordValue
            share.publicPermission = .none // Private - requires invitation

            let modifyOperation = CKModifyRecordsOperation(
                recordsToSave: [householdRecord, share],
                recordIDsToDelete: nil
            )
            modifyOperation.savePolicy = .changedKeys

            let createdShare = try await withCheckedThrowingContinuation { continuation in
                var savedShare: CKShare?

                modifyOperation.perRecordSaveBlock = { _, result in
                    if case let .success(record) = result, let ckshare = record as? CKShare {
                        savedShare = ckshare
                    }
                }

                modifyOperation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        if let share = savedShare {
                            continuation.resume(returning: share)
                        } else {
                            _Concurrency.Task {
                                do {
                                    let fallbackShare = try await self.fetchExistingShare(
                                        for: householdRecord.recordID
                                    )
                                    continuation.resume(returning: fallbackShare)
                                } catch {
                                    let shareError = CloudKitManagerError.shareNotCreated
                                    self.recordCloudKitFailure(
                                        shareError,
                                        operation: "createShare.fallbackFetch"
                                    )
                                    continuation.resume(throwing: shareError)
                                }
                            }
                        }
                    case let .failure(error):
                        let categorized = self.categorizeError(error)
                        self.recordCloudKitFailure(categorized, operation: "createShare.modifyRecords")
                        continuation.resume(throwing: categorized)
                    }
                }

                db.add(modifyOperation)
            }

            clearCloudKitFailure()
            return createdShare
        } catch {
            recordCloudKitFailure(error, operation: "createShare")
            throw error
        }
    }

    private func fetchExistingShare(for householdRecordID: CKRecord.ID) async throws -> CKShare {
        let db = await activeHouseholdDatabase
        let refreshedHousehold = try await db.record(for: householdRecordID)
        rememberRecordZone(refreshedHousehold, explicitHouseholdId: UUID(uuidString: householdRecordID.recordName))

        guard let shareReference = refreshedHousehold.share else {
            throw CloudKitManagerError.shareNotCreated
        }

        let shareRecord = try await db.record(for: shareReference.recordID)
        guard let share = shareRecord as? CKShare else {
            throw CloudKitManagerError.shareNotCreated
        }
        return share
    }

    func fetchShare(for householdId: UUID) async throws -> CKShare? {
        let record = try await fetchHouseholdRecord(id: householdId)
        guard let shareReference = record.share else { return nil }

        let shareRecord = try await activeHouseholdDatabase.record(for: shareReference.recordID)
        return shareRecord as? CKShare
    }

    /// Get share URL for inviting members
    func getShareURL(for householdId: UUID) async throws -> URL? {
        try await fetchShare(for: householdId)?.url
    }

    /// Accept a CloudKit share invitation and return shared household.
    func acceptShare(metadata: CKShare.Metadata) async throws -> Household {
        let ckContainer = await container
        let acceptOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        acceptOperation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            acceptOperation.perShareResultBlock = { _, result in
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
        let record = try await db.record(for: metadata.rootRecordID)
        if let householdId = UUID(uuidString: metadata.rootRecordID.recordName) {
            rememberRecordZone(record, explicitHouseholdId: householdId)
        } else {
            rememberRecordZone(record, explicitHouseholdId: nil)
        }
        return try household(from: record)
    }

    /// Accept a share using an invite code (share URL string)
    /// Returns the shared household after accepting
    func acceptShare(inviteCode: String) async throws -> Household {
        let shareURL: URL
        do {
            shareURL = try InviteInputNormalizer.normalizedURL(from: inviteCode)
        } catch {
            throw HouseholdError.invalidInviteCode
        }

        // Fetch share metadata from the URL
        let ckContainer = await container
        let metadata = try await ckContainer.shareMetadata(for: shareURL)

        // Accept the share
        return try await acceptShare(metadata: metadata)
    }

    // MARK: - Error Handling

    /// Categorize CloudKit errors into user-friendly error messages
    private func categorizeError(_ error: Error) -> CloudKitManagerError {
        guard let ckError = error as? CKError else {
            return .unknownError(error)
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .notAuthenticated:
            return .notAuthenticated
        case .quotaExceeded:
            return .quotaExceeded
        case .serverRecordChanged:
            return .serverRecordChanged
        default:
            return .unknownError(error)
        }
    }
}

// swiftlint:enable type_body_length
