import Foundation
import Testing
@testable import ScreenTimeSharingCore

@Test func homeEngagementBuildsBaselineWarmupState() throws {
    let calendar = makeHomeCalendar()
    let history = (1...3).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 40,
            selectedDuration: 2 * 3_600,
            calendar: calendar
        )
    }

    let summary = HomeEngagementBuilder.summary(
        history: history,
        calendar: calendar,
        now: makeHomeDate(2026, 5, 4, calendar: calendar)
    )

    #expect(summary.baselineStatus == .ready(days: 0))
    #expect(summary.netSavedDuration == 3 * (5.5 * 3_600 - 4 * 3_600))
    #expect(summary.screenTimePercentChange != nil)
}

@Test func homeEngagementCalculatesNetSavedAndPercentDrops() throws {
    let calendar = makeHomeCalendar()
    let baseline = (1...7).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 6 * 3_600,
            pickups: 60,
            selectedDuration: 3 * 3_600,
            calendar: calendar
        )
    }
    let comparison = (8...9).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 30,
            selectedDuration: 90 * 60,
            calendar: calendar
        )
    }

    let summary = HomeEngagementBuilder.summary(
        history: baseline + comparison,
        calendar: calendar,
        now: makeHomeDate(2026, 5, 10, calendar: calendar)
    )

    #expect(summary.baselineStatus == .ready(days: 7))
    let baselineAverage = try #require(summary.baselineDailyAverage)
    #expect(baselineAverage == TimeInterval(6 * 3_600))
    #expect(summary.netSavedDuration == 4 * 3_600)
    #expect(abs((summary.screenTimePercentChange ?? 0) - 33.333) < 0.01)
    #expect(summary.pickupPercentChange == 50)
    let improvement = try #require(summary.topImprovement)
    #expect(improvement.title == "Selected apps down")
    #expect(improvement.savedDuration == TimeInterval(3 * 3_600))
}

@Test func homeEngagementOnlyAccumulatesDaysUnderBaseline() throws {
    let calendar = makeHomeCalendar()
    let baseline = (1...7).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 40,
            selectedDuration: 2 * 3_600,
            calendar: calendar
        )
    }
    let comparison = [
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 8, calendar: calendar),
            duration: 5 * 3_600,
            pickups: 50,
            selectedDuration: 150 * 60,
            calendar: calendar
        )
    ]

    let summary = HomeEngagementBuilder.summary(
        history: baseline + comparison,
        calendar: calendar,
        now: makeHomeDate(2026, 5, 9, calendar: calendar)
    )

    #expect(summary.baselineDailyAverage == HomeEngagementBuilder.fallbackDailyBaseline)
    #expect(summary.netSavedDuration == 30 * 60)
    #expect(abs((summary.screenTimePercentChange ?? 0) - 9.09) < 0.01)
    #expect(summary.topImprovement == nil)
}

@Test func homeEngagementUsesPreDenyDaysAndMinimumUSBaselineFloor() throws {
    let calendar = makeHomeCalendar()
    let beforeDeny = (20...22).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 35,
            selectedDuration: 2 * 3_600,
            calendar: calendar
        )
    }
    let afterDeny = [
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 23, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 30,
            selectedDuration: 90 * 60,
            calendar: calendar
        ),
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 24, calendar: calendar),
            duration: 7 * 3_600,
            pickups: 70,
            selectedDuration: 4 * 3_600,
            calendar: calendar
        )
    ]

    let summary = HomeEngagementBuilder.summary(
        history: beforeDeny + afterDeny,
        appStartedAt: makeHomeDate(2026, 5, 23, calendar: calendar),
        calendar: calendar,
        now: makeHomeDate(2026, 5, 25, calendar: calendar)
    )

    #expect(summary.baselineStatus == .ready(days: 3))
    #expect(summary.baselineDailyAverage == HomeEngagementBuilder.fallbackDailyBaseline)
    #expect(summary.netSavedDuration == 90 * 60)
}

@Test func homeEngagementFallsBackToUSBaselineWhenNoPreDenyHistoryExists() throws {
    let calendar = makeHomeCalendar()
    let history = [
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 23, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 30,
            selectedDuration: 90 * 60,
            calendar: calendar
        )
    ]

    let summary = HomeEngagementBuilder.summary(
        history: history,
        appStartedAt: makeHomeDate(2026, 5, 23, calendar: calendar),
        calendar: calendar,
        now: makeHomeDate(2026, 5, 24, calendar: calendar)
    )

    #expect(summary.baselineStatus == .ready(days: 0))
    #expect(summary.baselineDailyAverage == HomeEngagementBuilder.fallbackDailyBaseline)
    #expect(summary.netSavedDuration == 90 * 60)
    #expect(summary.pickupPercentChange == nil)
}

@Test func homeEngagementStreakExcludesToday() throws {
    let calendar = makeHomeCalendar()
    let baseline = (1...7).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 5 * 3_600,
            pickups: 40,
            selectedDuration: 2 * 3_600,
            calendar: calendar
        )
    }
    let comparison = [
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 8, calendar: calendar),
            duration: 4 * 3_600,
            pickups: 35,
            selectedDuration: 90 * 60,
            calendar: calendar
        ),
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 9, calendar: calendar),
            duration: 4.4 * 3_600,
            pickups: 35,
            selectedDuration: 90 * 60,
            calendar: calendar
        ),
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 10, calendar: calendar),
            duration: 10 * 3_600,
            pickups: 80,
            selectedDuration: 5 * 3_600,
            calendar: calendar
        )
    ]

    let summary = HomeEngagementBuilder.summary(
        history: baseline + comparison,
        calendar: calendar,
        now: makeHomeDate(2026, 5, 10, calendar: calendar)
    )

    #expect(summary.beatBaselineStreakDays == 2)
    #expect(summary.isTodayBelowBaseline == false)
}

@Test func homeEngagementFindsLargestAppImprovement() throws {
    let calendar = makeHomeCalendar()
    let baseline = (1...7).map { day in
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, day, calendar: calendar),
            duration: 6 * 3_600,
            pickups: 60,
            selectedDuration: 4 * 3_600,
            apps: [
                SharedAppUsage(id: "a", displayName: "TikTok", bundleIdentifier: "a", duration: 2 * 3_600),
                SharedAppUsage(id: "b", displayName: "YouTube", bundleIdentifier: "b", duration: 3_600)
            ],
            calendar: calendar
        )
    }
    let comparison = [
        makeHomeSnapshot(
            date: makeHomeDate(2026, 5, 8, calendar: calendar),
            duration: 3 * 3_600,
            pickups: 20,
            selectedDuration: 90 * 60,
            apps: [
                SharedAppUsage(id: "a", displayName: "TikTok", bundleIdentifier: "a", duration: 30 * 60),
                SharedAppUsage(id: "b", displayName: "YouTube", bundleIdentifier: "b", duration: 45 * 60)
            ],
            calendar: calendar
        )
    ]

    let summary = HomeEngagementBuilder.summary(
        history: baseline + comparison,
        calendar: calendar,
        now: makeHomeDate(2026, 5, 9, calendar: calendar)
    )

    let improvement = try #require(summary.topImprovement)
    #expect(improvement.title == "TikTok down")
    #expect(improvement.savedDuration == TimeInterval(90 * 60))
    #expect(improvement.percentChange == 75)
}

private func makeHomeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}

private func makeHomeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    calendar: Calendar
) -> Date {
    DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: 12
    ).date!
}

private func makeHomeSnapshot(
    date: Date,
    duration: TimeInterval,
    pickups: Int,
    selectedDuration: TimeInterval,
    apps: [SharedAppUsage] = [],
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
        selectedAppDuration: selectedDuration,
        pickupCount: pickups,
        appRows: apps,
        lastUpdated: date,
        capability: apps.isEmpty ? .aggregateOnly(reason: "Selected-app total only") : .fullAppDetail
    )
}
