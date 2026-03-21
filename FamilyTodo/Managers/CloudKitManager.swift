import CloudKit
import Foundation

// swiftlint:disable type_body_length file_length
actor CloudKitManager {
    static let shared = CloudKitManager()

    enum HouseholdDatabaseScope {
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

    private struct DatabaseZoneContext {
        var zoneByHouseholdId: [UUID: CKRecordZone.ID] = [:]
        var zoneByRecordName: [String: CKRecordZone.ID] = [:]
        var lastResolvedZones: [CKRecordZone.ID] = []
    }

    private struct SharedZoneContext {
        var ownerPrivate = DatabaseZoneContext()
        var participantShared = DatabaseZoneContext()
    }

    struct OwnerPrivateScanResult {
        let authoritativeRecords: [CKRecord]
        let legacyDuplicateRecordIDs: [CKRecord.ID]
    }

    private typealias ZoneScopedQueryFactory = (CKRecordZone.ID?) -> CKQuery

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
    private var migratedMemberColorHouseholds: Set<UUID>
    private var recentInviteRedeemAttempts: [Date] = []

    private static let ownerZoneContextDefaultsKey = "CloudKit.ownerZoneByHouseholdId"
    private static let sharedZoneContextDefaultsKey = "CloudKit.sharedZoneByHouseholdId"
    private static let memberColorMigrationDefaultsKey = "CloudKit.memberColorMigrationCompletedHouseholds"
    private static let sharedGraphRepairDefaultsKey = "CloudKit.sharedGraphRepairCompletedHouseholds.v3"
    private static let ownerHouseholdZonePrefix = "HouseholdZone-"
    private static let defaultQueryPageSize = 200
    private static let inviteCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let inviteCodeLength = InviteInputNormalizer.preferredInviteCodeLength
    private static let inviteCodeMaxAttempts = 24
    private static let inviteCodeMaxUses = 100
    private static let inviteCodeMaxFailedAttempts = 8
    private static let inviteCodeLockWindow: TimeInterval = 10 * 60
    private static let inviteCodeAttemptWindow: TimeInterval = 5 * 60
    private static let inviteCodeAttemptLimit = 12

    private func resolvedScope(_ explicitScope: HouseholdDatabaseScope?) -> HouseholdDatabaseScope {
        explicitScope ?? householdScope
    }

    static func sanitizeShareTitle(_ rawValue: String?) -> String {
        guard let rawValue else {
            return "Household"
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Household"
        }

        let suffixes = ["(owner)", "(właściciel)"]
        for suffix in suffixes where trimmed.range(
            of: suffix,
            options: [.caseInsensitive, .anchored, .backwards]
        ) != nil {
            let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -suffix.count)
            let cleaned = trimmed[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Household" : String(cleaned)
        }
        return trimmed
    }

    static func isZoneCompatible(
        _ zoneID: CKRecordZone.ID,
        for scope: HouseholdDatabaseScope
    ) -> Bool {
        switch scope {
        case .ownerPrivate:
            return true
        case .participantShared:
            let defaultZone = CKRecordZone.default().zoneID
            return zoneID != defaultZone
        }
    }

    /// Gets the shared container, must call ensureReady() first
    private var container: CKContainer {
        get async {
            // Container should be created by ensureReady() on main thread
            await MainActor.run {
                if let existingContainer = Self._sharedContainer {
                    return existingContainer
                }
                let container = CKContainer(identifier: Self.containerIdentifier)
                Self._sharedContainer = container
                return container
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

    private func activeHouseholdDatabase(for scope: HouseholdDatabaseScope) async -> CKDatabase {
        switch scope {
        case .ownerPrivate:
            await privateDatabase
        case .participantShared:
            await sharedDatabase
        }
    }

    private var activeHouseholdDatabase: CKDatabase {
        get async {
            await activeHouseholdDatabase(for: householdScope)
        }
    }

    init() {
        // Container is lazily initialized on first use via ensureReady()
        sharedZoneContext.ownerPrivate.zoneByHouseholdId = Self.loadStoredZoneByHouseholdId(
            defaultsKey: Self.ownerZoneContextDefaultsKey
        )
        sharedZoneContext.participantShared.zoneByHouseholdId = Self.loadStoredZoneByHouseholdId(
            defaultsKey: Self.sharedZoneContextDefaultsKey
        )
        migratedMemberColorHouseholds = Self.loadMigratedMemberColorHouseholds()
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
        if let isAvailable {
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

    func setSharedZoneContext(
        householdId: UUID,
        zoneID: CKRecordZone.ID,
        scope: HouseholdDatabaseScope
    ) {
        updateZoneContext(for: scope) { context in
            context.zoneByHouseholdId[householdId] = zoneID
        }
        persistSharedZoneContext(for: scope)
        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        print("CloudKitScope: mapped household \(householdId) to zone \(zoneID.zoneName) for \(scopeName)")
    }

    func setSharedZoneContext(householdId: UUID, zoneID: CKRecordZone.ID) {
        setSharedZoneContext(householdId: householdId, zoneID: zoneID, scope: householdScope)
    }

    private func persistSharedZoneContext(for scope: HouseholdDatabaseScope) {
        let encoded = zoneContext(for: scope).zoneByHouseholdId.reduce(into: [String: String]()) { output, element in
            let householdId = element.key.uuidString
            let zoneID = element.value
            output[householdId] = Self.encodedZoneID(zoneID)
        }
        UserDefaults.standard.set(encoded, forKey: Self.defaultsKey(for: scope))
    }

    private static func loadStoredZoneByHouseholdId(defaultsKey: String) -> [UUID: CKRecordZone.ID] {
        guard
            let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]
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

    private static func defaultsKey(for scope: HouseholdDatabaseScope) -> String {
        switch scope {
        case .ownerPrivate:
            ownerZoneContextDefaultsKey
        case .participantShared:
            sharedZoneContextDefaultsKey
        }
    }

    private func zoneContext(for scope: HouseholdDatabaseScope) -> DatabaseZoneContext {
        switch scope {
        case .ownerPrivate:
            sharedZoneContext.ownerPrivate
        case .participantShared:
            sharedZoneContext.participantShared
        }
    }

    private func updateZoneContext(
        for scope: HouseholdDatabaseScope,
        _ mutate: (inout DatabaseZoneContext) -> Void
    ) {
        switch scope {
        case .ownerPrivate:
            mutate(&sharedZoneContext.ownerPrivate)
        case .participantShared:
            mutate(&sharedZoneContext.participantShared)
        }
    }

    private func persistMigratedMemberColorHouseholds() {
        let raw = migratedMemberColorHouseholds.map(\.uuidString)
        UserDefaults.standard.set(raw, forKey: Self.memberColorMigrationDefaultsKey)
    }

    private static func loadMigratedMemberColorHouseholds() -> Set<UUID> {
        guard let raw = UserDefaults.standard.array(forKey: memberColorMigrationDefaultsKey) as? [String] else {
            return []
        }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func markSharedGraphRepairCompleted(householdId: UUID) {
        var repaired = Self.loadRepairedSharedGraphHouseholds()
        repaired.insert(householdId)
        UserDefaults.standard.set(
            repaired.map(\.uuidString),
            forKey: Self.sharedGraphRepairDefaultsKey
        )
    }

    private func hasCompletedSharedGraphRepair(householdId: UUID) -> Bool {
        Self.loadRepairedSharedGraphHouseholds().contains(householdId)
    }

    private static func loadRepairedSharedGraphHouseholds() -> Set<UUID> {
        guard let raw = UserDefaults.standard.array(forKey: sharedGraphRepairDefaultsKey) as? [String] else {
            return []
        }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private static func encodedZoneID(_ zoneID: CKRecordZone.ID) -> String {
        "\(zoneID.zoneName)|\(zoneID.ownerName)"
    }

    private static func decodedZoneID(_ raw: String) -> CKRecordZone.ID? {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return CKRecordZone.ID(zoneName: String(parts[0]), ownerName: String(parts[1]))
    }

    private func rememberRecordZone(
        _ record: CKRecord,
        explicitHouseholdId: UUID?,
        scope: HouseholdDatabaseScope
    ) {
        let zoneID = record.recordID.zoneID
        updateZoneContext(for: scope) { context in
            context.zoneByRecordName[record.recordID.recordName] = zoneID
        }

        if let explicitHouseholdId {
            updateZoneContext(for: scope) { context in
                context.zoneByHouseholdId[explicitHouseholdId] = zoneID
            }
            persistSharedZoneContext(for: scope)
            return
        }

        if record.recordType == "Household",
           let householdRaw = record["id"] as? String,
           let householdId = UUID(uuidString: householdRaw)
        {
            updateZoneContext(for: scope) { context in
                context.zoneByHouseholdId[householdId] = zoneID
            }
            persistSharedZoneContext(for: scope)
            return
        }

        if let householdRef = record["householdId"] as? CKRecord.Reference,
           let householdId = UUID(uuidString: householdRef.recordID.recordName)
        {
            updateZoneContext(for: scope) { context in
                context.zoneByHouseholdId[householdId] = zoneID
            }
            persistSharedZoneContext(for: scope)
        }
    }

    private func rememberRecordZone(_ record: CKRecord, explicitHouseholdId: UUID?) {
        rememberRecordZone(record, explicitHouseholdId: explicitHouseholdId, scope: householdScope)
    }

    private func resolveZoneForRecordName(
        _ recordName: String,
        scope: HouseholdDatabaseScope
    ) -> CKRecordZone.ID? {
        guard let zoneID = zoneContext(for: scope).zoneByRecordName[recordName] else {
            return nil
        }
        guard Self.isZoneCompatible(zoneID, for: scope) else {
            updateZoneContext(for: scope) { context in
                context.zoneByRecordName.removeValue(forKey: recordName)
            }
            return nil
        }
        return zoneID
    }

    private func resolveZoneForRecordName(_ recordName: String) -> CKRecordZone.ID? {
        resolveZoneForRecordName(recordName, scope: householdScope)
    }

    private func resolveCachedZone(
        for householdId: UUID?,
        scope: HouseholdDatabaseScope
    ) -> CKRecordZone.ID? {
        guard let householdId else { return nil }
        guard let zoneID = zoneContext(for: scope).zoneByHouseholdId[householdId] else {
            return nil
        }
        guard Self.isZoneCompatible(zoneID, for: scope) else {
            clearCachedZone(for: householdId, scope: scope)
            return nil
        }
        return zoneID
    }

    private func resolveCachedZone(for householdId: UUID?) -> CKRecordZone.ID? {
        resolveCachedZone(for: householdId, scope: householdScope)
    }

    private func clearCachedZone(for householdId: UUID?) {
        clearCachedZone(for: householdId, scope: householdScope)
    }

    private func clearCachedZone(
        for householdId: UUID?,
        scope: HouseholdDatabaseScope
    ) {
        guard let householdId else { return }
        updateZoneContext(for: scope) { context in
            context.zoneByHouseholdId.removeValue(forKey: householdId)
        }
        persistSharedZoneContext(for: scope)
        print("CloudKitScope: cleared cached zone for household \(householdId)")
    }

    func clearAllCachedZones(for householdId: UUID) {
        clearCachedZone(for: householdId, scope: .ownerPrivate)
        clearCachedZone(for: householdId, scope: .participantShared)
        let recordName = householdId.uuidString
        updateZoneContext(for: .ownerPrivate) { context in
            context.zoneByRecordName.removeValue(forKey: recordName)
        }
        updateZoneContext(for: .participantShared) { context in
            context.zoneByRecordName.removeValue(forKey: recordName)
        }
    }

    private nonisolated func recordCloudKitFailure(_ error: Error, operation: String) {
        _Concurrency.Task { @MainActor in
            CloudKitDiagnosticsState.shared.record(error: error, operation: operation)
        }
    }

    private nonisolated func clearCloudKitFailure() {
        _Concurrency.Task { @MainActor in
            CloudKitDiagnosticsState.shared.clear()
        }
    }

    nonisolated static func generateInviteCode(length: Int = inviteCodeLength) -> String {
        let resolvedLength = max(inviteCodeLength, length)
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< resolvedLength).map { _ in
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

    // swiftlint:disable cyclomatic_complexity function_body_length
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

    // swiftlint:enable cyclomatic_complexity function_body_length

    // swiftlint:disable function_body_length
    func repairSharedHouseholdGraphIfNeeded(
        householdId: UUID,
        force: Bool = false
    ) async throws {
        guard householdScope == .ownerPrivate else { return }
        guard force || !hasCompletedSharedGraphRepair(householdId: householdId) else { return }

        try await migrateHouseholdToCustomZoneIfNeeded(householdId: householdId)

        let querySpecs: [(String, ZoneScopedQueryFactory)] = [
            (
                "Member",
                { zoneID in
                    let query = CKQuery(
                        recordType: "Member",
                        predicate: self.referenceMatchPredicate(
                            field: "householdId",
                            id: householdId,
                            zoneID: zoneID
                        )
                    )
                    query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
                    return query
                }
            ),
            (
                "Task",
                { zoneID in
                    let query = CKQuery(
                        recordType: "Task",
                        predicate: self.referenceMatchPredicate(
                            field: "householdId",
                            id: householdId,
                            zoneID: zoneID
                        )
                    )
                    query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
                    return query
                }
            ),
            (
                "ShoppingItem",
                { zoneID in
                    let query = CKQuery(
                        recordType: "ShoppingItem",
                        predicate: self.referenceMatchPredicate(
                            field: "householdId",
                            id: householdId,
                            zoneID: zoneID
                        )
                    )
                    query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                    return query
                }
            ),
            (
                "ShoppingBundle",
                { zoneID in
                    let query = CKQuery(
                        recordType: "ShoppingBundle",
                        predicate: self.referenceMatchPredicate(
                            field: "householdId",
                            id: householdId,
                            zoneID: zoneID
                        )
                    )
                    query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                    return query
                }
            ),
            (
                "BacklogCategory",
                { zoneID in
                    let query = CKQuery(
                        recordType: "BacklogCategory",
                        predicate: self.referenceMatchPredicate(
                            field: "householdId",
                            id: householdId,
                            zoneID: zoneID
                        )
                    )
                    query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
                    return query
                }
            ),
            (
                "BacklogItem",
                { zoneID in
                    let query = CKQuery(
                        recordType: "BacklogItem",
                        predicate: self.referenceMatchPredicate(
                            field: "householdId",
                            id: householdId,
                            zoneID: zoneID
                        )
                    )
                    query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                    return query
                }
            ),
        ]

        do {
            for (recordType, query) in querySpecs {
                let scanResult = try await queryOwnerPrivateRecordsAcrossAllZones(query, householdId: householdId)
                guard !scanResult.authoritativeRecords.isEmpty else { continue }
                print("CloudKitScope: repairing \(recordType) records into owner zone for household \(householdId)")
                _ = try await saveRecordsBatchWithZoneRecovery(
                    scanResult.authoritativeRecords,
                    householdId: householdId,
                    scope: .ownerPrivate
                )
                try await deleteLegacyOwnerPrivateRecordsIfNeeded(
                    scanResult.legacyDuplicateRecordIDs
                )
            }

            markSharedGraphRepairCompleted(householdId: householdId)
            clearCloudKitFailure()
        } catch {
            recordCloudKitFailure(error, operation: "repairSharedHouseholdGraphIfNeeded")
            throw error
        }
    }

    // swiftlint:enable function_body_length

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
        let zoneIDs = zones.map(\.zoneID).filter {
            Self.isZoneCompatible($0, for: .participantShared)
        }
        updateZoneContext(for: .participantShared) { context in
            context.lastResolvedZones = zoneIDs
        }
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

    private static func recordFreshnessTimestamp(_ record: CKRecord) -> Date {
        if let updatedAt = record["updatedAt"] as? Date {
            return updatedAt
        }
        if let joinedAt = record["joinedAt"] as? Date {
            return joinedAt
        }
        if let createdAt = record["createdAt"] as? Date {
            return createdAt
        }
        return .distantPast
    }

    private static func isPreferredOwnerPrivateCandidate(
        _ candidate: CKRecord,
        over current: CKRecord,
        targetZoneID: CKRecordZone.ID
    ) -> Bool {
        let candidateFreshness = recordFreshnessTimestamp(candidate)
        let currentFreshness = recordFreshnessTimestamp(current)

        if candidateFreshness != currentFreshness {
            return candidateFreshness > currentFreshness
        }

        let candidateIsTarget = candidate.recordID.zoneID == targetZoneID
        let currentIsTarget = current.recordID.zoneID == targetZoneID
        if candidateIsTarget != currentIsTarget {
            return candidateIsTarget
        }

        return false
    }

    private static func compareRecordValues(_ lhs: CKRecordValueProtocol?, _ rhs: CKRecordValueProtocol?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhsDate as Date, rhsDate as Date):
            lhsDate.compare(rhsDate)
        case let (lhsNumber as NSNumber, rhsNumber as NSNumber):
            lhsNumber.compare(rhsNumber)
        case let (lhsString as NSString, rhsString as NSString):
            lhsString.compare(rhsString as String)
        case (nil, nil):
            .orderedSame
        case (nil, _):
            .orderedAscending
        case (_, nil):
            .orderedDescending
        default:
            .orderedSame
        }
    }

    private static func sortRecords(
        _ records: [CKRecord],
        using sortDescriptors: [NSSortDescriptor]
    ) -> [CKRecord] {
        guard !sortDescriptors.isEmpty else {
            return records.sorted {
                $0.recordID.recordName < $1.recordID.recordName
            }
        }

        return records.sorted { lhs, rhs in
            for sortDescriptor in sortDescriptors {
                guard let key = sortDescriptor.key else { continue }
                let comparison = compareRecordValues(lhs[key], rhs[key])
                guard comparison != .orderedSame else { continue }
                return sortDescriptor.ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }

            return lhs.recordID.recordName < rhs.recordID.recordName
        }
    }

    private static func deduplicateRecordIDs(_ recordIDs: [CKRecord.ID]) -> [CKRecord.ID] {
        var seen = Set<String>()
        var unique: [CKRecord.ID] = []
        unique.reserveCapacity(recordIDs.count)

        for recordID in recordIDs {
            let key = "\(recordID.recordName)|\(recordID.zoneID.zoneName)|\(recordID.zoneID.ownerName)"
            guard seen.insert(key).inserted else { continue }
            unique.append(recordID)
        }

        return unique
    }

    private static func deduplicateReferences(
        _ references: [CKRecord.Reference]
    ) -> [CKRecord.Reference] {
        var seen = Set<String>()
        var unique: [CKRecord.Reference] = []
        unique.reserveCapacity(references.count)

        for reference in references {
            let recordID = reference.recordID
            let key = [
                recordID.recordName,
                recordID.zoneID.zoneName,
                recordID.zoneID.ownerName,
                String(reference.action.rawValue),
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }
            unique.append(reference)
        }

        return unique
    }

    static func referenceMatchPredicate(
        field: String,
        references: [CKRecord.Reference]
    ) -> NSPredicate {
        let uniqueReferences = deduplicateReferences(references)
        guard let firstReference = uniqueReferences.first else {
            return NSPredicate(value: false)
        }
        guard uniqueReferences.count > 1 else {
            return NSPredicate(format: "%K == %@", field, firstReference)
        }
        return NSPredicate(
            format: "%K IN %@",
            field,
            NSArray(array: uniqueReferences)
        )
    }

    private func referenceMatchPredicate(
        field: String,
        id: UUID,
        zoneID: CKRecordZone.ID?
    ) -> NSPredicate {
        let legacyReference = reference(for: id)
        guard let zoneID else {
            return Self.referenceMatchPredicate(field: field, references: [legacyReference])
        }

        let scopedReference = reference(for: id, in: zoneID)
        return Self.referenceMatchPredicate(
            field: field,
            references: [scopedReference, legacyReference]
        )
    }

    private static let householdGraphRecordTypes: Set<String> = [
        "Household",
        "Member",
        "Area",
        "Task",
        "WorkItem",
        "RecurringChore",
        "ShoppingItem",
        "ShoppingBundle",
        "BacklogCategory",
        "BacklogItem",
    ]

    private static let participantSharedChildRecordTypes: Set<String> = [
        "Member",
        "Area",
        "Task",
        "WorkItem",
        "RecurringChore",
        "ShoppingItem",
        "ShoppingBundle",
        "BacklogCategory",
        "BacklogItem",
    ]

    private static let singleGraphReferenceKeys = [
        "householdId",
        "assigneeId",
        "backlogCategoryId",
        "areaId",
        "recurringChoreId",
        "defaultAssigneeId",
        "categoryId",
    ]

    private static let arrayGraphReferenceKeys = [
        "assigneeIds",
        "defaultAssigneeIds",
    ]

    private func rewriteGraphReferenceFields(
        in record: CKRecord,
        targetZoneID: CKRecordZone.ID
    ) {
        for key in Self.singleGraphReferenceKeys {
            guard let reference = record[key] as? CKRecord.Reference,
                  UUID(uuidString: reference.recordID.recordName) != nil
            else {
                continue
            }
            record[key] = CKRecord.Reference(
                recordID: CKRecord.ID(
                    recordName: reference.recordID.recordName,
                    zoneID: targetZoneID
                ),
                action: reference.action
            )
        }

        for key in Self.arrayGraphReferenceKeys {
            guard let references = record[key] as? [CKRecord.Reference] else { continue }
            record[key] = references.map { reference in
                CKRecord.Reference(
                    recordID: CKRecord.ID(
                        recordName: reference.recordID.recordName,
                        zoneID: targetZoneID
                    ),
                    action: reference.action
                )
            } as CKRecordValue
        }
    }

    func validateGraphReferenceFields(
        in record: CKRecord,
        targetZoneID: CKRecordZone.ID,
        scope: HouseholdDatabaseScope
    ) throws {
        guard Self.householdGraphRecordTypes.contains(record.recordType) else {
            return
        }

        func validate(reference: CKRecord.Reference, key: String) throws {
            let actualZoneID = reference.recordID.zoneID
            guard actualZoneID == targetZoneID else {
                let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
                throw CloudKitManagerError.crossZoneReferenceViolation(
                    "Cross-zone reference violation for \(record.recordType).\(key) in \(scopeName): " +
                        "expected \(targetZoneID.zoneName), got \(actualZoneID.zoneName)."
                )
            }
        }

        for key in Self.singleGraphReferenceKeys {
            guard let reference = record[key] as? CKRecord.Reference,
                  UUID(uuidString: reference.recordID.recordName) != nil
            else {
                continue
            }
            try validate(reference: reference, key: key)
        }

        for key in Self.arrayGraphReferenceKeys {
            guard let references = record[key] as? [CKRecord.Reference] else { continue }
            for reference in references where UUID(uuidString: reference.recordID.recordName) != nil {
                try validate(reference: reference, key: key)
            }
        }
    }

    static func mergeOwnerPrivateRecords(
        _ records: [CKRecord],
        targetZoneID: CKRecordZone.ID,
        sortDescriptors: [NSSortDescriptor]
    ) -> OwnerPrivateScanResult {
        guard !records.isEmpty else {
            return OwnerPrivateScanResult(authoritativeRecords: [], legacyDuplicateRecordIDs: [])
        }

        var groupedByRecordName: [String: [CKRecord]] = [:]
        for record in records {
            groupedByRecordName[record.recordID.recordName, default: []].append(record)
        }

        var authoritativeRecords: [CKRecord] = []
        var legacyDuplicateRecordIDs: [CKRecord.ID] = []
        authoritativeRecords.reserveCapacity(groupedByRecordName.count)

        for recordsWithSameName in groupedByRecordName.values {
            guard var authoritativeRecord = recordsWithSameName.first else { continue }

            for candidate in recordsWithSameName.dropFirst() where isPreferredOwnerPrivateCandidate(
                candidate,
                over: authoritativeRecord,
                targetZoneID: targetZoneID
            ) {
                authoritativeRecord = candidate
            }

            authoritativeRecords.append(authoritativeRecord)
            legacyDuplicateRecordIDs.append(contentsOf: recordsWithSameName.compactMap { record in
                record.recordID.zoneID == targetZoneID ? nil : record.recordID
            })
        }

        return OwnerPrivateScanResult(
            authoritativeRecords: sortRecords(authoritativeRecords, using: sortDescriptors),
            legacyDuplicateRecordIDs: deduplicateRecordIDs(legacyDuplicateRecordIDs)
        )
    }

    private func queryOwnerPrivateRecordsAcrossAllZones(
        _ queryFactory: ZoneScopedQueryFactory,
        householdId: UUID
    ) async throws -> OwnerPrivateScanResult {
        let db = await privateDatabase
        let targetZoneID = try await ensureHouseholdOwnerZone(householdId: householdId)
        let defaultZoneID = CKRecordZone.default().zoneID

        var zoneIDs: [CKRecordZone.ID] = [targetZoneID, defaultZoneID]
        for zoneID in try await allPrivateZoneIDs() where !zoneIDs.contains(zoneID) {
            zoneIDs.append(zoneID)
        }

        var scannedRecords: [CKRecord] = []
        for zoneID in zoneIDs {
            let query = queryFactory(zoneID)
            let zoneRecords = try await queryRecordsPaginated(
                query,
                database: db,
                zoneID: zoneID
            )
            scannedRecords.append(contentsOf: zoneRecords)
        }

        return Self.mergeOwnerPrivateRecords(
            scannedRecords,
            targetZoneID: targetZoneID,
            sortDescriptors: queryFactory(targetZoneID).sortDescriptors ?? []
        )
    }

    private func deleteLegacyOwnerPrivateRecordsIfNeeded(_ recordIDs: [CKRecord.ID]) async throws {
        guard !recordIDs.isEmpty else { return }
        let db = await privateDatabase

        for recordID in recordIDs {
            do {
                _ = try await db.deleteRecord(withID: recordID)
                _Concurrency.Task { @MainActor in
                    CloudKitSubscriptionManager.shared.registerLocalMutation(
                        recordName: recordID.recordName
                    )
                }
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue
            }
        }
    }

    private func zoneCacheKey(_ zoneID: CKRecordZone.ID) -> String {
        "\(zoneID.zoneName)|\(zoneID.ownerName)"
    }

    private func removeCachedRecordZones(_ zoneID: CKRecordZone.ID) {
        removeCachedRecordZones(zoneID, scope: householdScope)
    }

    private func removeCachedRecordZones(
        _ zoneID: CKRecordZone.ID,
        scope: HouseholdDatabaseScope
    ) {
        let target = zoneCacheKey(zoneID)
        updateZoneContext(for: scope) { context in
            context.zoneByRecordName = context.zoneByRecordName.filter { _, value in
                zoneCacheKey(value) != target
            }
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

    private func resolveHouseholdZone(
        for householdId: UUID,
        scope: HouseholdDatabaseScope
    ) async throws -> CKRecordZone.ID? {
        if let cachedZone = resolveCachedZone(for: householdId, scope: scope) {
            return cachedZone
        }

        let householdPredicate = NSPredicate(format: "id == %@", householdId.uuidString)
        let householdQuery = CKQuery(recordType: "Household", predicate: householdPredicate)
        _ = try await queryRecords(householdQuery, householdId: householdId, scope: scope)
        return resolveCachedZone(for: householdId, scope: scope)
    }

    private func resolveHouseholdZone(for householdId: UUID) async throws -> CKRecordZone.ID? {
        try await resolveHouseholdZone(for: householdId, scope: householdScope)
    }

    private func candidateZoneIDs(
        recordName: String,
        householdId: UUID?,
        scope: HouseholdDatabaseScope
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

        appendUnique(resolveZoneForRecordName(recordName, scope: scope))
        appendUnique(resolveCachedZone(for: householdId, scope: scope))

        if let householdId {
            try await appendUnique(resolveHouseholdZone(for: householdId, scope: scope))
        }

        switch scope {
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

    private func candidateZoneIDs(
        recordName: String,
        householdId: UUID?
    ) async throws -> [CKRecordZone.ID] {
        try await candidateZoneIDs(recordName: recordName, householdId: householdId, scope: householdScope)
    }

    private func queryRecordsPage(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?,
        database: CKDatabase,
        zoneID: CKRecordZone.ID?,
        resultsLimit: Int
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else if let query {
                operation = CKQueryOperation(query: query)
                operation.zoneID = zoneID
            } else {
                continuation.resume(throwing: CloudKitManagerError.invalidRecord)
                return
            }

            operation.resultsLimit = max(1, resultsLimit)
            operation.qualityOfService = .userInitiated

            var pageRecords: [CKRecord] = []
            operation.recordMatchedBlock = { _, result in
                guard case let .success(record) = result else { return }
                pageRecords.append(record)
            }

            operation.queryResultBlock = { result in
                switch result {
                case let .success(nextCursor):
                    continuation.resume(returning: (pageRecords, nextCursor))
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private func queryRecordsPaginated(
        _ query: CKQuery,
        database: CKDatabase,
        zoneID: CKRecordZone.ID? = nil,
        resultsLimit: Int = CloudKitManager.defaultQueryPageSize
    ) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        var isFirstPage = true

        while isFirstPage || cursor != nil {
            let (pageRecords, nextCursor) = try await queryRecordsPage(
                query: isFirstPage ? query : nil,
                cursor: cursor,
                database: database,
                zoneID: zoneID,
                resultsLimit: resultsLimit
            )
            allRecords.append(contentsOf: pageRecords)
            cursor = nextCursor
            isFirstPage = false
        }

        return allRecords
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    private func queryRecords(
        householdId: UUID? = nil,
        scope: HouseholdDatabaseScope,
        queryFactory: ZoneScopedQueryFactory
    ) async throws -> [CKRecord] {
        let db = await activeHouseholdDatabase(for: scope)
        let baselineSortDescriptors = queryFactory(nil).sortDescriptors ?? []

        switch scope {
        case .ownerPrivate:
            print("CloudKitScope: query ownerPrivate \(queryFactory(nil).recordType)")
            if let householdId {
                let scanResult = try await queryOwnerPrivateRecordsAcrossAllZones(
                    queryFactory,
                    householdId: householdId
                )
                for authoritativeRecord in scanResult.authoritativeRecords {
                    rememberRecordZone(authoritativeRecord, explicitHouseholdId: householdId, scope: scope)
                }
                return scanResult.authoritativeRecords
            }

            let query = queryFactory(nil)
            let records = try await queryRecordsPaginated(query, database: db)
            records.forEach { rememberRecordZone($0, explicitHouseholdId: householdId, scope: scope) }
            return Self.sortRecords(records, using: baselineSortDescriptors)

        case .participantShared:
            let cachedZone = resolveCachedZone(for: householdId, scope: scope)
            let initialZoneIDs: [CKRecordZone.ID] = if let cachedZone {
                [cachedZone]
            } else {
                try await allSharedZoneIDs()
            }

            var aggregatedByRecordName: [String: CKRecord] = [:]
            var needsZoneRefresh = false

            for zoneID in initialZoneIDs {
                let query = queryFactory(zoneID)
                print("CloudKitScope: query participantShared \(query.recordType) in zone \(zoneID.zoneName)")
                do {
                    let zoneRecords = try await queryRecordsPaginated(
                        query,
                        database: db,
                        zoneID: zoneID
                    )
                    for record in zoneRecords {
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

            if let cachedZone, records.isEmpty || needsZoneRefresh {
                clearCachedZone(for: householdId, scope: scope)
                var fallbackZones = try await allSharedZoneIDs()
                fallbackZones.removeAll(where: { $0 == cachedZone })

                if !fallbackZones.isEmpty {
                    print("CloudKitScope: retrying participantShared query across refreshed zones")
                    var fallbackByRecordName: [String: CKRecord] = [:]
                    for zoneID in fallbackZones {
                        let query = queryFactory(zoneID)
                        print(
                            "CloudKitScope: query participantShared \(query.recordType) fallback zone \(zoneID.zoneName)"
                        )
                        do {
                            let zoneRecords = try await queryRecordsPaginated(
                                query,
                                database: db,
                                zoneID: zoneID
                            )
                            for record in zoneRecords {
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
                        records = Self.sortRecords(
                            Array(fallbackByRecordName.values),
                            using: baselineSortDescriptors
                        )
                    }
                }
            }

            records.forEach { rememberRecordZone($0, explicitHouseholdId: householdId, scope: scope) }
            return Self.sortRecords(records, using: baselineSortDescriptors)
        }
    }

    private func queryRecords(
        _ query: CKQuery,
        householdId: UUID? = nil,
        scope: HouseholdDatabaseScope
    ) async throws -> [CKRecord] {
        try await queryRecords(householdId: householdId, scope: scope) { _ in query }
    }

    private func queryRecords(
        _ query: CKQuery,
        householdId: UUID? = nil
    ) async throws -> [CKRecord] {
        try await queryRecords(query, householdId: householdId, scope: householdScope)
    }

    private func queryRecords(
        _ query: CKQuery,
        scope: HouseholdDatabaseScope
    ) async throws -> [CKRecord] {
        try await queryRecords(query, householdId: nil, scope: scope)
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    private func fetchRecord(
        id: UUID,
        householdId: UUID? = nil,
        scope: HouseholdDatabaseScope
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase(for: scope)
        let recordName = id.uuidString

        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        let zoneIDs = try await candidateZoneIDs(
            recordName: recordName,
            householdId: householdId,
            scope: scope
        )

        for zoneID in zoneIDs {
            do {
                print("CloudKitScope: fetch \(recordName) in \(scopeName) zone \(zoneID.zoneName)")
                let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
                let record = try await db.record(for: recordID)
                rememberRecordZone(record, explicitHouseholdId: householdId, scope: scope)
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

    private func fetchRecord(
        id: UUID,
        householdId: UUID? = nil
    ) async throws -> CKRecord {
        try await fetchRecord(id: id, householdId: householdId, scope: householdScope)
    }

    private func deleteRecord(
        id: UUID,
        householdId: UUID? = nil,
        scope: HouseholdDatabaseScope
    ) async throws {
        let db = await activeHouseholdDatabase(for: scope)
        let recordName = id.uuidString

        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        let zoneIDs = try await candidateZoneIDs(
            recordName: recordName,
            householdId: householdId,
            scope: scope
        )

        for zoneID in zoneIDs {
            do {
                print("CloudKitScope: delete \(recordName) in \(scopeName) zone \(zoneID.zoneName)")
                let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
                _ = try await db.deleteRecord(withID: recordID)
                _Concurrency.Task { @MainActor in
                    CloudKitSubscriptionManager.shared.registerLocalMutation(recordName: recordName)
                }
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

    private func deleteRecord(
        id: UUID,
        householdId: UUID? = nil
    ) async throws {
        try await deleteRecord(id: id, householdId: householdId, scope: householdScope)
    }

    private func recordForSave(
        _ record: CKRecord,
        householdId: UUID?,
        scope: HouseholdDatabaseScope
    ) async throws -> CKRecord {
        var zoneID = resolveCachedZone(for: householdId, scope: scope)
        if zoneID == nil {
            zoneID = resolveZoneForRecordName(record.recordID.recordName, scope: scope)
        }
        if zoneID == nil, let householdId {
            zoneID = try await resolveHouseholdZone(for: householdId, scope: scope)
        }

        guard let zoneID else {
            if Self.householdGraphRecordTypes.contains(record.recordType) {
                let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
                throw CloudKitManagerError.missingTargetZone(
                    "Could not resolve a target zone for \(record.recordType) in \(scopeName)." +
                        (householdId.map { " householdId=\($0.uuidString)" } ?? "")
                )
            }
            return record
        }
        let currentID = record.recordID
        if currentID.zoneID == zoneID {
            rewriteGraphReferenceFields(in: record, targetZoneID: zoneID)
            try validateGraphReferenceFields(
                in: record,
                targetZoneID: zoneID,
                scope: scope
            )
            attachParticipantSharedRootParentIfNeeded(
                to: record,
                householdId: householdId,
                scope: scope,
                zoneID: zoneID
            )
            return record
        }

        let newRecordID = CKRecord.ID(recordName: currentID.recordName, zoneID: zoneID)
        let rewritten = CKRecord(recordType: record.recordType, recordID: newRecordID)
        for key in record.allKeys() {
            rewritten[key] = record[key]
        }
        rewriteGraphReferenceFields(in: rewritten, targetZoneID: zoneID)
        try validateGraphReferenceFields(
            in: rewritten,
            targetZoneID: zoneID,
            scope: scope
        )
        attachParticipantSharedRootParentIfNeeded(
            to: rewritten,
            householdId: householdId,
            scope: scope,
            zoneID: zoneID
        )
        return rewritten
    }

    func attachParticipantSharedRootParentIfNeeded(
        to record: CKRecord,
        householdId: UUID?,
        scope: HouseholdDatabaseScope,
        zoneID: CKRecordZone.ID
    ) {
        guard scope == .participantShared,
              Self.participantSharedChildRecordTypes.contains(record.recordType),
              let householdId
        else {
            return
        }

        let householdRecordID = CKRecord.ID(
            recordName: householdId.uuidString,
            zoneID: zoneID
        )
        record.parent = CKRecord.Reference(
            recordID: householdRecordID,
            action: .none
        )
    }

    private func recordForSave(
        _ record: CKRecord,
        householdId: UUID?
    ) async throws -> CKRecord {
        try await recordForSave(record, householdId: householdId, scope: householdScope)
    }

    private func saveRecordWithZoneRecovery(
        _ record: CKRecord,
        householdId: UUID?,
        scope: HouseholdDatabaseScope
    ) async throws -> CKRecord {
        let db = await activeHouseholdDatabase(for: scope)
        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        let scopedRecord = try await recordForSave(record, householdId: householdId, scope: scope)
        do {
            print(
                "CloudKitScope: save \(record.recordType) in \(scopeName) zone \(scopedRecord.recordID.zoneID.zoneName)"
            )
            let saved = try await saveRecordWithChangedKeys(scopedRecord, database: db)
            rememberRecordZone(saved, explicitHouseholdId: householdId, scope: scope)
            return saved
        } catch {
            guard isRetryableZoneResolutionError(error) else {
                recordCloudKitFailure(error, operation: "saveRecordWithZoneRecovery.initial.\(record.recordType)")
                throw error
            }

            print(
                "CloudKitScope: save \(record.recordType) failed in \(scopeName), retrying with refreshed zone context"
            )
            updateZoneContext(for: scope) { context in
                context.zoneByRecordName.removeValue(forKey: record.recordID.recordName)
            }
            clearCachedZone(for: householdId, scope: scope)
            if let householdId {
                _ = try await resolveHouseholdZone(for: householdId, scope: scope)
            }

            let retryRecord = try await recordForSave(record, householdId: householdId, scope: scope)
            print(
                "CloudKitScope: retry save \(record.recordType) in \(scopeName) zone \(retryRecord.recordID.zoneID.zoneName)"
            )
            do {
                let saved = try await saveRecordWithChangedKeys(retryRecord, database: db)
                rememberRecordZone(saved, explicitHouseholdId: householdId, scope: scope)
                return saved
            } catch {
                recordCloudKitFailure(error, operation: "saveRecordWithZoneRecovery.retry.\(record.recordType)")
                throw error
            }
        }
    }

    private func saveRecordWithZoneRecovery(
        _ record: CKRecord,
        householdId: UUID?
    ) async throws -> CKRecord {
        try await saveRecordWithZoneRecovery(record, householdId: householdId, scope: householdScope)
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
                    let resolvedRecord = savedRecord ?? record
                    _Concurrency.Task { @MainActor in
                        CloudKitSubscriptionManager.shared.registerLocalMutation(
                            recordName: resolvedRecord.recordID.recordName
                        )
                    }
                    continuation.resume(returning: resolvedRecord)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private func modifyRecordsBatch(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        database: CKDatabase
    ) async throws -> (saved: [CKRecord], deleted: [CKRecord.ID]) {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave.isEmpty ? nil : recordsToSave,
                recordIDsToDelete: recordIDsToDelete.isEmpty ? nil : recordIDsToDelete
            )
            operation.savePolicy = .changedKeys
            operation.isAtomic = false
            operation.qualityOfService = .userInitiated

            var saved: [CKRecord] = []
            var deleted: [CKRecord.ID] = []
            var firstFailure: Error?

            operation.perRecordSaveBlock = { _, result in
                switch result {
                case let .success(record):
                    saved.append(record)
                case let .failure(error):
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }

            operation.perRecordDeleteBlock = { recordID, result in
                switch result {
                case .success:
                    deleted.append(recordID)
                case let .failure(error):
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let firstFailure {
                        continuation.resume(throwing: firstFailure)
                    } else {
                        continuation.resume(returning: (saved, deleted))
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private func saveRecordsBatchWithZoneRecovery(
        _ records: [CKRecord],
        householdId: UUID?,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [CKRecord] {
        guard !records.isEmpty else { return [] }
        let scope = resolvedScope(explicitScope)
        let db = await activeHouseholdDatabase(for: scope)

        func scopedRecords(from sourceRecords: [CKRecord]) async throws -> [CKRecord] {
            var output: [CKRecord] = []
            output.reserveCapacity(sourceRecords.count)
            for record in sourceRecords {
                try await output.append(
                    recordForSave(record, householdId: householdId, scope: scope)
                )
            }
            return output
        }

        let initialScopedRecords = try await scopedRecords(from: records)

        do {
            let outcome = try await modifyRecordsBatch(
                recordsToSave: initialScopedRecords,
                recordIDsToDelete: [],
                database: db
            )
            for record in outcome.saved {
                rememberRecordZone(record, explicitHouseholdId: householdId, scope: scope)
                _Concurrency.Task { @MainActor in
                    CloudKitSubscriptionManager.shared.registerLocalMutation(
                        recordName: record.recordID.recordName
                    )
                }
            }
            return outcome.saved
        } catch {
            guard isRetryableZoneResolutionError(error) else {
                throw error
            }

            clearCachedZone(for: householdId, scope: scope)
            if let householdId {
                _ = try await resolveHouseholdZone(for: householdId, scope: scope)
            }

            let retryScopedRecords = try await scopedRecords(from: records)

            let outcome = try await modifyRecordsBatch(
                recordsToSave: retryScopedRecords,
                recordIDsToDelete: [],
                database: db
            )
            for record in outcome.saved {
                rememberRecordZone(record, explicitHouseholdId: householdId, scope: scope)
                _Concurrency.Task { @MainActor in
                    CloudKitSubscriptionManager.shared.registerLocalMutation(
                        recordName: record.recordID.recordName
                    )
                }
            }
            return outcome.saved
        }
    }

    private func batchDeleteRecordIDs(
        recordNames: [String],
        householdId: UUID?,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        guard !recordNames.isEmpty else { return }
        let scope = resolvedScope(explicitScope)
        let db = await activeHouseholdDatabase(for: scope)

        func resolvedDeleteIDs() async throws -> [CKRecord.ID] {
            var resolvedZoneID = resolveCachedZone(for: householdId, scope: scope)
            if resolvedZoneID == nil, let householdId {
                resolvedZoneID = try await resolveHouseholdZone(for: householdId, scope: scope)
            }
            if let resolvedZoneID {
                return recordNames.map { CKRecord.ID(recordName: $0, zoneID: resolvedZoneID) }
            }
            return recordNames.map { CKRecord.ID(recordName: $0) }
        }

        do {
            let deleteIDs = try await resolvedDeleteIDs()
            let outcome = try await modifyRecordsBatch(
                recordsToSave: [],
                recordIDsToDelete: deleteIDs,
                database: db
            )
            for recordID in outcome.deleted {
                _Concurrency.Task { @MainActor in
                    CloudKitSubscriptionManager.shared.registerLocalMutation(
                        recordName: recordID.recordName
                    )
                }
            }
        } catch {
            guard isRetryableZoneResolutionError(error) else {
                throw error
            }

            clearCachedZone(for: householdId, scope: scope)
            if let householdId {
                _ = try await resolveHouseholdZone(for: householdId, scope: scope)
            }
            let retryDeleteIDs = try await resolvedDeleteIDs()
            let outcome = try await modifyRecordsBatch(
                recordsToSave: [],
                recordIDsToDelete: retryDeleteIDs,
                database: db
            )
            for recordID in outcome.deleted {
                _Concurrency.Task { @MainActor in
                    CloudKitSubscriptionManager.shared.registerLocalMutation(
                        recordName: recordID.recordName
                    )
                }
            }
        }
    }

    func saveTasksBatch(
        _ tasks: [Task],
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        guard !tasks.isEmpty else { return }
        let scope = resolvedScope(explicitScope)
        let householdId = tasks.first?.householdId
        let records = tasks.map { taskRecord(from: $0) }
        _ = try await saveRecordsBatchWithZoneRecovery(
            records,
            householdId: householdId,
            scope: scope
        )
    }

    func saveShoppingItemsBatch(
        _ items: [ShoppingItem],
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        guard !items.isEmpty else { return }
        let scope = resolvedScope(explicitScope)
        let householdId = items.first?.householdId
        let records = items.map { shoppingItemRecord(from: $0) }
        _ = try await saveRecordsBatchWithZoneRecovery(
            records,
            householdId: householdId,
            scope: scope
        )
    }

    func saveBacklogCategoriesBatch(
        _ categories: [BacklogCategory],
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        guard !categories.isEmpty else { return }
        let scope = resolvedScope(explicitScope)
        let householdId = categories.first?.householdId
        let records = categories.map { backlogCategoryRecord(from: $0) }
        _ = try await saveRecordsBatchWithZoneRecovery(
            records,
            householdId: householdId,
            scope: scope
        )
    }

    func deleteTasksBatch(
        ids: Set<UUID>,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        let recordNames = ids.map(\.uuidString)
        try await batchDeleteRecordIDs(
            recordNames: recordNames,
            householdId: householdId,
            scope: scope
        )
    }

    func deleteShoppingItemsBatch(
        ids: Set<UUID>,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        let recordNames = ids.map(\.uuidString)
        try await batchDeleteRecordIDs(
            recordNames: recordNames,
            householdId: householdId,
            scope: scope
        )
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

    private func markMemberColorMigrationCompleted(householdId: UUID) {
        migratedMemberColorHouseholds.insert(householdId)
        persistMigratedMemberColorHouseholds()
    }

    func migrateMemberColorsIfNeeded(householdId: UUID) async {
        guard !migratedMemberColorHouseholds.contains(householdId) else { return }

        do {
            let records = try await queryRecords(householdId: householdId, scope: householdScope) { zoneID in
                let query = CKQuery(
                    recordType: "Member",
                    predicate: self.referenceMatchPredicate(
                        field: "householdId",
                        id: householdId,
                        zoneID: zoneID
                    )
                )
                query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
                return query
            }
            var recordsToSave: [CKRecord] = []
            recordsToSave.reserveCapacity(records.count)

            for record in records {
                let stableId = UUID(uuidString: record.recordID.recordName) ??
                    UUID(uuidString: record["id"] as? String ?? "")
                guard let stableId else { continue }

                let colorState = resolvedPaletteColor(
                    rawColorHex: record["colorHex"] as? String,
                    stableId: stableId
                )
                guard colorState.requiresMigration else { continue }

                record["colorHex"] = colorState.hex as CKRecordValue
                recordsToSave.append(record)
            }

            if !recordsToSave.isEmpty {
                _ = try await saveRecordsBatchWithZoneRecovery(recordsToSave, householdId: householdId)
            }

            markMemberColorMigrationCompleted(householdId: householdId)
        } catch {
            print("CloudKitScope: member color migration skipped: \(error.localizedDescription)")
        }
    }

    enum CloudKitManagerError: LocalizedError {
        case invalidRecord
        case shareNotCreated
        case sharePermissionValidationFailed(String)
        case missingTargetZone(String)
        case crossZoneReferenceViolation(String)
        case inviteCodeInvalid
        case inviteCodeNotFound
        case inviteTokenFetchFailed(String)
        case shareMetadataFetchFailed(String)
        case acceptShareFailed(String)
        case sharedHouseholdFetchFailed(String)
        case inviteCodeExpired
        case inviteCodeRevoked
        case inviteCodeLocked
        case inviteCodeRateLimited
        case inviteCodeUsageLimitReached
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
            case let .sharePermissionValidationFailed(message),
                 let .missingTargetZone(message),
                 let .crossZoneReferenceViolation(message),
                 let .inviteTokenFetchFailed(message),
                 let .shareMetadataFetchFailed(message),
                 let .acceptShareFailed(message),
                 let .sharedHouseholdFetchFailed(message):
                message
            case .inviteCodeInvalid:
                "The invite code is invalid."
            case .inviteCodeNotFound:
                "Invite code was not found."
            case .inviteCodeExpired:
                "This invite code has expired."
            case .inviteCodeRevoked:
                "This invite code is no longer active."
            case .inviteCodeLocked:
                "This invite code is temporarily locked. Try again in a few minutes."
            case .inviteCodeRateLimited:
                "Too many invite attempts. Please wait and try again."
            case .inviteCodeUsageLimitReached:
                "This invite code reached its usage limit."
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

    func saveHousehold(
        _ household: Household,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        // Zone is expected to be ensured by the caller (createHousehold, createShare, etc.).
        // saveRecordWithZoneRecovery handles missing-zone fallback if needed.
        let record = householdRecord(from: household)
        let saved = try await saveRecordWithZoneRecovery(
            record,
            householdId: household.id,
            scope: scope
        )
        clearCloudKitFailure()
        return saved
    }

    func updateHouseholdMetadata(
        householdId: UUID,
        newName: String,
        newIconSymbol: String,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        var retryCount = 0

        while true {
            let existingRecord = try await fetchRecord(
                id: householdId,
                householdId: householdId,
                scope: scope
            )
            existingRecord["name"] = newName as CKRecordValue
            existingRecord["iconSymbol"] = newIconSymbol as CKRecordValue
            existingRecord["updatedAt"] = Date() as CKRecordValue

            do {
                let saved = try await saveRecordWithZoneRecovery(
                    existingRecord,
                    householdId: householdId,
                    scope: scope
                )
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
                updateZoneContext(for: scope) { context in
                    context.zoneByRecordName.removeValue(forKey: householdId.uuidString)
                }
                clearCachedZone(for: householdId, scope: scope)
                _ = try await resolveHouseholdZone(for: householdId, scope: scope)
            }
        }
    }

    func fetchHousehold(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> Household {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, householdId: id, scope: scope)
        return try household(from: record)
    }

    func deleteHousehold(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: id, scope: scope)
    }

    func leaveSharedHousehold(householdId: UUID) async throws {
        guard householdScope == .participantShared else { return }

        let resolvedZone: CKRecordZone.ID? = if let cachedZone = resolveCachedZone(for: householdId) {
            cachedZone
        } else {
            try await resolveHouseholdZone(for: householdId)
        }

        do {
            try await deleteRecord(id: householdId, householdId: householdId)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // Already removed from the participant's shared database.
        }

        clearCachedZone(for: householdId, scope: .participantShared)
        if let resolvedZone {
            removeCachedRecordZones(resolvedZone, scope: .participantShared)
        }
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

    func saveMember(
        _ member: Member,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = memberRecord(from: member)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: member.householdId,
            scope: scope
        )
    }

    /// Batched household creation: ensures zone in one round-trip, then saves
    /// household + member records together in a single CKModifyRecordsOperation.
    func createHouseholdWithMember(
        _ household: Household,
        member: Member
    ) async throws -> (householdRecord: CKRecord, memberRecord: CKRecord) {
        let zoneID = try await ensureHouseholdOwnerZone(householdId: household.id)

        let householdRec = householdRecord(from: household)
        let memberRec = memberRecord(from: member)

        let scopedHousehold = try await recordForSave(
            householdRec,
            householdId: household.id,
            scope: .ownerPrivate
        )
        let scopedMember = try await recordForSave(
            memberRec,
            householdId: member.householdId,
            scope: .ownerPrivate
        )

        let db = await privateDatabase
        let result = try await modifyRecordsBatch(
            recordsToSave: [scopedHousehold, scopedMember],
            recordIDsToDelete: [],
            database: db
        )

        for saved in result.saved {
            rememberRecordZone(
                saved,
                explicitHouseholdId: household.id,
                scope: .ownerPrivate
            )
        }
        clearCloudKitFailure()

        let savedHousehold = result.saved.first { $0.recordType == "Household" } ?? scopedHousehold
        let savedMember = result.saved.first { $0.recordType == "Member" } ?? scopedMember
        print("CloudKitScope: batched createHouseholdWithMember in zone \(zoneID.zoneName)")
        return (savedHousehold, savedMember)
    }

    private func updateMemberRecord(
        memberId: UUID,
        householdId: UUID,
        operationName: String,
        scope explicitScope: HouseholdDatabaseScope? = nil,
        mutate: (CKRecord) -> Void
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let scopeName = scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        var retryCount = 0

        while true {
            let existingRecord = try await fetchRecord(
                id: memberId,
                householdId: householdId,
                scope: scope
            )
            mutate(existingRecord)

            do {
                print(
                    "CloudKitScope: patch Member (\(operationName)) in \(scopeName) zone \(existingRecord.recordID.zoneID.zoneName)"
                )
                let saved = try await saveRecordWithZoneRecovery(
                    existingRecord,
                    householdId: householdId,
                    scope: scope
                )
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
                updateZoneContext(for: scope) { context in
                    context.zoneByRecordName.removeValue(forKey: memberId.uuidString)
                }
                clearCachedZone(for: householdId, scope: scope)
                _ = try await resolveHouseholdZone(for: householdId, scope: scope)
            }
        }
    }

    func updateMemberDisplayName(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "displayName",
            scope: explicitScope
        ) { record in
            record["displayName"] = newDisplayName as CKRecordValue
        }
    }

    func updateMemberProfile(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newColorHex: String,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "profile",
            scope: explicitScope
        ) { record in
            record["displayName"] = newDisplayName as CKRecordValue
            record["colorHex"] = newColorHex as CKRecordValue
        }
    }

    func updateMemberRole(
        memberId: UUID,
        householdId: UUID,
        newRole: Member.MemberRole,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "role",
            scope: explicitScope
        ) { record in
            record["role"] = newRole.rawValue as CKRecordValue
        }
    }

    // swiftlint:disable function_parameter_count
    func updateMemberState(
        memberId: UUID,
        householdId: UUID,
        newDisplayName: String,
        newRole: Member.MemberRole,
        isActive: Bool,
        colorHex: String,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        try await updateMemberRecord(
            memberId: memberId,
            householdId: householdId,
            operationName: "state",
            scope: explicitScope
        ) { record in
            record["displayName"] = newDisplayName as CKRecordValue
            record["role"] = newRole.rawValue as CKRecordValue
            record["isActive"] = (isActive ? 1 : 0) as CKRecordValue
            record["colorHex"] = colorHex as CKRecordValue
        }
    }

    // swiftlint:enable function_parameter_count

    func fetchMember(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> Member {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try member(from: record)
    }

    func deleteMember(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteMember(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Find active member by Apple user ID in active database scope.
    func fetchMemberByUserId(
        _ userId: String,
        householdId: UUID? = nil,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> Member? {
        let scope = resolvedScope(explicitScope)
        let records: [CKRecord]
        if let householdId {
            records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
                let predicates = [
                    NSPredicate(format: "userId == %@", userId),
                    self.referenceMatchPredicate(
                        field: "householdId",
                        id: householdId,
                        zoneID: zoneID
                    ),
                ]
                let query = CKQuery(
                    recordType: "Member",
                    predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                )
                query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: false)]
                return query
            }
        } else {
            let query = CKQuery(
                recordType: "Member",
                predicate: NSPredicate(format: "userId == %@", userId)
            )
            query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: false)]
            records = try await queryRecords(query, householdId: householdId, scope: scope)
        }
        let members = try records.map(member(from:))

        return members.first(where: { $0.isActive })
    }

    func fetchActiveMembersByUserId(
        _ userId: String,
        householdId: UUID? = nil,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [Member] {
        let scope = resolvedScope(explicitScope)
        let records: [CKRecord]
        if let householdId {
            records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
                let predicates = [
                    NSPredicate(format: "userId == %@", userId),
                    self.referenceMatchPredicate(
                        field: "householdId",
                        id: householdId,
                        zoneID: zoneID
                    ),
                ]
                let query = CKQuery(
                    recordType: "Member",
                    predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                )
                query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: false)]
                return query
            }
        } else {
            let query = CKQuery(
                recordType: "Member",
                predicate: NSPredicate(format: "userId == %@", userId)
            )
            query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: false)]
            records = try await queryRecords(query, householdId: householdId, scope: scope)
        }

        return try records.map(member(from:)).filter(\.isActive)
    }

    /// Fetch all members for a household
    func fetchMembers(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [Member] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "Member",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
            return query
        }
        return try records.map(member(from:))
    }

    // MARK: - Area

    func saveArea(
        _ area: Area,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = areaRecord(from: area)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: area.householdId,
            scope: scope
        )
    }

    func fetchArea(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> Area {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try area(from: record)
    }

    func deleteArea(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteArea(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Fetch all areas for a household
    func fetchAreas(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [Area] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "Area",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            return query
        }
        return try records.map(area(from:))
    }

    // MARK: - Task

    func saveTask(
        _ task: Task,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = taskRecord(from: task)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: task.householdId,
            scope: scope
        )
    }

    func fetchTask(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> Task {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try task(from: record)
    }

    func deleteTask(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteTask(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Fetch all tasks for a household
    func fetchTasks(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [Task] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "Task",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return query
        }
        return try records.map(task(from:))
    }

    /// Fetch tasks filtered by status
    func fetchTasks(
        householdId: UUID,
        status: Task.TaskStatus,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [Task] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let predicates = [
                self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                ),
                NSPredicate(format: "status == %@", status.rawValue),
            ]
            let query = CKQuery(
                recordType: "Task",
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            )
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return query
        }
        return try records.map(task(from:))
    }

    /// Fetch tasks assigned to a specific member in "next" status (for WIP limit check)
    func fetchNextTasks(
        householdId: UUID,
        assigneeId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [Task] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let predicates = [
                self.referenceMatchPredicate(
                    field: "assigneeId",
                    id: assigneeId,
                    zoneID: zoneID
                ),
                NSPredicate(format: "status == %@", Task.TaskStatus.next.rawValue),
            ]
            let query = CKQuery(
                recordType: "Task",
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            )
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return query
        }
        return try records.map(task(from:))
    }

    /// Count tasks in "next" for a member (WIP limit = 3)
    func countNextTasks(
        householdId: UUID,
        assigneeId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> Int {
        try await fetchNextTasks(
            householdId: householdId,
            assigneeId: assigneeId,
            scope: explicitScope
        ).count
    }

    // MARK: - WorkItem

    func saveWorkItem(
        _ item: WorkItem,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = workItemRecord(from: item)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: item.householdId,
            scope: scope
        )
    }

    func fetchWorkItem(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> WorkItem {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try workItem(from: record)
    }

    func deleteWorkItem(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteWorkItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    func fetchWorkItems(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [WorkItem] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "WorkItem",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return query
        }
        return try records.map(workItem(from:))
    }

    func fetchUnifiedWorkItems(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [WorkItem] {
        async let fetchedWorkItems = fetchWorkItems(householdId: householdId, scope: explicitScope)
        async let fetchedTasks = fetchTasks(householdId: householdId, scope: explicitScope)
        async let fetchedIdeas = fetchBacklogItems(householdId: householdId, scope: explicitScope)

        let (workItems, tasks, ideas) = try await (fetchedWorkItems, fetchedTasks, fetchedIdeas)
        return mergeUnifiedWorkItems(workItems: workItems, tasks: tasks, ideas: ideas)
    }

    private func mergeUnifiedWorkItems(
        workItems: [WorkItem],
        tasks: [Task],
        ideas: [BacklogItem]
    ) -> [WorkItem] {
        var mergedByLogicalID = Dictionary(uniqueKeysWithValues: workItems.map { ($0.logicalItemID, $0) })

        for task in tasks {
            let candidate = WorkItem(task: task)
            guard mergedByLogicalID[candidate.logicalItemID] == nil else { continue }
            mergedByLogicalID[candidate.logicalItemID] = candidate
        }

        for idea in ideas {
            let candidate = WorkItem(idea: idea)
            if let existing = mergedByLogicalID[candidate.logicalItemID] {
                guard shouldReplaceUnifiedWorkItem(existing: existing, with: candidate) else {
                    continue
                }
            }
            mergedByLogicalID[candidate.logicalItemID] = candidate
        }

        return mergedByLogicalID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func shouldReplaceUnifiedWorkItem(existing: WorkItem, with candidate: WorkItem) -> Bool {
        let existingPriority = unifiedWorkItemStatusPriority(existing.status)
        let candidatePriority = unifiedWorkItemStatusPriority(candidate.status)

        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority
        }

        return candidate.updatedAt > existing.updatedAt
    }

    private func unifiedWorkItemStatusPriority(_ status: WorkItem.Status) -> Int {
        switch status {
        case .done:
            4
        case .next:
            3
        case .backlog:
            2
        case .idea:
            1
        }
    }

    // MARK: - Recurring Chore

    func saveRecurringChore(
        _ chore: RecurringChore,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = recurringChoreRecord(from: chore)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: chore.householdId,
            scope: scope
        )
    }

    func fetchRecurringChore(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> RecurringChore {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try recurringChore(from: record)
    }

    func deleteRecurringChore(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteRecurringChore(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Fetch all recurring chores for a household
    func fetchRecurringChores(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [RecurringChore] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "RecurringChore",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            return query
        }
        return try records.map(recurringChore(from:))
    }

    // MARK: - Shopping Item

    func saveShoppingItem(
        _ item: ShoppingItem,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = shoppingItemRecord(from: item)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: item.householdId,
            scope: scope
        )
    }

    func fetchShoppingItem(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> ShoppingItem {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try shoppingItem(from: record)
    }

    func deleteShoppingItem(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteShoppingItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Fetch all shopping items for a household
    func fetchShoppingItems(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [ShoppingItem] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "ShoppingItem",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            return query
        }
        return try records.map(shoppingItem(from:))
    }

    // MARK: - Shopping Bundle

    func saveShoppingBundle(
        _ bundle: ShoppingBundle,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = shoppingBundleRecord(from: bundle)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: bundle.householdId,
            scope: scope
        )
    }

    func fetchShoppingBundle(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> ShoppingBundle {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try shoppingBundle(from: record)
    }

    func deleteShoppingBundle(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteShoppingBundle(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    func fetchShoppingBundles(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [ShoppingBundle] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "ShoppingBundle",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            return query
        }
        return try records.map(shoppingBundle(from:))
    }

    // MARK: - Backlog Category

    func saveBacklogCategory(
        _ category: BacklogCategory,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = backlogCategoryRecord(from: category)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: category.householdId,
            scope: scope
        )
    }

    func updateBacklogCategoryMetadata(
        categoryId: UUID,
        householdId: UUID,
        newTitle: String,
        newColorHex: String,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        var didRetryAfterConflict = false

        while true {
            do {
                let existingRecord = try await fetchRecord(
                    id: categoryId,
                    householdId: householdId,
                    scope: scope
                )
                existingRecord["title"] = newTitle as CKRecordValue
                existingRecord["colorHex"] = newColorHex as CKRecordValue
                existingRecord["updatedAt"] = Date() as CKRecordValue

                return try await saveRecordWithZoneRecovery(
                    existingRecord,
                    householdId: householdId,
                    scope: scope
                )
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
                _ = try await resolveHouseholdZone(for: householdId, scope: scope)
            } catch {
                recordCloudKitFailure(error, operation: "updateBacklogCategoryMetadata")
                throw error
            }
        }
    }

    func fetchBacklogCategory(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> BacklogCategory {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try backlogCategory(from: record)
    }

    func deleteBacklogCategory(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteBacklogCategory(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Fetch all backlog categories for a household
    func fetchBacklogCategories(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [BacklogCategory] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "BacklogCategory",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            return query
        }
        return try records.map(backlogCategory(from:))
    }

    // MARK: - Backlog Item

    func saveBacklogItem(
        _ item: BacklogItem,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> CKRecord {
        let scope = resolvedScope(explicitScope)
        let record = backlogItemRecord(from: item)
        return try await saveRecordWithZoneRecovery(
            record,
            householdId: item.householdId,
            scope: scope
        )
    }

    func fetchBacklogItem(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> BacklogItem {
        let scope = resolvedScope(explicitScope)
        let record = try await fetchRecord(id: id, scope: scope)
        return try backlogItem(from: record)
    }

    func deleteBacklogItem(
        id: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, scope: scope)
    }

    func deleteBacklogItem(
        id: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws {
        let scope = resolvedScope(explicitScope)
        try await deleteRecord(id: id, householdId: householdId, scope: scope)
    }

    /// Fetch all backlog items for a category
    func fetchBacklogItems(
        categoryId: UUID,
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [BacklogItem] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "BacklogItem",
                predicate: self.referenceMatchPredicate(
                    field: "categoryId",
                    id: categoryId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return query
        }
        return try records.map(backlogItem(from:))
    }

    /// Fetch all backlog items for a household
    func fetchBacklogItems(
        householdId: UUID,
        scope explicitScope: HouseholdDatabaseScope? = nil
    ) async throws -> [BacklogItem] {
        let scope = resolvedScope(explicitScope)
        let records = try await queryRecords(householdId: householdId, scope: scope) { zoneID in
            let query = CKQuery(
                recordType: "BacklogItem",
                predicate: self.referenceMatchPredicate(
                    field: "householdId",
                    id: householdId,
                    zoneID: zoneID
                )
            )
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            return query
        }
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

    private func debugErrorDescription(_ error: Error) -> String {
        let localized = error.localizedDescription
        let reflected = String(describing: error)
        var components: [String] = []

        if !localized.isEmpty {
            components.append(localized)
        }
        if reflected != localized {
            components.append(reflected)
        }

        if let ckError = error as? CKError {
            components.append("CKError.\(ckError.code)")

            if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] {
                components.append("retryAfter=\(retryAfter)")
            }
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
               !partialErrors.isEmpty
            {
                let partialDescriptions = partialErrors
                    .map { key, value in "\(key): \(debugErrorDescription(value))" }
                    .sorted()
                    .joined(separator: "; ")
                components.append("partialErrors=\(partialDescriptions)")
            }
        }

        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            let underlyingDescription = debugErrorDescription(underlying)
            if !underlyingDescription.isEmpty {
                components.append("underlying=\(underlyingDescription)")
            }
        }

        let filtered = components.filter { !$0.isEmpty }
        return filtered.joined(separator: " | ")
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
        guard savedShare.publicPermission == .readWrite else {
            throw CloudKitManagerError.sharePermissionValidationFailed(
                "Share permission failed: expected readWrite, got \(savedShare.publicPermission)."
            )
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
                    if let savedShare, savedShare.publicPermission != .readWrite {
                        continuation.resume(
                            throwing: CloudKitManagerError.sharePermissionValidationFailed(
                                "Share permission failed: expected readWrite, got \(savedShare.publicPermission)."
                            )
                        )
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
    // swiftlint:disable function_body_length
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

    // swiftlint:enable function_body_length

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

    private func enforceInviteRedeemAttemptBudget(at now: Date) throws {
        recentInviteRedeemAttempts.removeAll {
            now.timeIntervalSince($0) > Self.inviteCodeAttemptWindow
        }
        guard recentInviteRedeemAttempts.count < Self.inviteCodeAttemptLimit else {
            throw CloudKitManagerError.inviteCodeRateLimited
        }
        recentInviteRedeemAttempts.append(now)
    }

    private func clearInviteRedeemAttemptBudget() {
        recentInviteRedeemAttempts.removeAll()
    }

    static func canReuseInviteToken(
        _ token: InviteToken,
        shareURL: String?,
        at now: Date
    ) -> Bool {
        guard token.isActive(at: now),
              token.usesCount < inviteCodeMaxUses,
              let shareURL,
              !shareURL.isEmpty
        else {
            return false
        }

        return token.shareURL == shareURL
    }

    private func isInviteTokenLocked(_ token: InviteToken, at now: Date) -> Bool {
        guard token.failedAttempts >= Self.inviteCodeMaxFailedAttempts,
              let lastAttemptAt = token.lastAttemptAt
        else {
            return false
        }
        return now.timeIntervalSince(lastAttemptAt) < Self.inviteCodeLockWindow
    }

    private func mutateInviteTokenRecord(
        code: String,
        database: CKDatabase,
        maxRetries: Int = 3,
        mutate: (CKRecord) -> Void
    ) async throws -> InviteToken? {
        var attempts = 0
        while attempts < maxRetries {
            guard let record = try await fetchInviteTokenRecordIfExists(code: code, database: database) else {
                return nil
            }

            mutate(record)
            do {
                let saved = try await saveRecordWithChangedKeys(record, database: database)
                return try inviteToken(from: saved)
            } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                attempts += 1
                continue
            }
        }

        throw CloudKitManagerError.serverRecordChanged
    }

    private func registerInviteRedeemFailure(
        code: String,
        at now: Date,
        database: CKDatabase
    ) async {
        do {
            _ = try await mutateInviteTokenRecord(code: code, database: database) { record in
                let currentFailedAttempts =
                    record["failedAttempts"] as? Int64
                        ?? Int64(record["failedAttempts"] as? Int ?? 0)
                record["failedAttempts"] = Int64(currentFailedAttempts + 1) as CKRecordValue
                record["lastAttemptAt"] = now as CKRecordValue
            }
        } catch {
            recordCloudKitFailure(error, operation: "inviteCode.redeem.failureCounter")
        }
    }

    private func registerInviteRedeemSuccess(
        code: String,
        at now: Date,
        database: CKDatabase
    ) async throws {
        _ = try await mutateInviteTokenRecord(code: code, database: database) { record in
            let currentUses = record["usesCount"] as? Int64 ?? Int64(record["usesCount"] as? Int ?? 0)
            record["usesCount"] = Int64(currentUses + 1) as CKRecordValue
            record["failedAttempts"] = Int64(0) as CKRecordValue
            record["lastAttemptAt"] = now as CKRecordValue
            record["lastRedeemedAt"] = now as CKRecordValue
        }
    }

    private func shouldRegisterInviteFailureCounter(for error: Error) -> Bool {
        guard let managerError = error as? CloudKitManagerError else { return true }
        switch managerError {
        case .inviteCodeInvalid, .inviteCodeNotFound, .inviteCodeRateLimited, .inviteCodeLocked:
            return false
        default:
            return true
        }
    }

    // swiftlint:disable function_body_length
    func createInviteCode(for household: Household) async throws -> InviteToken {
        try await checkAvailability()
        setHouseholdScope(.ownerPrivate)

        var stage = "inviteCode.create.lookupExisting"
        do {
            // Fast path: check public DB for existing active tokens BEFORE
            // running the full createShare pipeline (~4 round-trips).
            let db = await publicDatabase
            let now = Date()
            var activeExistingTokens: [InviteToken] = []
            let existingPredicate = NSPredicate(
                format: "householdId == %@ AND isRevoked == %@",
                household.id.uuidString,
                NSNumber(value: Int64(0))
            )
            let existingQuery = CKQuery(recordType: "InviteToken", predicate: existingPredicate)
            existingQuery.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            let existingRecords = try await queryRecordsPaginated(existingQuery, database: db)
            for record in existingRecords {
                let token = try inviteToken(from: record)
                if token.isActive(at: now), token.usesCount < Self.inviteCodeMaxUses {
                    activeExistingTokens.append(token)
                }
            }

            if !activeExistingTokens.isEmpty {
                stage = "inviteCode.create.verifyShare"
                let existingShareURL = try await fetchShare(for: household.id)?.url?.absoluteString
                if let matchingToken = activeExistingTokens.first(where: {
                    Self.canReuseInviteToken($0, shareURL: existingShareURL, at: now)
                }) {
                    clearCloudKitFailure()
                    return matchingToken
                }
            }

            if !activeExistingTokens.isEmpty {
                stage = "inviteCode.create.repairShare"
                try await repairSharedHouseholdGraphIfNeeded(householdId: household.id)
            }

            // Slow path: no reusable token exists, need to ensure share first.
            stage = "inviteCode.create.ensureShare"
            let share = try await createShare(for: household)
            guard let shareURL = share.url else {
                let error = CloudKitManagerError.shareNotCreated
                recordCloudKitFailure(error, operation: stage)
                throw error
            }
            let shareURLString = shareURL.absoluteString

            if let matchingToken = activeExistingTokens.first(where: {
                Self.canReuseInviteToken($0, shareURL: shareURLString, at: now)
            }) {
                clearCloudKitFailure()
                return matchingToken
            }

            if !activeExistingTokens.isEmpty {
                stage = "inviteCode.create.revokeStale"
                for token in activeExistingTokens {
                    _ = try await mutateInviteTokenRecord(code: token.code, database: db) { record in
                        record["isRevoked"] = Int64(1) as CKRecordValue
                    }
                }
            }

            stage = "inviteCode.create.save"
            for _ in 0 ..< Self.inviteCodeMaxAttempts {
                let code = Self.generateInviteCode(length: Self.inviteCodeLength)
                if try await fetchInviteTokenRecordIfExists(code: code, database: db) != nil {
                    continue
                }

                let token = InviteToken(
                    id: code,
                    code: code,
                    householdId: household.id,
                    shareURL: shareURLString,
                    createdAt: now,
                    expiresAt: now.addingTimeInterval(InviteToken.ttl),
                    isRevoked: false,
                    usesCount: 0,
                    failedAttempts: 0,
                    lastAttemptAt: nil,
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

    // swiftlint:enable function_body_length

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

    func deleteInviteTokens(for householdId: UUID) async throws {
        try await checkAvailability()

        let db = await publicDatabase
        let predicate = NSPredicate(format: "householdId == %@", householdId.uuidString)
        let query = CKQuery(recordType: "InviteToken", predicate: predicate)
        let records = try await queryRecordsPaginated(query, database: db)

        for record in records {
            do {
                _ = try await db.deleteRecord(withID: record.recordID)
            } catch let ckError as CKError where ckError.code == .unknownItem {
                continue
            }
        }
    }

    func redeemInviteCode(_ rawCode: String) async throws -> Household {
        let context = try await resolveAcceptedShareContext(fromInviteCode: rawCode)
        return context.household
    }

    private func fetchShareMetadata(for shareURL: URL) async throws -> CKShare.Metadata {
        let ckContainer = await container

        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            operation.qualityOfService = .userInitiated

            var fetchedMetadata: CKShare.Metadata?
            var firstFailure: Error?

            operation.perShareMetadataResultBlock = { _, result in
                switch result {
                case let .success(metadata):
                    fetchedMetadata = metadata
                case let .failure(error):
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }

            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let firstFailure {
                        continuation.resume(throwing: firstFailure)
                        return
                    }
                    if let fetchedMetadata {
                        continuation.resume(returning: fetchedMetadata)
                        return
                    }
                    continuation.resume(
                        throwing: CloudKitManagerError.shareMetadataFetchFailed(
                            "Metadata fetch failed: CKFetchShareMetadataOperation returned no metadata."
                        )
                    )
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            ckContainer.add(operation)
        }
    }

    private func resolveJoinShareMetadata(
        for shareURL: URL,
        expectedHouseholdId: UUID? = nil
    ) async throws -> CKShare.Metadata {
        let metadata: CKShare.Metadata
        do {
            metadata = try await fetchShareMetadata(for: shareURL)
        } catch let error as CloudKitManagerError {
            throw error
        } catch {
            throw CloudKitManagerError.shareMetadataFetchFailed(
                "Metadata fetch failed: \(debugErrorDescription(error))"
            )
        }

        if let expectedHouseholdId {
            let metadataHouseholdId = UUID(uuidString: metadata.rootRecordID.recordName)
            guard metadataHouseholdId == expectedHouseholdId else {
                throw CloudKitManagerError.shareMetadataFetchFailed(
                    "Metadata fetch failed: Share metadata household mismatch."
                )
            }
        }

        return metadata
    }

    private func fetchRedeemableInviteToken(
        code: String,
        at now: Date,
        database: CKDatabase
    ) async throws -> InviteToken {
        let record: CKRecord
        do {
            guard let fetchedRecord = try await fetchInviteTokenRecordIfExists(code: code, database: database) else {
                throw CloudKitManagerError.inviteTokenFetchFailed(
                    "Token fetch failed: Invite code was not found."
                )
            }
            record = fetchedRecord
        } catch let error as CloudKitManagerError {
            throw error
        } catch {
            throw CloudKitManagerError.inviteTokenFetchFailed(
                "Token fetch failed: \(debugErrorDescription(error))"
            )
        }

        let token = try inviteToken(from: record)
        if token.isRevoked {
            throw CloudKitManagerError.inviteCodeRevoked
        }
        if token.isExpired(at: now) {
            throw CloudKitManagerError.inviteCodeExpired
        }
        if token.usesCount >= Self.inviteCodeMaxUses {
            throw CloudKitManagerError.inviteCodeUsageLimitReached
        }
        if isInviteTokenLocked(token, at: now) {
            throw CloudKitManagerError.inviteCodeLocked
        }
        return token
    }

    func resolveAcceptedShareContext(fromInviteCode rawCode: String) async throws -> AcceptedShareContext {
        try await checkAvailability()
        let normalizedCode = InviteInputNormalizer.normalizeInviteCodeToken(rawCode)
        if normalizedCode == nil {
            let shareURL: URL
            do {
                shareURL = try InviteInputNormalizer.normalizedURL(from: rawCode)
            } catch {
                throw HouseholdError.invalidInviteCode
            }

            let metadata = try await resolveJoinShareMetadata(for: shareURL)
            return try await acceptShareContext(
                metadata: metadata,
                shareURL: shareURL
            )
        }

        let now = Date()
        var stage = "inviteCode.redeem.attemptBudget"
        do {
            try enforceInviteRedeemAttemptBudget(at: now)

            guard let code = normalizedCode else {
                throw CloudKitManagerError.inviteCodeInvalid
            }

            stage = "inviteCode.redeem.fetchToken"
            let db = await publicDatabase
            logJoinStage("join.resolveInviteToken")
            let token = try await fetchRedeemableInviteToken(code: code, at: now, database: db)

            stage = "inviteCode.redeem.metadata"
            guard let shareURL = URL(string: token.shareURL) else {
                throw CloudKitManagerError.shareMetadataFetchFailed(
                    "Metadata fetch failed: Invite token contains an invalid share URL."
                )
            }
            print("CloudKitJoin: stage=join.resolveShareMetadata householdId=\(token.householdId)")

            let metadata = try await resolveJoinShareMetadata(
                for: shareURL,
                expectedHouseholdId: token.householdId
            )

            stage = "inviteCode.redeem.acceptShare"
            let context = try await acceptShareContext(
                metadata: metadata,
                shareURL: shareURL
            )

            stage = "inviteCode.redeem.usageUpdate"
            try await registerInviteRedeemSuccess(code: token.code, at: now, database: db)

            clearInviteRedeemAttemptBudget()
            clearCloudKitFailure()
            return context
        } catch {
            if let normalizedCode,
               shouldRegisterInviteFailureCounter(for: error)
            {
                let db = await publicDatabase
                await registerInviteRedeemFailure(code: normalizedCode, at: now, database: db)
            }
            recordCloudKitFailure(error, operation: stage)
            throw error
        }
    }

    func resolveAcceptedShareContext(metadata: CKShare.Metadata) async throws -> AcceptedShareContext {
        try await acceptShareContext(metadata: metadata, shareURL: nil)
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
        let context = try await acceptShareContext(metadata: metadata, shareURL: nil)
        return context.household
    }

    private func logJoinStage(
        _ stage: String,
        householdId: UUID? = nil,
        zoneID: CKRecordZone.ID? = nil,
        scope: HouseholdDatabaseScope? = nil,
        error: Error? = nil
    ) {
        let householdComponent = householdId?.uuidString ?? "unknown"
        let zoneComponent = zoneID?.zoneName ?? "unknown"
        let scopeComponent: String = if let scope {
            scope == .ownerPrivate ? "ownerPrivate" : "participantShared"
        } else {
            "unspecified"
        }

        if let error {
            print(
                "CloudKitJoin: stage=\(stage) householdId=\(householdComponent) zone=\(zoneComponent) scope=\(scopeComponent) error=\(debugErrorDescription(error))"
            )
        } else {
            print(
                "CloudKitJoin: stage=\(stage) householdId=\(householdComponent) zone=\(zoneComponent) scope=\(scopeComponent)"
            )
        }
    }

    private func acceptShareContext(
        metadata: CKShare.Metadata,
        shareURL: URL?
    ) async throws -> AcceptedShareContext {
        var stage: AcceptShareStage = .acceptOperation
        let householdId = UUID(uuidString: metadata.rootRecordID.recordName)
        let zoneID = metadata.rootRecordID.zoneID
        do {
            logJoinStage(
                "join.acceptShare",
                householdId: householdId,
                zoneID: zoneID,
                scope: .participantShared
            )
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
            if let householdId {
                setSharedZoneContext(householdId: householdId, zoneID: zoneID)
            }

            stage = .fetchRoot
            let db = await sharedDatabase
            logJoinStage(
                "join.acceptShare.fetchRoot",
                householdId: householdId,
                zoneID: zoneID,
                scope: .participantShared
            )
            let record: CKRecord
            do {
                record = try await fetchAcceptedRootRecord(metadata: metadata, database: db)
            } catch {
                throw CloudKitManagerError.sharedHouseholdFetchFailed(
                    "Shared household fetch failed: \(debugErrorDescription(error))"
                )
            }

            stage = .finalize
            if let householdId {
                rememberRecordZone(record, explicitHouseholdId: householdId)
            } else {
                rememberRecordZone(record, explicitHouseholdId: nil)
            }

            clearCloudKitFailure()
            let household = try household(from: record)
            return AcceptedShareContext(
                household: household,
                householdId: household.id,
                zoneID: zoneID,
                shareURL: shareURL
            )
        } catch {
            let wrappedError: Error = switch stage {
            case .acceptOperation:
                if error is CloudKitManagerError {
                    error
                } else {
                    CloudKitManagerError.acceptShareFailed(
                        "Accept share failed: \(debugErrorDescription(error))"
                    )
                }
            case .fetchRoot:
                if error is CloudKitManagerError {
                    error
                } else {
                    CloudKitManagerError.sharedHouseholdFetchFailed(
                        "Shared household fetch failed: \(debugErrorDescription(error))"
                    )
                }
            case .finalize:
                error
            }
            logJoinStage(
                "join.acceptShare.\(stage.rawValue)",
                householdId: householdId,
                zoneID: zoneID,
                scope: .participantShared,
                error: wrappedError
            )
            recordCloudKitFailure(wrappedError, operation: "acceptShare.\(stage.rawValue)")
            throw wrappedError
        }
    }

    private func fetchAcceptedRootRecord(
        metadata: CKShare.Metadata,
        database: CKDatabase
    ) async throws -> CKRecord {
        let backoffDelays: [UInt64] = [
            300_000_000,
            800_000_000,
            1_500_000_000,
        ]

        var lastError: Error?
        for attempt in 0 ..< backoffDelays.count {
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
        let context = try await resolveAcceptedShareContext(fromInviteCode: inviteCode)
        return context.household
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
