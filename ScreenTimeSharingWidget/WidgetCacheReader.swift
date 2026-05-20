import Foundation

enum WidgetCacheReader {
    static func payload() -> WidgetCachePayload? {
        guard let data = UserDefaults(suiteName: WidgetCacheCodec.suiteName)?
            .data(forKey: WidgetCacheCodec.storageKey) else {
            return nil
        }

        return try? WidgetCacheCodec.decode(data)
    }

    static func friends() -> [FriendUsageSummary] {
        payload()?.friends ?? []
    }
}
