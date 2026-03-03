import CloudKit
import Foundation

// swiftlint:disable type_body_length file_length
actor CloudKitManager {
    static let shared = CloudKitManager()

    enum HouseholdDatabaseScope: Sendable {
        case ownerPrivate
        case participantShared
    }

    private enum ShareCreationStage: String {
        case ensureZone
        case migrate
        case fetchRoot
        case modifyRecords
        case fallbackPoll
        case final
    }

    private enum AcceptShareStage: String {
        case acceptOperation
        case fetchRoot
        case finalize
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
    private static let inviteCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let inviteCodeLength = 6
    private static let inviteCodeMaxAttempts = 12

    static func sanitizeShareTitle(_ rawValue: String?) -> String {
        guard let rawValue else {
            return "Household"
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Household"
        }

        let suffixes = ["(owner)", "(właściciel)"]
        for suffix in suffixes {
            if trimmed.range(
                of: suffix,
                options: [.caseInsensitive, .anchored, .backwards]
            ) != nil {
                let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -suffix.count)
                let cleaned = trimmed[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? "Household" : String(cleaned)
            }
        }
        return trimmed
    }

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

    private var publicDatabase: CKDatabase {
        get async {
            await container.publicCloudDatabase
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
        _Concurrency.Task { @MainActor in
            CloudKitDiagnosticsState.shared.record(error: error, operation: operation)
        }
    }

    nonisolated private func clearCloudKitFailure() {
        _Concurrency.Task { @MainActor in
            CloudKitDiagnosticsState.shared.clear()
        }
    }

    nonisolated static func generateInviteCode(length: Int = 6) -> String {
        let resolvedLength = max(5, length)
        var generator = SystemRandomNumberGenerator()
        return String((0..<resolvedLength).map { _ in
            inviteCodeAlphabet.randomElement(using: &generator) ?? "A"
        })
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
            let db = await privateDatabase
            let defaultZoneID = CKRecordZone.default().zoneID
            let defaultRecordID = CKRecord.ID(
                recordName: householdId.uuidString,
                zoneID: defaultZoneID
            )
            let ownerRecordID = CKRecord.ID(recordName: householdId.uuidString, zoneID: targetZoneID)

            let ownerRecord = try await fetchRecordIfExists(ownerRecordID, database: db)
            var defaultRecord = try await fetchRecordIfExists(defaultRecordID, database: db)

            if ownerRecord == nil, defaultRecord == nil {
                let privateZoneIDs = try await allPrivateZoneIDs().filter {
                    $0 != defaultZoneID && $0 != targetZoneID
                }
                for zoneID in privateZoneIDs {
                    let candidateRecordID = CKRecord.ID(recordName: householdId.uuidString, zoneID: zoneID)
                    if let candidateRecord = try await fetchRecordIfExists(candidateRecordID, database: db) {
                        defaultRecord = candidateRecord
                        break
                    }
                }
            }

            let authoritativeRecord: CKRecord
            if let existingOwner = ownerRecord {
                authoritativeRecord = existingOwner
            } else if let sourceRecord = defaultRecord {
                print(
                    "CloudKitScope: migrating household \(householdId) from zone \(sourceRecord.recordID.zoneID.zoneName) to \(targetZoneID.zoneName)"
                )

                let migratedRecord = CKRecord(recordType: sourceRecord.recordType, recordID: ownerRecordID)
                for key in sourceRecord.allKeys() {
                    migratedRecord[key] = sourceRecord[key]
                }

                do {
                    authoritativeRecord = try await saveRecordWithChangedKeys(
                        migratedRecord,
                        database: db
                    )
                } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                    authoritativeRecord = try await db.record(for: ownerRecordID)
                }

                if sourceRecord.recordID != authoritativeRecord.recordID {
                    do {
                        _ = try await db.deleteRecord(withID: sourceRecord.recordID)
                    } catch let ckError as CKError where ckError.code == .unknownItem {
                        // Source may already be removed.
                    }
                }
            } else {
                throw CKError(.unknownItem)
            }

            if authoritativeRecord.recordID.zoneID != defaultZoneID {
                do {
                    _ = try await db.deleteRecord(withID: defaultRecordID)
                } catch let ckError as CKError where ckError.code == .unknownItem {
                    // No legacy default-zone duplicate.
                } catch {
                    recordCloudKitFailure(
                        error,
                        operation: "migrateHouseholdToCustomZoneIfNeeded.cleanupDefaultDuplicate"
                    )
                }
            }

            setSharedZoneContext(householdId: householdId, zoneID: targetZoneID)
            rememberRecordZone(authoritativeRecord, explicitHouseholdId: householdId)
        } catch {
            recordCloudKitFailure(error, operation: "migrateHouseholdToCustomZoneIfNeeded")
            throw error
        }
    }

    private func fetchRecordIfExists(
        _ recordID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
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
            let saved = try await saveRecordWithChangedKeys(scopedRecord, database: db)
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
                let saved = try await saveRecordWithChangedKeys(retryRecord, database: db)
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

    private func resolvedPaletteColor(
        rawColorHex: String?,
        stableId: UUID
    ) -> (hex: String, requiresMigration: Bool) {
        guard let normalized = MemberColorToken.normalize(hex: rawColorHex),
              MemberColorToken.isAllowed(hex: normalized)
        else {
            return (MemberColorToken.migratedHex(for: stableId), true)
        }
        if rawColorHex != normalized {
            return (normalized, true)
        }
        return (normalized, false)
    }

    private func migrateColorIfNeeded(
        for record: CKRecord,
        stableId: UUID,
        explicitHouseholdId: UUID?,
        operation: String,
        database: CKDatabase
    ) async -> String {
        let currentColor = record["colorHex"] as? String
        let colorState = resolvedPaletteColor(rawColorHex: currentColor, stableId: stableId)
        guard colorState.requiresMigration else {
            return colorState.hex
        }

        record["colorHex"] = colorState.hex as CKRecordValue
        do {
            let saved = try await saveRecordWithChangedKeys(record, database: database)
            rememberRecordZone(saved, explicitHouseholdId: explicitHouseholdId)
        } catch {
            print("CloudKitScope: \(operation) color migration skipped: \(error.localizedDescription)")
        }
        return colorState.hex
    }

    enum CloudKitManagerError: LocalizedError {
        case invalidRecord
        case shareNotCreated
        case inviteCodeInvalid
        case inviteCodeNotFound
        case inviteCodeExpired
        case inviteCodeRevoked
        case inviteCodeUnavailable
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
            case .inviteCodeInvalid:
                "The invite code is invalid."
            case .inviteCodeNotFound:
                "Invite code was not found."
            case .inviteCodeExpired:
                "This invite code has expired."
            case .inviteCodeRevoked:
                "This invite code is no longer active."
            case .inviteCodeUnavailable:
                "Could not generate a unique invite code. Try again."
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

    func updateHouseholdMetadata(
        householdId: UUID,
        newName: String,
        newIconSymbol: String
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase
        var retryCount = 0

        while true {
            let existingRecord = try await fetchRecord(id: householdId, householdId: householdId)
            existingRecord["name"] = newName as CKRecordValue
            existingRecord["iconSymbol"] = newIconSymbol as CKRecordValue
            existingRecord["updatedAt"] = Date() as CKRecordValue

            do {
                let saved = try await saveRecordWithChangedKeys(existingRecord, database: db)
                rememberRecordZone(saved, explicitHouseholdId: householdId)
                clearCloudKitFailure()
                return saved
            } catch let ckError as CKError where ckError.code == .serverRecordChanged && retryCount == 0 {
                retryCount += 1
                continue
            } catch {
                guard retryCount == 0, isRetryableZoneResolutionError(error) else {
                    recordCloudKitFailure(error, operation: "updateHouseholdMetadata")
                    throw error
                }

                retryCount += 1
                sharedZoneContext.zoneByRecordName.removeValue(forKey: householdId.uuidString)
                clearCachedZone(for: householdId)
                _ = try await resolveHouseholdZone(for: householdId)
            }
        }
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

    func updateMemberProfile(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newColorHex: String
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "profile"
        ) { record in
            record["displayName"] = newDisplayName as CKRecordValue
            record["colorHex"] = newColorHex as CKRecordValue
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

    func updateMemberState(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newRole: Member.MemberRole,
        isActive: Bool,
        colorHex: String
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "state"
        ) { record in
            record["displayName"] = newDisplayName as CKRecordValue
            record["role"] = newRole.rawValue as CKRecordValue
            record["isActive"] = (isActive ? 1 : 0) as CKRecordValue
            record["colorHex"] = colorHex as CKRecordValue
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

        let db = await activeHouseholdDatabase
        let records = try await queryRecords(query, householdId: householdId)
        var migratedRecords: [CKRecord] = []
        migratedRecords.reserveCapacity(records.count)

        for record in records {
            let stableId = UUID(uuidString: record.recordID.recordName) ??
                UUID(uuidString: record["id"] as? String ?? "")
            if let stableId {
                let migratedColor = await migrateColorIfNeeded(
                    for: record,
                    stableId: stableId,
                    explicitHouseholdId: householdId,
                    operation: "member.fetch",
                    database: db
                )
                record["colorHex"] = migratedColor as CKRecordValue
            }
            migratedRecords.append(record)
        }

        return try migratedRecords.map(member(from:))
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

    func updateBacklogCategoryMetadata(
        categoryId: UUID,
        householdId: UUID,
        newTitle: String,
        newColorHex: String
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase
        var didRetryAfterConflict = false

        while true {
            do {
                let existingRecord = try await fetchRecord(id: categoryId, householdId: householdId)
                existingRecord["title"] = newTitle as CKRecordValue
                existingRecord["colorHex"] = newColorHex as CKRecordValue
                existingRecord["updatedAt"] = Date() as CKRecordValue

                let saved = try await saveRecordWithChangedKeys(existingRecord, database: db)
                rememberRecordZone(saved, explicitHouseholdId: householdId)
                return saved
            } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                if didRetryAfterConflict {
                    recordCloudKitFailure(ckError, operation: "updateBacklogCategoryMetadata")
                    throw ckError
                }
                didRetryAfterConflict = true
                _ = try await resolveHouseholdZone(for: householdId)
            } catch CloudKitManagerError.serverRecordChanged {
                if didRetryAfterConflict {
                    recordCloudKitFailure(
                        CloudKitManagerError.serverRecordChanged,
                        operation: "updateBacklogCategoryMetadata"
                    )
                    throw CloudKitManagerError.serverRecordChanged
                }
                didRetryAfterConflict = true
                _ = try await resolveHouseholdZone(for: householdId)
            } catch {
                recordCloudKitFailure(error, operation: "updateBacklogCategoryMetadata")
                throw error
            }
        }
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

    private func fetchOwnerHouseholdRecordStrict(householdId: UUID) async throws -> CKRecord {
        let rootRecordID = CKRecord.ID(
            recordName: householdId.uuidString,
            zoneID: ownerZoneID(for: householdId)
        )
        let db = await privateDatabase
        let record = try await db.record(for: rootRecordID)
        rememberRecordZone(record, explicitHouseholdId: householdId)
        return record
    }

    private func fetchShareRecord(
        withID shareRecordID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> CKShare? {
        do {
            let shareRecord = try await database.record(for: shareRecordID)
            return shareRecord as? CKShare
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    private func fetchExistingShare(
        for householdRecordID: CKRecord.ID,
        database: CKDatabase
    ) async throws -> CKShare? {
        let refreshedHousehold = try await database.record(for: householdRecordID)
        rememberRecordZone(
            refreshedHousehold,
            explicitHouseholdId: UUID(uuidString: householdRecordID.recordName)
        )

        guard let shareReference = refreshedHousehold.share else {
            return nil
        }

        return try await fetchShareRecord(withID: shareReference.recordID, database: database)
    }

    private func ensureShareMetadata(
        _ share: CKShare,
        householdName: String,
        database: CKDatabase
    ) async throws -> CKShare {
        let sanitizedTitle = Self.sanitizeShareTitle(householdName)
        let existingTitle = (share[CKShare.SystemFieldKey.title] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldUpdateTitle = existingTitle != sanitizedTitle
        let shouldUpdatePermission = share.publicPermission != .readWrite

        guard shouldUpdateTitle || shouldUpdatePermission else {
            return share
        }

        if shouldUpdatePermission {
            share.publicPermission = .readWrite
        }
        if shouldUpdateTitle {
            share[CKShare.SystemFieldKey.title] = sanitizedTitle as CKRecordValue
        }
        let saved = try await saveRecordWithChangedKeys(share, database: database)
        guard let savedShare = saved as? CKShare else {
            throw CloudKitManagerError.invalidRecord
        }
        return savedShare
    }

    private func pollForExistingShare(
        rootRecordID: CKRecord.ID,
        database: CKDatabase,
        maxAttempts: Int = 5,
        delayNanoseconds: UInt64 = 300_000_000
    ) async throws -> CKShare? {
        var attempt = 0
        while attempt < maxAttempts {
            if let existingShare = try await fetchExistingShare(for: rootRecordID, database: database) {
                return existingShare
            }

            attempt += 1
            if attempt < maxAttempts {
                try await _Concurrency.Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        return nil
    }

    private func saveShareRecords(
        rootRecord householdRecord: CKRecord,
        householdName: String,
        database: CKDatabase
    ) async throws -> CKShare? {
        let share = CKShare(rootRecord: householdRecord)
        share[CKShare.SystemFieldKey.title] = Self.sanitizeShareTitle(householdName) as CKRecordValue
        share.publicPermission = .readWrite

        return try await withCheckedThrowingContinuation { continuation in
            let modifyOperation = CKModifyRecordsOperation(
                recordsToSave: [householdRecord, share],
                recordIDsToDelete: nil
            )
            modifyOperation.savePolicy = .ifServerRecordUnchanged
            modifyOperation.isAtomic = true
            modifyOperation.qualityOfService = .userInitiated

            var savedShare: CKShare?
            var firstFailure: Error?
            let shareRecordID = share.recordID

            modifyOperation.perRecordSaveBlock = { recordID, result in
                switch result {
                case let .success(record):
                    if let ckShare = record as? CKShare {
                        savedShare = ckShare
                    }
                case let .failure(error):
                    if firstFailure == nil || recordID == shareRecordID {
                        firstFailure = error
                    }
                }
            }

            modifyOperation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let firstFailure {
                        continuation.resume(throwing: firstFailure)
                        return
                    }
                    continuation.resume(returning: savedShare)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(modifyOperation)
        }
    }

    private func isShareNotCreatedError(_ error: Error) -> Bool {
        if let managerError = error as? CloudKitManagerError,
           case .shareNotCreated = managerError
        {
            return true
        }
        return false
    }

    /// Create a CKShare for a household
    func createShare(for household: Household) async throws -> CKShare {
        var stage: ShareCreationStage = .ensureZone
        do {
            setHouseholdScope(.ownerPrivate)

            stage = .ensureZone
            _ = try await ensureHouseholdOwnerZone(householdId: household.id)

            stage = .migrate
            try await migrateHouseholdToCustomZoneIfNeeded(householdId: household.id)

            stage = .fetchRoot
            let db = await privateDatabase
            var householdRecord = try await fetchOwnerHouseholdRecordStrict(householdId: household.id)

            if let shareReference = householdRecord.share,
               let existingShare = try await fetchShareRecord(withID: shareReference.recordID, database: db)
            {
                stage = .modifyRecords
                let normalizedShare = try await ensureShareMetadata(
                    existingShare,
                    householdName: household.name,
                    database: db
                )
                clearCloudKitFailure()
                return normalizedShare
            }

            stage = .modifyRecords
            var createdShare: CKShare?
            do {
                createdShare = try await saveShareRecords(
                    rootRecord: householdRecord,
                    householdName: household.name,
                    database: db
                )
            } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                householdRecord = try await fetchOwnerHouseholdRecordStrict(householdId: household.id)
                createdShare = try await saveShareRecords(
                    rootRecord: householdRecord,
                    householdName: household.name,
                    database: db
                )
            } catch CloudKitManagerError.serverRecordChanged {
                householdRecord = try await fetchOwnerHouseholdRecordStrict(householdId: household.id)
                createdShare = try await saveShareRecords(
                    rootRecord: householdRecord,
                    householdName: household.name,
                    database: db
                )
            }

            if let createdShare {
                let normalizedShare = try await ensureShareMetadata(
                    createdShare,
                    householdName: household.name,
                    database: db
                )
                clearCloudKitFailure()
                return normalizedShare
            }

            stage = .fallbackPoll
            if let fallbackShare = try await pollForExistingShare(
                rootRecordID: householdRecord.recordID,
                database: db
            ) {
                let normalizedShare = try await ensureShareMetadata(
                    fallbackShare,
                    householdName: household.name,
                    database: db
                )
                clearCloudKitFailure()
                return normalizedShare
            }

            stage = .final
            let shareError = CloudKitManagerError.shareNotCreated
            recordCloudKitFailure(shareError, operation: "createShare.\(stage.rawValue)")
            throw shareError
        } catch {
            if isShareNotCreatedError(error) {
                throw error
            }

            recordCloudKitFailure(error, operation: "createShare.\(stage.rawValue)")
            throw error
        }
    }

    func fetchShare(for householdId: UUID) async throws -> CKShare? {
        switch householdScope {
        case .ownerPrivate:
            let db = await privateDatabase
            let record = try await fetchOwnerHouseholdRecordStrict(householdId: householdId)
            guard let shareReference = record.share else { return nil }
            guard let share = try await fetchShareRecord(withID: shareReference.recordID, database: db) else {
                return nil
            }
            let householdName = (record["name"] as? String) ?? "Household"
            return try await ensureShareMetadata(
                share,
                householdName: householdName,
                database: db
            )
        case .participantShared:
            let record = try await fetchHouseholdRecord(id: householdId)
            guard let shareReference = record.share else { return nil }
            let shareRecord = try await activeHouseholdDatabase.record(for: shareReference.recordID)
            return shareRecord as? CKShare
        }
    }

    /// Get share URL for inviting members
    func getShareURL(for householdId: UUID) async throws -> URL? {
        try await fetchShare(for: householdId)?.url
    }

    // MARK: - Invite Code (Public DB Fallback)

    private func fetchInviteTokenRecordIfExists(
        code: String,
        database: CKDatabase
    ) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: code)
        do {
            return try await database.record(for: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    func createInviteCode(for household: Household) async throws -> InviteToken {
        try await checkAvailability()
        setHouseholdScope(.ownerPrivate)

        var stage = "inviteCode.create.ensureShare"
        do {
            let share = try await createShare(for: household)
            guard let shareURL = share.url else {
                let error = CloudKitManagerError.shareNotCreated
                recordCloudKitFailure(error, operation: stage)
                throw error
            }

            stage = "inviteCode.create.lookupExisting"
            let db = await publicDatabase
            let now = Date()
            let existingPredicate = NSPredicate(
                format: "householdId == %@ AND isRevoked == %@",
                household.id.uuidString,
                NSNumber(value: Int64(0))
            )
            let existingQuery = CKQuery(recordType: "InviteToken", predicate: existingPredicate)
            existingQuery.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            let (existingResults, _) = try await db.records(matching: existingQuery)
            for (_, result) in existingResults {
                guard case let .success(record) = result else { continue }
                let token = try inviteToken(from: record)
                if token.isActive(at: now) {
                    clearCloudKitFailure()
                    return token
                }
            }

            stage = "inviteCode.create.save"
            for _ in 0..<Self.inviteCodeMaxAttempts {
                let code = Self.generateInviteCode(length: Self.inviteCodeLength)
                if try await fetchInviteTokenRecordIfExists(code: code, database: db) != nil {
                    continue
                }

                let token = InviteToken(
                    id: code,
                    code: code,
                    householdId: household.id,
                    shareURL: shareURL.absoluteString,
                    createdAt: now,
                    expiresAt: now.addingTimeInterval(InviteToken.ttl),
                    isRevoked: false,
                    usesCount: 0,
                    lastRedeemedAt: nil
                )

                do {
                    _ = try await saveRecordWithChangedKeys(
                        inviteTokenRecord(from: token),
                        database: db
                    )
                    clearCloudKitFailure()
                    return token
                } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                    continue
                } catch {
                    recordCloudKitFailure(error, operation: stage)
                    throw error
                }
            }

            let error = CloudKitManagerError.inviteCodeUnavailable
            recordCloudKitFailure(error, operation: "inviteCode.create.exhausted")
            throw error
        } catch {
            if let managerError = error as? CloudKitManagerError,
               case .inviteCodeUnavailable = managerError
            {
                throw error
            }
            recordCloudKitFailure(error, operation: stage)
            throw error
        }
    }

    func fetchInviteToken(code rawCode: String) async throws -> InviteToken {
        try await checkAvailability()
        guard let code = InviteInputNormalizer.normalizeInviteCodeToken(rawCode) else {
            throw CloudKitManagerError.inviteCodeInvalid
        }

        let db = await publicDatabase
        guard let record = try await fetchInviteTokenRecordIfExists(code: code, database: db) else {
            throw CloudKitManagerError.inviteCodeNotFound
        }

        return try inviteToken(from: record)
    }

    func redeemInviteCode(_ rawCode: String) async throws -> Household {
        var stage = "inviteCode.redeem.fetchToken"
        do {
            try await checkAvailability()
            let token = try await fetchInviteToken(code: rawCode)
            let now = Date()
            if token.isRevoked {
                throw CloudKitManagerError.inviteCodeRevoked
            }
            if token.isExpired(at: now) {
                throw CloudKitManagerError.inviteCodeExpired
            }

            stage = "inviteCode.redeem.metadata"
            guard let shareURL = URL(string: token.shareURL) else {
                throw CloudKitManagerError.inviteCodeInvalid
            }

            let ckContainer = await container
            let metadata = try await ckContainer.shareMetadata(for: shareURL)

            stage = "inviteCode.redeem.acceptShare"
            let household = try await acceptShare(metadata: metadata)

            stage = "inviteCode.redeem.usageUpdate"
            let db = await publicDatabase
            if let record = try await fetchInviteTokenRecordIfExists(code: token.code, database: db) {
                record["usesCount"] = Int64(token.usesCount + 1) as CKRecordValue
                record["lastRedeemedAt"] = now as CKRecordValue
                do {
                    _ = try await saveRecordWithChangedKeys(record, database: db)
                } catch {
                    recordCloudKitFailure(error, operation: stage)
                }
            }

            clearCloudKitFailure()
            return household
        } catch {
            recordCloudKitFailure(error, operation: stage)
            throw error
        }
    }

    func revokeInviteCode(_ rawCode: String) async throws {
        try await checkAvailability()
        guard let code = InviteInputNormalizer.normalizeInviteCodeToken(rawCode) else {
            throw CloudKitManagerError.inviteCodeInvalid
        }

        let db = await publicDatabase
        guard let record = try await fetchInviteTokenRecordIfExists(code: code, database: db) else {
            throw CloudKitManagerError.inviteCodeNotFound
        }

        record["isRevoked"] = Int64(1) as CKRecordValue
        _ = try await saveRecordWithChangedKeys(record, database: db)
        clearCloudKitFailure()
    }

    /// Accept a CloudKit share invitation and return shared household.
    func acceptShare(metadata: CKShare.Metadata) async throws -> Household {
        var stage: AcceptShareStage = .acceptOperation
        do {
            let ckContainer = await container
            let acceptOperation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            acceptOperation.qualityOfService = .userInitiated

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                acceptOperation.acceptSharesResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
                ckContainer.add(acceptOperation)
            }

            setHouseholdScope(.participantShared)
            if let householdId = UUID(uuidString: metadata.rootRecordID.recordName) {
                setSharedZoneContext(householdId: householdId, zoneID: metadata.rootRecordID.zoneID)
            }

            stage = .fetchRoot
            let db = await sharedDatabase
            let record = try await fetchAcceptedRootRecord(metadata: metadata, database: db)

            stage = .finalize
            if let householdId = UUID(uuidString: metadata.rootRecordID.recordName) {
                rememberRecordZone(record, explicitHouseholdId: householdId)
            } else {
                rememberRecordZone(record, explicitHouseholdId: nil)
            }

            clearCloudKitFailure()
            return try household(from: record)
        } catch {
            recordCloudKitFailure(error, operation: "acceptShare.\(stage.rawValue)")
            throw error
        }
    }

    private func fetchAcceptedRootRecord(
        metadata: CKShare.Metadata,
        database: CKDatabase
    ) async throws -> CKRecord {
        let backoffDelays: [UInt64] = [
            500_000_000,
            1_000_000_000,
            2_000_000_000,
            3_000_000_000,
            4_000_000_000,
        ]

        var lastError: Error?
        for attempt in 0..<backoffDelays.count {
            do {
                return try await database.record(for: metadata.rootRecordID)
            } catch let ckError as CKError where ckError.code == .unknownItem {
                lastError = ckError
                guard attempt < backoffDelays.count - 1 else {
                    break
                }
                try await _Concurrency.Task.sleep(nanoseconds: backoffDelays[attempt])
            } catch {
                throw error
            }
        }

        throw lastError ?? CKError(.unknownItem)
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
