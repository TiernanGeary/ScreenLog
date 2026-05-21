import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func aggregateOnlySnapshotsDropPerAppRowsBeforeUpload() throws {
    let snapshot = DailyUsageSnapshot(
        id: "profile-1-2026-05-20",
        ownerProfileID: "profile-1",
        date: Date(timeIntervalSince1970: 1_779_232_800),
        calendarIdentifier: "gregorian",
        timeZoneIdentifier: "America/New_York",
        totalDuration: 10_800,
        selectedAppDuration: 3_600,
        pickupCount: 22,
        appRows: [
            SharedAppUsage(
                id: "app-1",
                displayName: "Example",
                bundleIdentifier: "com.example.app",
                duration: 1_800
            )
        ],
        lastUpdated: Date(timeIntervalSince1970: 1_779_236_400),
        capability: .aggregateOnly(reason: "Detailed usage not approved")
    )

    let payload = try #require(try SnapshotRecordPayloadMapper.payload(from: snapshot))

    #expect(payload.selectedAppDuration == 3_600)
    #expect(payload.pickupCount == 22)
    #expect(payload.appRowsJSON == nil)
    #expect(payload.capabilityStatus == ScreenTimeCapabilityStatus.aggregateOnly.rawValue)
}

@Test func unavailableSnapshotsAreNotUploadable() throws {
    let snapshot = DailyUsageSnapshot(
        id: "profile-1-2026-05-20",
        ownerProfileID: "profile-1",
        date: Date(),
        calendarIdentifier: "gregorian",
        timeZoneIdentifier: "America/New_York",
        totalDuration: nil,
        selectedAppDuration: nil,
        appRows: [],
        lastUpdated: Date(),
        capability: .unavailable(reason: "Authorization denied")
    )

    #expect(try SnapshotRecordPayloadMapper.payload(from: snapshot) == nil)
}

@Test func fullDetailSnapshotsRoundTripRows() throws {
    let snapshot = DailyUsageSnapshot(
        id: "profile-1-2026-05-20",
        ownerProfileID: "profile-1",
        date: Date(timeIntervalSince1970: 1_779_232_800),
        calendarIdentifier: "gregorian",
        timeZoneIdentifier: "America/New_York",
        totalDuration: 10_800,
        selectedAppDuration: 3_600,
        pickupCount: 22,
        appRows: [
            SharedAppUsage(
                id: "app-1",
                displayName: "Example",
                bundleIdentifier: "com.example.app",
                duration: 1_800
            )
        ],
        lastUpdated: Date(timeIntervalSince1970: 1_779_236_400),
        capability: .fullAppDetail
    )

    let payload = try #require(try SnapshotRecordPayloadMapper.payload(from: snapshot))
    let decoded = try SnapshotRecordPayloadMapper.snapshot(from: payload)

    #expect(decoded == snapshot)
}
