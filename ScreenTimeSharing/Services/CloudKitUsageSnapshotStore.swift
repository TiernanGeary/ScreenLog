import CloudKit
import Foundation

enum CloudAvailability: Equatable {
    case checking
    case available
    case noAccount
    case restricted
    case unavailable(String)

    var label: String {
        switch self {
        case .checking:
            return "Checking iCloud"
        case .available:
            return "iCloud available"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "iCloud restricted"
        case .unavailable(let message):
            return message
        }
    }

    var allowsCloudWrites: Bool {
        self == .available
    }
}

private enum CloudKitUsageSnapshotStoreError: LocalizedError {
    case unavailableInSimulator
    case cloudKitSaveFailed(context: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unavailableInSimulator:
            "iCloud sharing is unavailable in this simulator build."
        case .cloudKitSaveFailed(let context, let reason):
            "\(context) failed: \(reason)"
        }
    }
}

@MainActor
final class CloudKitUsageSnapshotStore {
    private enum RecordType {
        static let userProfile = "UserProfile"
        static let dailyUsageSnapshot = "DailyUsageSnapshot"
        static let friendTimeRequest = "FriendTimeRequest"
        static let friendInbox = "FriendInbox"
    }

    private enum Field {
        static let displayName = "displayName"
        static let avatarColorHex = "avatarColorHex"
        static let avatarImageData = "avatarImageData"
        static let shareStatus = "shareStatus"
        static let updatedAt = "updatedAt"
        static let ownerProfileID = "ownerProfileID"
        static let appleUserID = "appleUserID"
        static let date = "date"
        static let calendarIdentifier = "calendarIdentifier"
        static let timeZoneIdentifier = "timeZoneIdentifier"
        static let totalDuration = "totalDuration"
        static let selectedAppDuration = "selectedAppDuration"
        static let appRowsJSON = "appRowsJSON"
        static let lastUpdated = "lastUpdated"
        static let capabilityStatus = "capabilityStatus"
        static let capabilityReason = "capabilityReason"
        static let profileReference = "profileReference"
        static let requestID = "requestID"
        static let groupID = "groupID"
        static let requestedSeconds = "requestedSeconds"
        static let selectedFriendIDs = "selectedFriendIDs"
        static let message = "message"
        static let requesterID = "requesterID"
        static let requesterDisplayName = "requesterDisplayName"
        static let approvedByFriendID = "approvedByFriendID"
        static let status = "status"
        static let createdAt = "createdAt"
        static let resolvedAt = "resolvedAt"
        static let collectedAt = "collectedAt"
        static let expiresAt = "expiresAt"
        static let approvedExpiresAt = "approvedExpiresAt"
        static let photoAsset = "photoAsset"
        static let inboxFriendID = "inboxFriendID"
        static let inboxOwnerProfileID = "inboxOwnerProfileID"
    }

    private let container: CKContainer?
    private let sharedZoneStore: SharedZoneStore

    init(
        containerIdentifier: String = AppConfiguration.cloudKitContainerIdentifier,
        sharedZoneStore: SharedZoneStore = SharedZoneStore()
    ) {
        #if targetEnvironment(simulator)
        self.container = nil
        #else
        self.container = CKContainer(identifier: containerIdentifier)
        #endif
        self.sharedZoneStore = sharedZoneStore
    }

    func cloudAvailability() async -> CloudAvailability {
        guard let container else {
            return .unavailable("iCloud unavailable in simulator")
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<CloudAvailability, Never>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(returning: .unavailable(error.localizedDescription))
                    return
                }

                switch status {
                case .available:
                    continuation.resume(returning: .available)
                case .noAccount:
                    continuation.resume(returning: .noAccount)
                case .restricted:
                    continuation.resume(returning: .restricted)
                case .couldNotDetermine:
                    continuation.resume(returning: .unavailable("Could not determine iCloud status"))
                case .temporarilyUnavailable:
                    continuation.resume(returning: .unavailable("iCloud is temporarily unavailable"))
                @unknown default:
                    continuation.resume(returning: .unavailable("Unknown iCloud status"))
                }
            }
        }
    }

    func fetchExistingProfile(id appleUserID: String) async throws -> UserProfile? {
        guard let container else {
            return nil
        }

        try await ensurePrivateZone(in: container)
        let database = container.privateCloudDatabase
        let query = CKQuery(
            recordType: RecordType.userProfile,
            predicate: NSPredicate(format: "%K == %@", Field.appleUserID, appleUserID)
        )

        let response = try await database.records(
            matching: query,
            inZoneWith: privateZoneID,
            desiredKeys: nil,
            resultsLimit: 1
        )

        guard let record = response.matchResults.compactMap({ try? $0.1.get() }).first else {
            return nil
        }

        let profileID = record[Field.ownerProfileID] as? String ?? appleUserID
        let displayName = record[Field.displayName] as? String ?? "Me"
        let avatarColorHex = record[Field.avatarColorHex] as? String ?? AppConfiguration.defaultAvatarColor
        let avatarImageData = record[Field.avatarImageData] as? Data
        let shareStatusRaw = record[Field.shareStatus] as? String
        let shareStatus = shareStatusRaw.flatMap(ShareStatus.init(rawValue:)) ?? .notShared
        let updatedAt = record[Field.updatedAt] as? Date ?? Date()
        let resolvedAppleUserID = record[Field.appleUserID] as? String ?? appleUserID

        return UserProfile(
            id: profileID,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            avatarImageData: avatarImageData,
            shareStatus: shareStatus,
            updatedAt: updatedAt,
            appleUserID: resolvedAppleUserID
        )
    }

    func publish(profile: UserProfile, snapshot: DailyUsageSnapshot) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        guard let payload = try SnapshotRecordPayloadMapper.payload(from: snapshot) else {
            return
        }

        try await ensurePrivateZone(in: container)

        let profileRecord = makeProfileRecord(profile)
        let snapshotRecord = makeSnapshotRecord(payload, profileRecordID: profileRecord.recordID)

        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [profileRecord, snapshotRecord],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        for saveResult in result.saveResults.values {
            _ = try saveResult.get()
        }

        try? await publishAcceptedShareMirrors(profile: profile, snapshot: snapshot)
    }

    func prepareProfileShare(profile: UserProfile) async throws -> (share: CKShare, container: CKContainer) {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)
        let database = container.privateCloudDatabase

        var sharingProfile = profile
        sharingProfile.shareStatus = .sharing
        sharingProfile.updatedAt = Date()

        let profileRecord = makeProfileRecord(sharingProfile)
        let shareID = CKRecord.ID(recordName: "share-\(profile.id)", zoneID: privateZoneID)
        let existingShare = try await existingProfileShare(shareID: shareID, database: database)
        let share = existingShare ?? CKShare(rootRecord: profileRecord, shareID: shareID)
        configureProfileShare(share, profile: profile)

        let savedShare: CKShare
        if existingShare == nil {
            savedShare = try await saveNewShare(
                rootRecord: profileRecord,
                share: share,
                in: database,
                context: "Creating your invite link"
            )
        } else {
            _ = try await saveRecord(
                profileRecord,
                in: database,
                context: "Saving your share profile"
            )
            savedShare = try await saveShare(
                share,
                in: database,
                context: "Updating your invite link"
            )
        }

        var resolvedShare = savedShare
        if resolvedShare.url == nil,
           let refetchedShare = try await existingProfileShare(shareID: shareID, database: database) {
            resolvedShare = refetchedShare
        }

        return (resolvedShare, container)
    }

    func publishProfile(_ profile: UserProfile) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: "share-\(profile.id)", zoneID: privateZoneID)
        let existingShare = try await existingProfileShare(shareID: shareID, database: database)

        var cloudProfile = profile
        if existingShare != nil {
            cloudProfile.shareStatus = .sharing
        }

        _ = try await saveRecord(
            makeProfileRecord(cloudProfile),
            in: database,
            context: "Updating your profile"
        )

        if let existingShare {
            configureProfileShare(existingShare, profile: profile)
            _ = try await saveShare(
                existingShare,
                in: database,
                context: "Updating your invite profile"
            )
        }

        try? await publishAcceptedShareMirrors(profile: profile)
    }

    #if DEBUG
    func bootstrapDevelopmentSchema(profile: UserProfile) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)

        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dayStart = calendar.startOfDay(for: now)
        let snapshot = DailyUsageSnapshot(
            id: "schema-bootstrap-\(profile.id)",
            ownerProfileID: profile.id,
            date: dayStart,
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            totalDuration: 60,
            selectedAppDuration: 30,
            pickupCount: 1,
            appRows: [
                SharedAppUsage(
                    id: "schema-bootstrap-app",
                    displayName: "Schema Bootstrap",
                    bundleIdentifier: "com.jdco.schema-bootstrap",
                    duration: 30
                )
            ],
            lastUpdated: now,
            capability: .fullAppDetail
        )

        var bootstrapProfile = profile
        if bootstrapProfile.avatarImageData == nil {
            bootstrapProfile.avatarImageData = Self.schemaBootstrapJPEGData
        }
        // Ensure the appleUserID field (and its queryable index) materializes in
        // the schema even before a real sign-in writes it.
        if bootstrapProfile.appleUserID == nil {
            bootstrapProfile.appleUserID = "schema-bootstrap-apple-id"
        }
        try await publish(profile: bootstrapProfile, snapshot: snapshot)
        try await bootstrapAvatarImageDataField(profile: bootstrapProfile, in: container.privateCloudDatabase)

        let requestID = "schema-bootstrap-\(profile.id)"
        // Populate every optional field with a non-nil value: CloudKit only
        // adds a field to the schema when a saved record carries a value for it,
        // so an approved request is required to create approvedByFriendID,
        // resolvedAt, collectedAt, and approvedExpiresAt.
        let request = BlockFriendRequest(
            id: requestID,
            groupID: "schema-bootstrap-group",
            requestedSeconds: 5 * 60,
            selectedFriendIDs: ["schema-bootstrap-friend"],
            message: "Schema bootstrap",
            requesterID: profile.id,
            requesterDisplayName: profile.displayName,
            approvedByFriendID: profile.id,
            status: .collected,
            createdAt: now,
            resolvedAt: now,
            collectedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60),
            approvedExpiresAt: now.addingTimeInterval(60 * 60),
            photoReference: BlockFriendRequestPhotoReference(localIdentifier: "schema-bootstrap-photo")
        )

        try await publishFriendRequest(
            request,
            profile: profile,
            photoData: Self.schemaBootstrapJPEGData
        )

        try await deleteSchemaBootstrapRecords(snapshot: snapshot, request: request, profile: profile, in: container.privateCloudDatabase)
    }
    #endif

    func publishFriendRequest(
        _ request: BlockFriendRequest,
        profile: UserProfile,
        photoData: Data?
    ) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)
        let database = container.privateCloudDatabase

        // Resolve each selected friend's CloudKit identity so we can grant them
        // (and only them) write access to their private inbox share.
        let userRecordIDsByFriendID = (try? await friendUserRecordIDs(
            for: request.selectedFriendIDs,
            profile: profile,
            database: database
        )) ?? [:]
        let participantsByUserRecordName = (try? await shareParticipants(
            for: Array(Set(userRecordIDsByFriendID.values)),
            in: container
        )) ?? [:]

        for friendID in request.selectedFriendIDs {
            let friendParticipant = userRecordIDsByFriendID[friendID]
                .flatMap { participantsByUserRecordName[$0.recordName] }
            let inboxRecordID = inboxRecordID(ownerProfileID: profile.id, friendID: friendID)
            let inboxRecord = try await ensureInboxRecord(
                recordID: inboxRecordID,
                ownerProfileID: profile.id,
                friendID: friendID,
                database: database
            )
            try await ensureInboxShare(
                inboxRecord: inboxRecord,
                friendID: friendID,
                friendParticipant: friendParticipant,
                profile: profile,
                database: database
            )

            let requestRecord = try makeFriendRequestRecord(
                request,
                profileRecordID: inboxRecordID,
                existingRecord: nil,
                photoData: photoData
            )

            let result = try await database.modifyRecords(
                saving: [requestRecord.record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )

            try requestRecord.cleanup()
            for saveResult in result.saveResults.values {
                _ = try saveResult.get()
            }
        }
    }

    func updateFriendRequest(_ request: BlockFriendRequest) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)

        if try await updateFriendRequest(request, database: container.privateCloudDatabase, zoneID: privateZoneID) {
            return
        }

        for zoneID in await allSharedZoneIDs(in: container) {
            if try await updateFriendRequest(request, database: container.sharedCloudDatabase, zoneID: zoneID) {
                return
            }
        }
    }

    func fetchFriendRequests(
        knownRequestIDs: Set<String> = [],
        savePhotoData: (String, Data) throws -> BlockFriendRequestPhotoReference
    ) async throws -> [BlockFriendRequest] {
        guard let container else {
            return []
        }

        try await ensurePrivateZone(in: container)

        let knownRequestIDs = Set(knownRequestIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var requestsByID: [String: BlockFriendRequest] = [:]
        var firstQueryError: Error?

        func merge(records: [CKRecord]) {
            for request in records.compactMap({ makeFriendRequest(record: $0, savePhotoData: savePhotoData) }) {
                requestsByID[request.id] = request
            }
        }

        if !knownRequestIDs.isEmpty {
            merge(
                records: try await friendRequestRecords(
                    ids: knownRequestIDs,
                    in: container.privateCloudDatabase,
                    zoneID: privateZoneID
                )
            )
        }

        do {
            merge(records: try await friendRequestRecords(in: container.privateCloudDatabase, zoneID: privateZoneID))
        } catch {
            firstQueryError = firstQueryError ?? error
        }

        for zoneID in await allSharedZoneIDs(in: container) {
            if !knownRequestIDs.isEmpty {
                merge(
                    records: try await friendRequestRecords(
                        ids: knownRequestIDs,
                        in: container.sharedCloudDatabase,
                        zoneID: zoneID
                    )
                )
            }

            do {
                merge(records: try await friendRequestRecords(in: container.sharedCloudDatabase, zoneID: zoneID))
            } catch {
                firstQueryError = firstQueryError ?? error
            }
        }

        if requestsByID.isEmpty, let firstQueryError {
            throw firstQueryError
        }

        return requestsByID.values.sorted { friendRequestSortDate($0) > friendRequestSortDate($1) }
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard container != nil else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        let acceptingContainer = CKContainer(identifier: metadata.containerIdentifier)
        let result = try await acceptingContainer.accept([metadata])

        for (acceptedMetadata, shareResult) in result {
            let share = try shareResult.get()
            sharedZoneStore.insert(
                shareID: share.recordID,
                rootRecordID: acceptedMetadata.hierarchicalRootRecordID
            )
        }
    }

    func publishAcceptedShareMirrors(
        profile: UserProfile,
        snapshot: DailyUsageSnapshot? = nil
    ) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        let shares = sharedZoneStore.loadShares()
        guard !shares.isEmpty else {
            return
        }

        let userRecordID = try await currentUserRecordID(in: container)
        try await publishParticipantMirrors(
            profile: profile,
            snapshot: snapshot,
            userRecordID: userRecordID,
            shares: shares,
            database: container.sharedCloudDatabase
        )
    }

    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        let result = try await container.shareMetadatas(for: [url])
        guard let metadataResult = result[url] else {
            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: "Loading friend invite",
                reason: "iCloud did not return share metadata for this link."
            )
        }

        return try metadataResult.get()
    }

    func fetchFriendSummaries(now: Date = Date()) async throws -> [FriendUsageSummary] {
        try await fetchFriendSummaries(for: nil, now: now)
    }

    func fetchFriendSummaries(for currentProfile: UserProfile, now: Date = Date()) async throws -> [FriendUsageSummary] {
        try await fetchFriendSummaries(for: Optional(currentProfile), now: now)
    }

    private func fetchFriendSummaries(for currentProfile: UserProfile?, now: Date) async throws -> [FriendUsageSummary] {
        guard let container else {
            return []
        }

        var summariesByID: [String: FriendUsageSummary] = [:]

        func merge(_ summary: FriendUsageSummary) {
            if let existing = summariesByID[summary.id] {
                summariesByID[summary.id] = preferredSummary(existing, summary)
            } else {
                summariesByID[summary.id] = summary
            }
        }

        for share in sharedZoneStore.loadShares() {
            let zoneID = share.zoneID
            guard let profileRecord = try await sharedProfileRecord(
                rootRecordID: share.rootRecordID,
                database: container.sharedCloudDatabase,
                zoneID: zoneID
            ) else {
                continue
            }
            let snapshotRecord = try await latestSharedSnapshotRecord(
                for: profileRecord,
                database: container.sharedCloudDatabase,
                zoneID: zoneID,
                now: now
            )

            let shareRecord = try await sharedShareRecord(
                share: share,
                profileID: profileID(from: profileRecord),
                database: container.sharedCloudDatabase
            )

            let summary = makeFriendSummary(
                profileRecord: profileRecord,
                snapshotRecord: snapshotRecord,
                shareRecord: shareRecord,
                now: now
            )
            merge(summary)
        }

        if let currentProfile {
            for summary in try await acceptedParticipantSummaries(for: currentProfile, now: now) {
                merge(summary)
            }
        }

        return summariesByID.values.sorted { lhs, rhs in
            (lhs.lastUpdated ?? .distantPast) > (rhs.lastUpdated ?? .distantPast)
        }
    }

    private var privateZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "ScreenTimeSharing", ownerName: CKCurrentUserDefaultName)
    }

    private func ensurePrivateZone(in container: CKContainer) async throws {
        let existingZones = try? await container.privateCloudDatabase.recordZones(for: [privateZoneID])
        if let zoneResult = existingZones?[privateZoneID],
           case .success = zoneResult {
            return
        }

        let zone = CKRecordZone(zoneID: privateZoneID)
        let result = try await container.privateCloudDatabase.modifyRecordZones(
            saving: [zone],
            deleting: []
        )

        if let saveResult = result.saveResults[privateZoneID] {
            _ = try saveResult.get()
        }
    }

    private func inboxRecordID(ownerProfileID: String, friendID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "inbox-\(ownerProfileID)-\(friendID)", zoneID: privateZoneID)
    }

    private func ensureInboxRecord(
        recordID: CKRecord.ID,
        ownerProfileID: String,
        friendID: String,
        database: CKDatabase
    ) async throws -> CKRecord {
        let response = try await database.records(for: [recordID])
        if let result = response[recordID] {
            do {
                return try result.get()
            } catch {
                if !isUnknownItemError(error) {
                    throw error
                }
            }
        }

        let record = CKRecord(recordType: RecordType.friendInbox, recordID: recordID)
        record[Field.inboxOwnerProfileID] = ownerProfileID as CKRecordValue
        record[Field.inboxFriendID] = friendID as CKRecordValue
        record[Field.createdAt] = Date() as CKRecordValue

        let saveResult = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )

        return try savedRecord(for: recordID, from: saveResult.saveResults, context: "Creating friend inbox")
    }

    private func ensureInboxShare(
        inboxRecord: CKRecord,
        friendID: String,
        friendParticipant: CKShare.Participant?,
        profile: UserProfile,
        database: CKDatabase
    ) async throws {
        let shareID = CKRecord.ID(
            recordName: "inbox-share-\(profile.id)-\(friendID)",
            zoneID: privateZoneID
        )

        if let existingShare = try await existingProfileShare(shareID: shareID, database: database) {
            var changed = false
            if existingShare.publicPermission != .none {
                existingShare.publicPermission = .none
                changed = true
            }
            if let friendParticipant, addParticipantIfNeeded(friendParticipant, to: existingShare) {
                changed = true
            }
            if changed {
                _ = try await saveShare(existingShare, in: database, context: "Updating inbox share")
            }
            return
        }

        let share = CKShare(rootRecord: inboxRecord, shareID: shareID)
        share[CKShare.SystemFieldKey.title] = "Friend Requests" as CKRecordValue
        // Keep the inbox private to its single recipient: no public access, only
        // the explicitly-added friend participant can read it and write replies.
        share.publicPermission = .none
        if let friendParticipant {
            _ = addParticipantIfNeeded(friendParticipant, to: share)
        }

        _ = try await saveNewShare(
            rootRecord: inboxRecord,
            share: share,
            in: database,
            context: "Creating friend inbox share"
        )
    }

    /// Adds the friend to the inbox share with read/write access (so they can
    /// receive the request and write the approval back) unless already present.
    @discardableResult
    private func addParticipantIfNeeded(_ participant: CKShare.Participant, to share: CKShare) -> Bool {
        guard let target = participant.userIdentity.userRecordID else {
            return false
        }
        let alreadyPresent = share.participants.contains { existing in
            existing.userIdentity.userRecordID == target
        }
        guard !alreadyPresent else {
            return false
        }
        participant.permission = .readWrite
        share.addParticipant(participant)
        return true
    }

    /// Resolves selected friend profile IDs to their CloudKit user record IDs by
    /// cross-referencing this user's profile-share participants with the mirrored
    /// `participant-profile-*` records that carry each friend's profile ID.
    private func friendUserRecordIDs(
        for friendProfileIDs: [String],
        profile: UserProfile,
        database: CKDatabase
    ) async throws -> [String: CKRecord.ID] {
        guard !friendProfileIDs.isEmpty else {
            return [:]
        }

        let shareID = CKRecord.ID(recordName: "share-\(profile.id)", zoneID: privateZoneID)
        guard let share = try await existingProfileShare(shareID: shareID, database: database) else {
            return [:]
        }

        var userRecordIDByMirrorName: [String: CKRecord.ID] = [:]
        var mirrorRecordIDs: [CKRecord.ID] = []
        for participant in share.participants {
            guard participant.role != .owner,
                  let userRecordID = participant.userIdentity.userRecordID else {
                continue
            }
            let mirrorName = participantProfileRecordName(for: userRecordID)
            if userRecordIDByMirrorName[mirrorName] == nil {
                userRecordIDByMirrorName[mirrorName] = userRecordID
                mirrorRecordIDs.append(CKRecord.ID(recordName: mirrorName, zoneID: privateZoneID))
            }
        }

        guard !mirrorRecordIDs.isEmpty else {
            return [:]
        }

        let wantedProfileIDs = Set(friendProfileIDs)
        let response = try await database.records(for: mirrorRecordIDs)
        var result: [String: CKRecord.ID] = [:]
        for (recordID, recordResult) in response {
            guard let record = try? recordResult.get(),
                  let ownerProfileID = record[Field.ownerProfileID] as? String,
                  wantedProfileIDs.contains(ownerProfileID),
                  let userRecordID = userRecordIDByMirrorName[recordID.recordName] else {
                continue
            }
            result[ownerProfileID] = userRecordID
        }
        return result
    }

    /// Fetches `CKShare.Participant` objects for the given user record IDs so they
    /// can be added to a share. Keyed by user record name.
    private func shareParticipants(
        for userRecordIDs: [CKRecord.ID],
        in container: CKContainer
    ) async throws -> [String: CKShare.Participant] {
        guard !userRecordIDs.isEmpty else {
            return [:]
        }

        let lookupInfos = userRecordIDs.map { CKUserIdentity.LookupInfo(userRecordID: $0) }
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: lookupInfos)
            var participants: [String: CKShare.Participant] = [:]
            operation.perShareParticipantResultBlock = { _, result in
                if case .success(let participant) = result,
                   let recordName = participant.userIdentity.userRecordID?.recordName {
                    participants[recordName] = participant
                }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: participants)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// All zones the user can reach in the shared database — the persisted set
    /// plus any newly delivered shares (e.g. a friend's inbox) discovered live.
    private func allSharedZoneIDs(in container: CKContainer) async -> [CKRecordZone.ID] {
        var seenKeys = Set<String>()
        var zoneIDs: [CKRecordZone.ID] = []

        func add(_ zoneID: CKRecordZone.ID) {
            let key = "\(zoneID.zoneName)|\(zoneID.ownerName)"
            if seenKeys.insert(key).inserted {
                zoneIDs.append(zoneID)
            }
        }

        for zoneID in sharedZoneStore.load() {
            add(zoneID)
        }
        if let zones = try? await container.sharedCloudDatabase.allRecordZones() {
            for zone in zones {
                add(zone.zoneID)
            }
        }
        return zoneIDs
    }

    private func inboxZoneIDs(for friendID: String, in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        var zoneIDs: [CKRecordZone.ID] = [privateZoneID]
        zoneIDs.append(contentsOf: sharedZoneStore.load())
        return zoneIDs
    }

    func migrateLegacyFriendRequests(profile: UserProfile) async throws {
        guard let container else {
            return
        }

        try await ensurePrivateZone(in: container)
        let database = container.privateCloudDatabase

        let query = CKQuery(
            recordType: RecordType.friendTimeRequest,
            predicate: NSPredicate(format: "%K == %@", Field.requesterID, profile.id)
        )

        let response: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?)
        do {
            response = try await database.records(
                matching: query,
                inZoneWith: privateZoneID,
                desiredKeys: [Field.requestID],
                resultsLimit: 200
            )
        } catch {
            if isUnknownItemError(error) {
                return
            }
            throw error
        }

        let legacyRecordIDs = response.matchResults.compactMap { recordID, result -> CKRecord.ID? in
            guard let record = try? result.get() else {
                return nil
            }
            if record.parent?.recordID.recordName.hasPrefix("inbox-") == true {
                return nil
            }
            return record.recordID
        }

        guard !legacyRecordIDs.isEmpty else {
            return
        }

        let deleteResult = try await database.modifyRecords(
            saving: [],
            deleting: legacyRecordIDs,
            savePolicy: .changedKeys,
            atomically: false
        )

        for result in deleteResult.deleteResults.values {
            do {
                _ = try result.get()
            } catch {
                if !isUnknownItemError(error) {
                    throw error
                }
            }
        }
    }

    private func currentUserRecordID(in container: CKContainer) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let recordID else {
                    continuation.resume(
                        throwing: CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                            context: "Loading your iCloud user",
                            reason: "iCloud did not return a user record ID."
                        )
                    )
                    return
                }

                continuation.resume(returning: recordID)
            }
        }
    }

    private func existingProfileShare(shareID: CKRecord.ID, database: CKDatabase) async throws -> CKShare? {
        let records = try await database.records(for: [shareID])
        guard let recordResult = records[shareID] else {
            return nil
        }

        do {
            return try recordResult.get() as? CKShare
        } catch {
            if let cloudError = error as? CKError,
               cloudError.code == .unknownItem {
                return nil
            }

            throw error
        }
    }

    private func saveRecord(_ record: CKRecord, in database: CKDatabase, context: String) async throws -> CKRecord {
        do {
            let result = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )

            return try savedRecord(
                for: record.recordID,
                from: result.saveResults,
                context: context
            )
        } catch {
            if let storeError = error as? CloudKitUsageSnapshotStoreError {
                throw storeError
            }

            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: context,
                reason: cloudKitFailureMessage(for: error)
            )
        }
    }

    private func saveShare(_ share: CKShare, in database: CKDatabase, context: String) async throws -> CKShare {
        let record = try await saveRecord(share, in: database, context: context)
        guard let savedShare = record as? CKShare else {
            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: context,
                reason: "iCloud did not return a share record."
            )
        }

        return savedShare
    }

    private func saveNewShare(
        rootRecord: CKRecord,
        share: CKShare,
        in database: CKDatabase,
        context: String
    ) async throws -> CKShare {
        do {
            let result = try await database.modifyRecords(
                saving: [rootRecord, share],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )

            let record = try savedRecord(
                for: share.recordID,
                from: result.saveResults,
                context: context
            )
            guard let savedShare = record as? CKShare else {
                throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                    context: context,
                    reason: "iCloud did not return a share record."
                )
            }

            return savedShare
        } catch {
            if let storeError = error as? CloudKitUsageSnapshotStoreError {
                throw storeError
            }

            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: context,
                reason: cloudKitFailureMessage(for: error)
            )
        }
    }

    private func savedRecord(
        for recordID: CKRecord.ID,
        from saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        context: String
    ) throws -> CKRecord {
        guard let saveResult = saveResults[recordID] else {
            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: context,
                reason: "iCloud did not return a save result."
            )
        }

        do {
            return try saveResult.get()
        } catch {
            throw CloudKitUsageSnapshotStoreError.cloudKitSaveFailed(
                context: context,
                reason: cloudKitFailureMessage(for: error)
            )
        }
    }

    private func cloudKitFailureMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        let detail = (ckError.partialErrorsByItemID ?? [:])
            .map { item in
                "\(String(describing: item.key)): \(item.value.localizedDescription)"
            }
            .sorted()
            .joined(separator: " ")

        var message = detail.isEmpty ? ckError.localizedDescription : detail

        if ckError.code == .serverRejectedRequest || ckError.code == .unknownItem {
            message += " In TestFlight this usually means the CloudKit Production schema has not been deployed for this container."
        }

        return message
    }

    private func makeProfileRecord(_ profile: UserProfile) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "profile-\(profile.id)", zoneID: privateZoneID)
        return makeProfileRecord(profile, recordID: recordID, includesAvatarImageData: true)
    }

    private func makeProfileRecord(
        _ profile: UserProfile,
        recordID: CKRecord.ID,
        parentRecordID: CKRecord.ID? = nil,
        includesAvatarImageData: Bool = false
    ) -> CKRecord {
        let record = CKRecord(recordType: RecordType.userProfile, recordID: recordID)
        if let parentRecordID {
            record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
        }
        record[Field.ownerProfileID] = profile.id as CKRecordValue
        if let appleUserID = profile.appleUserID, !appleUserID.isEmpty {
            record[Field.appleUserID] = appleUserID as CKRecordValue
        }
        record[Field.displayName] = profile.displayName as CKRecordValue
        record[Field.avatarColorHex] = profile.avatarColorHex as CKRecordValue
        if includesAvatarImageData,
           let avatarImageData = profile.avatarImageData,
           !avatarImageData.isEmpty {
            record[Field.avatarImageData] = avatarImageData as CKRecordValue
        }
        record[Field.shareStatus] = profile.shareStatus.rawValue as CKRecordValue
        record[Field.updatedAt] = profile.updatedAt as CKRecordValue
        return record
    }

    private func configureProfileShare(_ share: CKShare, profile: UserProfile) {
        share[CKShare.SystemFieldKey.title] = "\(profile.displayName)'s Screen Time" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.jdco.ScreenTimeSharing.profile" as CKRecordValue
        if let avatarImageData = profile.avatarImageData, !avatarImageData.isEmpty {
            share[CKShare.SystemFieldKey.thumbnailImageData] = avatarImageData as CKRecordValue
        } else {
            share[CKShare.SystemFieldKey.thumbnailImageData] = nil
        }
        // Participants must write their own `participant-profile-*` mirror record
        // back into this shared zone for bi-directional discovery, so the share
        // needs write access. The privacy boundary is enforced per-record-type,
        // not by share permission.
        share.publicPermission = .readWrite
    }

    private func makeSnapshotRecord(
        _ payload: DailyUsageSnapshotRecordPayload,
        profileRecordID: CKRecord.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "snapshot-\(payload.recordName)", zoneID: privateZoneID)
        return makeSnapshotRecord(payload, profileRecordID: profileRecordID, recordID: recordID)
    }

    private func makeSnapshotRecord(
        _ payload: DailyUsageSnapshotRecordPayload,
        profileRecordID: CKRecord.ID,
        recordID: CKRecord.ID
    ) -> CKRecord {
        let record = CKRecord(recordType: RecordType.dailyUsageSnapshot, recordID: recordID)
        record.parent = CKRecord.Reference(recordID: profileRecordID, action: .none)
        record[Field.profileReference] = CKRecord.Reference(recordID: profileRecordID, action: .none)
        record[Field.ownerProfileID] = payload.ownerProfileID as CKRecordValue
        record[Field.date] = payload.date as CKRecordValue
        record[Field.calendarIdentifier] = payload.calendarIdentifier as CKRecordValue
        record[Field.timeZoneIdentifier] = payload.timeZoneIdentifier as CKRecordValue
        record[Field.lastUpdated] = payload.lastUpdated as CKRecordValue
        record[Field.capabilityStatus] = payload.capabilityStatus as CKRecordValue

        if let totalDuration = payload.totalDuration {
            record[Field.totalDuration] = NSNumber(value: totalDuration)
        }

        if let selectedAppDuration = payload.selectedAppDuration {
            record[Field.selectedAppDuration] = NSNumber(value: selectedAppDuration)
        }

        if let appRowsJSON = payload.appRowsJSON {
            record[Field.appRowsJSON] = appRowsJSON as CKRecordValue
        }

        if let capabilityReason = payload.capabilityReason {
            record[Field.capabilityReason] = capabilityReason as CKRecordValue
        }

        return record
    }

    #if DEBUG
    private static let schemaBootstrapJPEGData = Data([0xFF, 0xD8, 0xFF, 0xD9])

    private func bootstrapAvatarImageDataField(profile: UserProfile, in database: CKDatabase) async throws {
        let recordID = CKRecord.ID(recordName: "schema-bootstrap-avatar-\(profile.id)", zoneID: privateZoneID)
        let record = makeProfileRecord(profile, recordID: recordID, includesAvatarImageData: true)
        let saveResult = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )

        for result in saveResult.saveResults.values {
            _ = try result.get()
        }

        let deleteResult = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .changedKeys,
            atomically: false
        )

        for result in deleteResult.deleteResults.values {
            _ = try result.get()
        }
    }

    private func deleteSchemaBootstrapRecords(
        snapshot: DailyUsageSnapshot,
        request: BlockFriendRequest,
        profile: UserProfile,
        in database: CKDatabase
    ) async throws {
        let payload = try SnapshotRecordPayloadMapper.payload(from: snapshot)
        var recordIDs: [CKRecord.ID] = []
        if let snapshotPayload = payload {
            recordIDs.append(CKRecord.ID(recordName: "snapshot-\(snapshotPayload.recordName)", zoneID: privateZoneID))
        }
        recordIDs.append(CKRecord.ID(recordName: "friend-request-\(request.id)", zoneID: privateZoneID))
        for friendID in request.selectedFriendIDs {
            recordIDs.append(CKRecord.ID(recordName: "inbox-share-\(profile.id)-\(friendID)", zoneID: privateZoneID))
            recordIDs.append(CKRecord.ID(recordName: "inbox-\(profile.id)-\(friendID)", zoneID: privateZoneID))
        }

        guard !recordIDs.isEmpty else {
            return
        }

        let result = try await database.modifyRecords(
            saving: [],
            deleting: recordIDs,
            savePolicy: .changedKeys,
            atomically: false
        )

        for deleteResult in result.deleteResults.values {
            do {
                _ = try deleteResult.get()
            } catch {
                if !isUnknownItemError(error) {
                    throw error
                }
            }
        }
    }
    #endif

    private func records(
        ofType recordType: String,
        in database: CKDatabase,
        zoneID: CKRecordZone.ID,
        sortedBy field: String
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: field, ascending: false)]

        let response = try await database.records(
            matching: query,
            inZoneWith: zoneID,
            desiredKeys: nil,
            resultsLimit: 12
        )

        return try response.matchResults.map { _, result in
            try result.get()
        }
    }

    private func sharedProfileRecord(
        rootRecordID: CKRecord.ID?,
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> CKRecord? {
        if let rootRecordID {
            let response = try await database.records(for: [rootRecordID])
            if let result = response[rootRecordID] {
                do {
                    return try result.get()
                } catch {
                    if !isUnknownItemError(error) {
                        throw error
                    }
                }
            }
        }

        return nil
    }

    private func latestSharedSnapshotRecord(
        for profileRecord: CKRecord,
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        now: Date
    ) async throws -> CKRecord? {
        let profileID = profileID(from: profileRecord)
        let recordIDs = recentSnapshotRecordIDs(profileID: profileID, zoneID: zoneID, now: now)
        guard !recordIDs.isEmpty else {
            return nil
        }

        let response = try await database.records(for: recordIDs)
        let records = response.compactMap { _, result -> CKRecord? in
            try? result.get()
        }

        return records.max { lhs, rhs in
            let lhsDate = lhs[Field.lastUpdated] as? Date ?? .distantPast
            let rhsDate = rhs[Field.lastUpdated] as? Date ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    private func recentSnapshotRecordIDs(
        profileID: String,
        zoneID: CKRecordZone.ID,
        now: Date,
        dayCount: Int = 14
    ) -> [CKRecord.ID] {
        var currentCalendar = Calendar(identifier: .gregorian)
        currentCalendar.timeZone = .current

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        var recordNames: [String] = []
        var seenRecordNames = Set<String>()

        for calendar in [currentCalendar, utcCalendar] {
            for offset in -1...dayCount {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else {
                    continue
                }

                let snapshotID = UsageDateBoundary.snapshotID(
                    profileID: profileID,
                    date: date,
                    calendar: calendar
                )
                let recordName = "snapshot-\(snapshotID)"
                guard seenRecordNames.insert(recordName).inserted else {
                    continue
                }
                recordNames.append(recordName)
            }
        }

        return recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
    }

    private func sharedShareRecord(
        share: SharedZoneStore.AcceptedShare,
        profileID: String,
        database: CKDatabase
    ) async throws -> CKShare? {
        var recordIDs: [CKRecord.ID] = []
        var seenRecordNames = Set<String>()

        for recordID in [
            share.shareID,
            CKRecord.ID(recordName: "share-\(profileID)", zoneID: share.zoneID)
        ].compactMap({ $0 }) where seenRecordNames.insert(recordID.recordName).inserted {
            recordIDs.append(recordID)
        }

        guard !recordIDs.isEmpty else {
            return nil
        }

        let response = try await database.records(for: recordIDs)
        for recordID in recordIDs {
            guard let result = response[recordID] else {
                continue
            }

            do {
                if let share = try result.get() as? CKShare {
                    return share
                }
            } catch {
                if !isUnknownItemError(error) {
                    throw error
                }
            }
        }

        return nil
    }

    private func acceptedParticipantSummaries(
        for profile: UserProfile,
        now: Date
    ) async throws -> [FriendUsageSummary] {
        guard let container else {
            return []
        }

        let database = container.privateCloudDatabase
        var recordIDs: [CKRecord.ID] = []
        var seenRecordNames = Set<String>()

        let shareID = CKRecord.ID(recordName: "share-\(profile.id)", zoneID: privateZoneID)
        if let share = try await existingProfileShare(shareID: shareID, database: database) {
            for id in acceptedParticipantProfileRecordIDs(from: share, zoneID: privateZoneID)
                where seenRecordNames.insert(id.recordName).inserted {
                recordIDs.append(id)
            }
        }

        let participantQuery = CKQuery(
            recordType: RecordType.userProfile,
            predicate: NSPredicate(format: "%K != %@", Field.ownerProfileID, profile.id)
        )
        do {
            let queryResponse = try await database.records(
                matching: participantQuery,
                inZoneWith: privateZoneID,
                desiredKeys: nil,
                resultsLimit: 50
            )
            for (_, result) in queryResponse.matchResults {
                if let record = try? result.get(),
                   record.recordID.recordName.hasPrefix("participant-profile-"),
                   seenRecordNames.insert(record.recordID.recordName).inserted {
                    recordIDs.append(record.recordID)
                }
            }
        } catch {
            if !isUnknownItemError(error) {
                throw error
            }
        }

        guard !recordIDs.isEmpty else {
            return []
        }

        let response = try await database.records(for: recordIDs)
        var summaries: [FriendUsageSummary] = []

        for recordID in recordIDs {
            guard let result = response[recordID] else {
                continue
            }

            let profileRecord: CKRecord
            do {
                profileRecord = try result.get()
            } catch {
                if isUnknownItemError(error) {
                    continue
                }
                throw error
            }

            let snapshotRecord = try await latestSharedSnapshotRecord(
                for: profileRecord,
                database: database,
                zoneID: privateZoneID,
                now: now
            )
            summaries.append(
                makeFriendSummary(
                    profileRecord: profileRecord,
                    snapshotRecord: snapshotRecord,
                    shareRecord: nil,
                    now: now
                )
            )
        }

        return summaries
    }

    private func acceptedParticipantProfileRecordIDs(from share: CKShare, zoneID: CKRecordZone.ID) -> [CKRecord.ID] {
        var seenRecordNames = Set<String>()
        return share.participants.compactMap { participant in
            guard participant.acceptanceStatus == .accepted,
                  participant.role != .owner,
                  let userRecordID = participant.userIdentity.userRecordID else {
                return nil
            }

            let recordName = participantProfileRecordName(for: userRecordID)
            guard seenRecordNames.insert(recordName).inserted else {
                return nil
            }

            return CKRecord.ID(recordName: recordName, zoneID: zoneID)
        }
    }

    private func publishParticipantMirrors(
        profile: UserProfile,
        snapshot: DailyUsageSnapshot?,
        userRecordID: CKRecord.ID,
        shares: [SharedZoneStore.AcceptedShare],
        database: CKDatabase
    ) async throws {
        for share in shares {
            guard let rootRecordID = share.rootRecordID else {
                continue
            }

            let profileRecordID = CKRecord.ID(
                recordName: participantProfileRecordName(for: userRecordID),
                zoneID: share.zoneID
            )
            let profileRecord = makeProfileRecord(
                profile,
                recordID: profileRecordID,
                parentRecordID: rootRecordID,
                includesAvatarImageData: true
            )
            var recordsToSave = [profileRecord]

            if let snapshot,
               let payload = try SnapshotRecordPayloadMapper.payload(from: snapshot) {
                let snapshotRecordID = CKRecord.ID(
                    recordName: "snapshot-\(payload.recordName)",
                    zoneID: share.zoneID
                )
                recordsToSave.append(
                    makeSnapshotRecord(
                        payload,
                        profileRecordID: profileRecordID,
                        recordID: snapshotRecordID
                    )
                )
            }

            do {
                try await saveParticipantMirrorRecords(recordsToSave, in: database)
            } catch {
                guard profile.avatarImageData != nil else {
                    throw error
                }

                recordsToSave[0] = makeProfileRecord(
                    profile,
                    recordID: profileRecordID,
                    parentRecordID: rootRecordID,
                    includesAvatarImageData: false
                )
                try await saveParticipantMirrorRecords(recordsToSave, in: database)
            }
        }
    }

    private func saveParticipantMirrorRecords(_ records: [CKRecord], in database: CKDatabase) async throws {
        let result = try await database.modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false
        )

        for saveResult in result.saveResults.values {
            _ = try saveResult.get()
        }
    }

    private func participantProfileRecordName(for userRecordID: CKRecord.ID) -> String {
        "participant-profile-\(recordNameComponent(for: userRecordID.recordName))"
    }

    private func recordNameComponent(for value: String) -> String {
        let encoded = Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return encoded.isEmpty ? "unknown" : encoded
    }

    private func friendRequestRecords(in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: RecordType.friendTimeRequest,
            predicate: NSPredicate(format: "%K IN %@", Field.status, BlockRequestStatus.allCases.map(\.rawValue))
        )

        do {
            let response = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: nil,
                resultsLimit: 100
            )

            return try response.matchResults.map { _, result in
                try result.get()
            }
        } catch {
            if isUnknownItemError(error) {
                return []
            }
            throw error
        }
    }

    private func friendRequestRecords(
        ids: Set<String>,
        in database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [CKRecord] {
        let recordIDs = ids.map { CKRecord.ID(recordName: "friend-request-\($0)", zoneID: zoneID) }
        guard !recordIDs.isEmpty else {
            return []
        }

        do {
            let response = try await database.records(for: recordIDs)
            return response.compactMap { _, result in
                try? result.get()
            }
        } catch {
            if isUnknownItemError(error) {
                return []
            }
            throw error
        }
    }

    private func updateFriendRequest(
        _ request: BlockFriendRequest,
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> Bool {
        guard let existingRecord = try await friendRequestRecord(id: request.id, database: database, zoneID: zoneID) else {
            return false
        }

        let updatedRecord = try makeFriendRequestRecord(
            request,
            profileRecordID: existingRecord.parent?.recordID,
            existingRecord: existingRecord,
            photoData: nil
        )
        let result = try await database.modifyRecords(
            saving: [updatedRecord.record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        try updatedRecord.cleanup()
        for saveResult in result.saveResults.values {
            _ = try saveResult.get()
        }
        return true
    }

    private func friendRequestRecord(
        id: String,
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: "friend-request-\(id)", zoneID: zoneID)
        let response = try await database.records(for: [recordID])

        guard let result = response[recordID] else {
            return nil
        }

        do {
            return try result.get()
        } catch {
            if isUnknownItemError(error) {
                return nil
            }
            throw error
        }
    }

    private struct PreparedFriendRequestRecord {
        let record: CKRecord
        let temporaryAssetURL: URL?

        func cleanup() throws {
            if let temporaryAssetURL {
                try? FileManager.default.removeItem(at: temporaryAssetURL)
            }
        }
    }

    private func makeFriendRequestRecord(
        _ request: BlockFriendRequest,
        profileRecordID: CKRecord.ID?,
        existingRecord: CKRecord?,
        photoData: Data?
    ) throws -> PreparedFriendRequestRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.friendTimeRequest,
            recordID: CKRecord.ID(recordName: "friend-request-\(request.id)", zoneID: privateZoneID)
        )

        if let profileRecordID {
            record.parent = CKRecord.Reference(recordID: profileRecordID, action: .none)
            record[Field.profileReference] = CKRecord.Reference(recordID: profileRecordID, action: .none)
        }

        record[Field.requestID] = request.id as CKRecordValue
        record[Field.groupID] = request.groupID as CKRecordValue
        record[Field.requestedSeconds] = NSNumber(value: request.requestedSeconds)
        record[Field.selectedFriendIDs] = request.selectedFriendIDs as NSArray
        record[Field.message] = request.message as CKRecordValue
        record[Field.status] = request.status.rawValue as CKRecordValue
        record[Field.createdAt] = request.createdAt as CKRecordValue

        setOptionalString(request.requesterID, for: Field.requesterID, on: record)
        setOptionalString(request.requesterDisplayName, for: Field.requesterDisplayName, on: record)
        setOptionalString(request.approvedByFriendID, for: Field.approvedByFriendID, on: record)
        setOptionalDate(request.resolvedAt, for: Field.resolvedAt, on: record)
        setOptionalDate(request.collectedAt, for: Field.collectedAt, on: record)
        setOptionalDate(request.expiresAt, for: Field.expiresAt, on: record)
        setOptionalDate(request.approvedExpiresAt, for: Field.approvedExpiresAt, on: record)

        let temporaryURL: URL?
        if let photoData, !photoData.isEmpty {
            let assetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("friend-request-\(request.id)-\(UUID().uuidString).jpg")
            try photoData.write(to: assetURL, options: [.atomic])
            record[Field.photoAsset] = CKAsset(fileURL: assetURL)
            temporaryURL = assetURL
        } else {
            temporaryURL = nil
        }

        return PreparedFriendRequestRecord(record: record, temporaryAssetURL: temporaryURL)
    }

    private func makeFriendRequest(
        record: CKRecord,
        savePhotoData: (String, Data) throws -> BlockFriendRequestPhotoReference
    ) -> BlockFriendRequest? {
        guard let id = record[Field.requestID] as? String,
              let groupID = record[Field.groupID] as? String,
              let requestedSeconds = (record[Field.requestedSeconds] as? NSNumber)?.doubleValue,
              let statusRaw = record[Field.status] as? String,
              let status = BlockRequestStatus(rawValue: statusRaw),
              let createdAt = record[Field.createdAt] as? Date else {
            return nil
        }
        let selectedFriendIDs = Self.stringArray(from: record[Field.selectedFriendIDs])

        let photoReference: BlockFriendRequestPhotoReference?
        if let asset = record[Field.photoAsset] as? CKAsset,
           let fileURL = asset.fileURL,
           let data = try? Data(contentsOf: fileURL) {
            photoReference = try? savePhotoData(id, data)
        } else {
            photoReference = nil
        }

        return BlockFriendRequest(
            id: id,
            groupID: groupID,
            requestedSeconds: requestedSeconds,
            selectedFriendIDs: selectedFriendIDs,
            message: record[Field.message] as? String ?? "",
            requesterID: record[Field.requesterID] as? String,
            requesterDisplayName: record[Field.requesterDisplayName] as? String,
            approvedByFriendID: record[Field.approvedByFriendID] as? String,
            status: status,
            createdAt: createdAt,
            resolvedAt: record[Field.resolvedAt] as? Date,
            collectedAt: record[Field.collectedAt] as? Date,
            expiresAt: record[Field.expiresAt] as? Date,
            approvedExpiresAt: record[Field.approvedExpiresAt] as? Date,
            photoReference: photoReference
        )
    }

    private func setOptionalString(_ value: String?, for key: String, on record: CKRecord) {
        if let value {
            record[key] = value as CKRecordValue
        } else {
            record[key] = nil
        }
    }

    private func setOptionalDate(_ value: Date?, for key: String, on record: CKRecord) {
        if let value {
            record[key] = value as CKRecordValue
        } else {
            record[key] = nil
        }
    }

    private static func stringArray(from value: CKRecordValue?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }

        if let strings = value as? [NSString] {
            return strings.map { String($0) }
        }

        if let array = value as? NSArray {
            return array.compactMap { $0 as? String }
        }

        return []
    }

    private func isUnknownItemError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else {
            return false
        }

        return ckError.code == .unknownItem || ckError.code == .zoneNotFound
    }

    private func makeFriendSummary(
        profileRecord: CKRecord,
        snapshotRecord: CKRecord?,
        shareRecord: CKShare?,
        now: Date
    ) -> FriendUsageSummary {
        let profileID = profileID(from: profileRecord)
        let profileDisplayName = profileRecord[Field.displayName] as? String
        let displayName = resolvedDisplayName(profileDisplayName: profileDisplayName, shareRecord: shareRecord)
        let avatarColorHex = profileRecord[Field.avatarColorHex] as? String ?? AppConfiguration.defaultAvatarColor
        let avatarImageData = shareRecord.flatMap(shareThumbnailImageData) ?? profileAvatarImageData(from: profileRecord)
        let totalDuration = (snapshotRecord?[Field.totalDuration] as? NSNumber)?.doubleValue
        let selectedAppDuration = (snapshotRecord?[Field.selectedAppDuration] as? NSNumber)?.doubleValue
        let lastUpdated = snapshotRecord?[Field.lastUpdated] as? Date
        let statusRaw = snapshotRecord?[Field.capabilityStatus] as? String
        let status = statusRaw.flatMap(ScreenTimeCapabilityStatus.init(rawValue:)) ?? .unavailable
        let reason = (snapshotRecord?[Field.capabilityReason] as? String) ?? "Waiting for Screen Time"

        return FriendUsageSummary(
            id: profileID,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            avatarImageData: avatarImageData,
            totalDuration: totalDuration,
            selectedAppDuration: selectedAppDuration,
            capability: ScreenTimeCapability(status: status, reason: reason),
            lastUpdated: lastUpdated,
            isStale: lastUpdated.map { now.timeIntervalSince($0) > 3_600 } ?? true
        )
    }

    private func preferredSummary(_ lhs: FriendUsageSummary, _ rhs: FriendUsageSummary) -> FriendUsageSummary {
        let lhsDate = lhs.lastUpdated ?? .distantPast
        let rhsDate = rhs.lastUpdated ?? .distantPast
        var preferred = rhsDate >= lhsDate ? rhs : lhs
        let fallback = rhsDate >= lhsDate ? lhs : rhs

        if preferred.avatarImageData == nil {
            preferred.avatarImageData = fallback.avatarImageData
        }

        if preferred.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || preferred.displayName.localizedCaseInsensitiveCompare("Friend") == .orderedSame
            || preferred.displayName.localizedCaseInsensitiveCompare("Me") == .orderedSame {
            preferred.displayName = fallback.displayName
        }

        if preferred.totalDuration == nil {
            preferred.totalDuration = fallback.totalDuration
            preferred.selectedAppDuration = fallback.selectedAppDuration
            preferred.capability = fallback.capability
            preferred.lastUpdated = fallback.lastUpdated
            preferred.isStale = fallback.isStale
        }

        return preferred
    }

    private func resolvedDisplayName(profileDisplayName: String?, shareRecord: CKShare?) -> String {
        let trimmedProfileName = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedProfileName.isEmpty,
           trimmedProfileName.localizedCaseInsensitiveCompare("Me") != .orderedSame {
            return trimmedProfileName
        }

        if let shareTitle = shareRecord?[CKShare.SystemFieldKey.title] as? String,
           let titleName = profileName(fromShareTitle: shareTitle) {
            return titleName
        }

        return trimmedProfileName.isEmpty ? "Friend" : trimmedProfileName
    }

    private func profileName(fromShareTitle title: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = ["'s Screen Time", "’s Screen Time"]

        for suffix in suffixes where trimmedTitle.hasSuffix(suffix) {
            let name = String(trimmedTitle.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name.localizedCaseInsensitiveCompare("Me") != .orderedSame {
                return name
            }
        }

        return nil
    }

    private func shareThumbnailImageData(_ share: CKShare) -> Data? {
        if let data = share[CKShare.SystemFieldKey.thumbnailImageData] as? Data {
            return data
        }

        if let data = share[CKShare.SystemFieldKey.thumbnailImageData] as? NSData {
            return data as Data
        }

        return nil
    }

    private func profileAvatarImageData(from profileRecord: CKRecord) -> Data? {
        if let data = profileRecord[Field.avatarImageData] as? Data {
            return data
        }

        if let data = profileRecord[Field.avatarImageData] as? NSData {
            return data as Data
        }

        return nil
    }

    private func profileID(from profileRecord: CKRecord) -> String {
        profileRecord[Field.ownerProfileID] as? String
            ?? profileRecord.recordID.recordName.replacingOccurrences(of: "profile-", with: "")
    }

    private func friendRequestSortDate(_ request: BlockFriendRequest) -> Date {
        request.collectedAt ?? request.resolvedAt ?? request.createdAt
    }
}

@MainActor
final class SharedZoneStore {
    struct AcceptedShare: Equatable {
        var zoneID: CKRecordZone.ID
        var rootRecordID: CKRecord.ID?
        var shareID: CKRecord.ID?
    }

    private struct StoredShare: Codable, Equatable {
        var zoneName: String
        var ownerName: String
        var rootRecordName: String?
        var shareRecordName: String?

        var zoneID: CKRecordZone.ID {
            CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        }

        var rootRecordID: CKRecord.ID? {
            rootRecordName.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        }

        var shareID: CKRecord.ID? {
            shareRecordName.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        }
    }

    private let defaults: UserDefaults
    private let key = "AcceptedCloudKitShareZones.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [CKRecordZone.ID] {
        loadShares().map(\.zoneID)
    }

    func loadShares() -> [AcceptedShare] {
        loadStoredShares().map { share in
            AcceptedShare(zoneID: share.zoneID, rootRecordID: share.rootRecordID, shareID: share.shareID)
        }
    }

    func insert(shareID: CKRecord.ID, rootRecordID: CKRecord.ID?) {
        var shares = loadStoredShares()
        shares.removeAll { storedShare in
            storedShare.zoneName == shareID.zoneID.zoneName
                && storedShare.ownerName == shareID.zoneID.ownerName
        }
        shares.append(
            StoredShare(
                zoneName: shareID.zoneID.zoneName,
                ownerName: shareID.zoneID.ownerName,
                rootRecordName: rootRecordID?.recordName,
                shareRecordName: shareID.recordName
            )
        )

        save(shares)
    }

    private func loadStoredShares() -> [StoredShare] {
        guard let data = defaults.data(forKey: key),
              let shares = try? JSONDecoder().decode([StoredShare].self, from: data) else {
            return []
        }

        return shares
    }

    private func save(_ shares: [StoredShare]) {
        guard let data = try? JSONEncoder().encode(shares) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
