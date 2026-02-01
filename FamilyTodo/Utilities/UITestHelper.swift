import Foundation
import SwiftData

/// Helper to configure the app state for UI Testing based on launch arguments
@MainActor
struct UITestHelper {
    static func configure(modelContext: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        
        // Only run if uiTestMode is enabled
        guard args.contains("-uiTestMode") else { return }
        
        // Reset Data
        if args.contains("-resetData") {
            clearAllData(context: modelContext)
        }
        
        // Seeding Scenarios
        if args.contains("-seedShoppingList") {
            seedShoppingList(context: modelContext)
        }
        
        if args.contains("-seedTasks") {
            seedTasks(context: modelContext)
        }
        
        if args.contains("-seedBacklog") {
            seedBacklog(context: modelContext)
        }
        
        // Save changes
        try? modelContext.save()
    }
    
    private static func clearAllData(context: ModelContext) {
        do {
            try context.delete(model: CachedShoppingItem.self)
            try context.delete(model: CachedTask.self)
            try context.delete(model: CachedBacklogItem.self)
            try context.delete(model: CachedBacklogCategory.self)
            try context.delete(model: CachedMember.self)
            try context.delete(model: CachedHousehold.self)
        } catch {
            print("Failed to clear data: \(error)")
        }
    }
    
    private static func seedShoppingList(context: ModelContext) {
        let items = [
            CachedShoppingItem(name: "Milk", isBought: false),
            CachedShoppingItem(name: "Bread", isBought: false),
            CachedShoppingItem(name: "Eggs", isBought: true)
        ]
        items.forEach { context.insert($0) }
    }
    
    private static func seedTasks(context: ModelContext) {
        let tasks = [
            CachedTask(title: "Pay bills", isCompleted: false),
            CachedTask(title: "Call mom", isCompleted: false),
            CachedTask(title: "Walk dog", isCompleted: true)
        ]
        tasks.forEach { context.insert($0) }
    }
    
    private static func seedBacklog(context: ModelContext) {
        let category = CachedBacklogCategory(name: "Groceries")
        context.insert(category)
        
        let items = [
            CachedBacklogItem(name: "Olive Oil", category: category),
            CachedBacklogItem(name: "Spices", category: category)
        ]
        items.forEach { context.insert($0) }
    }
}
