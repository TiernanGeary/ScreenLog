import Foundation

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var avatarColorHex: String
    public var shareStatus: ShareStatus
    public var updatedAt: Date

    public init(
        id: String,
        displayName: String,
        avatarColorHex: String,
        shareStatus: ShareStatus,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.shareStatus = shareStatus
        self.updatedAt = updatedAt
    }
}

public enum ShareStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case notShared
    case sharing
    case revoked
}

public struct SharedAppUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var bundleIdentifier: String?
    public var duration: TimeInterval

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String?,
        duration: TimeInterval
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.duration = duration
    }
}

public struct DailyUsageSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var ownerProfileID: String
    public var date: Date
    public var calendarIdentifier: String
    public var timeZoneIdentifier: String
    public var totalDuration: TimeInterval?
    public var selectedAppDuration: TimeInterval?
    public var appRows: [SharedAppUsage]
    public var lastUpdated: Date
    public var capability: ScreenTimeCapability

    public init(
        id: String,
        ownerProfileID: String,
        date: Date,
        calendarIdentifier: String,
        timeZoneIdentifier: String,
        totalDuration: TimeInterval?,
        selectedAppDuration: TimeInterval?,
        appRows: [SharedAppUsage],
        lastUpdated: Date,
        capability: ScreenTimeCapability
    ) {
        self.id = id
        self.ownerProfileID = ownerProfileID
        self.date = date
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.totalDuration = totalDuration
        self.selectedAppDuration = selectedAppDuration
        self.appRows = appRows
        self.lastUpdated = lastUpdated
        self.capability = capability
    }

    public func sanitizedForUpload() -> DailyUsageSnapshot? {
        guard capability.allowsUpload else {
            return nil
        }

        var copy = self
        if !capability.allowsPerAppRows {
            copy.appRows = []
        }
        return copy
    }
}

public struct FriendShare: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var friendProfileID: String
    public var displayName: String
    public var acceptedAt: Date
    public var canReadSnapshots: Bool
    public var revokedAt: Date?

    public init(
        id: String,
        friendProfileID: String,
        displayName: String,
        acceptedAt: Date,
        canReadSnapshots: Bool,
        revokedAt: Date?
    ) {
        self.id = id
        self.friendProfileID = friendProfileID
        self.displayName = displayName
        self.acceptedAt = acceptedAt
        self.canReadSnapshots = canReadSnapshots
        self.revokedAt = revokedAt
    }
}
