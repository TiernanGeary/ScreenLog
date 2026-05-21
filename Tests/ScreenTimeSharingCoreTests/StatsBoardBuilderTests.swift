import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func statsBoardBestControlSortsByLowRequestedThenEmergenciesThenStreak() {
    let entries = [
        makeStatsEntry(userID: "riley", name: "Riley", requestedMinutes: 10, requestCount: 1, emergencyCount: 1, streak: 9),
        makeStatsEntry(userID: "sam", name: "Sam", requestedMinutes: 10, requestCount: 2, emergencyCount: 0, streak: 3),
        makeStatsEntry(userID: "maya", name: "Maya", requestedMinutes: 0, requestCount: 0, emergencyCount: 0, streak: 1),
        makeStatsEntry(userID: "alex", name: "Alex", requestedMinutes: 10, requestCount: 1, emergencyCount: 0, streak: 5)
    ]

    let sorted = StatsBoardBuilder.bestControl(entries: entries)

    #expect(sorted.map(\.userID) == ["maya", "alex", "sam", "riley"])
}

@Test func statsBoardMostExtraRequestedSortsByHighRequestedThenRequestCount() {
    let entries = [
        makeStatsEntry(userID: "sam", name: "Sam", requestedMinutes: 30, requestCount: 1),
        makeStatsEntry(userID: "maya", name: "Maya", requestedMinutes: 45, requestCount: 1),
        makeStatsEntry(userID: "riley", name: "Riley", requestedMinutes: 45, requestCount: 3),
        makeStatsEntry(userID: "alex", name: "Alex", requestedMinutes: 5, requestCount: 5)
    ]

    let sorted = StatsBoardBuilder.mostExtraRequested(entries: entries)

    #expect(sorted.map(\.userID) == ["riley", "maya", "sam", "alex"])
}

@Test func statsBoardFindsCurrentUserEntry() throws {
    let entries = [
        makeStatsEntry(userID: "sam", name: "Sam", requestedMinutes: 10, requestCount: 1),
        makeStatsEntry(userID: "me", name: "You", requestedMinutes: 20, requestCount: 2)
    ]

    let current = try #require(StatsBoardBuilder.entry(for: "me", in: entries))

    #expect(current.displayName == "You")
    #expect(current.requestedExtraSeconds == 20 * 60)
    #expect(StatsBoardBuilder.entry(for: "missing", in: entries) == nil)
}

private func makeStatsEntry(
    userID: String,
    name: String,
    requestedMinutes: Int,
    requestCount: Int,
    emergencyCount: Int = 0,
    streak: Int = 0
) -> LeaderboardEntry {
    LeaderboardEntry(
        id: userID,
        userID: userID,
        displayName: name,
        avatarColorHex: "#1B998B",
        requestedExtraSeconds: TimeInterval(requestedMinutes * 60),
        approvedExtraSeconds: 0,
        requestCount: requestCount,
        deniedCount: 0,
        emergencyUnlockCount: emergencyCount,
        settingsResetCount: 0,
        currentStreakDays: streak,
        lastUpdated: nil
    )
}
