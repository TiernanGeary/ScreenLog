import Foundation
import Testing
@testable import ScreenTimeSharingCore

@Test func screenTimeReportStorageUpsertsSnapshotAndHourlyDurations() throws {
    let suiteName = "ScreenTimeReportStorageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let calendar = Calendar(identifier: .gregorian)
    let date = Date(timeIntervalSince1970: 1_779_236_400)
    let profileID = "profile-1"
    let snapshot = DailyUsageSnapshot(
        id: UsageDateBoundary.snapshotID(profileID: profileID, date: date, calendar: calendar),
        ownerProfileID: profileID,
        date: UsageDateBoundary.dayInterval(containing: date, calendar: calendar).start,
        calendarIdentifier: String(describing: calendar.identifier),
        timeZoneIdentifier: calendar.timeZone.identifier,
        totalDuration: 3_600,
        selectedAppDuration: 3_600,
        pickupCount: 12,
        appRows: [
            SharedAppUsage(id: "com.example.app", displayName: "Example", bundleIdentifier: "com.example.app", duration: 3_600)
        ],
        lastUpdated: date,
        capability: .fullAppDetail
    )

    ScreenTimeReportStorage.saveProfileID(profileID, defaults: defaults)
    try ScreenTimeReportStorage.upsert(
        snapshot: snapshot,
        hourlyDurations: Array(repeating: 150, count: 24),
        defaults: defaults,
        calendar: calendar
    )

    let loaded = try #require(ScreenTimeReportStorage.latestSnapshot(
        for: profileID,
        on: date,
        defaults: defaults,
        calendar: calendar
    ))
    let payload = ScreenTimeReportStorage.loadPayload(defaults: defaults)
    let dayKey = UsageDateBoundary.localDayKey(date: date, calendar: calendar)

    #expect(ScreenTimeReportStorage.loadProfileID(defaults: defaults) == profileID)
    #expect(loaded == snapshot)
    #expect(payload.hourlyDurationsByDayID[dayKey]?.count == 24)
}

@Test func screenTimeReportStoragePreservesHourlyDurationsWhenNewSnapshotHasNoHourlyBreakdown() throws {
    let suiteName = "ScreenTimeReportStorageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let calendar = Calendar(identifier: .gregorian)
    let date = Date(timeIntervalSince1970: 1_779_236_400)
    let profileID = "profile-1"
    let dayStart = UsageDateBoundary.dayInterval(containing: date, calendar: calendar).start
    let firstSnapshot = DailyUsageSnapshot(
        id: UsageDateBoundary.snapshotID(profileID: profileID, date: dayStart, calendar: calendar),
        ownerProfileID: profileID,
        date: dayStart,
        calendarIdentifier: String(describing: calendar.identifier),
        timeZoneIdentifier: calendar.timeZone.identifier,
        totalDuration: 3_600,
        selectedAppDuration: 3_600,
        pickupCount: 12,
        appRows: [],
        lastUpdated: date,
        capability: .fullAppDetail
    )
    let updatedSnapshot = DailyUsageSnapshot(
        id: firstSnapshot.id,
        ownerProfileID: profileID,
        date: dayStart,
        calendarIdentifier: firstSnapshot.calendarIdentifier,
        timeZoneIdentifier: firstSnapshot.timeZoneIdentifier,
        totalDuration: 4_200,
        selectedAppDuration: 4_200,
        pickupCount: 14,
        appRows: [],
        lastUpdated: date.addingTimeInterval(60),
        capability: .fullAppDetail
    )
    let originalHourlyDurations = Array(repeating: TimeInterval(150), count: 24)

    try ScreenTimeReportStorage.upsert(
        snapshot: firstSnapshot,
        hourlyDurations: originalHourlyDurations,
        defaults: defaults,
        calendar: calendar
    )
    try ScreenTimeReportStorage.upsert(
        snapshot: updatedSnapshot,
        hourlyDurations: nil,
        defaults: defaults,
        calendar: calendar
    )

    let payload = ScreenTimeReportStorage.loadPayload(defaults: defaults)
    let dayKey = UsageDateBoundary.localDayKey(date: date, calendar: calendar)

    #expect(payload.snapshots.first?.totalDuration == 4_200)
    #expect(payload.hourlyDurationsByDayID[dayKey] == originalHourlyDurations)
}
