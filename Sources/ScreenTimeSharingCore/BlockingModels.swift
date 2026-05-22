import CryptoKit
import Foundation

public enum BlockWeekday: Int, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var id: Int { rawValue }

    public var shortLabel: String {
        switch self {
        case .sunday:
            return "Sun"
        case .monday:
            return "Mon"
        case .tuesday:
            return "Tue"
        case .wednesday:
            return "Wed"
        case .thursday:
            return "Thu"
        case .friday:
            return "Fri"
        case .saturday:
            return "Sat"
        }
    }

    public static func < (lhs: BlockWeekday, rhs: BlockWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static var weekdays: [BlockWeekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }

    public static var weekend: [BlockWeekday] {
        [.saturday, .sunday]
    }

    public static var everyDay: [BlockWeekday] {
        allCases.sorted()
    }
}

public enum BlockingTimeLimitRange {
    public static let minimumSeconds: TimeInterval = 5 * 60
    public static let maximumSeconds: TimeInterval = 8 * 3_600
    public static let stepSeconds: TimeInterval = 5 * 60

    public static func snappedSeconds(_ seconds: TimeInterval) -> TimeInterval {
        let clamped = min(maximumSeconds, max(minimumSeconds, seconds))
        let steps = (clamped / stepSeconds).rounded()
        return steps * stepSeconds
    }

    public static func isValid(_ seconds: TimeInterval) -> Bool {
        let snapped = snappedSeconds(seconds)
        return snapped == seconds && (minimumSeconds...maximumSeconds).contains(seconds)
    }
}

public enum BlockingUnblockDurationOptions {
    public static let minutes = [1, 5, 10, 15, 30, 60]

    public static func normalizedMinutes(_ minutes: Int) -> Int {
        Self.minutes.min { lhs, rhs in
            abs(lhs - minutes) < abs(rhs - minutes)
        } ?? 15
    }
}

public enum BlockingDisplayFormatter {
    public static func durationLabel(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }

    public static func fullDurationLabel(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var components: [String] = []

        if hours > 0 {
            components.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }

        if minutes > 0 || components.isEmpty {
            components.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }

        return components.joined(separator: " ")
    }
}

public enum BlockGroupMode: Codable, Equatable, Sendable {
    case scheduled(startMinute: Int, endMinute: Int, days: [BlockWeekday])
    case timeLimit(limitSeconds: TimeInterval, days: [BlockWeekday])

    private enum CodingKeys: String, CodingKey {
        case type
        case startMinute
        case endMinute
        case limitSeconds
        case days
    }

    private enum ModeType: String, Codable {
        case scheduled
        case timeLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ModeType.self, forKey: .type)

        switch type {
        case .scheduled:
            self = .scheduled(
                startMinute: try container.decode(Int.self, forKey: .startMinute),
                endMinute: try container.decode(Int.self, forKey: .endMinute),
                days: BlockRuleKind.normalizedDays(try container.decode([BlockWeekday].self, forKey: .days))
            )
        case .timeLimit:
            self = .timeLimit(
                limitSeconds: try container.decode(TimeInterval.self, forKey: .limitSeconds),
                days: BlockRuleKind.normalizedDays(try container.decode([BlockWeekday].self, forKey: .days))
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .scheduled(let startMinute, let endMinute, let days):
            try container.encode(ModeType.scheduled, forKey: .type)
            try container.encode(startMinute, forKey: .startMinute)
            try container.encode(endMinute, forKey: .endMinute)
            try container.encode(BlockRuleKind.normalizedDays(days), forKey: .days)
        case .timeLimit(let limitSeconds, let days):
            try container.encode(ModeType.timeLimit, forKey: .type)
            try container.encode(limitSeconds, forKey: .limitSeconds)
            try container.encode(BlockRuleKind.normalizedDays(days), forKey: .days)
        }
    }

    public var days: [BlockWeekday] {
        switch self {
        case .scheduled(_, _, let days), .timeLimit(_, let days):
            return BlockRuleKind.normalizedDays(days)
        }
    }

    public var label: String {
        switch self {
        case .scheduled(let startMinute, let endMinute, let days):
            return "\(BlockRuleKind.dayLabel(days)) \(BlockRuleKind.timeLabel(startMinute))-\(BlockRuleKind.timeLabel(endMinute))"
        case .timeLimit(let limitSeconds, let days):
            return "\(BlockingDisplayFormatter.durationLabel(limitSeconds)) per day, \(BlockRuleKind.dayLabel(days))"
        }
    }

    public var isValid: Bool {
        switch self {
        case .scheduled(let startMinute, let endMinute, let days):
            return !days.isEmpty
                && BlockRuleKind.isValidMinute(startMinute)
                && BlockRuleKind.isValidMinute(endMinute)
                && startMinute != endMinute
        case .timeLimit(let limitSeconds, let days):
            return !days.isEmpty && BlockingTimeLimitRange.isValid(limitSeconds)
        }
    }

    public static var defaultTimeLimit: BlockGroupMode {
        .timeLimit(limitSeconds: 30 * 60, days: BlockWeekday.everyDay)
    }
}

public struct BlockUnblockConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var unblocksPerDay: Int
    public var maxDurationSeconds: TimeInterval

    public init(
        isEnabled: Bool = true,
        unblocksPerDay: Int = 3,
        maxDurationSeconds: TimeInterval = 15 * 60
    ) {
        self.isEnabled = isEnabled
        self.unblocksPerDay = max(1, unblocksPerDay)
        let minutes = max(1, Int((maxDurationSeconds / 60).rounded()))
        self.maxDurationSeconds = TimeInterval(BlockingUnblockDurationOptions.normalizedMinutes(minutes) * 60)
    }

    public static var disabled: BlockUnblockConfig {
        BlockUnblockConfig(isEnabled: false, unblocksPerDay: 1, maxDurationSeconds: 5 * 60)
    }
}

public struct BlockFriendRequestConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

public struct BlockGroupPassword: Codable, Equatable, Sendable {
    public var salt: String
    public var hash: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(salt: String, hash: String, createdAt: Date, updatedAt: Date) {
        self.salt = salt
        self.hash = hash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BlockPasswordResetState: Codable, Equatable, Sendable {
    public var requestedAt: Date
    public var availableAt: Date

    public init(requestedAt: Date, availableAt: Date? = nil) {
        self.requestedAt = requestedAt
        self.availableAt = availableAt ?? requestedAt.addingTimeInterval(24 * 3_600)
    }

    public func isAvailable(now: Date = Date()) -> Bool {
        now >= availableAt
    }
}

public enum BlockingPasswordHasher {
    public static func makePassword(
        _ password: String,
        now: Date = Date(),
        salt: String = UUID().uuidString
    ) -> BlockGroupPassword {
        BlockGroupPassword(
            salt: salt,
            hash: hash(password: password, salt: salt),
            createdAt: now,
            updatedAt: now
        )
    }

    public static func verify(_ password: String, against storedPassword: BlockGroupPassword) -> Bool {
        hash(password: password, salt: storedPassword.salt) == storedPassword.hash
    }

    private static func hash(password: String, salt: String) -> String {
        let input = Data("\(salt):\(password)".utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct BlockGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var selectionData: Data
    public var isEnabled: Bool
    public var mode: BlockGroupMode
    public var unblockConfig: BlockUnblockConfig
    public var friendRequestConfig: BlockFriendRequestConfig
    public var password: BlockGroupPassword?
    public var passwordReset: BlockPasswordResetState?
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case selectionData
        case isEnabled
        case mode
        case unblockConfig
        case friendRequestConfig
        case password
        case passwordReset
        case createdAt
        case updatedAt
    }

    public init(
        id: String,
        name: String,
        colorHex: String,
        selectionData: Data,
        isEnabled: Bool = true,
        mode: BlockGroupMode = .defaultTimeLimit,
        unblockConfig: BlockUnblockConfig = BlockUnblockConfig(),
        friendRequestConfig: BlockFriendRequestConfig = BlockFriendRequestConfig(),
        password: BlockGroupPassword? = nil,
        passwordReset: BlockPasswordResetState? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.selectionData = selectionData
        self.isEnabled = isEnabled
        self.mode = mode
        self.unblockConfig = unblockConfig
        self.friendRequestConfig = friendRequestConfig
        self.password = password
        self.passwordReset = passwordReset
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        selectionData = try container.decode(Data.self, forKey: .selectionData)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mode = try container.decodeIfPresent(BlockGroupMode.self, forKey: .mode) ?? .defaultTimeLimit
        unblockConfig = try container.decodeIfPresent(BlockUnblockConfig.self, forKey: .unblockConfig) ?? BlockUnblockConfig()
        friendRequestConfig = try container.decodeIfPresent(BlockFriendRequestConfig.self, forKey: .friendRequestConfig) ?? BlockFriendRequestConfig()
        password = try container.decodeIfPresent(BlockGroupPassword.self, forKey: .password)
        passwordReset = try container.decodeIfPresent(BlockPasswordResetState.self, forKey: .passwordReset)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(selectionData, forKey: .selectionData)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mode, forKey: .mode)
        try container.encode(unblockConfig, forKey: .unblockConfig)
        try container.encode(friendRequestConfig, forKey: .friendRequestConfig)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encodeIfPresent(passwordReset, forKey: .passwordReset)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var requiresPasswordSetup: Bool {
        password == nil
    }
}

public enum BlockRuleKind: Codable, Equatable, Sendable {
    case dailyAllowance(seconds: TimeInterval)
    case scheduledWindow(days: [BlockWeekday], startMinute: Int, endMinute: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case seconds
        case days
        case startMinute
        case endMinute
    }

    private enum KindType: String, Codable {
        case dailyAllowance
        case scheduledWindow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)

        switch type {
        case .dailyAllowance:
            let seconds = try container.decode(TimeInterval.self, forKey: .seconds)
            self = .dailyAllowance(seconds: seconds)
        case .scheduledWindow:
            let days = try container.decode([BlockWeekday].self, forKey: .days)
            let startMinute = try container.decode(Int.self, forKey: .startMinute)
            let endMinute = try container.decode(Int.self, forKey: .endMinute)
            self = .scheduledWindow(
                days: Self.normalizedDays(days),
                startMinute: startMinute,
                endMinute: endMinute
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .dailyAllowance(let seconds):
            try container.encode(KindType.dailyAllowance, forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        case .scheduledWindow(let days, let startMinute, let endMinute):
            try container.encode(KindType.scheduledWindow, forKey: .type)
            try container.encode(Self.normalizedDays(days), forKey: .days)
            try container.encode(startMinute, forKey: .startMinute)
            try container.encode(endMinute, forKey: .endMinute)
        }
    }

    public var label: String {
        switch self {
        case .dailyAllowance(let seconds):
            return "\(BlockingDisplayFormatter.durationLabel(seconds)) per day"
        case .scheduledWindow(let days, let startMinute, let endMinute):
            return "\(Self.dayLabel(days)) \(Self.timeLabel(startMinute))-\(Self.timeLabel(endMinute))"
        }
    }

    public var isValid: Bool {
        switch self {
        case .dailyAllowance(let seconds):
            return seconds > 0
        case .scheduledWindow(let days, let startMinute, let endMinute):
            return !days.isEmpty
                && Self.isValidMinute(startMinute)
                && Self.isValidMinute(endMinute)
                && startMinute != endMinute
        }
    }

    public static func normalizedDays(_ days: [BlockWeekday]) -> [BlockWeekday] {
        Array(Set(days)).sorted()
    }

    public static func isValidMinute(_ minute: Int) -> Bool {
        (0..<1_440).contains(minute)
    }

    public static func timeLabel(_ minute: Int) -> String {
        guard isValidMinute(minute) else {
            return "--"
        }

        let hour = minute / 60
        let minuteComponent = minute % 60
        let suffix = hour >= 12 ? "PM" : "AM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", displayHour, minuteComponent, suffix)
    }

    public static func dayLabel(_ days: [BlockWeekday]) -> String {
        let normalized = normalizedDays(days)
        if normalized == BlockWeekday.weekdays {
            return "Weekdays"
        }

        if normalized == BlockWeekday.weekend {
            return "Weekend"
        }

        if normalized == BlockWeekday.everyDay {
            return "Every day"
        }

        return normalized.map(\.shortLabel).joined(separator: ", ")
    }
}

public struct BlockRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var groupID: String
    public var isEnabled: Bool
    public var kind: BlockRuleKind
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        groupID: String,
        isEnabled: Bool = true,
        kind: BlockRuleKind,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.groupID = groupID
        self.isEnabled = isEnabled
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum BlockRequestStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case pending
    case approved
    case denied
    case expired
    case collected
}

public enum BlockFriendRequestLifecycle {
    public static let pendingExpirationSeconds: TimeInterval = 8 * 3_600
    public static let approvedCollectionExpirationSeconds: TimeInterval = 24 * 3_600

    public static func pendingExpirationDate(createdAt: Date) -> Date {
        createdAt.addingTimeInterval(pendingExpirationSeconds)
    }

    public static func approvedExpirationDate(approvedAt: Date) -> Date {
        approvedAt.addingTimeInterval(approvedCollectionExpirationSeconds)
    }
}

public enum BlockingFriendRequestIntentStore {
    public static let groupIDKey = "PendingShieldFriendRequestGroupID.v1"
    public static let createdAtKey = "PendingShieldFriendRequestCreatedAt.v1"
    public static let expirationSeconds: TimeInterval = 10 * 60
}

public struct BlockRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var groupID: String
    public var requestedSeconds: TimeInterval
    public var status: BlockRequestStatus
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: String,
        groupID: String,
        requestedSeconds: TimeInterval,
        status: BlockRequestStatus,
        createdAt: Date,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.requestedSeconds = requestedSeconds
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    public func resolving(as status: BlockRequestStatus, at date: Date) -> BlockRequest {
        var copy = self
        copy.status = status
        copy.resolvedAt = date
        return copy
    }
}

public struct BlockFriendRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var groupID: String
    public var requestedSeconds: TimeInterval
    public var selectedFriendIDs: [String]
    public var message: String
    public var requesterID: String?
    public var requesterDisplayName: String?
    public var approvedByFriendID: String?
    public var status: BlockRequestStatus
    public var createdAt: Date
    public var resolvedAt: Date?
    public var collectedAt: Date?
    public var expiresAt: Date?
    public var approvedExpiresAt: Date?

    public init(
        id: String,
        groupID: String,
        requestedSeconds: TimeInterval,
        selectedFriendIDs: [String],
        message: String,
        requesterID: String? = nil,
        requesterDisplayName: String? = nil,
        approvedByFriendID: String? = nil,
        status: BlockRequestStatus = .pending,
        createdAt: Date,
        resolvedAt: Date? = nil,
        collectedAt: Date? = nil,
        expiresAt: Date? = nil,
        approvedExpiresAt: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.requestedSeconds = requestedSeconds
        self.selectedFriendIDs = selectedFriendIDs
        self.message = message
        self.requesterID = requesterID
        self.requesterDisplayName = requesterDisplayName
        self.approvedByFriendID = approvedByFriendID
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.collectedAt = collectedAt
        self.expiresAt = expiresAt
        self.approvedExpiresAt = approvedExpiresAt
    }

    public var pendingExpiresAt: Date {
        expiresAt ?? BlockFriendRequestLifecycle.pendingExpirationDate(createdAt: createdAt)
    }

    public var collectionExpiresAt: Date? {
        guard let resolvedAt else {
            return approvedExpiresAt
        }

        return approvedExpiresAt ?? BlockFriendRequestLifecycle.approvedExpirationDate(approvedAt: resolvedAt)
    }

    public func resolving(
        as status: BlockRequestStatus,
        at date: Date,
        approvedByFriendID: String? = nil
    ) -> BlockFriendRequest {
        var copy = self
        copy.status = status
        copy.resolvedAt = date
        if status == .approved {
            copy.approvedByFriendID = approvedByFriendID
            copy.approvedExpiresAt = BlockFriendRequestLifecycle.approvedExpirationDate(approvedAt: date)
        }
        return copy
    }

    public func collecting(at date: Date) -> BlockFriendRequest {
        var copy = self
        copy.status = .collected
        copy.collectedAt = date
        return copy
    }

    public func expiringIfNeeded(now: Date) -> BlockFriendRequest {
        switch status {
        case .pending where now >= pendingExpiresAt:
            return resolving(as: .expired, at: pendingExpiresAt)
        case .approved:
            guard let collectionExpiresAt, now >= collectionExpiresAt else {
                return self
            }
            var copy = self
            copy.status = .expired
            copy.approvedExpiresAt = collectionExpiresAt
            return copy
        case .pending, .denied, .expired, .collected:
            return self
        }
    }

    public func isSent(by userID: String) -> Bool {
        requesterID == nil || requesterID == userID
    }

    public func isReceived(by userID: String) -> Bool {
        requesterID != nil && requesterID != userID && selectedFriendIDs.contains(userID)
    }
}

public struct BlockUnblockSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var groupID: String
    public var durationSeconds: TimeInterval
    public var startedAt: Date
    public var expiresAt: Date

    public init(
        id: String,
        groupID: String,
        durationSeconds: TimeInterval,
        startedAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.groupID = groupID
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    public func isActive(now: Date = Date()) -> Bool {
        startedAt <= now && now < expiresAt
    }
}

public struct BlockingState: Codable, Equatable, Sendable {
    public var groups: [BlockGroup]
    public var rules: [BlockRule]
    public var requests: [BlockRequest]
    public var friendRequests: [BlockFriendRequest]
    public var unblockSessions: [BlockUnblockSession]
    public var lastUpdated: Date

    private enum CodingKeys: String, CodingKey {
        case groups
        case rules
        case requests
        case friendRequests
        case unblockSessions
        case lastUpdated
    }

    public init(
        groups: [BlockGroup] = [],
        rules: [BlockRule] = [],
        requests: [BlockRequest] = [],
        friendRequests: [BlockFriendRequest] = [],
        unblockSessions: [BlockUnblockSession] = [],
        lastUpdated: Date = Date()
    ) {
        self.groups = groups
        self.rules = rules
        self.requests = requests
        self.friendRequests = friendRequests
        self.unblockSessions = unblockSessions
        self.lastUpdated = lastUpdated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decodeIfPresent([BlockGroup].self, forKey: .groups) ?? []
        rules = try container.decodeIfPresent([BlockRule].self, forKey: .rules) ?? []
        requests = try container.decodeIfPresent([BlockRequest].self, forKey: .requests) ?? []
        friendRequests = try container.decodeIfPresent([BlockFriendRequest].self, forKey: .friendRequests) ?? []
        unblockSessions = try container.decodeIfPresent([BlockUnblockSession].self, forKey: .unblockSessions) ?? []
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groups, forKey: .groups)
        try container.encode(rules, forKey: .rules)
        try container.encode(requests, forKey: .requests)
        try container.encode(friendRequests, forKey: .friendRequests)
        try container.encode(unblockSessions, forKey: .unblockSessions)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

public enum BlockingStateMigrator {
    public static func migrated(_ state: BlockingState, now: Date = Date()) -> BlockingState {
        guard !state.rules.isEmpty else {
            return state
        }

        var copy = state
        copy.groups = state.groups.map { group in
            guard group.password == nil,
                  let legacyRule = state.rules.first(where: { $0.groupID == group.id && $0.kind.isValid }) else {
                return group
            }

            var migrated = group
            switch legacyRule.kind {
            case .dailyAllowance(let seconds):
                migrated.mode = .timeLimit(
                    limitSeconds: BlockingTimeLimitRange.snappedSeconds(seconds),
                    days: BlockWeekday.everyDay
                )
            case .scheduledWindow(let days, let startMinute, let endMinute):
                migrated.mode = .scheduled(
                    startMinute: startMinute,
                    endMinute: endMinute,
                    days: BlockRuleKind.normalizedDays(days)
                )
            }
            migrated.updatedAt = max(group.updatedAt, now)
            return migrated
        }

        copy.lastUpdated = max(state.lastUpdated, now)
        return copy
    }
}

public enum BlockingStoreCodec {
    public static let suiteName = "group.com.jdco.ScreenTimeSharing"
    public static let storageKey = "BlockingState.v1"

    public static func encode(_ state: BlockingState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    public static func decode(_ data: Data) throws -> BlockingState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BlockingState.self, from: data)
    }
}

public struct BlockingStateStore {
    private let defaults: UserDefaults?
    private let key: String

    public init(
        defaults: UserDefaults? = UserDefaults(suiteName: BlockingStoreCodec.suiteName),
        key: String = BlockingStoreCodec.storageKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> BlockingState {
        guard let data = defaults?.data(forKey: key),
              let state = try? BlockingStoreCodec.decode(data) else {
            return BlockingState()
        }

        return BlockingStateMigrator.migrated(state)
    }

    public func save(_ state: BlockingState) throws {
        let data = try BlockingStoreCodec.encode(state)
        defaults?.set(data, forKey: key)
    }
}

public enum BlockingStateResolver {
    public static func group(for groupID: String, in state: BlockingState) -> BlockGroup? {
        state.groups.first { $0.id == groupID }
    }

    public static func rules(for groupID: String, in state: BlockingState) -> [BlockRule] {
        state.rules.filter { $0.groupID == groupID }
    }

    public static func enabledGroups(in state: BlockingState) -> [BlockGroup] {
        state.groups.filter { $0.isEnabled && $0.mode.isValid }
    }

    public static func enabledRules(in state: BlockingState) -> [BlockRule] {
        let enabledGroupIDs = Set(state.groups.filter(\.isEnabled).map(\.id))
        return state.rules.filter { rule in
            rule.isEnabled
                && rule.kind.isValid
                && enabledGroupIDs.contains(rule.groupID)
        }
    }

    public static func activeGroupIDs(in state: BlockingState) -> Set<String> {
        Set(enabledGroups(in: state).map(\.id))
    }

    public static func pendingRequests(in state: BlockingState) -> [BlockRequest] {
        state.requests.filter { $0.status == .pending }
    }

    public static func pendingFriendRequests(in state: BlockingState) -> [BlockFriendRequest] {
        state.friendRequests.filter { $0.status == .pending }
    }

    public static func dailyAllowanceSeconds(for groupID: String, in state: BlockingState) -> TimeInterval? {
        timeLimitSeconds(for: groupID, in: state)
    }

    public static func timeLimitSeconds(for groupID: String, in state: BlockingState) -> TimeInterval? {
        guard let group = group(for: groupID, in: state) else {
            return nil
        }

        if case .timeLimit(let seconds, _) = group.mode {
            return seconds
        }

        return rules(for: groupID, in: state)
            .filter { $0.isEnabled && $0.kind.isValid }
            .compactMap { rule -> TimeInterval? in
                guard case .dailyAllowance(let seconds) = rule.kind else {
                    return nil
                }
                return seconds
            }
            .min()
    }

    public static func activeUnblockSessions(
        in state: BlockingState,
        now: Date = Date()
    ) -> [BlockUnblockSession] {
        state.unblockSessions.filter { $0.isActive(now: now) }
    }

    public static func suppressedGroupIDs(
        in state: BlockingState,
        now: Date = Date()
    ) -> Set<String> {
        Set(activeUnblockSessions(in: state, now: now).map(\.groupID))
    }

    public static func remainingUnblocks(
        for groupID: String,
        in state: BlockingState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard let group = group(for: groupID, in: state),
              group.unblockConfig.isEnabled else {
            return 0
        }

        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return 0
        }

        let usedToday = state.unblockSessions.filter { session in
            session.groupID == groupID && (start..<end).contains(session.startedAt)
        }.count

        return max(0, group.unblockConfig.unblocksPerDay - usedToday)
    }
}

public enum BlockingMonitorNameBuilder {
    public static let prefix = "screenlog.block"

    public static func dailyAllowanceActivityName(ruleID: String) -> String {
        "\(prefix).allowance.\(sanitized(ruleID))"
    }

    public static func dailyAllowanceEventName(ruleID: String) -> String {
        "\(prefix).threshold.\(sanitized(ruleID))"
    }

    public static func scheduledActivityName(ruleID: String, weekday: BlockWeekday) -> String {
        "\(prefix).schedule.\(sanitized(ruleID)).\(weekday.rawValue)"
    }

    public static func timeLimitActivityName(groupID: String) -> String {
        "\(prefix).limit.\(sanitized(groupID))"
    }

    public static func timeLimitActivityName(groupID: String, weekday: BlockWeekday) -> String {
        "\(prefix).limit.\(sanitized(groupID)).\(weekday.rawValue)"
    }

    public static func timeLimitEventName(groupID: String) -> String {
        "\(prefix).limit.threshold.\(sanitized(groupID))"
    }

    public static func scheduledActivityName(groupID: String, weekday: BlockWeekday) -> String {
        "\(prefix).group.schedule.\(sanitized(groupID)).\(weekday.rawValue)"
    }

    public static func unblockActivityName(sessionID: String) -> String {
        "\(prefix).unblock.\(sanitized(sessionID))"
    }

    public static func parseRuleID(from rawName: String) -> String? {
        let parts = rawName.split(separator: ".").map(String.init)
        guard parts.count >= 4,
              parts[0] == "screenlog",
              parts[1] == "block" else {
            return nil
        }
        return parts[3]
    }

    public static func parseGroupID(from rawName: String) -> String? {
        let parts = rawName.split(separator: ".").map(String.init)
        guard parts.count >= 4,
              parts[0] == "screenlog",
              parts[1] == "block" else {
            return nil
        }

        if parts[2] == "limit" {
            return parts.count >= 4 ? parts[3] : nil
        }

        if parts.count >= 5, parts[2] == "group", parts[3] == "schedule" {
            return parts[4]
        }

        return nil
    }

    public static func isTimeLimitActivity(_ rawName: String) -> Bool {
        rawName.contains(".limit.")
    }

    public static func isScheduledActivity(_ rawName: String) -> Bool {
        rawName.contains(".group.schedule.")
    }

    public static func isUnblockActivity(_ rawName: String) -> Bool {
        rawName.contains(".unblock.")
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
