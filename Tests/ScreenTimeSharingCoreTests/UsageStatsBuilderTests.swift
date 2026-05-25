import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func usageStatsBuildsCurrentWeekSummaryAndLabels() throws {
    let calendar = makeCalendar()
    let now = try makeDate(2026, 5, 21, 12, calendar: calendar)
    let history = [
        makeSnapshot(date: try makeDate(2026, 5, 17, 10, calendar: calendar), duration: 7_200, pickups: 2, calendar: calendar),
        makeSnapshot(date: try makeDate(2026, 5, 18, 10, calendar: calendar), duration: 3_600, pickups: 1, calendar: calendar)
    ]

    let summary = UsageStatsBuilder.summary(
        range: .week,
        selectedDate: now,
        history: history,
        calendar: calendar,
        now: now
    )

    #expect(summary.periodLabel == "This Week")
    #expect(summary.dateRangeLabel == "May 17-23, 2026")
    #expect(summary.totalDuration == 10_800)
    #expect(summary.dailyAverageDuration == 2_160)
    #expect(summary.pickupTotal == 3)
    #expect(summary.hasScreenTimeData)
}

@Test func usageStatsBuildsDaySummaryWithoutNotifications() throws {
    let calendar = makeCalendar()
    let now = try makeDate(2026, 5, 21, 12, calendar: calendar)
    let history = [
        makeSnapshot(date: now, duration: 21 * 60, pickups: 4, calendar: calendar)
    ]

    let summary = UsageStatsBuilder.summary(
        range: .day,
        selectedDate: now,
        history: history,
        calendar: calendar,
        now: now
    )

    #expect(summary.periodLabel == "Today")
    #expect(summary.dateRangeLabel == "Today, May 21")
    #expect(summary.totalDuration == 21 * 60)
    #expect(summary.dailyAverageDuration == 21 * 60)
    #expect(summary.pickupTotal == 4)
}

@Test func usageStatsChartBucketCountsMatchSelectedRange() throws {
    let calendar = makeCalendar()
    let now = try makeDate(2026, 5, 21, 12, calendar: calendar)
    let history = [
        makeSnapshot(date: now, duration: 21 * 60, pickups: 4, calendar: calendar)
    ]
    let dayKey = UsageDateBoundary.localDayKey(date: now, calendar: calendar)
    let hourly = Array(repeating: TimeInterval(60), count: 24)

    let monthBuckets = UsageStatsBuilder.chartBuckets(range: .month, selectedDate: now, history: history, calendar: calendar)
    let weekBuckets = UsageStatsBuilder.chartBuckets(range: .week, selectedDate: now, history: history, calendar: calendar)
    let hourlyBuckets = UsageStatsBuilder.chartBuckets(
        range: .day,
        selectedDate: now,
        history: history,
        hourlyDurationsByDayID: [dayKey: hourly],
        calendar: calendar
    )
    let fallbackBuckets = UsageStatsBuilder.chartBuckets(range: .day, selectedDate: now, history: history, calendar: calendar)

    #expect(monthBuckets.count == 31)
    #expect(weekBuckets.count == 7)
    #expect(weekBuckets.first?.id == "2026-05-17")
    #expect(weekBuckets.last?.id == "2026-05-23")
    #expect(hourlyBuckets.count == 24)
    #expect(fallbackBuckets.count == 24)
    #expect(fallbackBuckets.map(\.duration).allSatisfy { $0 == 0 })
}

@Test func usageStatsWeekKeepsFullWeekSpaceOnSunday() throws {
    let calendar = makeCalendar()
    let sunday = try makeDate(2026, 5, 24, 12, calendar: calendar)
    let buckets = UsageStatsBuilder.chartBuckets(
        range: .week,
        selectedDate: sunday,
        history: [
            makeSnapshot(date: sunday, duration: 1_800, pickups: 2, calendar: calendar)
        ],
        calendar: calendar
    )

    #expect(buckets.count == 7)
    #expect(buckets.first?.id == "2026-05-24")
    #expect(buckets.last?.id == "2026-05-30")
    #expect(buckets.map(\.duration) == [1_800, 0, 0, 0, 0, 0, 0])
}

@Test func usageStatsForwardNavigationUnlocksForEarlierPeriods() throws {
    let calendar = makeCalendar()
    let currentSunday = try makeDate(2026, 5, 24, 12, calendar: calendar)
    let priorWeek = try makeDate(2026, 5, 17, 12, calendar: calendar)
    let currentMonth = try makeDate(2026, 5, 21, 12, calendar: calendar)
    let priorMonth = try makeDate(2026, 4, 21, 12, calendar: calendar)

    #expect(!UsageStatsBuilder.canNavigateForward(range: .week, selectedDate: currentSunday, now: currentSunday, calendar: calendar))
    #expect(UsageStatsBuilder.canNavigateForward(range: .week, selectedDate: priorWeek, now: currentSunday, calendar: calendar))
    #expect(!UsageStatsBuilder.canNavigateForward(range: .month, selectedDate: currentMonth, now: currentSunday, calendar: calendar))
    #expect(UsageStatsBuilder.canNavigateForward(range: .month, selectedDate: priorMonth, now: currentSunday, calendar: calendar))
}

@Test func usageHistoryRoundTripAndSameDayReplacement() throws {
    let calendar = makeCalendar()
    let morning = try makeDate(2026, 5, 21, 8, calendar: calendar)
    let evening = try makeDate(2026, 5, 21, 20, calendar: calendar)
    let first = makeSnapshot(date: morning, duration: 1_200, pickups: 2, calendar: calendar)
    let replacement = makeSnapshot(date: evening, duration: 3_600, pickups: 5, calendar: calendar)

    let updated = UsageHistoryCodec.upserting(replacement, into: [first], calendar: calendar)
    let payload = UsageHistoryPayload(
        snapshots: updated,
        hourlyDurationsByDayID: [UsageDateBoundary.localDayKey(date: morning, calendar: calendar): [60, 120]]
    )
    let decoded = try UsageHistoryCodec.decode(try UsageHistoryCodec.encode(payload))

    #expect(updated.count == 1)
    #expect(updated.first?.totalDuration == 3_600)
    #expect(decoded == payload)
}

@Test func statsRangeMapsToLeaderboardWindow() {
    #expect(StatsRange.month.leaderboardWindow == .month)
    #expect(StatsRange.week.leaderboardWindow == .week)
    #expect(StatsRange.day.leaderboardWindow == .today)
}

@Test func usageStatsAggregatesAppRowsInSelectedRange() throws {
    let calendar = makeCalendar()
    let monday = try makeDate(2026, 5, 18, 10, calendar: calendar)
    let tuesday = try makeDate(2026, 5, 19, 10, calendar: calendar)
    let priorWeek = try makeDate(2026, 5, 12, 10, calendar: calendar)
    let history = [
        makeSnapshot(
            date: monday,
            duration: 3_600,
            pickups: 1,
            appRows: [
                SharedAppUsage(id: "tiktok-a", displayName: "TikTok", bundleIdentifier: "com.tiktok", duration: 900),
                SharedAppUsage(id: "youtube", displayName: "YouTube", bundleIdentifier: "com.youtube", duration: 1_200)
            ],
            calendar: calendar
        ),
        makeSnapshot(
            date: tuesday,
            duration: 3_600,
            pickups: 1,
            appRows: [
                SharedAppUsage(id: "tiktok-b", displayName: "TikTok", bundleIdentifier: "com.tiktok", duration: 1_800),
                SharedAppUsage(id: "messages", displayName: "Messages", bundleIdentifier: "com.messages", duration: 300)
            ],
            calendar: calendar
        ),
        makeSnapshot(
            date: priorWeek,
            duration: 3_600,
            pickups: 1,
            appRows: [
                SharedAppUsage(id: "reddit", displayName: "Reddit", bundleIdentifier: "com.reddit", duration: 9_000)
            ],
            calendar: calendar
        )
    ]

    let rows = UsageStatsBuilder.appUsageRows(
        range: .week,
        selectedDate: tuesday,
        history: history,
        calendar: calendar
    )

    #expect(rows.map(\.displayName) == ["TikTok", "YouTube", "Messages"])
    #expect(rows.first?.duration == 2_700)
    #expect(rows.first?.id == "com.tiktok")
}

private func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}

private func makeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    calendar: Calendar
) throws -> Date {
    let date = DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour
    ).date
    return try #require(date)
}

private func makeSnapshot(
    date: Date,
    duration: TimeInterval,
    pickups: Int,
    appRows: [SharedAppUsage] = [],
    calendar: Calendar
) -> DailyUsageSnapshot {
    let day = UsageDateBoundary.dayInterval(containing: date, calendar: calendar).start
    return DailyUsageSnapshot(
        id: UsageDateBoundary.snapshotID(profileID: "me", date: date, calendar: calendar),
        ownerProfileID: "me",
        date: day,
        calendarIdentifier: String(describing: calendar.identifier),
        timeZoneIdentifier: calendar.timeZone.identifier,
        totalDuration: duration,
        selectedAppDuration: duration,
        pickupCount: pickups,
        appRows: appRows,
        lastUpdated: date,
        capability: .fullAppDetail
    )
}
