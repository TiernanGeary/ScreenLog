import AppIntents
import Foundation

struct WidgetFriendEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Friend")
    static let defaultQuery = WidgetFriendQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct WidgetFriendQuery: EntityQuery {
    func entities(for identifiers: [WidgetFriendEntity.ID]) async throws -> [WidgetFriendEntity] {
        let friends = WidgetCacheReader.friends()
        return friends
            .filter { identifiers.contains($0.id) }
            .map { WidgetFriendEntity(id: $0.id, displayName: $0.displayName) }
    }

    func suggestedEntities() async throws -> [WidgetFriendEntity] {
        WidgetCacheReader.friends()
            .prefix(8)
            .map { WidgetFriendEntity(id: $0.id, displayName: $0.displayName) }
    }
}

struct WidgetFriendConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Friends"
    static let description = IntentDescription("Choose up to four friends for the Screen Time widget.")

    @Parameter(title: "Friend 1")
    var friend1: WidgetFriendEntity?

    @Parameter(title: "Friend 2")
    var friend2: WidgetFriendEntity?

    @Parameter(title: "Friend 3")
    var friend3: WidgetFriendEntity?

    @Parameter(title: "Friend 4")
    var friend4: WidgetFriendEntity?

    var selectedFriendIDs: [String] {
        [friend1?.id, friend2?.id, friend3?.id, friend4?.id].compactMap { $0 }
    }
}
