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

    private struct RuntimeBootstrapContext {
        let appSupportURL: URL
        let storeURL: URL
        let schemaModelNames: [String]
        let timestamp: String
    }

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
        let context = prepareRuntimeContext(dependencies: dependencies)
        var errorChain: [String] = []

        if let container = attemptPersistentContainer(
            schema: schema,
            storeURL: context.storeURL,
            dependencies: dependencies,
            failureLogPrefix: "initial persistent bootstrap failed",
            errorChain: &errorChain,
            cleanupURLOnFailure: context.appSupportURL
        ) {
            return readyResult(container: container, mode: .normal, message: nil, diagnostics: nil)
        }

        if let container = attemptPersistentContainer(
            schema: schema,
            storeURL: context.storeURL,
            dependencies: dependencies,
            failureLogPrefix: "persistent bootstrap after cleanup failed",
            errorChain: &errorChain
        ) {
            return recoveredResult(
                container: container,
                mode: .storeReset,
                context: context,
                errorChain: errorChain,
                dependencies: dependencies
            )
        }

        if let container = attemptInMemoryContainer(
            schema: schema,
            dependencies: dependencies,
            failureLogPrefix: "in-memory full schema bootstrap failed",
            errorChain: &errorChain
        ) {
            return recoveredResult(
                container: container,
                mode: .inMemoryFallback,
                context: context,
                errorChain: errorChain,
                dependencies: dependencies
            )
        }

        let failingModelNames = probeModelsIndividually(dependencies: dependencies)
        return emergencyResult(
            context: context,
            failingModelNames: failingModelNames,
            dependencies: dependencies,
            errorChain: &errorChain
        )
    }

    private static func prepareRuntimeContext(
        dependencies: Dependencies
    ) -> RuntimeBootstrapContext {
        let appSupportURL = dependencies.appSupportURLProvider(dependencies.fileManager)
        try? dependencies.fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        if dependencies.userDefaults.bool(forKey: pendingStoreResetUserDefaultsKey) {
            log("pending reset flag detected, clearing local store artifacts before bootstrap")
            _ = cleanupStoreArtifacts(in: appSupportURL, using: dependencies.fileManager)
            dependencies.userDefaults.removeObject(forKey: pendingStoreResetUserDefaultsKey)
        }

        dependencies.userDefaults.removeObject(forKey: bootstrapDiagnosticsUserDefaultsKey)
        dependencies.userDefaults.removeObject(forKey: recoveryUserDefaultsKey)

        return RuntimeBootstrapContext(
            appSupportURL: appSupportURL,
            storeURL: appSupportURL.appendingPathComponent(runtimeStoreFileName),
            schemaModelNames: runtimeModelProbes.map(\.name),
            timestamp: ISO8601DateFormatter().string(from: dependencies.now())
        )
    }

    private static func attemptPersistentContainer(
        schema: Schema,
        storeURL: URL,
        dependencies: Dependencies,
        failureLogPrefix: String,
        errorChain: inout [String],
        cleanupURLOnFailure: URL? = nil
    ) -> ModelContainer? {
        let configuration = persistentConfiguration(schema: schema, storeURL: storeURL)
        do {
            return try dependencies.containerBuilder(schema, configuration)
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("\(failureLogPrefix): \(details)")
            if let cleanupURLOnFailure {
                let removedArtifacts = cleanupStoreArtifacts(
                    in: cleanupURLOnFailure,
                    using: dependencies.fileManager
                )
                log("cleanup removed \(removedArtifacts.count) artifacts")
            }
            return nil
        }
    }

    private static func attemptInMemoryContainer(
        schema: Schema,
        dependencies: Dependencies,
        failureLogPrefix: String,
        errorChain: inout [String]
    ) -> ModelContainer? {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try dependencies.containerBuilder(schema, configuration)
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("\(failureLogPrefix): \(details)")
            return nil
        }
    }

    private static func recoveredResult(
        container: ModelContainer,
        mode: StoreRecoveryMode,
        context: RuntimeBootstrapContext,
        errorChain: [String],
        dependencies: Dependencies
    ) -> ModelContainerBootstrapResult {
        let diagnostics = makeDiagnostics(
            mode: mode,
            context: context,
            failingModelNames: [],
            errorChain: errorChain
        )
        persistRecoveryEvent(mode: mode, diagnostics: diagnostics, dependencies: dependencies)
        return readyResult(
            container: container,
            mode: mode,
            message: recoveryMessage,
            diagnostics: diagnostics
        )
    }

    private static func emergencyResult(
        context: RuntimeBootstrapContext,
        failingModelNames: [String],
        dependencies: Dependencies,
        errorChain: inout [String]
    ) -> ModelContainerBootstrapResult {
        let emergencySchema = Schema([StartupSentinel.self])
        let emergencyConfiguration = ModelConfiguration(
            schema: emergencySchema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try dependencies.containerBuilder(emergencySchema, emergencyConfiguration)
            let diagnostics = makeDiagnostics(
                mode: .schemaFailure,
                context: context,
                failingModelNames: failingModelNames,
                errorChain: errorChain
            )
            persistRecoveryEvent(mode: .schemaFailure, diagnostics: diagnostics, dependencies: dependencies)
            return ModelContainerBootstrapResult(
                container: container,
                recoveryMode: .schemaFailure,
                diagnosticMessage: emergencyMessage,
                bootstrapState: .emergency,
                diagnostics: diagnostics
            )
        } catch {
            let details = detailedErrorDescription(error)
            errorChain.append(details)
            log("emergency bootstrap failed: \(details)")
            let diagnostics = makeDiagnostics(
                mode: .schemaFailure,
                context: context,
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

    private static func makeDiagnostics(
        mode: StoreRecoveryMode,
        context: RuntimeBootstrapContext,
        failingModelNames: [String],
        errorChain: [String]
    ) -> BootstrapDiagnostics {
        BootstrapDiagnostics(
            recoveryMode: mode,
            timestampISO8601: context.timestamp,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            schemaModelNames: context.schemaModelNames,
            failingModelNames: failingModelNames,
            errorChain: errorChain
        )
    }

    private static func readyResult(
        container: ModelContainer,
        mode: StoreRecoveryMode,
        message: String?,
        diagnostics: BootstrapDiagnostics?
    ) -> ModelContainerBootstrapResult {
        ModelContainerBootstrapResult(
            container: container,
            recoveryMode: mode,
            diagnosticMessage: message,
            bootstrapState: .ready,
            diagnostics: diagnostics
        )
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
