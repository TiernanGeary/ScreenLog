import Foundation
import WidgetKit

final class AppGroupWidgetCacheWriter {
    private let defaults: UserDefaults?

    init(suiteName: String = AppConfiguration.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    func write(_ friends: [FriendUsageSummary]) throws {
        let payload = WidgetCachePayload(generatedAt: Date(), friends: friends)
        let data = try WidgetCacheCodec.encode(payload)
        defaults?.set(data, forKey: WidgetCacheCodec.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
