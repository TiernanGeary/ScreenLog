import Foundation

public struct DailyUsageSnapshotRecordPayload: Codable, Equatable, Sendable {
    public var recordName: String
    public var ownerProfileID: String
    public var date: Date
    public var calendarIdentifier: String
    public var timeZoneIdentifier: String
    public var totalDuration: TimeInterval?
    public var selectedAppDuration: TimeInterval?
    public var appRowsJSON: Data?
    public var lastUpdated: Date
    public var capabilityStatus: String
    public var capabilityReason: String?
}

public enum SnapshotRecordPayloadMapper {
    public static func payload(from snapshot: DailyUsageSnapshot) throws -> DailyUsageSnapshotRecordPayload? {
        guard let uploadable = snapshot.sanitizedForUpload() else {
            return nil
        }

        let rowsData: Data?
        if uploadable.appRows.isEmpty {
            rowsData = nil
        } else {
            rowsData = try JSONEncoder().encode(uploadable.appRows)
        }

        return DailyUsageSnapshotRecordPayload(
            recordName: uploadable.id,
            ownerProfileID: uploadable.ownerProfileID,
            date: uploadable.date,
            calendarIdentifier: uploadable.calendarIdentifier,
            timeZoneIdentifier: uploadable.timeZoneIdentifier,
            totalDuration: uploadable.totalDuration,
            selectedAppDuration: uploadable.selectedAppDuration,
            appRowsJSON: rowsData,
            lastUpdated: uploadable.lastUpdated,
            capabilityStatus: uploadable.capability.status.rawValue,
            capabilityReason: uploadable.capability.reason
        )
    }

    public static func snapshot(from payload: DailyUsageSnapshotRecordPayload) throws -> DailyUsageSnapshot {
        let rows: [SharedAppUsage]
        if let appRowsJSON = payload.appRowsJSON {
            rows = try JSONDecoder().decode([SharedAppUsage].self, from: appRowsJSON)
        } else {
            rows = []
        }

        let status = ScreenTimeCapabilityStatus(rawValue: payload.capabilityStatus) ?? .unavailable
        return DailyUsageSnapshot(
            id: payload.recordName,
            ownerProfileID: payload.ownerProfileID,
            date: payload.date,
            calendarIdentifier: payload.calendarIdentifier,
            timeZoneIdentifier: payload.timeZoneIdentifier,
            totalDuration: payload.totalDuration,
            selectedAppDuration: payload.selectedAppDuration,
            appRows: rows,
            lastUpdated: payload.lastUpdated,
            capability: ScreenTimeCapability(status: status, reason: payload.capabilityReason)
        )
    }
}
