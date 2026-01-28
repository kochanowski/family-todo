import Foundation
import SwiftUI

@MainActor
final class ShoppingListSettingsStore: ObservableObject {
    @AppStorage("shoppingList.suggestionLimit")
    var suggestionLimit = 10 {
        didSet { objectWillChange.send() }
    }

    /// Valid range: 5-50
    static let suggestionLimitRange = 5 ... 50
}
