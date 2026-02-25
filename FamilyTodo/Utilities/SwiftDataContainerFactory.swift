import Foundation
import SwiftData

enum StoreRecoveryMode: String {
    case normal
    case storeReset
    case inMemoryFallback
}

struct ModelContainerBootstrapResult {
    let container: ModelContainer
    let recoveryMode: StoreRecoveryMode
    let diagnosticMessage: String?
}

enum SwiftDataContainerFactory {
    typealias ContainerBuilder = (Schema, ModelConfiguration) throws -> ModelContainer
    typealias AppSupportURLProvider = (FileManager) -> URL

    static let recoveryUserDefaultsKey = "lastStoreRecoveryEvent"
    private static let legacyStorePrefix = "default.store"
    private static let runtimeStoreFileName = "HousePulse.store"
    private static let diagnosticMessage =
        "Wykryto problem lokalnej bazy. Cache został odtworzony. Dane w chmurze zsynchronizują się automatycznie."
    private static let removableStoreSuffixes = [
        ".store",
        ".store-shm",
        ".store-wal",
        ".sqlite",
        ".sqlite-shm",
        ".sqlite-wal",
    ]

    struct Dependencies {
        var fileManager: FileManager
        var userDefaults: UserDefaults
        var now: () -> Date
        var containerBuilder: ContainerBuilder
        var appSupportURLProvider: AppSupportURLProvider

        init(
            fileManager: FileManager = .default,
            userDefaults: UserDefaults = .standard,
            now: @escaping () -> Date = Date.init,
            containerBuilder: @escaping ContainerBuilder = defaultContainerBuilder,
            appSupportURLProvider: @escaping AppSupportURLProvider = defaultAppSupportURL(using:)
        ) {
            self.fileManager = fileManager
            self.userDefaults = userDefaults
            self.now = now
            self.containerBuilder = containerBuilder
            self.appSupportURLProvider = appSupportURLProvider
        }
    }

    static func bootstrap(
        schema: Schema,
        isCI: Bool = false,
        dependencies: Dependencies = .init()
    ) -> ModelContainerBootstrapResult {
        if isCI {
            return bootstrapForCI(schema: schema, dependencies: dependencies)
        }
        return bootstrapForRuntime(schema: schema, dependencies: dependencies)
    }

    private static func bootstrapForCI(
        schema: Schema,
        dependencies: Dependencies
    ) -> ModelContainerBootstrapResult {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try dependencies.containerBuilder(schema, configuration)
            return ModelContainerBootstrapResult(
                container: container,
                recoveryMode: .normal,
                diagnosticMessage: nil
            )
        } catch {
            fatalError("Could not create CI ModelContainer: \(error)")
        }
    }

    private static func bootstrapForRuntime(
        schema: Schema,
        dependencies: Dependencies
    ) -> ModelContainerBootstrapResult {
        let appSupportURL = dependencies.appSupportURLProvider(dependencies.fileManager)
        try? dependencies.fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )
        let storeURL = appSupportURL.appendingPathComponent(runtimeStoreFileName)

        do {
            let container = try dependencies.containerBuilder(
                schema,
                persistentConfiguration(schema: schema, storeURL: storeURL)
            )
            return ModelContainerBootstrapResult(
                container: container,
                recoveryMode: .normal,
                diagnosticMessage: nil
            )
        } catch {
            log("initial persistent bootstrap failed: \(shortErrorDescription(error))")
            let removedArtifacts = cleanupStoreArtifacts(in: appSupportURL, using: dependencies.fileManager)
            log("cleanup removed \(removedArtifacts.count) artifacts")

            do {
                let container = try dependencies.containerBuilder(
                    schema,
                    persistentConfiguration(schema: schema, storeURL: storeURL)
                )
                persistRecoveryEvent(
                    mode: .storeReset,
                    error: error,
                    dependencies: dependencies
                )
                return ModelContainerBootstrapResult(
                    container: container,
                    recoveryMode: .storeReset,
                    diagnosticMessage: diagnosticMessage
                )
            } catch {
                log("persistent bootstrap after cleanup failed: \(shortErrorDescription(error))")
                do {
                    let container = try dependencies.containerBuilder(
                        schema,
                        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    )
                    persistRecoveryEvent(
                        mode: .inMemoryFallback,
                        error: error,
                        dependencies: dependencies
                    )
                    return ModelContainerBootstrapResult(
                        container: container,
                        recoveryMode: .inMemoryFallback,
                        diagnosticMessage: diagnosticMessage
                    )
                } catch {
                    fatalError("Could not create ModelContainer including in-memory fallback: \(error)")
                }
            }
        }
    }

    @discardableResult
    static func cleanupStoreArtifacts(
        in appSupportURL: URL,
        using fileManager: FileManager = .default
    ) -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: appSupportURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var removed: [URL] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory ?? false
            let name = url.lastPathComponent
            guard shouldRemoveArtifact(named: name, isDirectory: isDirectory) else { continue }
            do {
                try fileManager.removeItem(at: url)
                removed.append(url)
                log("removed artifact: \(name)")
            } catch {
                log("failed to remove artifact \(name): \(shortErrorDescription(error))")
            }
        }

        return removed
    }

    private static func shouldRemoveArtifact(named name: String, isDirectory: Bool) -> Bool {
        if name.hasPrefix(legacyStorePrefix) {
            return true
        }
        if removableStoreSuffixes.contains(where: { name.hasSuffix($0) }) {
            return true
        }
        if isDirectory, name.hasSuffix("_SUPPORT") {
            return true
        }
        return false
    }

    private static func persistentConfiguration(schema: Schema, storeURL: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: storeURL)
    }

    private static func persistRecoveryEvent(
        mode: StoreRecoveryMode,
        error: Error,
        dependencies: Dependencies
    ) {
        let timestamp = ISO8601DateFormatter().string(from: dependencies.now())
        let payload: [String: String] = [
            "mode": mode.rawValue,
            "timestamp": timestamp,
            "error": shortErrorDescription(error),
        ]
        dependencies.userDefaults.set(payload, forKey: recoveryUserDefaultsKey)
    }

    private static func shortErrorDescription(_ error: Error) -> String {
        let description = String(describing: error)
        return String(description.prefix(160))
    }

    private static func log(_ message: String) {
        print("StoreRecovery: \(message)")
    }

    private static func defaultContainerBuilder(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func defaultAppSupportURL(using fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}
