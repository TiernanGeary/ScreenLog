import DeviceActivity
import FamilyControls
import SwiftUI
import _DeviceActivity_SwiftUI

struct ScreenTimeReportBridgeView: View {
    @EnvironmentObject private var model: AppModel
    let selection: FamilyActivitySelection

    private var canLoadReport: Bool {
        model.hasScreenTimeAuthorization
    }

    var body: some View {
        Group {
            if canLoadReport {
                DeviceActivityReport(.screenLogUsageSnapshot, filter: reportFilter)
                    .id(model.screenTimeReportRefreshID)
                    .frame(maxWidth: .infinity)
                    .frame(height: 8)
                    .clipped()
                    .accessibilityHidden(true)
                    .task(id: model.screenTimeReportRefreshID) {
                        await pollForReportSnapshot()
                    }
            } else {
                Color.clear
                    .frame(height: 1)
            }
        }
    }

    private var reportFilter: DeviceActivityFilter {
        DeviceActivityFilter.screenLog(
            segment: .hourly(during: UsageDateBoundary.dayInterval(containing: Date())),
            selection: selection
        )
    }

    private func pollForReportSnapshot() async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
        }

        model.refreshScreenTimeReportStatus()
    }
}

struct ScreenTimeLiveTodayReport: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.hasScreenTimeAuthorization {
            ZStack {
                ScreenTimeReportLoadingView(
                    title: "Preparing today's report",
                    message: "Screen Time data usually appears in a moment."
                )

                DeviceActivityReport(
                    .screenLogTodaySummary,
                    filter: .screenLogAllActivity(
                        segment: .hourly(during: UsageDateBoundary.dayInterval(containing: Date()))
                    )
                )
                .id(model.screenTimeReportRefreshID)
                .accessibilityLabel("Live Screen Time today report")
                .task(id: model.screenTimeReportRefreshID) {
                    await pollForReportSnapshot()
                }
            }
        }
    }

    private func pollForReportSnapshot() async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
        }

        model.refreshScreenTimeReportStatus()
    }
}

struct ScreenTimeLiveStatsReport: View {
    @EnvironmentObject private var model: AppModel
    let range: StatsRange
    let selectedDate: Date

    var body: some View {
        if model.hasScreenTimeAuthorization {
            ZStack {
                ScreenTimeReportLoadingView(
                    title: loadingTitle,
                    message: loadingMessage
                )

                DeviceActivityReport(
                    reportContext,
                    filter: .screenLogAllActivity(
                        segment: segmentInterval
                    )
                )
                .id(reportIdentity)
                .accessibilityLabel("Live Screen Time stats report")
                .task(id: reportIdentity) {
                    await pollForReportSnapshot()
                }
            }
        }
    }

    private var reportIdentity: String {
        let start = UsageStatsBuilder.periodInterval(for: range, containing: selectedDate).start
        return "\(range.id)-\(start.timeIntervalSinceReferenceDate)"
    }

    private var segmentInterval: DeviceActivityFilter.SegmentInterval {
        let interval = reportInterval
        switch range {
        case .day:
            return shouldUseHourlyDaySegments ? .hourly(during: interval) : .daily(during: interval)
        case .week, .month:
            return .daily(during: interval)
        }
    }

    private var shouldUseHourlyDaySegments: Bool {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let today = calendar.startOfDay(for: Date())
        guard let hourlyCutoff = calendar.date(byAdding: .day, value: -3, to: today) else {
            return true
        }

        return selectedDay >= hourlyCutoff
    }

    private var reportInterval: DateInterval {
        let period = UsageStatsBuilder.periodInterval(for: range, containing: selectedDate)
        let end = min(Date(), period.end)
        guard end > period.start else {
            return period
        }

        return DateInterval(start: period.start, end: end)
    }

    private var reportContext: DeviceActivityReport.Context {
        switch range {
        case .day:
            return .screenLogStatsDay
        case .week:
            return .screenLogStatsWeek
        case .month:
            return .screenLogStatsMonth
        }
    }

    private var loadingTitle: String {
        switch range {
        case .day:
            return "Preparing day report"
        case .week:
            return "Preparing week report"
        case .month:
            return "Preparing month report"
        }
    }

    private var loadingMessage: String {
        switch range {
        case .day:
            return "Screen Time data usually appears in a moment."
        case .week:
            return "Weekly reports can take a few extra seconds."
        case .month:
            return "Monthly reports scan more days, so they can take a bit longer."
        }
    }

    private func pollForReportSnapshot() async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
        }

        model.refreshScreenTimeReportStatus()
    }
}

private struct ScreenTimeReportLoadingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

private extension DeviceActivityFilter {
    static func screenLogAllActivity(
        segment: DeviceActivityFilter.SegmentInterval
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(segment: segment)
    }

    static func screenLog(
        segment: DeviceActivityFilter.SegmentInterval,
        selection: FamilyActivitySelection
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: segment,
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
    }
}
