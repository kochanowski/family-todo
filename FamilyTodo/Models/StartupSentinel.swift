import Foundation
import SwiftData

@Model
final class StartupSentinel {
    @Attribute(.unique) var id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}
