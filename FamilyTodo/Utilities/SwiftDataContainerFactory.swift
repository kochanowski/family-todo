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

enum BootstrapStage: String, Codable {
    case initialPersistent
    case persistentAfterCleanup
    case fullInMemory
    case emergencyInMemory
    case modelProbe
}

struct BootstrapErrorDetail: Codable {
    let stage: BootstrapStage
    let modelName: String?
    let summary: String
    let reflected: String
    let underlyingChain: [String]
}

struct BootstrapDiagnostics: Codable {
    let recoveryMode: StoreRecoveryMode
    let timestampISO8601: String
    let osVersion: String
    let cloudKitDatabaseMode: String
    let schemaModelNames: [String]
    let failingModelNames: [String]
    let errorChain: [String]
    let errorDetails: [BootstrapErrorDetail]
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
        let cloudKitDatabaseMode: String
    }

    static let recoveryUserDefaultsKey = "lastStoreRecoveryEvent"
    static let bootstrapDiagnosticsUserDefaultsKey = "lastStoreBootstrapDiagnostics"
    static let pendingStoreResetUserDefaultsKey = "pendingStoreReset"

    private static let legacyStorePrefix = "default.store"
    private static let runtimeStoreFileName = "HousePulse.store"
    private static let swiftDataCloudKitDatabaseMode = "none"
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
        let configuration = inMemoryConfiguration(schema: schema)
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
        var errorDetails: [BootstrapErrorDetail] = []

        if let container = attemptPersistentContainer(
            schema: schema,
            storeURL: context.storeURL,
            dependencies: dependencies,
            stage: .initialPersistent,
            failureLogPrefix: "initial persistent bootstrap failed",
            errorDetails: &errorDetails,
            cleanupURLOnFailure: context.appSupportURL
        ) {
            return readyResult(container: container, mode: .normal, message: nil, diagnostics: nil)
        }

        if let container = attemptPersistentContainer(
            schema: schema,
            storeURL: context.storeURL,
            dependencies: dependencies,
            stage: .persistentAfterCleanup,
            failureLogPrefix: "persistent bootstrap after cleanup failed",
            errorDetails: &errorDetails
        ) {
            return recoveredResult(
                container: container,
                mode: .storeReset,
                context: context,
                errorDetails: errorDetails,
                dependencies: dependencies
            )
        }

        if let container = attemptInMemoryContainer(
            schema: schema,
            dependencies: dependencies,
            stage: .fullInMemory,
            failureLogPrefix: "in-memory full schema bootstrap failed",
            errorDetails: &errorDetails
        ) {
            return recoveredResult(
                container: container,
                mode: .inMemoryFallback,
                context: context,
                errorDetails: errorDetails,
                dependencies: dependencies
            )
        }

        let failingModelNames = probeModelsIndividually(
            dependencies: dependencies,
            errorDetails: &errorDetails
        )
        return emergencyResult(
            context: context,
            failingModelNames: failingModelNames,
            dependencies: dependencies,
            errorDetails: &errorDetails
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
            timestamp: ISO8601DateFormatter().string(from: dependencies.now()),
            cloudKitDatabaseMode: swiftDataCloudKitDatabaseMode
        )
    }

    private static func attemptPersistentContainer(
        schema: Schema,
        storeURL: URL,
        dependencies: Dependencies,
        stage: BootstrapStage,
        failureLogPrefix: String,
        errorDetails: inout [BootstrapErrorDetail],
        cleanupURLOnFailure: URL? = nil
    ) -> ModelContainer? {
        let configuration = persistentConfiguration(schema: schema, storeURL: storeURL)
        do {
            return try dependencies.containerBuilder(schema, configuration)
        } catch {
            let detail = buildErrorDetail(stage: stage, error: error)
            errorDetails.append(detail)
            log("\(failureLogPrefix): \(detail.summary)")
            log("stage=\(detail.stage.rawValue) reflected=\(detail.reflected)")
            if !detail.underlyingChain.isEmpty {
                log("stage=\(detail.stage.rawValue) underlying=\(detail.underlyingChain.joined(separator: " || "))")
            }
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
        stage: BootstrapStage,
        failureLogPrefix: String,
        errorDetails: inout [BootstrapErrorDetail]
    ) -> ModelContainer? {
        let configuration = inMemoryConfiguration(schema: schema)
        do {
            return try dependencies.containerBuilder(schema, configuration)
        } catch {
            let detail = buildErrorDetail(stage: stage, error: error)
            errorDetails.append(detail)
            log("\(failureLogPrefix): \(detail.summary)")
            log("stage=\(detail.stage.rawValue) reflected=\(detail.reflected)")
            if !detail.underlyingChain.isEmpty {
                log("stage=\(detail.stage.rawValue) underlying=\(detail.underlyingChain.joined(separator: " || "))")
            }
            return nil
        }
    }

    private static func recoveredResult(
        container: ModelContainer,
        mode: StoreRecoveryMode,
        context: RuntimeBootstrapContext,
        errorDetails: [BootstrapErrorDetail],
        dependencies: Dependencies
    ) -> ModelContainerBootstrapResult {
        let diagnostics = makeDiagnostics(
            mode: mode,
            context: context,
            failingModelNames: [],
            errorDetails: errorDetails
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
        errorDetails: inout [BootstrapErrorDetail]
    ) -> ModelContainerBootstrapResult {
        let emergencySchema = Schema([StartupSentinel.self])
        let emergencyConfiguration = inMemoryConfiguration(schema: emergencySchema)

        do {
            let container = try dependencies.containerBuilder(emergencySchema, emergencyConfiguration)
            let diagnostics = makeDiagnostics(
                mode: .schemaFailure,
                context: context,
                failingModelNames: failingModelNames,
                errorDetails: errorDetails
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
            let detail = buildErrorDetail(stage: .emergencyInMemory, error: error)
            errorDetails.append(detail)
            log("emergency bootstrap failed: \(detail.summary)")
            log("stage=\(detail.stage.rawValue) reflected=\(detail.reflected)")
            if !detail.underlyingChain.isEmpty {
                log("stage=\(detail.stage.rawValue) underlying=\(detail.underlyingChain.joined(separator: " || "))")
            }
            let diagnostics = makeDiagnostics(
                mode: .schemaFailure,
                context: context,
                failingModelNames: failingModelNames,
                errorDetails: errorDetails
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
        errorDetails: [BootstrapErrorDetail]
    ) -> BootstrapDiagnostics {
        BootstrapDiagnostics(
            recoveryMode: mode,
            timestampISO8601: context.timestamp,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            cloudKitDatabaseMode: context.cloudKitDatabaseMode,
            schemaModelNames: context.schemaModelNames,
            failingModelNames: failingModelNames,
            errorChain: errorDetails.map(\.summary),
            errorDetails: errorDetails
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
        dependencies: Dependencies,
        errorDetails: inout [BootstrapErrorDetail]
    ) -> [String] {
        var failingModels: [String] = []
        for probe in runtimeModelProbes {
            let probeSchema = probe.makeSchema()
            let probeConfiguration = inMemoryConfiguration(schema: probeSchema)
            do {
                _ = try dependencies.containerBuilder(probeSchema, probeConfiguration)
            } catch {
                let detail = buildErrorDetail(
                    stage: .modelProbe,
                    modelName: probe.name,
                    error: error
                )
                errorDetails.append(detail)
                failingModels.append(probe.name)
                log("model probe failed for \(probe.name): \(detail.summary)")
                log("stage=\(detail.stage.rawValue) model=\(probe.name) reflected=\(detail.reflected)")
                if !detail.underlyingChain.isEmpty {
                    log("stage=\(detail.stage.rawValue) model=\(probe.name) underlying=\(detail.underlyingChain.joined(separator: " || "))")
                }
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
        localOnlyConfiguration(
            schema: schema,
            storeURL: storeURL,
            isStoredInMemoryOnly: false
        )
    }

    private static func inMemoryConfiguration(schema: Schema) -> ModelConfiguration {
        localOnlyConfiguration(
            schema: schema,
            storeURL: nil,
            isStoredInMemoryOnly: true
        )
    }

    private static func localOnlyConfiguration(
        schema: Schema,
        storeURL: URL?,
        isStoredInMemoryOnly: Bool
    ) -> ModelConfiguration {
        if let storeURL {
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        }

        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
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
            "cloudKitDatabaseMode": diagnostics.cloudKitDatabaseMode,
            "schemaModels": diagnostics.schemaModelNames.joined(separator: ","),
            "failingModels": diagnostics.failingModelNames.joined(separator: ","),
            "errorCount": diagnostics.errorChain.count,
            "lastError": diagnostics.errorChain.last ?? "",
            "lastStage": diagnostics.errorDetails.last?.stage.rawValue ?? "",
            "lastReflectedError": diagnostics.errorDetails.last?.reflected ?? "",
            "lastUnderlyingError": diagnostics.errorDetails.last?.underlyingChain.last ?? "",
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

    private static func buildErrorDetail(
        stage: BootstrapStage,
        modelName: String? = nil,
        error: Error
    ) -> BootstrapErrorDetail {
        BootstrapErrorDetail(
            stage: stage,
            modelName: modelName,
            summary: detailedErrorDescription(error),
            reflected: String(reflecting: error),
            underlyingChain: underlyingErrorChain(from: error)
        )
    }

    private static func underlyingErrorChain(from error: Error) -> [String] {
        var chain: [String] = []
        var current = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError

        while let currentError = current {
            var parts: [String] = [
                "domain=\(currentError.domain)",
                "code=\(currentError.code)",
                "description=\(currentError.localizedDescription)",
            ]
            if let reason = currentError.localizedFailureReason, !reason.isEmpty {
                parts.append("reason=\(reason)")
            }
            chain.append(parts.joined(separator: " | "))
            current = currentError.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return chain
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
