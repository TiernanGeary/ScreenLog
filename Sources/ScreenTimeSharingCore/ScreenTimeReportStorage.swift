import Foundation

public enum ScreenTimeReportStorage {
    public static let appGroupSuiteName = "group.com.jdco.ScreenLog"
    public static let profileIDKey = "ScreenTimeReport.ProfileID.v1"
    public static let lastRequestedAtKey = "ScreenTimeReport.LastRequestedAt.v1"
    public static let lastStartedAtKey = "ScreenTimeReport.LastStartedAt.v1"
    public static let lastGeneratedAtKey = "ScreenTimeReport.LastGeneratedAt.v1"
    public static let lastErrorKey = "ScreenTimeReport.LastError.v1"
    public static let lastSummaryKey = "ScreenTimeReport.LastSummary.v1"

    public struct GroupUsageSlotValue: Codable {
        public let groupBlockID: String
        public let dayKey: String
        public let seconds: Int
    }

    public static func saveProfileID(_ profileID: String, defaults: UserDefaults?) {
        defaults?.set(profileID, forKey: profileIDKey)
        defaults?.synchronize()
    }

    public static func loadProfileID(defaults: UserDefaults?) -> String? {
        defaults?.string(forKey: profileIDKey)
    }

    public static func markRequested(defaults: UserDefaults?) {
        defaults?.set(Date(), forKey: lastRequestedAtKey)
    }

    public static func markStarted(defaults: UserDefaults?) {
        defaults?.set(Date(), forKey: lastStartedAtKey)
        defaults?.removeObject(forKey: lastErrorKey)
    }

    public static func markFailed(_ error: String, defaults: UserDefaults?) {
        defaults?.set(error, forKey: lastErrorKey)
    }

    public static func saveSummary(_ summary: String, defaults: UserDefaults?) {
        defaults?.set(summary, forKey: lastSummaryKey)
        defaults?.set(Date(), forKey: lastGeneratedAtKey)
        defaults?.removeObject(forKey: lastErrorKey)
    }

    public static func loadPayload(defaults: UserDefaults?) -> UsageHistoryPayload {
        guard let data = defaults?.data(forKey: UsageHistoryCodec.storageKey),
              let payload = try? UsageHistoryCodec.decode(data) else {
            return UsageHistoryPayload(snapshots: [])
        }

        return payload
    }

    public static func savePayload(_ payload: UsageHistoryPayload, defaults: UserDefaults?) throws {
        let data = try UsageHistoryCodec.encode(payload)
        defaults?.set(data, forKey: UsageHistoryCodec.storageKey)
        defaults?.set(Date(), forKey: lastGeneratedAtKey)
        defaults?.removeObject(forKey: lastErrorKey)
    }

    public static func setGroupUsageSlot(
        _ slot: Int,
        groupBlockID: String,
        dayKey: String,
        seconds: Int,
        defaults: UserDefaults?
    ) {
        let value = GroupUsageSlotValue(
            groupBlockID: groupBlockID,
            dayKey: dayKey,
            seconds: seconds
        )
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        defaults?.set(data, forKey: groupUsageSlotKey(slot))
    }

    public static func groupUsageSlot(
        _ slot: Int,
        groupBlockID: String,
        dayKey: String,
        defaults: UserDefaults?
    ) -> Int {
        guard let data = defaults?.data(forKey: groupUsageSlotKey(slot)),
              let value = try? JSONDecoder().decode(GroupUsageSlotValue.self, from: data),
              value.groupBlockID == groupBlockID,
              value.dayKey == dayKey else {
            return 0
        }

        return value.seconds
    }

    public static func upsert(
        snapshot: DailyUsageSnapshot,
        hourlyDurations: [TimeInterval]?,
        defaults: UserDefaults?,
        calendar: Calendar = .current
    ) throws {
        let existing = loadPayload(defaults: defaults)
        let snapshots = UsageHistoryCodec.upserting(snapshot, into: existing.snapshots, calendar: calendar)
        var hourlyDurationsByDayID = existing.hourlyDurationsByDayID
        if let hourlyDurations {
            hourlyDurationsByDayID[UsageDateBoundary.localDayKey(date: snapshot.date, calendar: calendar)] = hourlyDurations
        }

        try savePayload(
            UsageHistoryPayload(
                snapshots: snapshots,
                hourlyDurationsByDayID: hourlyDurationsByDayID
            ),
            defaults: defaults
        )
    }

    public static func latestSnapshot(
        for profileID: String,
        on date: Date = Date(),
        defaults: UserDefaults?,
        calendar: Calendar = .current
    ) -> DailyUsageSnapshot? {
        let payload = loadPayload(defaults: defaults)
        let dayKey = UsageDateBoundary.localDayKey(date: date, calendar: calendar)

        return payload.snapshots
            .filter {
                $0.ownerProfileID == profileID
                    && UsageDateBoundary.localDayKey(date: $0.date, calendar: calendar) == dayKey
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }
            .first
    }

    private static func groupUsageSlotKey(_ slot: Int) -> String {
        "ScreenLogGroupUsage.slot.\(slot).v1"
    }

    // The app owns the slot -> group-block assignment and writes it here so the
    // report extension scene (which only sees filtered results, not which group
    // it is rendering) can tag the seconds it writes with the right group block.
    public static func setPoolSlotAssignment(_ slot: Int, groupBlockID: String?, ownerTimeZone: String?, defaults: UserDefaults?) {
        let key = poolSlotAssignmentKey(slot)
        let tzKey = poolSlotAssignmentTimeZoneKey(slot)
        if let groupBlockID {
            defaults?.set(groupBlockID, forKey: key)
            defaults?.set(ownerTimeZone ?? "UTC", forKey: tzKey)
        } else {
            defaults?.removeObject(forKey: key)
            defaults?.removeObject(forKey: tzKey)
        }
    }

    public static func poolSlotAssignment(_ slot: Int, defaults: UserDefaults?) -> (groupBlockID: String, ownerTimeZone: String)? {
        guard let groupBlockID = defaults?.string(forKey: poolSlotAssignmentKey(slot)) else {
            return nil
        }
        let ownerTimeZone = defaults?.string(forKey: poolSlotAssignmentTimeZoneKey(slot)) ?? "UTC"
        return (groupBlockID, ownerTimeZone)
    }

    private static func poolSlotAssignmentKey(_ slot: Int) -> String {
        "ScreenLogGroupUsage.assignment.\(slot).v1"
    }

    private static func poolSlotAssignmentTimeZoneKey(_ slot: Int) -> String {
        "ScreenLogGroupUsage.assignmentTZ.\(slot).v1"
    }
}
