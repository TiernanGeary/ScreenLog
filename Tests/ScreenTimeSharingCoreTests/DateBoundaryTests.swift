import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func dayIntervalUsesProvidedCalendarAndTimeZone() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

    let date = Date(timeIntervalSince1970: 1_764_508_200)
    let interval = UsageDateBoundary.dayInterval(containing: date, calendar: calendar)

    #expect(interval.duration == 86_400)
    #expect(calendar.component(.hour, from: interval.start) == 0)
    #expect(calendar.component(.minute, from: interval.start) == 0)
}

@Test func snapshotIDUsesLocalDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let date = Date(timeIntervalSince1970: 1_764_508_200)

    #expect(UsageDateBoundary.snapshotID(profileID: "profile-1", date: date, calendar: calendar) == "profile-1-2025-11-30")
}
