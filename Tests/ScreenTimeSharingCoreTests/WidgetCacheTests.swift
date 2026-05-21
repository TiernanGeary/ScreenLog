import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func widgetCachePayloadRoundTripsWithISODates() throws {
    let payload = WidgetCachePayload(
        generatedAt: Date(timeIntervalSince1970: 1_779_236_400),
        friends: [
            FriendUsageSummary(
                id: "friend-1",
                displayName: "Taylor",
                avatarColorHex: "#1B998B",
                totalDuration: 7_200,
                selectedAppDuration: 2_400,
                capability: .aggregateOnly(),
                lastUpdated: Date(timeIntervalSince1970: 1_779_236_000),
                isStale: false
            )
        ],
        leaderboardEntries: [
            LeaderboardEntry(
                id: "me",
                userID: "me",
                displayName: "You",
                avatarColorHex: "#6A4C93",
                requestedExtraSeconds: 15 * 60,
                approvedExtraSeconds: 15 * 60,
                requestCount: 1,
                deniedCount: 0,
                emergencyUnlockCount: 0,
                settingsResetCount: 0,
                currentStreakDays: 2,
                lastUpdated: Date(timeIntervalSince1970: 1_779_236_100)
            )
        ],
        currentUserID: "me"
    )

    let data = try WidgetCacheCodec.encode(payload)
    let decoded = try WidgetCacheCodec.decode(data)

    #expect(decoded == payload)
    #expect(decoded.currentUserID == "me")
    #expect(decoded.leaderboardEntries.first?.userID == "me")
}
