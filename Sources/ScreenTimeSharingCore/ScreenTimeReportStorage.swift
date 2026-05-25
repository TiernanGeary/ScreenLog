import Foundation

public enum ScreenTimeReportStorage {
    public static let appGroupSuiteName = "group.com.jdco.ScreenLog"
    public static let profileIDKey = "ScreenTimeReport.ProfileID.v1"
    public static let lastRequestedAtKey = "ScreenTimeReport.LastRequestedAt.v1"
    public static let lastStartedAtKey = "ScreenTimeReport.LastStartedAt.v1"
    public static let lastGeneratedAtKey = "ScreenTimeReport.LastGeneratedAt.v1"
    public static let lastErrorKey = "ScreenTimeReport.LastError.v1"
    public static let lastSummaryKey = "ScreenTimeReport.LastSummary.v1"

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
}
