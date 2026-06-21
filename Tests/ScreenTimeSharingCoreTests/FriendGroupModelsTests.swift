import XCTest
@testable import ScreenTimeSharingCore

final class FriendGroupModelsTests: XCTestCase {
    func test_normalize_trimsDropsEmptyDedupesCaseInsensitive() {
        let out = GroupAppNames.normalize([" Instagram ", "instagram", "", "TikTok", "  "])
        XCTAssertEqual(out, ["Instagram", "TikTok"])
    }
    func test_validation_perMember_requiresPositiveLimitAndApps() {
        XCTAssertTrue(GroupConfigValidation.errors(mode: .perMember, appNames: [], limitSeconds: 1800, approvalsRequired: 1).contains { $0.localizedCaseInsensitiveContains("app") })
        XCTAssertTrue(GroupConfigValidation.errors(mode: .perMember, appNames: ["IG"], limitSeconds: 0, approvalsRequired: 1).contains { $0.localizedCaseInsensitiveContains("limit") })
        XCTAssertTrue(GroupConfigValidation.errors(mode: .perMember, appNames: ["IG"], limitSeconds: 1800, approvalsRequired: 1).isEmpty)
    }
    func test_validation_approvalsAtLeastOne() {
        XCTAssertFalse(GroupConfigValidation.errors(mode: .pool, appNames: ["IG"], limitSeconds: 3600, approvalsRequired: 0).isEmpty)
    }
    func test_groupMode_rawValueMatchesBackend() {
        XCTAssertEqual(GroupMode.perMember.rawValue, "per_member")
        XCTAssertEqual(GroupMode.pool.rawValue, "pool")
    }
    func test_configuredSummary_countsAndPending() {
        let m = [
            GroupMemberInfo(userID: "1", displayName: "Leo", role: .owner, configured: true),
            GroupMemberInfo(userID: "2", displayName: "Mia", role: .member, configured: false),
            GroupMemberInfo(userID: "3", displayName: "Sam", role: .member, configured: false),
        ]
        let s = GroupMembership.configuredSummary(m)
        XCTAssertEqual(s.configured, 1); XCTAssertEqual(s.total, 3)
        XCTAssertEqual(s.pending, ["Mia", "Sam"])
    }
    func test_inviteCode_formatted() {
        XCTAssertEqual(GroupInviteCode.formatted("ABCD1234"), "ABCD-1234")
        XCTAssertEqual(GroupInviteCode.formatted("SHORT"), "SHORT")
    }
}
