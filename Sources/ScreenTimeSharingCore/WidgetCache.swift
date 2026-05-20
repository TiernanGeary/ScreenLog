import Foundation

public struct FriendUsageSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var avatarColorHex: String
    public var totalDuration: TimeInterval?
    public var selectedAppDuration: TimeInterval?
    public var capability: ScreenTimeCapability
    public var lastUpdated: Date?
    public var isStale: Bool

    public init(
        id: String,
        displayName: String,
        avatarColorHex: String,
        totalDuration: TimeInterval?,
        selectedAppDuration: TimeInterval?,
        capability: ScreenTimeCapability,
        lastUpdated: Date?,
        isStale: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.totalDuration = totalDuration
        self.selectedAppDuration = selectedAppDuration
        self.capability = capability
        self.lastUpdated = lastUpdated
        self.isStale = isStale
    }
}

public struct WidgetCachePayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var friends: [FriendUsageSummary]

    public init(generatedAt: Date, friends: [FriendUsageSummary]) {
        self.generatedAt = generatedAt
        self.friends = friends
    }
}

public enum WidgetCacheCodec {
    public static let suiteName = "group.com.jdco.ScreenTimeSharing"
    public static let storageKey = "WidgetFriendCache.v1"

    public static func encode(_ payload: WidgetCachePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func decode(_ data: Data) throws -> WidgetCachePayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetCachePayload.self, from: data)
    }
}
