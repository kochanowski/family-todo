import Foundation
@testable import HousePulse
import SwiftData

enum TestModelContainerFactory {
    enum SchemaProfile {
        case appCache
        case workItems
        case shopping
        case bundles
        case household
        case members
        case bootstrapProbe
    }

    static func makeInMemoryContainer(profile: SchemaProfile = .appCache) throws -> ModelContainer {
        let schema = schema(for: profile)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    static func makeUserDefaults(suitePrefix: String = "HousePulseTests") -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "\(suitePrefix).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite: \(suiteName)")
        }

        return (suiteName, defaults)
    }

    static func clearUserDefaults(
        suiteName: String?,
        defaults: UserDefaults? = nil
    ) {
        guard let suiteName else { return }
        defaults?.removePersistentDomain(forName: suiteName)
    }

    static func schema(for profile: SchemaProfile) -> Schema {
        switch profile {
        case .appCache:
            Schema([
                CachedWorkItem.self,
                CachedTask.self,
                CachedMember.self,
                CachedShoppingItem.self,
                CachedShoppingBundle.self,
                CachedBacklogCategory.self,
                CachedBacklogItem.self,
                CachedHousehold.self,
                CachedArea.self,
                CachedRecurringChore.self,
            ])
        case .workItems:
            Schema([
                CachedWorkItem.self,
                CachedBacklogCategory.self,
                CachedMember.self,
                CachedHousehold.self,
            ])
        case .shopping:
            Schema([
                CachedShoppingItem.self,
                CachedShoppingBundle.self,
                CachedHousehold.self,
            ])
        case .bundles:
            Schema([
                CachedShoppingBundle.self,
                CachedShoppingItem.self,
                CachedHousehold.self,
            ])
        case .household:
            Schema([
                CachedHousehold.self,
                CachedMember.self,
                CachedShoppingItem.self,
                CachedShoppingBundle.self,
                CachedWorkItem.self,
                CachedBacklogCategory.self,
                CachedArea.self,
                CachedRecurringChore.self,
            ])
        case .members:
            Schema([
                CachedMember.self,
                CachedHousehold.self,
            ])
        case .bootstrapProbe:
            Schema([
                CachedWorkItem.self,
                CachedTask.self,
                CachedMember.self,
                CachedShoppingItem.self,
                CachedShoppingBundle.self,
                CachedBacklogCategory.self,
                CachedBacklogItem.self,
                CachedHousehold.self,
                CachedArea.self,
                CachedRecurringChore.self,
                StartupSentinel.self,
            ])
        }
    }
}
