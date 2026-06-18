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
    @State private var isShowingLoading = false

    var body: some View {
        if model.hasScreenTimeAuthorization {
            ZStack {
                DeviceActivityReport(
                    .screenLogTodaySummary,
                    filter: .screenLogAllActivity(
                        segment: .hourly(during: UsageDateBoundary.dayInterval(containing: Date()))
                    )
                )
                .id(model.screenTimeReportRefreshID)
                .accessibilityLabel("Live Screen Time today report")

                if isShowingLoading {
                    ScreenTimeReportLoadingOverlay(
                        title: "Loading today's report",
                        message: "Screen Time data usually appears in a moment."
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isShowingLoading)
            .task(id: model.screenTimeReportRefreshID) {
                await pollForReportSnapshot(maxLoadingDuration: 3)
            }
        }
    }

    private var hasCachedTodayReport: Bool {
        guard let snapshot = model.localSnapshot,
              Calendar.current.isDateInToday(snapshot.date) else {
            return false
        }

        return snapshot.totalDuration != nil
            || snapshot.pickupCount != nil
            || !snapshot.appRows.isEmpty
    }

    private func pollForReportSnapshot(maxLoadingDuration: TimeInterval) async {
        let startedAt = Date()
        isShowingLoading = !hasCachedTodayReport

        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
            if hasCachedTodayReport || Date().timeIntervalSince(startedAt) >= maxLoadingDuration {
                isShowingLoading = false
            }
        }

        isShowingLoading = false
        model.refreshScreenTimeReportStatus()
    }
}

struct ScreenTimeLiveStatsReport: View {
    @EnvironmentObject private var model: AppModel
    let range: StatsRange
    let selectedDate: Date
    @State private var isShowingLoading = false

    var body: some View {
        if model.hasScreenTimeAuthorization {
            ZStack {
                DeviceActivityReport(
                    reportContext,
                    filter: .screenLogAllActivity(
                        segment: segmentInterval
                    )
                )
                .id(reportIdentity)
                .accessibilityLabel("Live Screen Time stats report")

                if isShowingLoading {
                    ScreenTimeReportLoadingOverlay(
                        title: loadingTitle,
                        message: loadingMessage
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isShowingLoading)
            .task(id: reportIdentity) {
                await pollForReportSnapshot(maxLoadingDuration: maxLoadingDuration)
            }
        }
    }

    private var hasCachedReportData: Bool {
        UsageStatsBuilder.summary(
            range: range,
            selectedDate: selectedDate,
            history: model.usageHistory
        ).hasScreenTimeData
    }

    private var reportIdentity: String {
        // Identity is stable per (range, period) so navigating between dates and
        // back reuses an already-loaded report instead of tearing it down and
        // showing the loading state again. (Previously this also included
        // screenTimeReportRefreshID, which changed on every date switch and
        // forced a full reload each time.)
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
            return "Loading day report"
        case .week:
            return "Loading week report"
        case .month:
            return "Loading month report"
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

    private var maxLoadingDuration: TimeInterval {
        switch range {
        case .day:
            return 3
        case .week:
            return 5
        case .month:
            return 6
        }
    }

    private func pollForReportSnapshot(maxLoadingDuration: TimeInterval) async {
        let startedAt = Date()
        isShowingLoading = !hasCachedReportData

        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            _ = model.reloadUsageHistoryFromSharedStorage()
            if hasCachedReportData || Date().timeIntervalSince(startedAt) >= maxLoadingDuration {
                isShowingLoading = false
            }
        }

        isShowingLoading = false
        model.refreshScreenTimeReportStatus()
    }
}

private struct ScreenTimeReportLoadingOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
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
        .background(reportSurfaceColor)
        .accessibilityElement(children: .combine)
    }

    private var reportSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.085, blue: 0.10)
            : Color(uiColor: .systemBackground)
    }
}

private extension DeviceActivityFilter {
    static func screenLogAllActivity(
        segment: DeviceActivityFilter.SegmentInterval
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(segment: segment, devices: .screenLogCurrentDevice)
    }

    static func screenLog(
        segment: DeviceActivityFilter.SegmentInterval,
        selection: FamilyActivitySelection
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: segment,
            devices: .screenLogCurrentDevice,
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
    }
}

private extension DeviceActivityFilter.Devices {
    static var screenLogCurrentDevice: Self {
        // The app is iPhone-first, and using the iPhone model keeps the report
        // aligned with the iPhone Screen Time screen instead of cross-device data.
        Self([.iPhone])
    }
}
