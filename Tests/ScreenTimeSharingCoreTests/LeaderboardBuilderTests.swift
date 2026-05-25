import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func leaderboardRanksLeastRequestedExtraTimeFirst() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12)))
    let participants = [
        AccountabilityParticipant(id: "maya", displayName: "Maya", avatarColorHex: "#E84855"),
        AccountabilityParticipant(id: "sam", displayName: "Sam", avatarColorHex: "#1B998B"),
        AccountabilityParticipant(id: "tiernan", displayName: "Tiernan", avatarColorHex: "#2E86AB")
    ]
    let events = [
        AccountabilityEvent(
            id: "event-1",
            userID: "tiernan",
            kind: .extraTimeRequested,
            occurredAt: now.addingTimeInterval(-300),
            seconds: 45 * 60
        ),
        AccountabilityEvent(
            id: "event-2",
            userID: "sam",
            kind: .extraTimeRequested,
            occurredAt: now.addingTimeInterval(-600),
            seconds: 10 * 60
        )
    ]

    let entries = LeaderboardBuilder.entries(
        participants: participants,
        events: events,
        window: .today,
        now: now,
        calendar: calendar
    )

    #expect(entries.map(\.userID) == ["maya", "sam", "tiernan"])
    #expect(entries[0].requestedExtraSeconds == 0)
    #expect(entries[2].requestCount == 1)
}

@Test func leaderboardAppliesWindowFiltering() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12)))
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
    let participant = AccountabilityParticipant(id: "sam", displayName: "Sam", avatarColorHex: "#1B998B")
    let events = [
        AccountabilityEvent(
            id: "today",
            userID: "sam",
            kind: .extraTimeRequested,
            occurredAt: now.addingTimeInterval(-60),
            seconds: 10 * 60
        ),
        AccountabilityEvent(
            id: "yesterday",
            userID: "sam",
            kind: .extraTimeRequested,
            occurredAt: yesterday,
            seconds: 20 * 60
        )
    ]

    let today = LeaderboardBuilder.entries(
        participants: [participant],
        events: events,
        window: .today,
        now: now,
        calendar: calendar
    )
    let allTime = LeaderboardBuilder.entries(
        participants: [participant],
        events: events,
        window: .allTime,
        now: now,
        calendar: calendar
    )

    #expect(today[0].requestedExtraSeconds == 10 * 60)
    #expect(allTime[0].requestedExtraSeconds == 30 * 60)
}

@Test func leaderboardWeekUsesSundayToSaturdayWindow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12)))
    let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 12)))
    let priorSaturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 12)))
    let participant = AccountabilityParticipant(id: "sam", displayName: "Sam", avatarColorHex: "#1B998B")
    let events = [
        AccountabilityEvent(
            id: "included",
            userID: "sam",
            kind: .extraTimeRequested,
            occurredAt: sunday,
            seconds: 20 * 60
        ),
        AccountabilityEvent(
            id: "excluded",
            userID: "sam",
            kind: .extraTimeRequested,
            occurredAt: priorSaturday,
            seconds: 40 * 60
        )
    ]

    let entries = LeaderboardBuilder.entries(
        participants: [participant],
        events: events,
        window: .week,
        now: now,
        calendar: calendar
    )

    #expect(LeaderboardWindow.week.label == "This Week")
    #expect(entries[0].requestedExtraSeconds == 20 * 60)
}

@Test func leaderboardUsesEmergencyUnlocksAndStreakAsTieBreakers() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12)))
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
    let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: now))
    let participants = [
        AccountabilityParticipant(id: "sam", displayName: "Sam", avatarColorHex: "#1B998B"),
        AccountabilityParticipant(id: "maya", displayName: "Maya", avatarColorHex: "#E84855"),
        AccountabilityParticipant(id: "riley", displayName: "Riley", avatarColorHex: "#F18F01")
    ]
    let events = [
        AccountabilityEvent(id: "sam-streak-1", userID: "sam", kind: .underLimitDayCompleted, occurredAt: yesterday),
        AccountabilityEvent(id: "sam-streak-2", userID: "sam", kind: .underLimitDayCompleted, occurredAt: twoDaysAgo),
        AccountabilityEvent(id: "maya-emergency", userID: "maya", kind: .emergencyUnlockUsed, occurredAt: now.addingTimeInterval(-60))
    ]

    let entries = LeaderboardBuilder.entries(
        participants: participants,
        events: events,
        window: .today,
        now: now,
        calendar: calendar
    )

    #expect(entries.map(\.userID) == ["sam", "riley", "maya"])
    #expect(entries[0].currentStreakDays == 2)
    #expect(entries[2].emergencyUnlockCount == 1)
}
