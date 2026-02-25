@testable import HousePulse
import Foundation
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

    func testBootstrapSuccessReturnsNormalMode() throws {
        let schema = Schema([CachedTask.self])
        let result = SwiftDataContainerFactory.bootstrap(
            schema: schema,
            dependencies: dependencies()
        )

        XCTAssertEqual(result.recoveryMode, .normal)
        XCTAssertNil(result.diagnosticMessage)
        XCTAssertNotNil(result.container.mainContext)
    }

    func testBootstrapAfterCleanupReturnsStoreResetMode() throws {
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
        XCTAssertNotNil(result.diagnosticMessage)

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.storeReset.rawValue)
    }

    func testBootstrapDoubleFailureReturnsInMemoryFallback() throws {
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

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(result.recoveryMode, .inMemoryFallback)
        XCTAssertNotNil(result.diagnosticMessage)

        let event = defaults.dictionary(forKey: SwiftDataContainerFactory.recoveryUserDefaultsKey)
        XCTAssertEqual(event?["mode"] as? String, StoreRecoveryMode.inMemoryFallback.rawValue)
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
