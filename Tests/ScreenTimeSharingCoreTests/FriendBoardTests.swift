import Foundation
import Testing
@testable import ScreenTimeSharingCore

private func makeSummary(
    id: String,
    name: String,
    total: TimeInterval?,
    lastUpdated: Date? = nil
) -> FriendUsageSummary {
    FriendUsageSummary(
        id: id,
        displayName: name,
        avatarColorHex: "#FFAA00",
        totalDuration: total,
        selectedAppDuration: nil,
        capability: .fullAppDetail,
        lastUpdated: lastUpdated,
        isStale: false
    )
}

@Test func friendFreshnessTierMapsElapsedTimeToSpecBuckets() {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    #expect(FriendFreshness.tier(lastUpdated: nil, now: now) == .missing)
    #expect(FriendFreshness.tier(lastUpdated: now.addingTimeInterval(-60), now: now) == .fresh)
    #expect(FriendFreshness.tier(lastUpdated: now.addingTimeInterval(-10 * 60), now: now) == .aging)
    #expect(FriendFreshness.tier(lastUpdated: now.addingTimeInterval(-2 * 3_600), now: now) == .stale)
}

@Test func activityRowsSortByUsageThenNameWithMissingDataLast() {
    let rows = FriendBoardBuilder.activityRows([
        makeSummary(id: "c", name: "Cara", total: nil),
        makeSummary(id: "a", name: "Avery", total: 3_600),
        makeSummary(id: "b", name: "Blake", total: 7_200),
        makeSummary(id: "d", name: "Drew", total: 3_600)
    ])
    #expect(rows.map(\.id) == ["b", "a", "d", "c"])
}
