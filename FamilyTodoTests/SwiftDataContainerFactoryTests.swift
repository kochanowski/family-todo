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
        let schema = Schema([CachedTask.self])
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
        let schema = Schema([CachedTask.self])
        var attempts = 0
        var capturedModes: [String] = []

        _ = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { schema, configuration in
                    attempts += 1
                    capturedModes.append(String(describing: configuration.cloudKitDatabase).lowercased())
                    if attempts <= 2 {
                        throw NSError(domain: "SwiftDataContainerFactoryTests", code: 901)
                    }
                    return try Self.makeInMemoryContainer(schema: schema)
                }
            )
        )

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(capturedModes.count, 3)
        XCTAssertTrue(capturedModes.allSatisfy { $0.contains("none") })
    }

    func testBootstrapAfterCleanupReturnsStoreResetReadyMode() {
        let schema = Schema([CachedTask.self])
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
        XCTAssertEqual(result.recoveryMode, .storeReset)
        XCTAssertEqual(result.bootstrapState, .ready)
        XCTAssertNotNil(result.diagnosticMessage)
        XCTAssertNotNil(result.diagnostics)
        XCTAssertNotNil(result.container)

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.storeReset.rawValue)
    }

    func testBootstrapDoubleFailureReturnsInMemoryFallbackReadyMode() {
        let schema = Schema([CachedTask.self])
        var attempts = 0
        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { schema, _ in
                    attempts += 1
                    if attempts <= 2 {
                        throw NSError(domain: "SwiftDataContainerFactoryTests", code: 1002)
                    }
                    return try Self.makeInMemoryContainer(schema: schema)
                }
            )
        )

        XCTAssertGreaterThanOrEqual(attempts, 3)
        XCTAssertEqual(result.recoveryMode, .inMemoryFallback)
        XCTAssertEqual(result.bootstrapState, .ready)
        XCTAssertNotNil(result.diagnosticMessage)
        XCTAssertNotNil(result.diagnostics)
        XCTAssertNotNil(result.container)

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.inMemoryFallback.rawValue)
    }

    func testBootstrapTripleFailureReturnsSchemaFailureEmergencyMode() {
        let schema = Schema([CachedTask.self])
        var attempts = 0
        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { schema, _ in
                    attempts += 1
                    if attempts <= 3 {
                        throw NSError(domain: "SwiftDataContainerFactoryTests", code: 1003)
                    }
                    return try Self.makeInMemoryContainer(schema: schema)
                }
            )
        )

        XCTAssertGreaterThanOrEqual(attempts, 4)
        XCTAssertEqual(result.recoveryMode, .schemaFailure)
        XCTAssertEqual(result.bootstrapState, .emergency)
        XCTAssertNotNil(result.diagnosticMessage)
        XCTAssertNotNil(result.diagnostics)
        XCTAssertNotNil(result.container)
        XCTAssertEqual(result.diagnostics?.cloudKitDatabaseMode, "none")

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.schemaFailure.rawValue)
    }

    func testBootstrapSchemaFailureRecordsStagewiseDetailedErrors() {
        let schema = Schema([CachedTask.self])
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
        XCTAssertTrue(diagnostics.errorDetails.contains(where: { $0.stage == .persistentAfterCleanup }))
        XCTAssertTrue(diagnostics.errorDetails.contains(where: { $0.stage == .fullInMemory }))
        XCTAssertTrue(diagnostics.errorDetails.contains(where: { $0.stage == .emergencyInMemory }))
        XCTAssertTrue(diagnostics.errorDetails.allSatisfy { !$0.reflected.isEmpty })
    }

    func testProbeModelsIndividuallyStillWorksWithCloudKitNone() {
        let schema = Schema([CachedTask.self])
        var attempts = 0
        var probeModeSamples: [String] = []

        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies(
                containerBuilder: { _, configuration in
                    attempts += 1
                    if attempts > 3 {
                        probeModeSamples.append(String(describing: configuration.cloudKitDatabase).lowercased())
                    }
                    throw NSError(domain: "SwiftDataContainerFactoryTests", code: 2002)
                }
            )
        )

        XCTAssertEqual(result.recoveryMode, .schemaFailure)
        XCTAssertEqual(result.bootstrapState, .emergency)
        XCTAssertNil(result.container)
        XCTAssertGreaterThanOrEqual(probeModeSamples.count, 8)
        XCTAssertTrue(probeModeSamples.allSatisfy { $0.contains("none") })

        let probeErrors = result.diagnostics?.errorDetails.filter { $0.stage == .modelProbe } ?? []
        XCTAssertEqual(probeErrors.count, 8)
        XCTAssertTrue(probeErrors.allSatisfy { $0.modelName != nil })
    }

    func testEmergencyPathReturnsWithoutCrashWhenAllContainerBuildsFail() {
        let schema = Schema([CachedTask.self])

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
        XCTAssertFalse(defaults.bool(forKey: SwiftDataContainerFactory.pendingStoreResetUserDefaultsKey))

        SwiftDataContainerFactory.requestStoreReset(defaults)

        XCTAssertTrue(defaults.bool(forKey: SwiftDataContainerFactory.pendingStoreResetUserDefaultsKey))
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
}
