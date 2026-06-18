import Foundation

public struct FriendUsageSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var avatarColorHex: String
    public var avatarImageData: Data?
    public var totalDuration: TimeInterval?
    public var selectedAppDuration: TimeInterval?
    public var capability: ScreenTimeCapability
    public var lastUpdated: Date?
    public var isStale: Bool

    public init(
        id: String,
        displayName: String,
        avatarColorHex: String,
        avatarImageData: Data? = nil,
        totalDuration: TimeInterval?,
        selectedAppDuration: TimeInterval?,
        capability: ScreenTimeCapability,
        lastUpdated: Date?,
        isStale: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.avatarImageData = avatarImageData
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
    public var leaderboardEntries: [LeaderboardEntry]
    public var currentUserID: String?

    public init(
        generatedAt: Date,
        friends: [FriendUsageSummary],
        leaderboardEntries: [LeaderboardEntry] = [],
        currentUserID: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.friends = friends
        self.leaderboardEntries = leaderboardEntries
        self.currentUserID = currentUserID
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case friends
        case leaderboardEntries
        case currentUserID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        friends = try container.decode([FriendUsageSummary].self, forKey: .friends)
        leaderboardEntries = try container.decodeIfPresent([LeaderboardEntry].self, forKey: .leaderboardEntries) ?? []
        currentUserID = try container.decodeIfPresent(String.self, forKey: .currentUserID)
    }
}

public enum WidgetCacheCodec {
    public static let suiteName = "group.com.jdco.ScreenLog"
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
