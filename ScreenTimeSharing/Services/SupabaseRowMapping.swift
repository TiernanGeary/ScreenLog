import Foundation

// Pure Codable row shapes for the Supabase tables/RPCs and their mappings to
// the domain models in ScreenTimeSharingCore. No networking here — this is the
// unit-testable seam between PostgREST JSON and the app.

struct ProfileRow: Codable {
    var id: UUID
    var displayName: String
    var avatarColorHex: String
    var avatarPath: String?
    var shareStatus: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarColorHex = "avatar_color_hex"
        case avatarPath = "avatar_path"
        case shareStatus = "share_status"
        case updatedAt = "updated_at"
    }

    func toDomain(avatarImageData: Data?) -> UserProfile {
        UserProfile(
            id: id.uuidString,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            avatarImageData: avatarImageData,
            shareStatus: ShareStatus(rawValue: shareStatus) ?? .notShared,
            updatedAt: updatedAt
        )
    }
}

/// Update payload for the `profiles` row (id comes from auth, timestamps from
/// the database trigger).
struct ProfileUpdate: Encodable {
    var displayName: String
    var avatarColorHex: String
    var avatarPath: String?
    var shareStatus: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarColorHex = "avatar_color_hex"
        case avatarPath = "avatar_path"
        case shareStatus = "share_status"
    }

    init(profile: UserProfile, avatarPath: String?) {
        self.displayName = profile.displayName
        self.avatarColorHex = profile.avatarColorHex
        self.avatarPath = avatarPath
        self.shareStatus = profile.shareStatus.rawValue
    }
}

struct SnapshotRow: Codable {
    var ownerId: UUID
    var day: String
    var date: Date
    var calendarIdentifier: String
    var timeZoneIdentifier: String
    var totalSeconds: Double?
    var selectedAppSeconds: Double?
    var pickupCount: Int?
    var appRows: [SharedAppUsage]
    var capabilityStatus: String
    var capabilityReason: String?
    var lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case day
        case date
        case calendarIdentifier = "calendar_identifier"
        case timeZoneIdentifier = "time_zone_identifier"
        case totalSeconds = "total_seconds"
        case selectedAppSeconds = "selected_app_seconds"
        case pickupCount = "pickup_count"
        case appRows = "app_rows"
        case capabilityStatus = "capability_status"
        case capabilityReason = "capability_reason"
        case lastUpdated = "last_updated"
    }

    /// Builds the upsert row from a snapshot, or nil when the snapshot's
    /// capability does not allow upload. `ownerID` is the auth user UUID.
    init?(snapshot: DailyUsageSnapshot, ownerID: UUID) {
        guard let uploadable = snapshot.sanitizedForUpload() else {
            return nil
        }

        self.ownerId = ownerID
        self.day = Self.dayKey(for: uploadable.date, timeZoneIdentifier: uploadable.timeZoneIdentifier)
        self.date = uploadable.date
        self.calendarIdentifier = uploadable.calendarIdentifier
        self.timeZoneIdentifier = uploadable.timeZoneIdentifier
        self.totalSeconds = uploadable.totalDuration
        self.selectedAppSeconds = uploadable.selectedAppDuration
        self.pickupCount = uploadable.pickupCount
        self.appRows = uploadable.appRows
        self.capabilityStatus = uploadable.capability.status.rawValue
        self.capabilityReason = uploadable.capability.reason
        self.lastUpdated = uploadable.lastUpdated
    }

    func toDomain() -> DailyUsageSnapshot {
        DailyUsageSnapshot(
            id: "snapshot-\(ownerId.uuidString)-\(day)",
            ownerProfileID: ownerId.uuidString,
            date: date,
            calendarIdentifier: calendarIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
            totalDuration: totalSeconds,
            selectedAppDuration: selectedAppSeconds,
            pickupCount: pickupCount,
            appRows: appRows,
            lastUpdated: lastUpdated,
            capability: ScreenTimeCapability(
                status: ScreenTimeCapabilityStatus(rawValue: capabilityStatus) ?? .unavailable,
                reason: capabilityReason
            )
        )
    }

    /// The user's local calendar day, matching `(owner_id, day)` uniqueness on
    /// the server (one snapshot per local day).
    static func dayKey(for date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct TimeRequestRow: Codable {
    var id: UUID
    var groupId: String
    var requesterId: UUID
    var requesterDisplayName: String?
    var recipientIds: [UUID]
    var requestedSeconds: Int
    var message: String
    var photoPath: String?
    var status: String
    var approvedBy: UUID?
    var createdAt: Date
    var expiresAt: Date
    var resolvedAt: Date?
    var approvedExpiresAt: Date?
    var collectedAt: Date?
    var groupAppNames: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case requesterId = "requester_id"
        case requesterDisplayName = "requester_display_name"
        case recipientIds = "recipient_ids"
        case requestedSeconds = "requested_seconds"
        case message
        case photoPath = "photo_path"
        case status
        case approvedBy = "approved_by"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case resolvedAt = "resolved_at"
        case approvedExpiresAt = "approved_expires_at"
        case collectedAt = "collected_at"
        case groupAppNames = "group_app_names"
    }

    /// Insert payload from a freshly created local request. Returns nil when the
    /// request id or recipients are not valid UUIDs (cannot happen for requests
    /// minted after the Supabase migration).
    init?(request: BlockFriendRequest, requesterID: UUID, photoPath: String?) {
        guard let requestID = UUID(uuidString: request.id) else {
            return nil
        }
        let recipients = request.selectedFriendIDs.compactMap(UUID.init(uuidString:))
        guard !recipients.isEmpty else {
            return nil
        }

        self.id = requestID
        self.groupId = request.groupID
        self.requesterId = requesterID
        self.requesterDisplayName = request.requesterDisplayName
        self.recipientIds = recipients
        self.requestedSeconds = max(1, Int(request.requestedSeconds.rounded()))
        self.message = request.message
        self.photoPath = photoPath
        self.status = BlockRequestStatus.pending.rawValue
        self.approvedBy = nil
        self.createdAt = request.createdAt
        self.expiresAt = request.expiresAt
            ?? BlockFriendRequestLifecycle.pendingExpirationDate(createdAt: request.createdAt)
        self.resolvedAt = nil
        self.approvedExpiresAt = nil
        self.collectedAt = nil
        self.groupAppNames = request.groupAppNames.map { Array($0.prefix(5)) }
    }

    func toDomain(photoReference: BlockFriendRequestPhotoReference?) -> BlockFriendRequest {
        BlockFriendRequest(
            id: id.uuidString,
            groupID: groupId,
            requestedSeconds: TimeInterval(requestedSeconds),
            selectedFriendIDs: recipientIds.map(\.uuidString),
            message: message,
            requesterID: requesterId.uuidString,
            requesterDisplayName: requesterDisplayName,
            approvedByFriendID: approvedBy?.uuidString,
            status: BlockRequestStatus(rawValue: status) ?? .pending,
            createdAt: createdAt,
            resolvedAt: resolvedAt,
            collectedAt: collectedAt,
            expiresAt: expiresAt,
            approvedExpiresAt: approvedExpiresAt,
            photoReference: photoReference,
            groupAppNames: groupAppNames
        )
    }
}

/// Row returned by the `get_friend_summaries` RPC: friend profile + their
/// latest snapshot(s) in one round trip.
struct FriendSummaryRPCRow: Decodable {
    var friendId: UUID
    var displayName: String
    var avatarColorHex: String
    var avatarPath: String?
    var shareStatus: String
    var friendedAt: Date
    var snapshots: [SnapshotRow]

    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case displayName = "display_name"
        case avatarColorHex = "avatar_color_hex"
        case avatarPath = "avatar_path"
        case shareStatus = "share_status"
        case friendedAt = "friended_at"
        case snapshots
    }

    func toSummary(now: Date, avatarImageData: Data?) -> FriendUsageSummary {
        let latest = snapshots.max { $0.day < $1.day }
        let capability: ScreenTimeCapability
        if let latest {
            capability = ScreenTimeCapability(
                status: ScreenTimeCapabilityStatus(rawValue: latest.capabilityStatus) ?? .unavailable,
                reason: latest.capabilityReason
            )
        } else {
            capability = ScreenTimeCapability(
                status: .unavailable,
                reason: shareStatus == ShareStatus.sharing.rawValue ? "No data yet" : "Not sharing"
            )
        }

        return FriendUsageSummary(
            id: friendId.uuidString,
            displayName: displayName.isEmpty ? "Friend" : displayName,
            avatarColorHex: avatarColorHex,
            avatarImageData: avatarImageData,
            totalDuration: latest?.totalSeconds,
            selectedAppDuration: latest?.selectedAppSeconds,
            capability: capability,
            lastUpdated: latest?.lastUpdated,
            isStale: latest.map { now.timeIntervalSince($0.lastUpdated) > 3_600 } ?? true
        )
    }
}

struct CreatedInviteRow: Decodable {
    var inviteId: UUID
    var code: String
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case code
        case expiresAt = "expires_at"
    }
}

struct PeekedInviteRow: Decodable {
    var inviterDisplayName: String
    var inviterAvatarColorHex: String

    enum CodingKeys: String, CodingKey {
        case inviterDisplayName = "inviter_display_name"
        case inviterAvatarColorHex = "inviter_avatar_color_hex"
    }
}

struct RedeemedInviteRow: Decodable {
    var friendId: UUID
    var friendDisplayName: String
    var friendAvatarColorHex: String

    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case friendDisplayName = "friend_display_name"
        case friendAvatarColorHex = "friend_avatar_color_hex"
    }
}

/// A shareable invite minted by the current user.
struct CreatedInvite: Equatable, Sendable {
    let code: String
    let url: URL
    let expiresAt: Date

    /// "ABCD-EFGH" presentation of the 8-character code.
    var formattedCode: String {
        guard code.count == 8 else {
            return code
        }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}

/// An invite received from someone else, shown in the accept sheet.
struct IncomingInvite: Equatable, Identifiable, Sendable {
    let code: String
    let inviterDisplayName: String
    let inviterAvatarColorHex: String?

    var id: String { code }
}

/// Result of redeeming an invite: the new friend.
struct RedeemedInvite: Equatable, Sendable {
    let inviterProfileID: String
    let inviterDisplayName: String
}

enum InviteDeepLink {
    /// Extracts an invite code from `deny://invite/<code>` (and tolerates a
    /// future `https://<host>/invite/<code>` universal link).
    static func code(from url: URL) -> String? {
        let normalized: String?
        if url.scheme?.lowercased() == "deny" {
            if url.host()?.lowercased() == "invite" {
                normalized = url.pathComponents.dropFirst().first
            } else {
                normalized = nil
            }
        } else if url.pathComponents.dropFirst().first?.lowercased() == "invite" {
            normalized = url.pathComponents.dropFirst(2).first
        } else {
            normalized = nil
        }

        guard let raw = normalized?
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
            !raw.isEmpty
        else {
            return nil
        }
        return raw
    }
}
