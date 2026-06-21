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

    func test_groupBlock_makeBlockGroup_perMemberDefaults() {
        let g = GroupBlock.makeBlockGroup(id: "g1", name: "Study group",
                                          selectionData: Data([0x01, 0x02]), limitSeconds: 1800)
        XCTAssertEqual(g.id, "g1")
        XCTAssertEqual(g.name, "Study group")
        XCTAssertEqual(g.selectionData, Data([0x01, 0x02]))
        XCTAssertTrue(g.isEnabled)
        if case let .timeLimit(secs, days) = g.mode {
            XCTAssertEqual(secs, 1800)
            XCTAssertEqual(days, BlockWeekday.everyDay)
        } else { XCTFail("must be .timeLimit everyday") }
    }

    func test_groupBlock_generatePassword_lengthAndCharset() {
        let p = GroupBlock.generatePassword()
        XCTAssertEqual(p.count, 16)
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
        XCTAssertTrue(p.allSatisfy { allowed.contains($0) })
        XCTAssertNotEqual(p, GroupBlock.generatePassword())
    }
}
