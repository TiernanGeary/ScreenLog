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
        ]
    )

    let data = try WidgetCacheCodec.encode(payload)
    let decoded = try WidgetCacheCodec.decode(data)

    #expect(decoded == payload)
}
