import Foundation
import Testing
@testable import ScreenTimeSharingCore

private func makeSnapshot(
    id: String,
    date: Date,
    total: TimeInterval,
    lastUpdated: Date
) -> DailyUsageSnapshot {
    DailyUsageSnapshot(
        id: id,
        ownerProfileID: "me",
        date: date,
        calendarIdentifier: "gregorian",
        timeZoneIdentifier: "UTC",
        totalDuration: total,
        selectedAppDuration: nil,
        pickupCount: nil,
        appRows: [],
        lastUpdated: lastUpdated,
        capability: .fullAppDetail
    )
}

@Test func usageHistorySignatureChangesWithContentAndIsStableForEqualInput() {
    let day = Date(timeIntervalSince1970: 1_779_236_400)
    let a = makeSnapshot(id: "d1", date: day, total: 3_600, lastUpdated: day)
    let sigA = UsageHistorySignature(history: [a], hourlyDurationsByDayID: ["d1": [3_600]])
    let sigA2 = UsageHistorySignature(history: [a], hourlyDurationsByDayID: ["d1": [3_600]])
    #expect(sigA == sigA2)

    let b = makeSnapshot(id: "d1", date: day, total: 7_200, lastUpdated: day.addingTimeInterval(60))
    let sigB = UsageHistorySignature(history: [b], hourlyDurationsByDayID: ["d1": [7_200]])
    #expect(sigA != sigB)
}

@Test func usageStatsCacheMemoizesUntilInputsChange() {
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let snap = makeSnapshot(id: "d1", date: now, total: 3_600, lastUpdated: now)
    let history = [snap]
    let hourly: [String: [TimeInterval]] = ["d1": [3_600]]
    let cache = UsageStatsCache()

    let r1 = cache.appUsageRows(range: .day, selectedDate: now, history: history, calendar: cal)
    let r2 = cache.appUsageRows(range: .day, selectedDate: now, history: history, calendar: cal)
    // Same inputs -> single computation (cache hit on 2nd call), equal result.
    #expect(r1 == r2)
    #expect(cache.appRowsComputeCount == 1)

    // Correctness: equals a direct builder call.
    let direct = UsageStatsBuilder.appUsageRows(range: .day, selectedDate: now, history: history, calendar: cal)
    #expect(r1 == direct)

    // Changed history -> recompute (miss).
    let snap2 = makeSnapshot(id: "d1", date: now, total: 7_200, lastUpdated: now.addingTimeInterval(60))
    _ = cache.appUsageRows(range: .day, selectedDate: now, history: [snap2], calendar: cal)
    #expect(cache.appRowsComputeCount == 2)
}

@Test func usageStatsCacheReusesAcrossDatesInSamePeriod() {
    let cal = Calendar(identifier: .gregorian)
    let monday = Date(timeIntervalSince1970: 1_779_236_400)
    let snap = makeSnapshot(id: "d1", date: monday, total: 3_600, lastUpdated: monday)
    let cache = UsageStatsCache()

    _ = cache.chartBuckets(range: .week, selectedDate: monday, history: [snap], hourlyDurationsByDayID: [:], calendar: cal)
    // A different date in the SAME week normalizes to the same period-start key -> cache hit.
    let nextDay = monday.addingTimeInterval(24 * 3_600)
    _ = cache.chartBuckets(range: .week, selectedDate: nextDay, history: [snap], hourlyDurationsByDayID: [:], calendar: cal)
    #expect(cache.bucketsComputeCount == 1)
}
