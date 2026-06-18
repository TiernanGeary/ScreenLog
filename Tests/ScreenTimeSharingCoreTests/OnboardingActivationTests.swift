import XCTest
@testable import ScreenTimeSharingCore

final class OnboardingActivationTests: XCTestCase {
    func test_shareMessage_containsBothAppStoreAndInviteURLs() {
        let appStore = URL(string: "https://apps.apple.com/app/id000000000")!
        let invite = URL(string: "deny://invite/ABCD1234")!

        let msg = OnboardingInvite.shareMessage(
            displayName: "Leo", appStoreURL: appStore, inviteURL: invite)

        XCTAssertTrue(msg.contains(appStore.absoluteString),
                      "share text must include the App Store install URL")
        XCTAssertTrue(msg.contains(invite.absoluteString),
                      "share text must include the deny:// invite URL")
    }

    func test_shareMessage_handlesNilName() {
        let appStore = URL(string: "https://apps.apple.com/app/id000000000")!
        let invite = URL(string: "deny://invite/ABCD1234")!

        let msg = OnboardingInvite.shareMessage(
            displayName: nil, appStoreURL: appStore, inviteURL: invite)

        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(msg.contains(invite.absoluteString))
    }

    func test_meetsMinimumSelection_falseWhenAllZero() {
        XCTAssertFalse(OnboardingBlock.meetsMinimumSelection(appCount: 0, categoryCount: 0, webCount: 0))
    }

    func test_meetsMinimumSelection_trueWhenAnyNonZero() {
        XCTAssertTrue(OnboardingBlock.meetsMinimumSelection(appCount: 1, categoryCount: 0, webCount: 0))
        XCTAssertTrue(OnboardingBlock.meetsMinimumSelection(appCount: 0, categoryCount: 2, webCount: 0))
        XCTAssertTrue(OnboardingBlock.meetsMinimumSelection(appCount: 0, categoryCount: 0, webCount: 3))
    }

    func test_makeFirstBlockGroup_defaultsToTimeLimit() {
        let data = Data([0x01, 0x02, 0x03]) // opaque, non-empty
        let group = OnboardingBlock.makeFirstBlockGroup(
            id: "grp-1", name: "My First Block", selectionData: data)

        XCTAssertEqual(group.id, "grp-1")
        XCTAssertEqual(group.name, "My First Block")
        XCTAssertEqual(group.selectionData, data)
        XCTAssertTrue(group.isEnabled)
        if case let .timeLimit(limitSeconds, days) = group.mode {
            XCTAssertEqual(limitSeconds, 30 * 60)
            XCTAssertEqual(days, BlockWeekday.everyDay)
        } else {
            XCTFail("default onboarding block must use .timeLimit mode")
        }
    }

    func test_makeFirstBlockGroup_usesProvidedTimeLimitMode() {
        let data = Data([0x09])
        let mode = BlockGroupMode.timeLimit(limitSeconds: 45 * 60, days: BlockWeekday.weekdays)
        let group = OnboardingBlock.makeFirstBlockGroup(
            id: "grp-2", name: "Focus", selectionData: data, mode: mode)

        XCTAssertEqual(group.mode, mode)
        if case let .timeLimit(limitSeconds, days) = group.mode {
            XCTAssertEqual(limitSeconds, 45 * 60)
            XCTAssertEqual(days, BlockWeekday.weekdays)
        } else {
            XCTFail("expected the provided .timeLimit mode")
        }
    }

    func test_makeFirstBlockGroup_usesProvidedScheduledMode() {
        let data = Data([0x09])
        let mode = BlockGroupMode.scheduled(startMinute: 22 * 60, endMinute: 7 * 60, days: BlockWeekday.everyDay)
        let group = OnboardingBlock.makeFirstBlockGroup(
            id: "grp-3", name: "Night", selectionData: data, mode: mode)

        XCTAssertEqual(group.mode, mode)
        if case let .scheduled(startMinute, endMinute, days) = group.mode {
            XCTAssertEqual(startMinute, 22 * 60)
            XCTAssertEqual(endMinute, 7 * 60)
            XCTAssertEqual(days, BlockWeekday.everyDay)
        } else {
            XCTFail("expected the provided .scheduled mode")
        }
    }
}
