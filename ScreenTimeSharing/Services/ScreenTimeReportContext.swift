import DeviceActivity
import _DeviceActivity_SwiftUI

extension DeviceActivityReport.Context {
    static let screenLogUsageSnapshot = Self("ScreenLogUsageSnapshot")
    static let screenLogTodaySummary = Self("ScreenLogTodaySummary")
    static let screenLogStatsDay = Self("ScreenLogStatsDay")
    static let screenLogStatsWeek = Self("ScreenLogStatsWeek")
    static let screenLogStatsMonth = Self("ScreenLogStatsMonth")
    // Per-group pool usage measurement slots (must match the report extension's
    // ScreenLogUsageReport.swift context strings exactly).
    static let screenLogGroupUsage0 = Self("ScreenLogGroupUsage0")
    static let screenLogGroupUsage1 = Self("ScreenLogGroupUsage1")
    static let screenLogGroupUsage2 = Self("ScreenLogGroupUsage2")
    static let screenLogGroupUsage3 = Self("ScreenLogGroupUsage3")
    static let screenLogGroupUsage4 = Self("ScreenLogGroupUsage4")
}
