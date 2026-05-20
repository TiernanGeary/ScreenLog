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

@MainActor
final class CloudKitUsageSnapshotStore {
    private enum RecordType {
        static let userProfile = "UserProfile"
        static let dailyUsageSnapshot = "DailyUsageSnapshot"
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
    }

    private let container: CKContainer
    private let sharedZoneStore: SharedZoneStore

    init(
        containerIdentifier: String = AppConfiguration.cloudKitContainerIdentifier,
        sharedZoneStore: SharedZoneStore = SharedZoneStore()
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.sharedZoneStore = sharedZoneStore
    }

    func cloudAvailability() async -> CloudAvailability {
        await withCheckedContinuation { continuation in
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
        guard let payload = try SnapshotRecordPayloadMapper.payload(from: snapshot) else {
            return
        }

        try await ensurePrivateZone()

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
        try await ensurePrivateZone()

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

    func acceptShare(metadata: CKShare.Metadata) async throws {
        let acceptingContainer = CKContainer(identifier: metadata.containerIdentifier)
        let result = try await acceptingContainer.accept([metadata])

        for (_, shareResult) in result {
            let share = try shareResult.get()
            sharedZoneStore.insert(share.recordID.zoneID)
        }
    }

    func fetchFriendSummaries(now: Date = Date()) async throws -> [FriendUsageSummary] {
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

            guard let profileRecord = try await profileRecords.first,
                  let snapshotRecord = try await snapshotRecords.first else {
                continue
            }

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

    private func ensurePrivateZone() async throws {
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

    private func makeFriendSummary(
        profileRecord: CKRecord,
        snapshotRecord: CKRecord,
        now: Date
    ) -> FriendUsageSummary {
        let displayName = profileRecord[Field.displayName] as? String ?? "Friend"
        let avatarColorHex = profileRecord[Field.avatarColorHex] as? String ?? AppConfiguration.defaultAvatarColor
        let totalDuration = (snapshotRecord[Field.totalDuration] as? NSNumber)?.doubleValue
        let selectedAppDuration = (snapshotRecord[Field.selectedAppDuration] as? NSNumber)?.doubleValue
        let lastUpdated = snapshotRecord[Field.lastUpdated] as? Date
        let statusRaw = snapshotRecord[Field.capabilityStatus] as? String
        let status = statusRaw.flatMap(ScreenTimeCapabilityStatus.init(rawValue:)) ?? .unavailable
        let reason = snapshotRecord[Field.capabilityReason] as? String

        return FriendUsageSummary(
            id: profileRecord.recordID.recordName,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            totalDuration: totalDuration,
            selectedAppDuration: selectedAppDuration,
            capability: ScreenTimeCapability(status: status, reason: reason),
            lastUpdated: lastUpdated,
            isStale: lastUpdated.map { now.timeIntervalSince($0) > 3_600 } ?? true
        )
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
