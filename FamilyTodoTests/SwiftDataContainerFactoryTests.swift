import Foundation
@testable import HousePulse
import SwiftData
import XCTest

@MainActor
final class SwiftDataContainerFactoryTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataContainerFactoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        defaultsSuiteName = "SwiftDataContainerFactoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil

        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testBootstrapSuccessReturnsReadyNormalMode() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies()
        )

        XCTAssertEqual(result.recoveryMode, .normal)
        XCTAssertEqual(result.bootstrapState, .ready)
        XCTAssertNil(result.diagnosticMessage)
        XCTAssertNil(result.diagnostics)
        XCTAssertNotNil(result.container)
    }

    func testBootstrapUsesCloudKitNoneForPersistentAndInMemoryPaths() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        var attempts = 0
        var capturedModes: [String] = []

        _ = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { schema, configuration in
                    attempts += 1
                    capturedModes.append(String(describing: configuration.cloudKitDatabase).lowercased())
                    if attempts == 1 {
                        throw NSError(domain: "SwiftDataContainerFactoryTests", code: 901)
                    }
                    return try Self.makeInMemoryContainer(schema: schema)
                }
            )
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(capturedModes.count, 2)
        XCTAssertTrue(capturedModes.allSatisfy { $0.contains("none") })
    }

    func testBootstrapAfterExplicitResetReturnsStoreResetReadyMode() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        let staleArtifactURL = tempDirectoryURL.appendingPathComponent("default.store-wal")
        FileManager.default.createFile(atPath: staleArtifactURL.path, contents: Data())
        SwiftDataContainerFactory.requestStoreReset(reason: .hardResetApp, defaults)

        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies()
        )

        XCTAssertEqual(result.recoveryMode, .storeReset)
        XCTAssertEqual(result.bootstrapState, .ready)
        XCTAssertNil(result.diagnosticMessage)
        XCTAssertNil(result.diagnostics)
        XCTAssertNotNil(result.container)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleArtifactURL.path))
        XCTAssertNil(defaults.data(forKey: SwiftDataContainerFactory.pendingStoreResetUserDefaultsKey))
    }

    func testBootstrapPersistentFailureReturnsRecoveryRequiredWithoutDeletingArtifacts() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        let staleArtifactURL = tempDirectoryURL.appendingPathComponent("default.store-wal")
        FileManager.default.createFile(atPath: staleArtifactURL.path, contents: Data())
        var attempts = 0

        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { schema, _ in
                    attempts += 1
                    if attempts == 1 {
                        throw NSError(domain: "SwiftDataContainerFactoryTests", code: 1001)
                    }
                    return try Self.makeInMemoryContainer(schema: schema)
                }
            )
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(result.recoveryMode, .recoveryRequired)
        XCTAssertEqual(result.bootstrapState, .recoveryRequired)
        XCTAssertNotNil(result.diagnosticMessage)
        XCTAssertNotNil(result.diagnostics)
        XCTAssertNil(result.container)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleArtifactURL.path))

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.recoveryRequired.rawValue)
    }

    func testBootstrapTripleFailureReturnsSchemaFailureEmergencyMode() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        var attempts = 0
        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { _, _ in
                    attempts += 1
                    throw NSError(domain: "SwiftDataContainerFactoryTests", code: 1003)
                }
            )
        )

        XCTAssertGreaterThanOrEqual(attempts, 4)
        XCTAssertEqual(result.recoveryMode, .schemaFailure)
        XCTAssertEqual(result.bootstrapState, .emergency)
        XCTAssertNotNil(result.diagnosticMessage)
        XCTAssertNotNil(result.diagnostics)
        XCTAssertNil(result.container)
        XCTAssertEqual(result.diagnostics?.cloudKitDatabaseMode, "none")

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.schemaFailure.rawValue)
    }

    func testBootstrapSchemaFailureRecordsStagewiseDetailedErrors() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { _, _ in
                    throw NSError(domain: "SwiftDataContainerFactoryTests", code: 2001)
                }
            )
        )

        XCTAssertEqual(result.recoveryMode, .schemaFailure)
        XCTAssertEqual(result.bootstrapState, .emergency)
        XCTAssertNil(result.container)

        guard let diagnostics = result.diagnostics else {
            XCTFail("Expected diagnostics for schema failure")
            return
        }

        XCTAssertEqual(diagnostics.cloudKitDatabaseMode, "none")
        XCTAssertEqual(diagnostics.errorChain, diagnostics.errorDetails.map(\.summary))
        XCTAssertTrue(diagnostics.errorDetails.contains(where: { $0.stage == .initialPersistent }))
        XCTAssertTrue(diagnostics.errorDetails.contains(where: { $0.stage == .fullInMemory }))
        XCTAssertTrue(diagnostics.errorDetails.contains(where: { $0.stage == .emergencyInMemory }))
        XCTAssertTrue(diagnostics.errorDetails.allSatisfy { !$0.reflected.isEmpty })
    }

    func testProbeModelsIndividuallyStillWorksWithCloudKitNone() {
        let schema = TestModelContainerFactory.schema(for: .appCache)
        var attempts = 0
        var probeModeSamples: [String] = []

        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { _, configuration in
                    attempts += 1
                    if attempts > 2 {
                        probeModeSamples.append(String(describing: configuration.cloudKitDatabase).lowercased())
                    }
                    throw NSError(domain: "SwiftDataContainerFactoryTests", code: 2002)
                }
            )
        )

        XCTAssertEqual(result.recoveryMode, .schemaFailure)
        XCTAssertEqual(result.bootstrapState, .emergency)
        XCTAssertNil(result.container)
        XCTAssertGreaterThanOrEqual(probeModeSamples.count, 10)
        XCTAssertTrue(probeModeSamples.allSatisfy { $0.contains("none") })

        let probeErrors = result.diagnostics?.errorDetails.filter { $0.stage == .modelProbe } ?? []
        XCTAssertEqual(probeErrors.count, 10)
        XCTAssertTrue(probeErrors.allSatisfy { $0.modelName != nil })
    }

    func testEmergencyPathReturnsWithoutCrashWhenAllContainerBuildsFail() {
        let schema = TestModelContainerFactory.schema(for: .appCache)

        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { _, _ in
                    throw NSError(domain: "SwiftDataContainerFactoryTests", code: 2003)
                }
            )
        )

        XCTAssertEqual(result.recoveryMode, .schemaFailure)
        XCTAssertEqual(result.bootstrapState, .emergency)
        XCTAssertNil(result.container)
        XCTAssertNotNil(result.diagnosticMessage)
        XCTAssertNotNil(result.diagnostics)
    }

    func testCleanupRemovesLegacyAndCurrentStoreArtifacts() throws {
        let removableNames = [
            "default.store",
            "default.store-wal",
            "cache.store",
            "cache.store-shm",
            "cache.sqlite",
            "cache.sqlite-wal",
        ]
        let keptNames = [
            "notes.txt",
            "image.png",
        ]

        for name in removableNames {
            FileManager.default.createFile(
                atPath: tempDirectoryURL.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        for name in keptNames {
            FileManager.default.createFile(
                atPath: tempDirectoryURL.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        let supportDirectory = tempDirectoryURL.appendingPathComponent("HousePulse_SUPPORT")
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: supportDirectory.appendingPathComponent("orphan.dat").path,
            contents: Data()
        )

        let removed = SwiftDataContainerFactory.cleanupStoreArtifacts(in: tempDirectoryURL)
        let removedNames = Set(removed.map(\.lastPathComponent))

        for name in removableNames {
            XCTAssertTrue(removedNames.contains(name))
            XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectoryURL.appendingPathComponent(name).path))
        }

        XCTAssertTrue(removedNames.contains("HousePulse_SUPPORT"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportDirectory.path))

        for name in keptNames {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectoryURL.appendingPathComponent(name).path))
        }
    }

    func testRequestStoreResetSetsFlag() {
        XCTAssertNil(defaults.data(forKey: SwiftDataContainerFactory.pendingStoreResetUserDefaultsKey))

        SwiftDataContainerFactory.requestStoreReset(reason: .debugCloudHouseholdDelete, defaults)

        let request = decodePendingResetRequest()
        XCTAssertEqual(request?.reason, .debugCloudHouseholdDelete)
    }

    private func dependencies(
        containerBuilder: @escaping SwiftDataContainerFactory.ContainerBuilder = { schema, configuration in
            try ModelContainer(for: schema, configurations: [configuration])
        }
    ) -> SwiftDataContainerFactory.Dependencies {
        SwiftDataContainerFactory.Dependencies(
            fileManager: .default,
            userDefaults: defaults,
            now: { Date(timeIntervalSince1970: 1_735_660_800) },
            containerBuilder: containerBuilder,
            appSupportURLProvider: { _ in self.tempDirectoryURL }
        )
    }

    private static func makeInMemoryContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func decodePendingResetRequest() -> PendingStoreResetRequest? {
        guard let data = defaults.data(forKey: SwiftDataContainerFactory.pendingStoreResetUserDefaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(PendingStoreResetRequest.self, from: data)
    }
}
