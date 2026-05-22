import Foundation

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var avatarColorHex: String
    public var avatarImageData: Data?
    public var shareStatus: ShareStatus
    public var updatedAt: Date

    public init(
        id: String,
        displayName: String,
        avatarColorHex: String,
        avatarImageData: Data? = nil,
        shareStatus: ShareStatus,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.avatarImageData = avatarImageData
        self.shareStatus = shareStatus
        self.updatedAt = updatedAt
    }
}

public enum ShareStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case notShared
    case sharing
    case revoked
}

public struct SharedAppUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var bundleIdentifier: String?
    public var duration: TimeInterval

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String?,
        duration: TimeInterval
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.duration = duration
    }
}

public struct DailyUsageSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var ownerProfileID: String
    public var date: Date
    public var calendarIdentifier: String
    public var timeZoneIdentifier: String
    public var totalDuration: TimeInterval?
    public var selectedAppDuration: TimeInterval?
    public var pickupCount: Int?
    public var appRows: [SharedAppUsage]
    public var lastUpdated: Date
    public var capability: ScreenTimeCapability

    public init(
        id: String,
        ownerProfileID: String,
        date: Date,
        calendarIdentifier: String,
        timeZoneIdentifier: String,
        totalDuration: TimeInterval?,
        selectedAppDuration: TimeInterval?,
        pickupCount: Int? = nil,
        appRows: [SharedAppUsage],
        lastUpdated: Date,
        capability: ScreenTimeCapability
    ) {
        self.id = id
        self.ownerProfileID = ownerProfileID
        self.date = date
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.totalDuration = totalDuration
        self.selectedAppDuration = selectedAppDuration
        self.pickupCount = pickupCount
        self.appRows = appRows
        self.lastUpdated = lastUpdated
        self.capability = capability
    }

    public func sanitizedForUpload() -> DailyUsageSnapshot? {
        guard capability.allowsUpload else {
            return nil
        }

        var copy = self
        if !capability.allowsPerAppRows {
            copy.appRows = []
        }
        return copy
    }
}

public struct FriendShare: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var friendProfileID: String
    public var displayName: String
    public var acceptedAt: Date
    public var canReadSnapshots: Bool
    public var revokedAt: Date?

    public init(
        id: String,
        friendProfileID: String,
        displayName: String,
        acceptedAt: Date,
        canReadSnapshots: Bool,
        revokedAt: Date?
    ) {
        self.id = id
        self.friendProfileID = friendProfileID
        self.displayName = displayName
        self.acceptedAt = acceptedAt
        self.canReadSnapshots = canReadSnapshots
        self.revokedAt = revokedAt
    }
}

public enum StatsRange: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case month
    case week
    case day

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .month:
            return "Month"
        case .week:
            return "Week"
        case .day:
            return "Day"
        }
    }

    public var leaderboardWindow: LeaderboardWindow {
        switch self {
        case .month:
            return .month
        case .week:
            return .week
        case .day:
            return .today
        }
    }
}

public struct UsageStatsSummary: Codable, Equatable, Sendable {
    public var range: StatsRange
    public var periodLabel: String
    public var dateRangeLabel: String
    public var totalDuration: TimeInterval
    public var dailyAverageDuration: TimeInterval
    public var pickupTotal: Int?
    public var hasScreenTimeData: Bool

    public init(
        range: StatsRange,
        periodLabel: String,
        dateRangeLabel: String,
        totalDuration: TimeInterval,
        dailyAverageDuration: TimeInterval,
        pickupTotal: Int?,
        hasScreenTimeData: Bool
    ) {
        self.range = range
        self.periodLabel = periodLabel
        self.dateRangeLabel = dateRangeLabel
        self.totalDuration = totalDuration
        self.dailyAverageDuration = dailyAverageDuration
        self.pickupTotal = pickupTotal
        self.hasScreenTimeData = hasScreenTimeData
    }
}

public struct UsageChartBucket: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var date: Date
    public var start: Date
    public var end: Date
    public var duration: TimeInterval

    public init(
        id: String,
        label: String,
        date: Date,
        start: Date,
        end: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.label = label
        self.date = date
        self.start = start
        self.end = end
        self.duration = duration
    }
}

public enum HomeROIBaselineStatus: Equatable, Sendable {
    case unavailable
    case building(daysCollected: Int, requiredDays: Int)
    case ready(days: Int)
}

public struct HomeTopImprovement: Equatable, Sendable {
    public var title: String
    public var savedDuration: TimeInterval
    public var percentChange: Double?

    public init(
        title: String,
        savedDuration: TimeInterval,
        percentChange: Double?
    ) {
        self.title = title
        self.savedDuration = savedDuration
        self.percentChange = percentChange
    }
}

public struct HomeEngagementSummary: Equatable, Sendable {
    public var baselineStatus: HomeROIBaselineStatus
    public var baselineDailyAverage: TimeInterval?
    public var netSavedDuration: TimeInterval
    public var screenTimePercentChange: Double?
    public var pickupPercentChange: Double?
    public var beatBaselineStreakDays: Int
    public var comparisonDayCount: Int
    public var isTodayBelowBaseline: Bool?
    public var topImprovement: HomeTopImprovement?

    public init(
        baselineStatus: HomeROIBaselineStatus,
        baselineDailyAverage: TimeInterval?,
        netSavedDuration: TimeInterval,
        screenTimePercentChange: Double?,
        pickupPercentChange: Double?,
        beatBaselineStreakDays: Int,
        comparisonDayCount: Int,
        isTodayBelowBaseline: Bool?,
        topImprovement: HomeTopImprovement?
    ) {
        self.baselineStatus = baselineStatus
        self.baselineDailyAverage = baselineDailyAverage
        self.netSavedDuration = netSavedDuration
        self.screenTimePercentChange = screenTimePercentChange
        self.pickupPercentChange = pickupPercentChange
        self.beatBaselineStreakDays = beatBaselineStreakDays
        self.comparisonDayCount = comparisonDayCount
        self.isTodayBelowBaseline = isTodayBelowBaseline
        self.topImprovement = topImprovement
    }
}

public struct UsageHistoryPayload: Codable, Equatable, Sendable {
    public var snapshots: [DailyUsageSnapshot]
    public var hourlyDurationsByDayID: [String: [TimeInterval]]

    public init(
        snapshots: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]] = [:]
    ) {
        self.snapshots = snapshots
        self.hourlyDurationsByDayID = hourlyDurationsByDayID
    }

    private enum CodingKeys: String, CodingKey {
        case snapshots
        case hourlyDurationsByDayID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshots = try container.decodeIfPresent([DailyUsageSnapshot].self, forKey: .snapshots) ?? []
        hourlyDurationsByDayID = try container.decodeIfPresent([String: [TimeInterval]].self, forKey: .hourlyDurationsByDayID) ?? [:]
    }
}

public enum HomeEngagementBuilder {
    public static let requiredBaselineDays = 7
    public static let streakImprovementThreshold = 0.10

    public static func summary(
        history: [DailyUsageSnapshot],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> HomeEngagementSummary {
        let snapshots = uniqueDailySnapshots(from: history, calendar: calendar)
        let usableSnapshots = snapshots.filter { $0.totalDuration != nil }

        guard !usableSnapshots.isEmpty else {
            return HomeEngagementSummary(
                baselineStatus: .unavailable,
                baselineDailyAverage: nil,
                netSavedDuration: 0,
                screenTimePercentChange: nil,
                pickupPercentChange: nil,
                beatBaselineStreakDays: 0,
                comparisonDayCount: 0,
                isTodayBelowBaseline: nil,
                topImprovement: nil
            )
        }

        guard usableSnapshots.count >= requiredBaselineDays else {
            return HomeEngagementSummary(
                baselineStatus: .building(daysCollected: usableSnapshots.count, requiredDays: requiredBaselineDays),
                baselineDailyAverage: nil,
                netSavedDuration: 0,
                screenTimePercentChange: nil,
                pickupPercentChange: nil,
                beatBaselineStreakDays: 0,
                comparisonDayCount: 0,
                isTodayBelowBaseline: nil,
                topImprovement: nil
            )
        }

        let baselineSnapshots = Array(usableSnapshots.prefix(requiredBaselineDays))
        let comparisonSnapshots = Array(usableSnapshots.dropFirst(requiredBaselineDays))
        let baselineTotal = baselineSnapshots.reduce(TimeInterval(0)) { partial, snapshot in
            partial + max(0, snapshot.totalDuration ?? 0)
        }
        let baselineAverage = baselineTotal / TimeInterval(requiredBaselineDays)
        let comparisonTotal = comparisonSnapshots.reduce(TimeInterval(0)) { partial, snapshot in
            partial + max(0, snapshot.totalDuration ?? 0)
        }
        let expectedComparisonTotal = baselineAverage * TimeInterval(comparisonSnapshots.count)
        let netSavedDuration = expectedComparisonTotal - comparisonTotal
        let screenTimePercentChange = percentChange(saved: netSavedDuration, expected: expectedComparisonTotal)

        return HomeEngagementSummary(
            baselineStatus: .ready(days: requiredBaselineDays),
            baselineDailyAverage: baselineAverage,
            netSavedDuration: netSavedDuration,
            screenTimePercentChange: screenTimePercentChange,
            pickupPercentChange: pickupPercentChange(
                baselineSnapshots: baselineSnapshots,
                comparisonSnapshots: comparisonSnapshots
            ),
            beatBaselineStreakDays: beatBaselineStreakDays(
                comparisonSnapshots: comparisonSnapshots,
                baselineAverage: baselineAverage,
                calendar: calendar,
                now: now
            ),
            comparisonDayCount: comparisonSnapshots.count,
            isTodayBelowBaseline: todayBelowBaseline(
                comparisonSnapshots: comparisonSnapshots,
                baselineAverage: baselineAverage,
                calendar: calendar,
                now: now
            ),
            topImprovement: topImprovement(
                baselineSnapshots: baselineSnapshots,
                comparisonSnapshots: comparisonSnapshots
            )
        )
    }

    private static func uniqueDailySnapshots(
        from history: [DailyUsageSnapshot],
        calendar: Calendar
    ) -> [DailyUsageSnapshot] {
        let grouped = Dictionary(
            grouping: history,
            by: { UsageDateBoundary.localDayKey(date: $0.date, calendar: calendar) }
        ).compactMapValues { snapshots in
            snapshots.sorted { $0.lastUpdated > $1.lastUpdated }.first
        }

        return grouped.values.sorted { lhs, rhs in
            calendar.startOfDay(for: lhs.date) < calendar.startOfDay(for: rhs.date)
        }
    }

    private static func percentChange(saved: TimeInterval, expected: TimeInterval) -> Double? {
        guard expected > 0 else {
            return nil
        }

        return (saved / expected) * 100
    }

    private static func pickupPercentChange(
        baselineSnapshots: [DailyUsageSnapshot],
        comparisonSnapshots: [DailyUsageSnapshot]
    ) -> Double? {
        let baselinePickups = baselineSnapshots.compactMap(\.pickupCount)
        let comparisonPickups = comparisonSnapshots.compactMap(\.pickupCount)
        guard !baselinePickups.isEmpty, !comparisonPickups.isEmpty else {
            return nil
        }

        let baselineAverage = Double(baselinePickups.reduce(0, +)) / Double(baselinePickups.count)
        let expectedPickups = baselineAverage * Double(comparisonPickups.count)
        guard expectedPickups > 0 else {
            return nil
        }

        let actualPickups = Double(comparisonPickups.reduce(0, +))
        return ((expectedPickups - actualPickups) / expectedPickups) * 100
    }

    private static func beatBaselineStreakDays(
        comparisonSnapshots: [DailyUsageSnapshot],
        baselineAverage: TimeInterval,
        calendar: Calendar,
        now: Date
    ) -> Int {
        guard baselineAverage > 0 else {
            return 0
        }

        let snapshotsByDay = Dictionary(
            uniqueKeysWithValues: comparisonSnapshots.map {
                (UsageDateBoundary.localDayKey(date: $0.date, calendar: calendar), $0)
            }
        )
        var streak = 0
        var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))

        while let date = cursor {
            let key = UsageDateBoundary.localDayKey(date: date, calendar: calendar)
            guard let snapshot = snapshotsByDay[key],
                  let duration = snapshot.totalDuration,
                  duration <= baselineAverage * (1 - streakImprovementThreshold) else {
                break
            }

            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: date)
        }

        return streak
    }

    private static func todayBelowBaseline(
        comparisonSnapshots: [DailyUsageSnapshot],
        baselineAverage: TimeInterval,
        calendar: Calendar,
        now: Date
    ) -> Bool? {
        guard baselineAverage > 0 else {
            return nil
        }

        let todayKey = UsageDateBoundary.localDayKey(date: now, calendar: calendar)
        guard let today = comparisonSnapshots.first(where: {
            UsageDateBoundary.localDayKey(date: $0.date, calendar: calendar) == todayKey
        }), let duration = today.totalDuration else {
            return nil
        }

        return duration <= baselineAverage * (1 - streakImprovementThreshold)
    }

    private static func topImprovement(
        baselineSnapshots: [DailyUsageSnapshot],
        comparisonSnapshots: [DailyUsageSnapshot]
    ) -> HomeTopImprovement? {
        guard !comparisonSnapshots.isEmpty else {
            return nil
        }

        if let appImprovement = topAppImprovement(
            baselineSnapshots: baselineSnapshots,
            comparisonSnapshots: comparisonSnapshots
        ) {
            return appImprovement
        }

        return selectedAppImprovement(
            baselineSnapshots: baselineSnapshots,
            comparisonSnapshots: comparisonSnapshots
        )
    }

    private static func topAppImprovement(
        baselineSnapshots: [DailyUsageSnapshot],
        comparisonSnapshots: [DailyUsageSnapshot]
    ) -> HomeTopImprovement? {
        let baselineTotals = appTotals(in: baselineSnapshots)
        let comparisonTotals = appTotals(in: comparisonSnapshots)
        guard !baselineTotals.isEmpty else {
            return nil
        }

        let improvements: [HomeTopImprovement] = baselineTotals.compactMap { id, baseline in
            let expected = baseline.duration / TimeInterval(requiredBaselineDays) * TimeInterval(comparisonSnapshots.count)
            let actual = comparisonTotals[id]?.duration ?? 0
            let saved = expected - actual
            guard saved > 0 else {
                return nil
            }

            return HomeTopImprovement(
                title: "\(baseline.displayName) down",
                savedDuration: saved,
                percentChange: percentChange(saved: saved, expected: expected)
            )
        }

        return improvements.sorted { lhs, rhs in
            if lhs.savedDuration != rhs.savedDuration {
                return lhs.savedDuration > rhs.savedDuration
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        .first
    }

    private static func selectedAppImprovement(
        baselineSnapshots: [DailyUsageSnapshot],
        comparisonSnapshots: [DailyUsageSnapshot]
    ) -> HomeTopImprovement? {
        let baselineDurations = baselineSnapshots.compactMap(\.selectedAppDuration)
        let comparisonDurations = comparisonSnapshots.compactMap(\.selectedAppDuration)
        guard !baselineDurations.isEmpty, !comparisonDurations.isEmpty else {
            return nil
        }

        let baselineAverage = baselineDurations.reduce(0, +) / TimeInterval(baselineDurations.count)
        let expected = baselineAverage * TimeInterval(comparisonDurations.count)
        let actual = comparisonDurations.reduce(0, +)
        let saved = expected - actual
        guard saved > 0 else {
            return nil
        }

        return HomeTopImprovement(
            title: "Selected apps down",
            savedDuration: saved,
            percentChange: percentChange(saved: saved, expected: expected)
        )
    }

    private static func appTotals(in snapshots: [DailyUsageSnapshot]) -> [String: (displayName: String, duration: TimeInterval)] {
        snapshots.reduce(into: [:]) { totals, snapshot in
            for row in snapshot.appRows {
                let key = row.bundleIdentifier ?? row.id
                let existing = totals[key]
                totals[key] = (
                    displayName: existing?.displayName ?? row.displayName,
                    duration: (existing?.duration ?? 0) + max(0, row.duration)
                )
            }
        }
    }
}

public enum UsageHistoryCodec {
    public static let storageKey = "LocalUsageHistory.v1"

    public static func encode(_ payload: UsageHistoryPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func decode(_ data: Data) throws -> UsageHistoryPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UsageHistoryPayload.self, from: data)
    }

    public static func upserting(
        _ snapshot: DailyUsageSnapshot,
        into snapshots: [DailyUsageSnapshot],
        calendar: Calendar = .current,
        maxStoredDays: Int = 62
    ) -> [DailyUsageSnapshot] {
        let replacementDayKey = UsageDateBoundary.localDayKey(date: snapshot.date, calendar: calendar)
        let filtered = snapshots.filter { existing in
            existing.ownerProfileID != snapshot.ownerProfileID
                || UsageDateBoundary.localDayKey(date: existing.date, calendar: calendar) != replacementDayKey
        }
        let updated = filtered + [snapshot]
        return Array(
            updated
                .sorted { $0.date > $1.date }
                .prefix(maxStoredDays)
        )
    }
}

public enum UsageStatsBuilder {
    public static func summary(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> UsageStatsSummary {
        let interval = periodInterval(for: range, containing: selectedDate, calendar: calendar)
        let snapshots = snapshots(in: interval, history: history, calendar: calendar)
        let totalDuration = snapshots.reduce(0) { partial, snapshot in
            partial + max(0, snapshot.totalDuration ?? 0)
        }
        let pickupValues = snapshots.compactMap(\.pickupCount)
        let pickupTotal = pickupValues.isEmpty ? nil : pickupValues.reduce(0, +)
        let averageDays = max(1, elapsedDayCount(in: interval, now: now, calendar: calendar))
        let hasData = snapshots.contains { ($0.totalDuration ?? 0) > 0 }

        return UsageStatsSummary(
            range: range,
            periodLabel: periodLabel(for: range, selectedDate: selectedDate, interval: interval, now: now, calendar: calendar),
            dateRangeLabel: dateRangeLabel(for: interval, range: range, selectedDate: selectedDate, now: now, calendar: calendar),
            totalDuration: totalDuration,
            dailyAverageDuration: totalDuration / TimeInterval(averageDays),
            pickupTotal: pickupTotal,
            hasScreenTimeData: hasData
        )
    }

    public static func chartBuckets(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]] = [:],
        calendar: Calendar = .current
    ) -> [UsageChartBucket] {
        let interval = periodInterval(for: range, containing: selectedDate, calendar: calendar)
        switch range {
        case .month, .week:
            return dailyBuckets(
                in: interval,
                range: range,
                history: history,
                calendar: calendar
            )
        case .day:
            return hourlyBuckets(
                in: interval,
                history: history,
                hourlyDurationsByDayID: hourlyDurationsByDayID,
                calendar: calendar
            )
        }
    }

    public static func appUsageRows(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        calendar: Calendar = .current
    ) -> [SharedAppUsage] {
        let interval = periodInterval(for: range, containing: selectedDate, calendar: calendar)
        let snapshots = snapshots(in: interval, history: history, calendar: calendar)
        var totals: [String: SharedAppUsage] = [:]

        for snapshot in snapshots {
            for row in snapshot.appRows {
                let key = row.bundleIdentifier ?? row.id
                let existing = totals[key]
                totals[key] = SharedAppUsage(
                    id: key,
                    displayName: existing?.displayName ?? row.displayName,
                    bundleIdentifier: existing?.bundleIdentifier ?? row.bundleIdentifier,
                    duration: (existing?.duration ?? 0) + max(0, row.duration)
                )
            }
        }

        return totals.values.sorted { lhs, rhs in
            if lhs.duration != rhs.duration {
                return lhs.duration > rhs.duration
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    public static func periodInterval(
        for range: StatsRange,
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        switch range {
        case .month:
            return calendar.dateInterval(of: .month, for: date)
                ?? UsageDateBoundary.dayInterval(containing: date, calendar: calendar)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
                ?? UsageDateBoundary.dayInterval(containing: date, calendar: calendar)
        case .day:
            return UsageDateBoundary.dayInterval(containing: date, calendar: calendar)
        }
    }

    public static func canNavigateForward(
        range: StatsRange,
        selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard range != .day,
              let nextDate = date(byMoving: range, value: 1, from: selectedDate, calendar: calendar) else {
            return false
        }

        let nextInterval = periodInterval(for: range, containing: nextDate, calendar: calendar)
        let currentInterval = periodInterval(for: range, containing: now, calendar: calendar)
        return nextInterval.start <= currentInterval.start
    }

    public static func date(
        byMoving range: StatsRange,
        value: Int,
        from date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch range {
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: value, to: date)
        case .day:
            return calendar.date(byAdding: .day, value: value, to: date)
        }
    }

    public static func snapshot(
        for date: Date,
        in history: [DailyUsageSnapshot],
        calendar: Calendar = .current
    ) -> DailyUsageSnapshot? {
        let dayKey = UsageDateBoundary.localDayKey(date: date, calendar: calendar)
        return history.first {
            UsageDateBoundary.localDayKey(date: $0.date, calendar: calendar) == dayKey
        }
    }

    private static func snapshots(
        in interval: DateInterval,
        history: [DailyUsageSnapshot],
        calendar: Calendar
    ) -> [DailyUsageSnapshot] {
        history.filter { snapshot in
            interval.contains(calendar.startOfDay(for: snapshot.date))
        }
    }

    private static func dailyBuckets(
        in interval: DateInterval,
        range: StatsRange,
        history: [DailyUsageSnapshot],
        calendar: Calendar
    ) -> [UsageChartBucket] {
        let snapshotsByDay = Dictionary(
            grouping: snapshots(in: interval, history: history, calendar: calendar),
            by: { UsageDateBoundary.localDayKey(date: $0.date, calendar: calendar) }
        ).compactMapValues { grouped in
            grouped.sorted { $0.lastUpdated > $1.lastUpdated }.first
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = range == .week ? "EEE" : "d"

        var buckets: [UsageChartBucket] = []
        var cursor = interval.start
        while cursor < interval.end {
            let dayInterval = UsageDateBoundary.dayInterval(containing: cursor, calendar: calendar)
            let key = UsageDateBoundary.localDayKey(date: cursor, calendar: calendar)
            let duration = max(0, snapshotsByDay[key]?.totalDuration ?? 0)
            buckets.append(
                UsageChartBucket(
                    id: key,
                    label: formatter.string(from: cursor),
                    date: cursor,
                    start: dayInterval.start,
                    end: dayInterval.end,
                    duration: duration
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return buckets
    }

    private static func hourlyBuckets(
        in interval: DateInterval,
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]],
        calendar: Calendar
    ) -> [UsageChartBucket] {
        let key = UsageDateBoundary.localDayKey(date: interval.start, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "ha"

        if let hourlyDurations = hourlyDurationsByDayID[key], !hourlyDurations.isEmpty {
            return (0..<24).compactMap { hour in
                guard let start = calendar.date(byAdding: .hour, value: hour, to: interval.start),
                      let end = calendar.date(byAdding: .hour, value: 1, to: start) else {
                    return nil
                }

                return UsageChartBucket(
                    id: "\(key)-\(hour)",
                    label: formatter.string(from: start),
                    date: start,
                    start: start,
                    end: end,
                    duration: max(0, hourlyDurations.indices.contains(hour) ? hourlyDurations[hour] : 0)
                )
            }
        }

        if let snapshot = snapshot(for: interval.start, in: history, calendar: calendar),
           let totalDuration = snapshot.totalDuration,
           totalDuration > 0 {
            return [
                UsageChartBucket(
                    id: "\(key)-total",
                    label: "Total",
                    date: interval.start,
                    start: interval.start,
                    end: interval.end,
                    duration: totalDuration
                )
            ]
        }

        return (0..<24).compactMap { hour in
            guard let start = calendar.date(byAdding: .hour, value: hour, to: interval.start),
                  let end = calendar.date(byAdding: .hour, value: 1, to: start) else {
                return nil
            }

            return UsageChartBucket(
                id: "\(key)-\(hour)",
                label: formatter.string(from: start),
                date: start,
                start: start,
                end: end,
                duration: 0
            )
        }
    }

    private static func elapsedDayCount(
        in interval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let clampedEnd = min(interval.end, UsageDateBoundary.dayInterval(containing: now, calendar: calendar).end)
        let components = calendar.dateComponents([.day], from: interval.start, to: clampedEnd)
        return max(1, components.day ?? 1)
    }

    private static func periodLabel(
        for range: StatsRange,
        selectedDate: Date,
        interval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> String {
        let currentInterval = periodInterval(for: range, containing: now, calendar: calendar)
        if interval.start == currentInterval.start {
            switch range {
            case .month:
                return "This Month"
            case .week:
                return "This Week"
            case .day:
                return "Today"
            }
        }

        switch range {
        case .month:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: selectedDate)
        case .week:
            return dateRangeLabel(for: interval, range: range, selectedDate: selectedDate, now: now, calendar: calendar)
        case .day:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEEE"
            return formatter.string(from: selectedDate)
        }
    }

    private static func dateRangeLabel(
        for interval: DateInterval,
        range: StatsRange,
        selectedDate: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        if range == .day {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMMM d"
            let dayText = formatter.string(from: selectedDate)
            return calendar.isDate(selectedDate, inSameDayAs: now) ? "Today, \(dayText)" : dayText
        }

        guard let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            return ""
        }

        let startComponents = calendar.dateComponents([.month, .year], from: interval.start)
        let endComponents = calendar.dateComponents([.month, .year], from: lastDay)
        let yearFormatter = DateFormatter()
        yearFormatter.calendar = calendar
        yearFormatter.timeZone = calendar.timeZone
        yearFormatter.dateFormat = "yyyy"

        if startComponents.month == endComponents.month,
           startComponents.year == endComponents.year {
            let monthFormatter = DateFormatter()
            monthFormatter.calendar = calendar
            monthFormatter.timeZone = calendar.timeZone
            monthFormatter.dateFormat = "MMMM"

            let dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = calendar.timeZone
            dayFormatter.dateFormat = "d"

            return "\(monthFormatter.string(from: interval.start)) \(dayFormatter.string(from: interval.start))-\(dayFormatter.string(from: lastDay)), \(yearFormatter.string(from: lastDay))"
        }

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = calendar
        shortFormatter.timeZone = calendar.timeZone
        shortFormatter.dateFormat = "MMM d"
        return "\(shortFormatter.string(from: interval.start))-\(shortFormatter.string(from: lastDay)), \(yearFormatter.string(from: lastDay))"
    }
}
