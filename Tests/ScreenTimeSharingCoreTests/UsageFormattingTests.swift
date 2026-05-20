import Testing
import Foundation
@testable import ScreenTimeSharingCore

@Test func durationFormattingUsesCompactHoursAndMinutes() {
    #expect(UsageFormatting.duration(nil) == "Unavailable")
    #expect(UsageFormatting.duration(0) == "0m")
    #expect(UsageFormatting.duration(59) == "0m")
    #expect(UsageFormatting.duration(60) == "1m")
    #expect(UsageFormatting.duration(3_600) == "1h")
    #expect(UsageFormatting.duration(5_460) == "1h 31m")
}

@Test func lastUpdatedFormattingUsesWidgetFriendlyCopy() {
    let now = Date(timeIntervalSince1970: 10_000)

    #expect(UsageFormatting.lastUpdated(nil, now: now) == "Never updated")
    #expect(UsageFormatting.lastUpdated(now.addingTimeInterval(-30), now: now) == "Updated just now")
    #expect(UsageFormatting.lastUpdated(now.addingTimeInterval(-600), now: now) == "Updated 10m ago")
    #expect(UsageFormatting.lastUpdated(now.addingTimeInterval(-7_200), now: now) == "Updated 2h ago")
}

@Test func capabilityLabelsAreExplicitAboutFallbacks() {
    #expect(UsageFormatting.capabilityLabel(.fullAppDetail) == "App detail available")
    #expect(UsageFormatting.capabilityLabel(.aggregateOnly()) == "Selected-app total only")
    #expect(UsageFormatting.capabilityLabel(.unavailable(reason: "Denied")) == "Screen Time unavailable")
}
