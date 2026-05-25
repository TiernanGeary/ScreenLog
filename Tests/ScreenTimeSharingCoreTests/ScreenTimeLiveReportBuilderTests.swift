import Foundation
import Testing
@testable import ScreenTimeSharingCore

@Test func liveReportBuilderMergesSegmentsAndApps() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24, hour: 9)))
    let nextHour = try #require(calendar.date(byAdding: .hour, value: 1, to: start))
    let end = try #require(calendar.date(byAdding: .hour, value: 2, to: start))

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: start, end: nextHour),
                totalActivityDuration: 1_200,
                pickupCount: 3,
                appRows: [
                    SharedAppUsage(id: "tiktok-a", displayName: "TikTok", bundleIdentifier: "com.tiktok", duration: 900),
                    SharedAppUsage(id: "youtube", displayName: "YouTube", bundleIdentifier: "com.youtube", duration: 300)
                ]
            ),
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: nextHour, end: end),
                totalActivityDuration: 1_800,
                pickupCount: 5,
                appRows: [
                    SharedAppUsage(id: "tiktok-b", displayName: "TikTok", bundleIdentifier: "com.tiktok", duration: 600),
                    SharedAppUsage(id: "messages", displayName: "Messages", bundleIdentifier: "com.messages", duration: 1_200)
                ]
            )
        ],
        generatedAt: end,
        calendar: calendar
    )

    #expect(configuration.totalDuration == 3_000)
    #expect(configuration.pickupCount == 8)
    #expect(configuration.buckets.map(\.duration) == [1_200, 1_800])
    #expect(configuration.appRows.map(\.displayName) == ["TikTok", "Messages", "YouTube"])
    #expect(configuration.appRows.map(\.duration) == [1_500, 1_200, 300])
}

@Test func liveReportBuilderClampsNegativeDurationsAndPickups() throws {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let end = start.addingTimeInterval(3_600)

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: start, end: end),
                totalActivityDuration: -60,
                pickupCount: -2,
                appRows: [
                    SharedAppUsage(id: "app", displayName: "App", bundleIdentifier: "app", duration: -120)
                ]
            )
        ],
        generatedAt: end
    )

    #expect(configuration.totalDuration == 0)
    #expect(configuration.pickupCount == 0)
    #expect(configuration.buckets.first?.duration == 0)
    #expect(configuration.appRows.first?.duration == 0)
}

@Test func liveReportBuilderCanAggregateHourlySegmentsIntoDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let dayOneStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 23, hour: 9)))
    let dayOneEnd = try #require(calendar.date(byAdding: .hour, value: 1, to: dayOneStart))
    let dayTwoStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24, hour: 10)))
    let dayTwoEnd = try #require(calendar.date(byAdding: .hour, value: 1, to: dayTwoStart))

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: dayOneStart, end: dayOneEnd),
                totalActivityDuration: 600,
                pickupCount: 1,
                appRows: []
            ),
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: dayOneEnd, end: dayOneEnd.addingTimeInterval(3_600)),
                totalActivityDuration: 900,
                pickupCount: 2,
                appRows: []
            ),
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: dayTwoStart, end: dayTwoEnd),
                totalActivityDuration: 1_200,
                pickupCount: 3,
                appRows: []
            )
        ],
        calendar: calendar,
        bucketGranularity: .day
    )

    #expect(configuration.buckets.count == 2)
    #expect(configuration.buckets.map(\.duration) == [1_500, 1_200])
    #expect(configuration.pickupCount == 6)
}

@Test func liveReportBuilderKeepsTwentyFourHourlyDayBuckets() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let dayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24)))
    let hourNine = try #require(calendar.date(byAdding: .hour, value: 9, to: dayStart))
    let hourTen = try #require(calendar.date(byAdding: .hour, value: 10, to: dayStart))

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: hourNine, end: hourTen),
                totalActivityDuration: 1_200,
                pickupCount: 2,
                appRows: []
            )
        ],
        calendar: calendar,
        bucketGranularity: .hourlyDay
    )

    #expect(configuration.buckets.count == 24)
    #expect(configuration.buckets[9].duration == 1_200)
    #expect(configuration.buckets.filter { $0.duration > 0 }.count == 1)
}

@Test func liveReportBuilderDoesNotRenderDailyTotalAsSingleHugeDayBar() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let dayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24)))
    let dayEnd = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: dayStart, end: dayEnd),
                totalActivityDuration: 7_200,
                pickupCount: 4,
                appRows: []
            )
        ],
        calendar: calendar,
        bucketGranularity: .hourlyDay
    )

    #expect(configuration.totalDuration == 7_200)
    #expect(configuration.buckets.count == 24)
    #expect(configuration.buckets.map(\.duration).allSatisfy { $0 == 0 })
}

@Test func liveReportBuilderPadsWeekBucketsToSundayThroughSaturday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let sundayMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24, hour: 9)))
    let sundayLateMorning = try #require(calendar.date(byAdding: .hour, value: 1, to: sundayMorning))
    let sundayNoon = try #require(calendar.date(byAdding: .hour, value: 2, to: sundayMorning))

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: sundayMorning, end: sundayLateMorning),
                totalActivityDuration: 600,
                pickupCount: 1,
                appRows: []
            ),
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: sundayLateMorning, end: sundayNoon),
                totalActivityDuration: 900,
                pickupCount: 2,
                appRows: []
            )
        ],
        calendar: calendar,
        bucketGranularity: .week
    )

    #expect(configuration.buckets.count == 7)
    #expect(configuration.buckets.first?.id == "2026-05-24")
    #expect(configuration.buckets.last?.id == "2026-05-30")
    #expect(configuration.buckets.map(\.label) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    #expect(configuration.buckets.map(\.duration) == [1_500, 0, 0, 0, 0, 0, 0])
    #expect(configuration.pickupCount == 3)
}

@Test func liveReportBuilderPadsMonthBucketsToWholeMonth() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may24 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 24, hour: 12)))
    let may25 = try #require(calendar.date(byAdding: .day, value: 1, to: may24))

    let configuration = ScreenTimeLiveReportBuilder.configuration(
        segments: [
            ScreenTimeReportSegmentInput(
                dateInterval: DateInterval(start: may24, end: may25),
                totalActivityDuration: 3_600,
                pickupCount: 1,
                appRows: []
            )
        ],
        calendar: calendar,
        bucketGranularity: .month
    )

    #expect(configuration.buckets.count == 31)
    #expect(configuration.buckets.first?.id == "2026-05-01")
    #expect(configuration.buckets.last?.id == "2026-05-31")
    #expect(configuration.buckets[23].duration == 3_600)
}
