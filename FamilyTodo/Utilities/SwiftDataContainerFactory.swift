import Foundation
import SwiftData

enum StoreRecoveryMode: String, Codable {
    case normal
    case storeReset
    case inMemoryFallback
    case schemaFailure
}

enum StartupBootstrapState: String, Codable {
    case ready
    case emergency
}

struct BootstrapDiagnostics: Codable {
    let recoveryMode: StoreRecoveryMode
    let timestampISO8601: String
    let osVersion: String
    let schemaModelNames: [String]
    let failingModelNames: [String]
    let errorChain: [String]
}

struct ModelContainerBootstrapResult {
    let container: ModelContainer?
    let recoveryMode: StoreRecoveryMode
    let diagnosticMessage: String?
    let bootstrapState: StartupBootstrapState
    let diagnostics: BootstrapDiagnostics?
}

enum SwiftDataContainerFactory {
    typealias ContainerBuilder = (Schema, ModelConfiguration) throws -> ModelContainer
    typealias AppSupportURLProvider = (FileManager) -> URL

    static let recoveryUserDefaultsKey = "lastStoreRecoveryEvent"
    static let bootstrapDiagnosticsUserDefaultsKey = "lastStoreBootstrapDiagnostics"
    static let pendingStoreResetUserDefaultsKey = "pendingStoreReset"

    private static let legacyStorePrefix = "default.store"
    private static let runtimeStoreFileName = "HousePulse.store"
    private static let recoveryMessage =
        "Wykryto problem lokalnej bazy. Cache został odtworzony. Dane w chmurze zsynchronizują się automatycznie."
    private static let emergencyMessage =
        "Wykryto krytyczny problem lokalnej bazy. Aplikacja uruchomiona w trybie awaryjnym."
    private static let removableStoreSuffixes = [
        ".store",
        ".store-shm",
        ".store-wal",
        ".sqlite",
        ".sqlite-shm",
        ".sqlite-wal",
    ]

    private struct ModelSchemaProbe {
        let name: String
        let makeSchema: () -> Schema
    }

    private static let runtimeModelProbes: [ModelSchemaProbe] = [
        .init(name: "CachedTask", makeSchema: { Schema([CachedTask.self]) }),
        .init(name: "CachedMember", makeSchema: { Schema([CachedMember.self]) }),
        .init(name: "CachedShoppingItem", makeSchema: { Schema([CachedShoppingItem.self]) }),
        .init(name: "CachedBacklogCategory", makeSchema: { Schema([CachedBacklogCategory.self]) }),
        .init(name: "CachedBacklogItem", makeSchema: { Schema([CachedBacklogItem.self]) }),
        .init(name: "CachedHousehold", makeSchema: { Schema([CachedHousehold.self]) }),
        .init(name: "CachedArea", makeSchema: { Schema([CachedArea.self]) }),
        .init(name: "CachedRecurringChore", makeSchema: { Schema([CachedRecurringChore.self]) }),
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

    static func requestStoreReset(_ userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: pendingStoreResetUserDefaultsKey)
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
                diagnosticMessage: nil,
                bootstrapState: .ready,
                diagnostics: nil
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

        let schemaModelNames = runtimeModelProbes.map(\.name)
        let timestamp = ISO8601DateFormatter().string(from: dependencies.now())
        let storeURL = appSupportURL.appendingPathComponent(runtimeStoreFileName)

        if dependencies.userDefaults.bool(forKey: pendingStoreResetUserDefaultsKey) {
            log("pending reset flag detected, clearing local store artifacts before bootstrap")
            _ = cleanupStoreArtifacts(in: appSupportURL, using: dependencies.fileManager)
            dependencies.userDefaults.removeObject(forKey: pendingStoreResetUserDefaultsKey)
        }

        dependencies.userDefaults.removeObject(forKey: bootstrapDiagnosticsUserDefaultsKey)
        dependencies.userDefaults.removeObject(forKey: recoveryUserDefaultsKey)

        var errorChain: [String] = []

        do {
            let container = try dependencies.containerBuilder(
                schema,
                persistentConfiguration(schema: schema, storeURL: storeURL)
            )
            return ModelContainerBootstrapResult(
                container: container,
                recoveryMode: .normal,
                diagnosticMessage: nil,
                bootstrapState: .ready,
                diagnostics: nil
            )
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("initial persistent bootstrap failed: \(details)")
            let removedArtifacts = cleanupStoreArtifacts(in: appSupportURL, using: dependencies.fileManager)
            log("cleanup removed \(removedArtifacts.count) artifacts")
        }

        do {
            let container = try dependencies.containerBuilder(
                schema,
                persistentConfiguration(schema: schema, storeURL: storeURL)
            )
            let diagnostics = BootstrapDiagnostics(
                recoveryMode: .storeReset,
                timestampISO8601: timestamp,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                schemaModelNames: schemaModelNames,
                failingModelNames: [],
                errorChain: errorChain
            )
            persistRecoveryEvent(mode: .storeReset, diagnostics: diagnostics, dependencies: dependencies)
            return ModelContainerBootstrapResult(
                container: container,
                recoveryMode: .storeReset,
                diagnosticMessage: recoveryMessage,
                bootstrapState: .ready,
                diagnostics: diagnostics
            )
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("persistent bootstrap after cleanup failed: \(details)")
        }

        do {
            let container = try dependencies.containerBuilder(
                schema,
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            let diagnostics = BootstrapDiagnostics(
                recoveryMode: .inMemoryFallback,
                timestampISO8601: timestamp,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                schemaModelNames: schemaModelNames,
                failingModelNames: [],
                errorChain: errorChain
            )
            persistRecoveryEvent(mode: .inMemoryFallback, diagnostics: diagnostics, dependencies: dependencies)
            return ModelContainerBootstrapResult(
                container: container,
                recoveryMode: .inMemoryFallback,
                diagnosticMessage: recoveryMessage,
                bootstrapState: .ready,
                diagnostics: diagnostics
            )
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("in-memory full schema bootstrap failed: \(details)")
        }

        let failingModelNames = probeModelsIndividually(dependencies: dependencies)

        do {
            let emergencySchema = Schema([StartupSentinel.self])
            let emergencyConfiguration = ModelConfiguration(
                schema: emergencySchema,
                isStoredInMemoryOnly: true
            )
            let emergencyContainer = try dependencies.containerBuilder(emergencySchema, emergencyConfiguration)
            let diagnostics = BootstrapDiagnostics(
                recoveryMode: .schemaFailure,
                timestampISO8601: timestamp,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                schemaModelNames: schemaModelNames,
                failingModelNames: failingModelNames,
                errorChain: errorChain
            )
            persistRecoveryEvent(mode: .schemaFailure, diagnostics: diagnostics, dependencies: dependencies)
            return ModelContainerBootstrapResult(
                container: emergencyContainer,
                recoveryMode: .schemaFailure,
                diagnosticMessage: emergencyMessage,
                bootstrapState: .emergency,
                diagnostics: diagnostics
            )
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("emergency bootstrap failed: \(details)")
            let diagnostics = BootstrapDiagnostics(
                recoveryMode: .schemaFailure,
                timestampISO8601: timestamp,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                schemaModelNames: schemaModelNames,
                failingModelNames: failingModelNames,
                errorChain: errorChain
            )
            persistRecoveryEvent(mode: .schemaFailure, diagnostics: diagnostics, dependencies: dependencies)
            return ModelContainerBootstrapResult(
                container: nil,
                recoveryMode: .schemaFailure,
                diagnosticMessage: emergencyMessage,
                bootstrapState: .emergency,
                diagnostics: diagnostics
            )
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
                log("failed to remove artifact \(name): \(detailedErrorDescription(error))")
            }
        }

        return removed
    }

    private static func probeModelsIndividually(
        dependencies: Dependencies
    ) -> [String] {
        var failingModels: [String] = []
        for probe in runtimeModelProbes {
            let probeSchema = probe.makeSchema()
            let probeConfiguration = ModelConfiguration(
                schema: probeSchema,
                isStoredInMemoryOnly: true
            )
            do {
                _ = try dependencies.containerBuilder(probeSchema, probeConfiguration)
            } catch {
                failingModels.append(probe.name)
                log("model probe failed for \(probe.name): \(detailedErrorDescription(error))")
            }
        }
        return failingModels
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
        diagnostics: BootstrapDiagnostics,
        dependencies: Dependencies
    ) {
        let payload: [String: Any] = [
            "mode": mode.rawValue,
            "timestamp": diagnostics.timestampISO8601,
            "osVersion": diagnostics.osVersion,
            "schemaModels": diagnostics.schemaModelNames.joined(separator: ","),
            "failingModels": diagnostics.failingModelNames.joined(separator: ","),
            "errorCount": diagnostics.errorChain.count,
            "lastError": diagnostics.errorChain.last ?? "",
        ]
        dependencies.userDefaults.set(payload, forKey: recoveryUserDefaultsKey)

        if let data = try? JSONEncoder().encode(diagnostics),
           let json = String(data: data, encoding: .utf8) {
            dependencies.userDefaults.set(json, forKey: bootstrapDiagnosticsUserDefaultsKey)
        }
    }

    private static func detailedErrorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)",
        ]
        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            parts.append("reason=\(reason)")
        }
        if !nsError.userInfo.isEmpty {
            parts.append("userInfo=\(String(describing: nsError.userInfo))")
        }
        return parts.joined(separator: " | ")
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
