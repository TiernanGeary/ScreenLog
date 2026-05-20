import Foundation

public enum LockMode: String, Codable, CaseIterable, Equatable, Sendable {
    case solo
    case buddy
    case group
}

public enum ApprovalPolicy: Codable, Equatable, Sendable {
    case passwordAfterDelay(delaySeconds: TimeInterval)
    case oneBuddy(timeoutSeconds: TimeInterval)
    case group(requiredApprovalCount: Int, timeoutSeconds: TimeInterval)
}

public enum FallbackPolicy: Codable, Equatable, Sendable {
    case delayedSelfUnlock(delaySeconds: TimeInterval)
    case emergencyUnlocksPerDay(Int)
    case buddyInactiveFallback(days: Int)
}

public enum UnlockRequestStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case emergency
}

public struct UnlockRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var userID: String
    public var requestedExtraSeconds: TimeInterval
    public var reason: String?
    public var status: UnlockRequestStatus
    public var createdAt: Date
    public var resolvedAt: Date?
    public var responderID: String?

    public init(
        id: String,
        userID: String,
        requestedExtraSeconds: TimeInterval,
        reason: String?,
        status: UnlockRequestStatus,
        createdAt: Date,
        resolvedAt: Date?,
        responderID: String?
    ) {
        self.id = id
        self.userID = userID
        self.requestedExtraSeconds = requestedExtraSeconds
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.responderID = responderID
    }
}

public enum AccountabilityEventKind: String, Codable, CaseIterable, Equatable, Sendable {
    case extraTimeRequested
    case extraTimeApproved
    case extraTimeDenied
    case emergencyUnlockUsed
    case settingsResetCompleted
    case underLimitDayCompleted
}

public struct AccountabilityEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var userID: String
    public var kind: AccountabilityEventKind
    public var occurredAt: Date
    public var seconds: TimeInterval
    public var requestID: String?
    public var actorUserID: String?

    public init(
        id: String,
        userID: String,
        kind: AccountabilityEventKind,
        occurredAt: Date,
        seconds: TimeInterval = 0,
        requestID: String? = nil,
        actorUserID: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.kind = kind
        self.occurredAt = occurredAt
        self.seconds = seconds
        self.requestID = requestID
        self.actorUserID = actorUserID
    }
}

public struct AccountabilityParticipant: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var avatarColorHex: String

    public init(id: String, displayName: String, avatarColorHex: String) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
    }
}

public enum LeaderboardWindow: String, Codable, CaseIterable, Equatable, Sendable {
    case today
    case week
    case month
    case allTime

    public var label: String {
        switch self {
        case .today:
            return "Today"
        case .week:
            return "This Week"
        case .month:
            return "This Month"
        case .allTime:
            return "All Time"
        }
    }
}

public struct LeaderboardEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var userID: String
    public var displayName: String
    public var avatarColorHex: String
    public var requestedExtraSeconds: TimeInterval
    public var approvedExtraSeconds: TimeInterval
    public var requestCount: Int
    public var deniedCount: Int
    public var emergencyUnlockCount: Int
    public var settingsResetCount: Int
    public var currentStreakDays: Int
    public var lastUpdated: Date?

    public init(
        id: String,
        userID: String,
        displayName: String,
        avatarColorHex: String,
        requestedExtraSeconds: TimeInterval,
        approvedExtraSeconds: TimeInterval,
        requestCount: Int,
        deniedCount: Int,
        emergencyUnlockCount: Int,
        settingsResetCount: Int,
        currentStreakDays: Int,
        lastUpdated: Date?
    ) {
        self.id = id
        self.userID = userID
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.requestedExtraSeconds = requestedExtraSeconds
        self.approvedExtraSeconds = approvedExtraSeconds
        self.requestCount = requestCount
        self.deniedCount = deniedCount
        self.emergencyUnlockCount = emergencyUnlockCount
        self.settingsResetCount = settingsResetCount
        self.currentStreakDays = currentStreakDays
        self.lastUpdated = lastUpdated
    }
}

public enum LeaderboardBuilder {
    public static func entries(
        participants: [AccountabilityParticipant],
        events: [AccountabilityEvent],
        window: LeaderboardWindow,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LeaderboardEntry] {
        let relevantEvents = events.filter { event in
            guard let interval = interval(for: window, now: now, calendar: calendar) else {
                return event.occurredAt <= now
            }
            return interval.contains(event.occurredAt)
        }

        let allEventsByUser = Dictionary(grouping: events, by: \.userID)
        let relevantEventsByUser = Dictionary(grouping: relevantEvents, by: \.userID)

        return participants
            .map { participant in
                makeEntry(
                    participant: participant,
                    relevantEvents: relevantEventsByUser[participant.id] ?? [],
                    allEvents: allEventsByUser[participant.id] ?? [],
                    now: now,
                    calendar: calendar
                )
            }
            .sorted(by: compare)
    }

    private static func makeEntry(
        participant: AccountabilityParticipant,
        relevantEvents: [AccountabilityEvent],
        allEvents: [AccountabilityEvent],
        now: Date,
        calendar: Calendar
    ) -> LeaderboardEntry {
        let requested = relevantEvents
            .filter { $0.kind == .extraTimeRequested }
            .reduce(0) { $0 + max(0, $1.seconds) }
        let approved = relevantEvents
            .filter { $0.kind == .extraTimeApproved }
            .reduce(0) { $0 + max(0, $1.seconds) }
        let requestCount = relevantEvents.filter { $0.kind == .extraTimeRequested }.count
        let deniedCount = relevantEvents.filter { $0.kind == .extraTimeDenied }.count
        let emergencyCount = relevantEvents.filter { $0.kind == .emergencyUnlockUsed }.count
        let resetCount = relevantEvents.filter { $0.kind == .settingsResetCompleted }.count
        let lastUpdated = relevantEvents.map(\.occurredAt).max()

        return LeaderboardEntry(
            id: participant.id,
            userID: participant.id,
            displayName: participant.displayName,
            avatarColorHex: participant.avatarColorHex,
            requestedExtraSeconds: requested,
            approvedExtraSeconds: approved,
            requestCount: requestCount,
            deniedCount: deniedCount,
            emergencyUnlockCount: emergencyCount,
            settingsResetCount: resetCount,
            currentStreakDays: streakDays(from: allEvents, now: now, calendar: calendar),
            lastUpdated: lastUpdated
        )
    }

    private static func compare(_ lhs: LeaderboardEntry, _ rhs: LeaderboardEntry) -> Bool {
        if lhs.requestedExtraSeconds != rhs.requestedExtraSeconds {
            return lhs.requestedExtraSeconds < rhs.requestedExtraSeconds
        }

        if lhs.emergencyUnlockCount != rhs.emergencyUnlockCount {
            return lhs.emergencyUnlockCount < rhs.emergencyUnlockCount
        }

        if lhs.currentStreakDays != rhs.currentStreakDays {
            return lhs.currentStreakDays > rhs.currentStreakDays
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func interval(
        for window: LeaderboardWindow,
        now: Date,
        calendar: Calendar
    ) -> DateInterval? {
        switch window {
        case .today:
            return UsageDateBoundary.dayInterval(containing: now, calendar: calendar)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        case .allTime:
            return nil
        }
    }

    private static func streakDays(
        from events: [AccountabilityEvent],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let days = Set(
            events
                .filter { $0.kind == .underLimitDayCompleted && $0.occurredAt <= now }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )

        guard !days.isEmpty else {
            return 0
        }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }

        return count
    }
}
