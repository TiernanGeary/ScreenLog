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

    var errorDescription: String? {
        "iCloud sharing is unavailable in this simulator build."
    }
}

@MainActor
final class CloudKitUsageSnapshotStore {
    private enum RecordType {
        static let userProfile = "UserProfile"
        static let dailyUsageSnapshot = "DailyUsageSnapshot"
        static let friendTimeRequest = "FriendTimeRequest"
    }

    private enum Field {
        static let displayName = "displayName"
        static let avatarColorHex = "avatarColorHex"
        static let shareStatus = "shareStatus"
        static let updatedAt = "updatedAt"
        static let ownerProfileID = "ownerProfileID"
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
    }

    func prepareProfileShare(profile: UserProfile) async throws -> (share: CKShare, container: CKContainer) {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)

        var sharingProfile = profile
        sharingProfile.shareStatus = .sharing
        sharingProfile.updatedAt = Date()

        let profileRecord = makeProfileRecord(sharingProfile)
        let shareID = CKRecord.ID(recordName: "share-\(profile.id)", zoneID: privateZoneID)
        let share = CKShare(rootRecord: profileRecord, shareID: shareID)
        share[CKShare.SystemFieldKey.title] = "\(profile.displayName)'s Screen Time" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.jdco.ScreenTimeSharing.profile" as CKRecordValue
        share.publicPermission = .none

        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [profileRecord, share],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        for saveResult in result.saveResults.values {
            _ = try saveResult.get()
        }

        return (share, container)
    }

    func publishFriendRequest(
        _ request: BlockFriendRequest,
        profile: UserProfile,
        photoData: Data?
    ) async throws {
        guard let container else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        try await ensurePrivateZone(in: container)

        let profileRecord = makeProfileRecord(profile)
        let requestRecord = try makeFriendRequestRecord(
            request,
            profileRecordID: profileRecord.recordID,
            existingRecord: nil,
            photoData: photoData
        )

        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [profileRecord, requestRecord.record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        try requestRecord.cleanup()
        for saveResult in result.saveResults.values {
            _ = try saveResult.get()
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

        for zoneID in sharedZoneStore.load() {
            if try await updateFriendRequest(request, database: container.sharedCloudDatabase, zoneID: zoneID) {
                return
            }
        }
    }

    func fetchFriendRequests(
        savePhotoData: (String, Data) throws -> BlockFriendRequestPhotoReference
    ) async throws -> [BlockFriendRequest] {
        guard let container else {
            return []
        }

        try await ensurePrivateZone(in: container)

        var requests: [BlockFriendRequest] = []
        requests.append(
            contentsOf: try await friendRequestRecords(in: container.privateCloudDatabase, zoneID: privateZoneID)
                .compactMap { record in
                    makeFriendRequest(record: record, savePhotoData: savePhotoData)
                }
        )

        for zoneID in sharedZoneStore.load() {
            requests.append(
                contentsOf: try await friendRequestRecords(in: container.sharedCloudDatabase, zoneID: zoneID)
                    .compactMap { record in
                        makeFriendRequest(record: record, savePhotoData: savePhotoData)
                    }
            )
        }

        return requests.sorted { friendRequestSortDate($0) > friendRequestSortDate($1) }
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard container != nil else {
            throw CloudKitUsageSnapshotStoreError.unavailableInSimulator
        }

        let acceptingContainer = CKContainer(identifier: metadata.containerIdentifier)
        let result = try await acceptingContainer.accept([metadata])

        for (_, shareResult) in result {
            let share = try shareResult.get()
            sharedZoneStore.insert(share.recordID.zoneID)
        }
    }

    func fetchFriendSummaries(now: Date = Date()) async throws -> [FriendUsageSummary] {
        guard let container else {
            return []
        }

        var summaries: [FriendUsageSummary] = []

        for zoneID in sharedZoneStore.load() {
            async let profileRecords = records(
                ofType: RecordType.userProfile,
                in: container.sharedCloudDatabase,
                zoneID: zoneID,
                sortedBy: Field.updatedAt
            )
            async let snapshotRecords = records(
                ofType: RecordType.dailyUsageSnapshot,
                in: container.sharedCloudDatabase,
                zoneID: zoneID,
                sortedBy: Field.lastUpdated
            )

            guard let profileRecord = try await profileRecords.first else {
                continue
            }
            let snapshotRecord = try? await snapshotRecords.first

            let summary = makeFriendSummary(
                profileRecord: profileRecord,
                snapshotRecord: snapshotRecord,
                now: now
            )
            summaries.append(summary)
        }

        return summaries.sorted { lhs, rhs in
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

    private func makeProfileRecord(_ profile: UserProfile) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "profile-\(profile.id)", zoneID: privateZoneID)
        let record = CKRecord(recordType: RecordType.userProfile, recordID: recordID)
        record[Field.ownerProfileID] = profile.id as CKRecordValue
        record[Field.displayName] = profile.displayName as CKRecordValue
        record[Field.avatarColorHex] = profile.avatarColorHex as CKRecordValue
        record[Field.shareStatus] = profile.shareStatus.rawValue as CKRecordValue
        record[Field.updatedAt] = profile.updatedAt as CKRecordValue
        return record
    }

    private func makeSnapshotRecord(
        _ payload: DailyUsageSnapshotRecordPayload,
        profileRecordID: CKRecord.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "snapshot-\(payload.recordName)", zoneID: privateZoneID)
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

    private func friendRequestRecords(in database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(recordType: RecordType.friendTimeRequest, predicate: NSPredicate(value: true))

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

        return ckError.code == .unknownItem
    }

    private func makeFriendSummary(
        profileRecord: CKRecord,
        snapshotRecord: CKRecord?,
        now: Date
    ) -> FriendUsageSummary {
        let profileID = profileRecord[Field.ownerProfileID] as? String
            ?? profileRecord.recordID.recordName.replacingOccurrences(of: "profile-", with: "")
        let displayName = profileRecord[Field.displayName] as? String ?? "Friend"
        let avatarColorHex = profileRecord[Field.avatarColorHex] as? String ?? AppConfiguration.defaultAvatarColor
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
            totalDuration: totalDuration,
            selectedAppDuration: selectedAppDuration,
            capability: ScreenTimeCapability(status: status, reason: reason),
            lastUpdated: lastUpdated,
            isStale: lastUpdated.map { now.timeIntervalSince($0) > 3_600 } ?? true
        )
    }

    private func friendRequestSortDate(_ request: BlockFriendRequest) -> Date {
        request.collectedAt ?? request.resolvedAt ?? request.createdAt
    }
}

@MainActor
final class SharedZoneStore {
    private struct StoredZone: Codable, Hashable {
        var zoneName: String
        var ownerName: String
    }

    private let defaults: UserDefaults
    private let key = "AcceptedCloudKitShareZones.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [CKRecordZone.ID] {
        guard let data = defaults.data(forKey: key),
              let zones = try? JSONDecoder().decode([StoredZone].self, from: data) else {
            return []
        }

        return zones.map {
            CKRecordZone.ID(zoneName: $0.zoneName, ownerName: $0.ownerName)
        }
    }

    func insert(_ zoneID: CKRecordZone.ID) {
        var zones = Set(load().map {
            StoredZone(zoneName: $0.zoneName, ownerName: $0.ownerName)
        })
        zones.insert(StoredZone(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName))

        guard let data = try? JSONEncoder().encode(Array(zones)) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
