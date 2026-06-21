import Foundation

public enum GroupMode: String, Codable, Sendable {
    case perMember = "per_member"
    case pool
}

public enum GroupRole: String, Codable, Sendable {
    case owner, member
}

public struct GroupBlockConfig: Codable, Equatable, Sendable {
    public var appNames: [String]
    public var perMemberLimitSeconds: Int?
    public var poolSeconds: Int?
    public var approvalsRequired: Int
    public init(appNames: [String], perMemberLimitSeconds: Int?, poolSeconds: Int?, approvalsRequired: Int) {
        self.appNames = appNames; self.perMemberLimitSeconds = perMemberLimitSeconds
        self.poolSeconds = poolSeconds; self.approvalsRequired = approvalsRequired
    }
}

public enum GroupAppNames {
    /// Trim, drop empties, dedupe case-insensitively (keep first spelling), cap length.
    public static func normalize(_ names: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for raw in names {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            if seen.insert(key).inserted { out.append(String(t.prefix(60))) }
        }
        return out
    }
}

public enum GroupConfigValidation {
    /// Returns a list of human-readable errors; empty means valid.
    public static func errors(mode: GroupMode, appNames: [String], limitSeconds: Int?, approvalsRequired: Int) -> [String] {
        var errs: [String] = []
        if GroupAppNames.normalize(appNames).isEmpty { errs.append("Add at least one app to restrict.") }
        if (limitSeconds ?? 0) <= 0 {
            errs.append(mode == .pool ? "Set a positive pool limit." : "Set a positive daily limit.")
        }
        if approvalsRequired < 1 { errs.append("Approvals required must be at least 1.") }
        return errs
    }
}

public struct GroupMemberInfo: Codable, Equatable, Identifiable, Sendable {
    public var userID: String
    public var displayName: String
    public var role: GroupRole
    public var configured: Bool
    public var id: String { userID }
    public init(userID: String, displayName: String, role: GroupRole, configured: Bool) {
        self.userID = userID; self.displayName = displayName; self.role = role; self.configured = configured
    }
}

public enum GroupMembership {
    public static func configuredSummary(_ members: [GroupMemberInfo]) -> (configured: Int, total: Int, pending: [String]) {
        let pending = members.filter { !$0.configured }.map(\.displayName)
        return (members.filter { $0.configured }.count, members.count, pending)
    }
}

public enum GroupInviteCode {
    public static func formatted(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}

public enum GroupBlock {
    /// Builds the local per-member block: a daily time-limit over the picked apps.
    public static func makeBlockGroup(id: String, name: String,
                                      selectionData: Data, limitSeconds: TimeInterval) -> BlockGroup {
        let now = Date()
        return BlockGroup(
            id: id,
            name: name,
            colorHex: "#6A4C93",
            selectionData: selectionData,
            isEnabled: true,
            mode: .timeLimit(limitSeconds: limitSeconds, days: BlockWeekday.everyDay),
            createdAt: now,
            updatedAt: now
        )
    }

    /// Random, member-hidden password for the auto-locked group block.
    public static func generatePassword(length: Int = 16) -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}
