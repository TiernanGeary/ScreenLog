import Foundation

/// Freshness tier for a friend's shared data, keyed off the snapshot's
/// lastUpdated timestamp. Thresholds follow the spec: green < 5 min,
/// yellow 5-60 min, orange beyond an hour.
public enum FriendFreshness: Equatable, Sendable {
    case fresh
    case aging
    case stale
    case missing

    public static func tier(lastUpdated: Date?, now: Date = Date()) -> FriendFreshness {
        guard let lastUpdated else {
            return .missing
        }

        let elapsed = now.timeIntervalSince(lastUpdated)
        if elapsed < 5 * 60 {
            return .fresh
        }
        if elapsed < 60 * 60 {
            return .aging
        }
        return .stale
    }
}

/// Pure ordering for the unified friends list's Activity mode:
/// highest screen time first, friends without data last, stable name order.
public enum FriendBoardBuilder {
    public static func activityRows(_ summaries: [FriendUsageSummary]) -> [FriendUsageSummary] {
        summaries.sorted { lhs, rhs in
            switch (lhs.totalDuration, rhs.totalDuration) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }

            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }
}
