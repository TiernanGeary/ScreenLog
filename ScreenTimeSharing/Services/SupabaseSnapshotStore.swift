import Foundation
import Supabase

/// Reachability/auth state of the Supabase backend. Mirrors the member names of
/// the old `CloudAvailability` so call sites stay unchanged.
enum BackendAvailability: Equatable {
    case checking
    case available
    case signedOut
    case unavailable(String)

    var label: String {
        switch self {
        case .checking:
            return "Checking sync"
        case .available:
            return "Connected"
        case .signedOut:
            return "Signed out"
        case .unavailable(let message):
            return message
        }
    }

    var allowsCloudWrites: Bool {
        self == .available
    }
}

private enum SupabaseSnapshotStoreError: LocalizedError {
    case notSignedIn
    case notConfigured
    case invalidInvite

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to sync with friends."
        case .notConfigured:
            return "Backend is not configured."
        case .invalidInvite:
            return "That invite code is not valid."
        }
    }
}

/// Supabase-backed replacement for the old CloudKit store: profiles, daily
/// usage snapshots, the friend graph (invite codes), and friend time requests.
/// All access control is enforced server-side by RLS + SECURITY DEFINER RPCs.
@MainActor
final class SupabaseSnapshotStore {
    private let client = SupabaseClientProvider.shared
    private var avatarCache: [String: Data] = [:]
    private var lastUploadedAvatarPath: String?

    // MARK: - Auth

    /// Exchanges an Apple identity token for a Supabase session. The returned
    /// auth user UUID is the canonical profile ID.
    func signIn(with credential: AppleCredential) async throws -> String {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: credential.identityToken,
                nonce: credential.rawNonce
            )
        )
        return session.user.id.uuidString
    }

    #if DEBUG
    /// Simulator/testing backdoor: signs in to one of ten pre-provisioned,
    /// already-confirmed accounts (deny-sim-0...9) so two simulators can act as
    /// two distinct users without Apple IDs or email confirmation.
    func signInWithDebugAccount(index: Int) async throws -> String {
        let n = ((index % 10) + 10) % 10
        let session = try await client.auth.signIn(
            email: "deny-sim-\(n)@stepai.co.jp",
            password: "deny-debug-sim-\(n)"
        )
        return session.user.id.uuidString
    }
    #endif

    /// Restores a persisted session (Keychain), refreshing if needed. Returns
    /// the auth user UUID or nil when signed out.
    func restoreSession() async -> String? {
        guard AppConfiguration.isSupabaseConfigured else {
            return nil
        }
        return (try? await client.auth.session)?.user.id.uuidString
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func cloudAvailability() async -> BackendAvailability {
        guard AppConfiguration.isSupabaseConfigured else {
            return .unavailable("Backend not configured")
        }
        return await restoreSession() == nil ? .signedOut : .available
    }

    private func currentUserID() async throws -> UUID {
        guard let session = try? await client.auth.session else {
            throw SupabaseSnapshotStoreError.notSignedIn
        }
        return session.user.id
    }

    // MARK: - Profile

    /// Loads the signed-in user's own profile row (auto-created at signup).
    func fetchOwnProfile() async throws -> UserProfile? {
        let uid = try await currentUserID()
        let rows: [ProfileRow] = try await client.from("profiles")
            .select()
            .eq("id", value: uid)
            .execute()
            .value
        guard let row = rows.first else {
            return nil
        }
        let avatarData = await avatarData(forPath: row.avatarPath, bucket: "avatars")
        return row.toDomain(avatarImageData: avatarData)
    }

    func publishProfile(_ profile: UserProfile) async throws {
        let uid = try await currentUserID()
        let avatarPath = try await uploadAvatarIfNeeded(profile, uid: uid)
        try await client.from("profiles")
            .update(ProfileUpdate(profile: profile, avatarPath: avatarPath))
            .eq("id", value: uid)
            .execute()
    }

    private func uploadAvatarIfNeeded(_ profile: UserProfile, uid: UUID) async throws -> String? {
        guard let imageData = profile.avatarImageData else {
            return nil
        }

        // Lowercase to match auth.uid()::text in the storage RLS policies.
        let path = "\(uid.uuidString.lowercased())/avatar-\(Int(profile.updatedAt.timeIntervalSince1970)).jpg"
        if path == lastUploadedAvatarPath {
            return path
        }

        try await client.storage.from("avatars").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        lastUploadedAvatarPath = path
        avatarCache[path] = imageData
        return path
    }

    private func avatarData(forPath path: String?, bucket: String) async -> Data? {
        guard let path else {
            return nil
        }
        if let cached = avatarCache[path] {
            return cached
        }
        guard let data = try? await client.storage.from(bucket).download(path: path) else {
            return nil
        }
        avatarCache[path] = data
        return data
    }

    // MARK: - Snapshots

    func publish(profile: UserProfile, snapshot: DailyUsageSnapshot) async throws {
        let uid = try await currentUserID()
        try await publishProfile(profile)
        guard let row = SnapshotRow(snapshot: snapshot, ownerID: uid) else {
            return
        }
        try await client.from("daily_snapshots")
            .upsert(row, onConflict: "owner_id,day")
            .execute()
    }

    // MARK: - Friends

    func fetchFriendSummaries(now: Date = Date()) async throws -> [FriendUsageSummary] {
        struct Params: Encodable {
            let pDays: Int
            enum CodingKeys: String, CodingKey { case pDays = "p_days" }
        }
        let rows: [FriendSummaryRPCRow] = try await client
            .rpc("get_friend_summaries", params: Params(pDays: 1))
            .execute()
            .value

        var summaries: [FriendUsageSummary] = []
        for row in rows {
            let avatarData = await avatarData(forPath: row.avatarPath, bucket: "avatars")
            summaries.append(row.toSummary(now: now, avatarImageData: avatarData))
        }
        return summaries.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Signature-compatible overload (the current profile is implied by the
    /// auth session now).
    func fetchFriendSummaries(for currentProfile: UserProfile, now: Date = Date()) async throws -> [FriendUsageSummary] {
        _ = currentProfile
        return try await fetchFriendSummaries(now: now)
    }

    // MARK: - Invites

    func createInvite() async throws -> CreatedInvite {
        let rows: [CreatedInviteRow] = try await client
            .rpc("create_friend_invite")
            .execute()
            .value
        guard let row = rows.first,
              let url = URL(string: "deny://invite/\(row.code)") else {
            throw SupabaseSnapshotStoreError.invalidInvite
        }
        return CreatedInvite(code: row.code, url: url, expiresAt: row.expiresAt)
    }

    func peekInvite(code: String) async throws -> IncomingInvite {
        struct Params: Encodable {
            let pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        let rows: [PeekedInviteRow] = try await client
            .rpc("peek_friend_invite", params: Params(pCode: code))
            .execute()
            .value
        guard let row = rows.first else {
            throw SupabaseSnapshotStoreError.invalidInvite
        }
        return IncomingInvite(
            code: code,
            inviterDisplayName: row.inviterDisplayName.isEmpty ? "Friend" : row.inviterDisplayName,
            inviterAvatarColorHex: row.inviterAvatarColorHex
        )
    }

    func redeemInvite(code: String) async throws -> RedeemedInvite {
        struct Params: Encodable {
            let pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        let rows: [RedeemedInviteRow] = try await client
            .rpc("redeem_friend_invite", params: Params(pCode: code))
            .execute()
            .value
        guard let row = rows.first else {
            throw SupabaseSnapshotStoreError.invalidInvite
        }
        return RedeemedInvite(
            inviterProfileID: row.friendId.uuidString,
            inviterDisplayName: row.friendDisplayName.isEmpty ? "Friend" : row.friendDisplayName
        )
    }

    // MARK: - Friend time requests

    struct FriendRequestDeliveryReport {
        var deliveredCount = 0
        var targetFriendIDs: [String] = []
        var deliveredFriendIDs: [String] = []
    }

    @discardableResult
    func publishFriendRequestDiagnostic(
        _ request: BlockFriendRequest,
        profile: UserProfile,
        photoData: Data?
    ) async throws -> FriendRequestDeliveryReport {
        let uid = try await currentUserID()
        var report = FriendRequestDeliveryReport(targetFriendIDs: request.selectedFriendIDs)

        var photoPath: String?
        if let photoData {
            // Lowercase to match auth.uid()::text / t.id::text in storage RLS.
            // Write-once (request IDs are unique), so no upsert needed.
            let path = "\(uid.uuidString.lowercased())/\(request.id.lowercased()).jpg"
            try await client.storage.from("request-photos").upload(
                path,
                data: photoData,
                options: FileOptions(contentType: "image/jpeg")
            )
            photoPath = path
        }

        guard let row = TimeRequestRow(request: request, requesterID: uid, photoPath: photoPath) else {
            return report
        }

        try await client.from("time_requests").insert(row).execute()
        report.deliveredCount = row.recipientIds.count
        report.deliveredFriendIDs = row.recipientIds.map(\.uuidString)
        return report
    }

    /// Pushes a local status transition to the server via the transition RPCs
    /// (approve/deny by a recipient, collect by the requester). Pending and
    /// expired states need no server write — expiry is enforced server-side.
    func updateFriendRequest(_ request: BlockFriendRequest) async throws {
        guard let requestID = UUID(uuidString: request.id) else {
            return
        }

        struct RespondParams: Encodable {
            let pRequestId: UUID
            let pApprove: Bool
            enum CodingKeys: String, CodingKey {
                case pRequestId = "p_request_id"
                case pApprove = "p_approve"
            }
        }
        struct CollectParams: Encodable {
            let pRequestId: UUID
            enum CodingKeys: String, CodingKey { case pRequestId = "p_request_id" }
        }

        switch request.status {
        case .approved:
            try await client
                .rpc("respond_to_time_request", params: RespondParams(pRequestId: requestID, pApprove: true))
                .execute()
        case .denied:
            try await client
                .rpc("respond_to_time_request", params: RespondParams(pRequestId: requestID, pApprove: false))
                .execute()
        case .collected:
            try await client
                .rpc("collect_time_request", params: CollectParams(pRequestId: requestID))
                .execute()
        case .pending, .expired:
            break
        }
    }

    func fetchFriendRequests(
        knownRequestIDs: Set<String> = [],
        savePhotoData: (String, Data) throws -> BlockFriendRequestPhotoReference
    ) async throws -> [BlockFriendRequest] {
        let uid = try await currentUserID()
        let rows: [TimeRequestRow] = try await client.from("time_requests")
            .select()
            .or("requester_id.eq.\(uid.uuidString),recipient_ids.cs.{\(uid.uuidString)}")
            .order("created_at", ascending: false)
            .execute()
            .value

        let knownIDs = Set(knownRequestIDs.compactMap { UUID(uuidString: $0)?.uuidString })
        var requests: [BlockFriendRequest] = []
        for row in rows {
            var photoReference: BlockFriendRequestPhotoReference?
            if let photoPath = row.photoPath, !knownIDs.contains(row.id.uuidString) {
                if let data = try? await client.storage.from("request-photos").download(path: photoPath) {
                    photoReference = try? savePhotoData(row.id.uuidString, data)
                }
            }
            requests.append(row.toDomain(photoReference: photoReference))
        }
        return requests
    }

    // MARK: - Account reset

    /// Deletes all of this user's server-side data (via SECURITY DEFINER RPC)
    /// and signs out. Keeps the auth user so the same Apple ID maps back to the
    /// same UUID if they return.
    func resetAllCloudData() async {
        _ = try? await client.rpc("delete_my_account_data").execute()
        await signOut()
        avatarCache = [:]
        lastUploadedAvatarPath = nil
    }

    /// Permanently deletes the account: removes the user's stored files via the
    /// Storage API (SQL can't touch storage), then a SECURITY DEFINER RPC
    /// deletes the auth user, cascading through all of their data. Signs out
    /// locally afterwards. Throws if the server-side deletion fails.
    func deleteAccount() async throws {
        let uid = try await currentUserID()
        let folder = uid.uuidString.lowercased()

        // Best-effort file cleanup; any stragglers are unreadable once the
        // rows behind the storage read policies are deleted below.
        for bucket in ["avatars", "request-photos"] {
            if let objects = try? await client.storage.from(bucket).list(path: folder), !objects.isEmpty {
                _ = try? await client.storage.from(bucket).remove(paths: objects.map { "\(folder)/\($0.name)" })
            }
        }

        try await client.rpc("delete_my_account").execute()
        await signOut()
        avatarCache = [:]
        lastUploadedAvatarPath = nil
    }
}
