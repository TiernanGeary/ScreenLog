import Foundation

/// Cheap, value-type change detector for usage history + hourly map.
/// Used as a memoization key and a stale-detection signal.
public struct UsageHistorySignature: Hashable, Sendable {
    public let snapshotCount: Int
    public let latestSnapshotUpdate: Date?
    public let totalDuration: TimeInterval
    public let hourlyDayCount: Int
    public let hourlyDuration: TimeInterval

    public init(
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]]
    ) {
        snapshotCount = history.count
        latestSnapshotUpdate = history.map(\.lastUpdated).max()
        totalDuration = history.reduce(TimeInterval(0)) { partial, snapshot in
            partial + max(0, snapshot.totalDuration ?? 0)
        }
        hourlyDayCount = hourlyDurationsByDayID.count
        hourlyDuration = hourlyDurationsByDayID.values.reduce(TimeInterval(0)) { partial, values in
            partial + values.reduce(TimeInterval(0)) { $0 + max(0, $1) }
        }
    }
}

/// In-memory memoization for the three pure usage-stats builders.
/// Recomputes only when (range, period start, history signature[, today]) changes.
/// Reference type so a single instance can be shared (e.g. held by AppModel).
public final class UsageStatsCache {
    public init() {}

    public private(set) var summaryComputeCount = 0
    public private(set) var bucketsComputeCount = 0
    public private(set) var appRowsComputeCount = 0

    private struct SummaryKey: Equatable {
        let range: StatsRange
        let periodStart: Date
        let signature: UsageHistorySignature
        let today: Date
    }

    private struct BucketsKey: Equatable {
        let range: StatsRange
        let periodStart: Date
        let signature: UsageHistorySignature
    }

    private struct RowsKey: Equatable {
        let range: StatsRange
        let periodStart: Date
        let signature: UsageHistorySignature
    }

    private var summaryKey: SummaryKey?
    private var summaryValue: UsageStatsSummary?
    private var bucketsKey: BucketsKey?
    private var bucketsValue: [UsageChartBucket]?
    private var rowsKey: RowsKey?
    private var rowsValue: [SharedAppUsage]?

    public func summary(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]] = [:],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> UsageStatsSummary {
        let key = SummaryKey(
            range: range,
            periodStart: UsageStatsBuilder.periodInterval(for: range, containing: selectedDate, calendar: calendar).start,
            signature: UsageHistorySignature(history: history, hourlyDurationsByDayID: hourlyDurationsByDayID),
            today: calendar.startOfDay(for: now)
        )
        if key == summaryKey, let summaryValue {
            return summaryValue
        }
        let value = UsageStatsBuilder.summary(
            range: range,
            selectedDate: selectedDate,
            history: history,
            calendar: calendar,
            now: now
        )
        summaryKey = key
        summaryValue = value
        summaryComputeCount += 1
        return value
    }

    public func chartBuckets(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        hourlyDurationsByDayID: [String: [TimeInterval]] = [:],
        calendar: Calendar = .current
    ) -> [UsageChartBucket] {
        let key = BucketsKey(
            range: range,
            periodStart: UsageStatsBuilder.periodInterval(for: range, containing: selectedDate, calendar: calendar).start,
            signature: UsageHistorySignature(history: history, hourlyDurationsByDayID: hourlyDurationsByDayID)
        )
        if key == bucketsKey, let bucketsValue {
            return bucketsValue
        }
        let value = UsageStatsBuilder.chartBuckets(
            range: range,
            selectedDate: selectedDate,
            history: history,
            hourlyDurationsByDayID: hourlyDurationsByDayID,
            calendar: calendar
        )
        bucketsKey = key
        bucketsValue = value
        bucketsComputeCount += 1
        return value
    }

    public func appUsageRows(
        range: StatsRange,
        selectedDate: Date,
        history: [DailyUsageSnapshot],
        calendar: Calendar = .current
    ) -> [SharedAppUsage] {
        let key = RowsKey(
            range: range,
            periodStart: UsageStatsBuilder.periodInterval(for: range, containing: selectedDate, calendar: calendar).start,
            signature: UsageHistorySignature(history: history, hourlyDurationsByDayID: [:])
        )
        if key == rowsKey, let rowsValue {
            return rowsValue
        }
        let value = UsageStatsBuilder.appUsageRows(
            range: range,
            selectedDate: selectedDate,
            history: history,
            calendar: calendar
        )
        rowsKey = key
        rowsValue = value
        appRowsComputeCount += 1
        return value
    }
}
