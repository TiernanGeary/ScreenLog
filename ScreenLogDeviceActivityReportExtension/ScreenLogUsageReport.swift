import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI
import UIKit

extension DeviceActivityReport.Context {
    static let screenLogUsageSnapshot = Self("ScreenLogUsageSnapshot")
    static let screenLogTodaySummary = Self("ScreenLogTodaySummary")
    static let screenLogStatsDay = Self("ScreenLogStatsDay")
    static let screenLogStatsWeek = Self("ScreenLogStatsWeek")
    static let screenLogStatsMonth = Self("ScreenLogStatsMonth")
    static let screenLogGroupUsage0 = Self("ScreenLogGroupUsage0")
    static let screenLogGroupUsage1 = Self("ScreenLogGroupUsage1")
    static let screenLogGroupUsage2 = Self("ScreenLogGroupUsage2")
    static let screenLogGroupUsage3 = Self("ScreenLogGroupUsage3")
    static let screenLogGroupUsage4 = Self("ScreenLogGroupUsage4")
}

struct ScreenLogTodaySummaryReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogTodaySummary
    let content: (ScreenTimeLiveReportConfiguration) -> ScreenLogTodaySummaryReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        await ScreenLogUsageReportBuilder.configuration(representing: data, persistsSnapshot: true)
    }
}

struct ScreenLogStatsDayReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogStatsDay
    let content: (ScreenTimeLiveReportConfiguration) -> ScreenLogStatsReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        await ScreenLogUsageReportBuilder.configuration(
            representing: data,
            bucketGranularity: .hourlyDay,
            persistsSnapshot: true
        )
    }
}

struct ScreenLogStatsWeekReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogStatsWeek
    let content: (ScreenTimeLiveReportConfiguration) -> ScreenLogStatsReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        await ScreenLogUsageReportBuilder.configuration(
            representing: data,
            bucketGranularity: .week,
            persistsSnapshot: true
        )
    }
}

struct ScreenLogStatsMonthReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogStatsMonth
    let content: (ScreenTimeLiveReportConfiguration) -> ScreenLogStatsReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        await ScreenLogUsageReportBuilder.configuration(
            representing: data,
            bucketGranularity: .month,
            persistsSnapshot: true
        )
    }
}

struct ScreenLogUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogUsageSnapshot
    let content: (ScreenTimeLiveReportConfiguration) -> ScreenLogUsageReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        await ScreenLogUsageReportBuilder.configuration(representing: data)
    }
}

struct GroupUsageHiddenReportView: View {
    var body: some View {
        Color.clear
    }
}

struct ScreenLogGroupUsageReport0: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogGroupUsage0
    let content: (ScreenTimeLiveReportConfiguration) -> GroupUsageHiddenReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        let config = await ScreenLogUsageReportBuilder.configuration(representing: data, persistsSnapshot: false)
        ScreenLogGroupUsageReportWriter.persist(slot: 0, seconds: Int(config.totalDuration))
        return config
    }
}

struct ScreenLogGroupUsageReport1: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogGroupUsage1
    let content: (ScreenTimeLiveReportConfiguration) -> GroupUsageHiddenReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        let config = await ScreenLogUsageReportBuilder.configuration(representing: data, persistsSnapshot: false)
        ScreenLogGroupUsageReportWriter.persist(slot: 1, seconds: Int(config.totalDuration))
        return config
    }
}

struct ScreenLogGroupUsageReport2: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogGroupUsage2
    let content: (ScreenTimeLiveReportConfiguration) -> GroupUsageHiddenReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        let config = await ScreenLogUsageReportBuilder.configuration(representing: data, persistsSnapshot: false)
        ScreenLogGroupUsageReportWriter.persist(slot: 2, seconds: Int(config.totalDuration))
        return config
    }
}

struct ScreenLogGroupUsageReport3: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogGroupUsage3
    let content: (ScreenTimeLiveReportConfiguration) -> GroupUsageHiddenReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        let config = await ScreenLogUsageReportBuilder.configuration(representing: data, persistsSnapshot: false)
        ScreenLogGroupUsageReportWriter.persist(slot: 3, seconds: Int(config.totalDuration))
        return config
    }
}

struct ScreenLogGroupUsageReport4: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .screenLogGroupUsage4
    let content: (ScreenTimeLiveReportConfiguration) -> GroupUsageHiddenReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeLiveReportConfiguration {
        let config = await ScreenLogUsageReportBuilder.configuration(representing: data, persistsSnapshot: false)
        ScreenLogGroupUsageReportWriter.persist(slot: 4, seconds: Int(config.totalDuration))
        return config
    }
}

private enum ScreenLogGroupUsageReportWriter {
    static func persist(slot: Int, seconds: Int) {
        let defaults = UserDefaults(suiteName: ScreenTimeReportStorage.appGroupSuiteName)
        guard let groupBlockID = ScreenTimeReportStorage.poolSlotAssignment(slot, defaults: defaults) else {
            return
        }

        ScreenTimeReportStorage.setGroupUsageSlot(
            slot,
            groupBlockID: groupBlockID,
            dayKey: UsageDateBoundary.localDayKey(date: Date(), calendar: .current),
            seconds: seconds,
            defaults: defaults
        )
    }
}

enum ScreenLogUsageReportBuilder {
    static func configuration(
        representing data: DeviceActivityResults<DeviceActivityData>,
        calendar: Calendar = .current,
        bucketGranularity: ScreenTimeLiveReportBucketGranularity = .segment,
        persistsSnapshot: Bool = false,
        defaults: UserDefaults? = UserDefaults(suiteName: ScreenTimeReportStorage.appGroupSuiteName)
    ) async -> ScreenTimeLiveReportConfiguration {
        var segments: [ScreenTimeReportSegmentInput] = []

        for await deviceData in data {
            for await segment in deviceData.activitySegments {
                var segmentRows: [SharedAppUsage] = []
                var pickupCount = max(0, segment.totalPickupsWithoutApplicationActivity)

                for await category in segment.categories {
                    for await application in category.applications {
                        pickupCount += max(0, application.numberOfPickups)
                        let key = application.application.bundleIdentifier
                            ?? application.application.localizedDisplayName
                            ?? "unknown-app"
                        let displayName = application.application.localizedDisplayName
                            ?? application.application.bundleIdentifier
                            ?? "App"
                        segmentRows.append(
                            SharedAppUsage(
                                id: key,
                                displayName: displayName,
                                bundleIdentifier: application.application.bundleIdentifier,
                                applicationTokenData: encodedTokenData(application.application.token),
                                duration: max(0, application.totalActivityDuration)
                            )
                        )
                    }

                    for await webDomain in category.webDomains {
                        let trimmedDomain = webDomain.webDomain.domain?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let domain = trimmedDomain?.isEmpty == false ? trimmedDomain! : "Website"
                        segmentRows.append(
                            SharedAppUsage(
                                id: SharedAppUsage.webDomainID(for: domain),
                                displayName: domain,
                                bundleIdentifier: nil,
                                duration: max(0, webDomain.totalActivityDuration)
                            )
                        )
                    }
                }

                segments.append(
                    ScreenTimeReportSegmentInput(
                        dateInterval: segment.dateInterval,
                        totalActivityDuration: segment.totalActivityDuration,
                        pickupCount: pickupCount,
                        appRows: segmentRows
                    )
                )
            }
        }

        let generatedAt = Date()
        let configuration = ScreenTimeLiveReportBuilder.configuration(
            segments: segments,
            generatedAt: generatedAt,
            calendar: calendar,
            bucketGranularity: bucketGranularity
        )

        if persistsSnapshot {
            persistDailySnapshots(
                segments: segments,
                configuration: configuration,
                generatedAt: generatedAt,
                calendar: calendar,
                defaults: defaults
            )
        }

        return configuration
    }

    private static func persistDailySnapshots(
        segments: [ScreenTimeReportSegmentInput],
        configuration: ScreenTimeLiveReportConfiguration,
        generatedAt: Date,
        calendar: Calendar,
        defaults: UserDefaults?
    ) {
        guard let defaults,
              let profileID = ScreenTimeReportStorage.loadProfileID(defaults: defaults) else {
            return
        }

        let groupedSegments = Dictionary(grouping: segments) { segment in
            UsageDateBoundary.localDayKey(date: segment.dateInterval.start, calendar: calendar)
        }
        guard !groupedSegments.isEmpty else {
            ScreenTimeReportStorage.saveSummary(summaryText(for: configuration), defaults: defaults)
            defaults.synchronize()
            return
        }

        do {
            for dailySegments in groupedSegments.values {
                guard let firstSegment = dailySegments.min(by: { $0.dateInterval.start < $1.dateInterval.start }) else {
                    continue
                }

                let dayInterval = UsageDateBoundary.dayInterval(containing: firstSegment.dateInterval.start, calendar: calendar)
                let dailyConfiguration = ScreenTimeLiveReportBuilder.configuration(
                    segments: dailySegments,
                    generatedAt: generatedAt,
                    calendar: calendar,
                    bucketGranularity: .segment
                )
                let snapshot = DailyUsageSnapshot(
                    id: UsageDateBoundary.snapshotID(profileID: profileID, date: dayInterval.start, calendar: calendar),
                    ownerProfileID: profileID,
                    date: dayInterval.start,
                    calendarIdentifier: String(describing: calendar.identifier),
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    totalDuration: dailyConfiguration.totalDuration,
                    selectedAppDuration: dailyConfiguration.totalDuration,
                    pickupCount: dailyConfiguration.pickupCount,
                    appRows: dailyConfiguration.appRows,
                    lastUpdated: generatedAt,
                    capability: .fullAppDetail
                )

                try ScreenTimeReportStorage.upsert(
                    snapshot: snapshot,
                    hourlyDurations: hourlyDurations(from: dailySegments, calendar: calendar),
                    defaults: defaults,
                    calendar: calendar
                )
            }
            ScreenTimeReportStorage.saveSummary(summaryText(for: configuration), defaults: defaults)
            defaults.synchronize()
        } catch {
            ScreenTimeReportStorage.markFailed(error.localizedDescription, defaults: defaults)
        }
    }

    private static func hourlyDurations(
        from segments: [ScreenTimeReportSegmentInput],
        calendar: Calendar
    ) -> [TimeInterval]? {
        guard !segments.isEmpty,
              segments.allSatisfy({ $0.dateInterval.duration <= 3_700 }) else {
            return nil
        }

        var durations = Array(repeating: TimeInterval(0), count: 24)
        for segment in segments {
            let hour = calendar.component(.hour, from: segment.dateInterval.start)
            guard durations.indices.contains(hour) else {
                continue
            }
            durations[hour] += max(0, segment.totalActivityDuration)
        }
        return durations
    }

    private static func summaryText(for configuration: ScreenTimeLiveReportConfiguration) -> String {
        let minutes = Int((configuration.totalDuration / 60).rounded())
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainingMinutes)m"
    }

    private static func encodedTokenData(_ token: ApplicationToken?) -> Data? {
        guard let token else {
            return nil
        }

        return try? JSONEncoder().encode(token)
    }
}

struct ScreenLogTodaySummaryReportView: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: ScreenTimeLiveReportConfiguration

    private var topApps: [SharedAppUsage] {
        Array(configuration.appRows.prefix(8))
    }

    private var hasReportData: Bool {
        configuration.totalDuration > 0
            || configuration.pickupCount > 0
            || configuration.appRows.contains { $0.duration > 0 }
            || configuration.buckets.contains { $0.duration > 0 }
    }

    var body: some View {
        Group {
            if hasReportData {
                reportContent
            } else {
                ReportNoDataView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hasReportData ? .topLeading : .center)
        .background(reportSurfaceColor)
    }

    private var reportSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.085, blue: 0.10)
            : .clear
    }

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

                HStack(alignment: .top, spacing: 14) {
                    ReportMetricColumn(
                        title: "Screen time",
                        value: ReportDurationFormatter.string(from: configuration.totalDuration)
                    )

                    ReportMetricColumn(
                        title: "Pickups",
                        value: "\(configuration.pickupCount)"
                    )
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        if topApps.isEmpty {
                            ReportTopAppTile(
                                id: "empty",
                                displayName: "No app or website detail yet",
                                duration: "Open apps, then refresh."
                            )
                        } else {
                            ForEach(topApps) { app in
                                ReportTopAppTile(
                                    id: app.id,
                                    displayName: app.displayName,
                                    applicationTokenData: app.applicationTokenData,
                                    duration: ReportDurationFormatter.string(from: app.duration)
                                )
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

struct ScreenLogStatsReportView: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: ScreenTimeLiveReportConfiguration
    @State private var selectedBucketID: String?

    private var maxBucketDuration: TimeInterval {
        max(1, configuration.buckets.map(\.duration).max() ?? 1)
    }

    private var selectedBucket: UsageChartBucket? {
        guard let selectedBucketID else {
            return nil
        }

        return configuration.buckets.first { $0.id == selectedBucketID }
    }

    private var primaryTitle: String {
        selectedBucket?.label ?? "Screen Time"
    }

    private var primaryDuration: TimeInterval {
        selectedBucket?.duration ?? configuration.totalDuration
    }

    private var detailText: String {
        if let selectedBucket {
            return selectedBucketDetailText(for: selectedBucket)
        }

        if isHourlyReport {
            return "\(configuration.pickupCount) pickups"
        }

        return "\(configuration.pickupCount) pickups • \(ReportDurationFormatter.string(from: averageDuration))/day avg"
    }

    private func selectedBucketDetailText(for bucket: UsageChartBucket) -> String {
        guard bucket.duration > 0 else {
            return "No screen time recorded"
        }

        return "\(ReportDurationFormatter.string(from: bucket.duration)) screen time"
    }

    private var averageDuration: TimeInterval {
        let elapsedBuckets = configuration.buckets.filter { $0.start <= Date() }
        let divisor = max(1, elapsedBuckets.count)
        return configuration.totalDuration / TimeInterval(divisor)
    }

    private var isHourlyReport: Bool {
        configuration.buckets.contains { bucket in
            bucket.end.timeIntervalSince(bucket.start) <= 3_700
        }
    }

    private var topApps: [SharedAppUsage] {
        Array(configuration.appRows.prefix(6))
    }

    private var hasReportData: Bool {
        configuration.totalDuration > 0
            || configuration.pickupCount > 0
            || configuration.appRows.contains { $0.duration > 0 }
            || configuration.buckets.contains { $0.duration > 0 }
    }

    var body: some View {
        Group {
            if hasReportData {
                reportContent
            } else {
                ReportNoDataView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hasReportData ? .topLeading : .center)
        .background(reportSurfaceColor)
        .padding(.top, hasReportData ? 2 : 0)
        .onChange(of: configuration.buckets.map(\.id)) { _, bucketIDs in
            guard let selectedBucketID, !bucketIDs.contains(selectedBucketID) else {
                return
            }

            self.selectedBucketID = nil
        }
    }

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(primaryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)

                Text(ReportDurationFormatter.string(from: primaryDuration))
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 88, alignment: .topLeading)
            .layoutPriority(2)
            .zIndex(1)

            ReportBarChart(
                buckets: configuration.buckets,
                maxDuration: maxBucketDuration,
                selectedBucketID: $selectedBucketID
            )
            .padding(.top, 4)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 10) {
                Text("Most Used")
                    .font(.subheadline.weight(.semibold))

                if topApps.isEmpty {
                    Text("No app or website detail available for this report yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(topApps.enumerated()), id: \.element.id) { index, app in
                        ReportMostUsedAppRow(
                            rank: index + 1,
                            app: app,
                            maxDuration: max(1, topApps.map(\.duration).max() ?? 1)
                        )
                    }
                }
            }
        }
    }

    private var reportSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.085, blue: 0.10)
            : .clear
    }
}

private struct ReportNoDataView: View {
    var body: some View {
        Text("No data available.\nApple provides only recent Screen Time.")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
    }
}

struct ScreenLogUsageReportView: View {
    let configuration: ScreenTimeLiveReportConfiguration

    var body: some View {
        ScreenLogTodaySummaryReportView(configuration: configuration)
            .accessibilityLabel("Screen Time report")
    }
}

private struct ReportMetricColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 40, weight: .regular).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.56)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReportTopAppTile: View {
    let id: String
    let displayName: String
    var applicationTokenData: Data? = nil
    let duration: String

    var body: some View {
        HStack(spacing: 10) {
            ReportAppIcon(
                name: displayName,
                applicationTokenData: applicationTokenData,
                isWebDomain: id.hasPrefix(SharedAppUsage.webDomainIDPrefix)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(duration)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(width: 160, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 0.7)
        }
    }
}

private struct ReportBarChart: View {
    let buckets: [UsageChartBucket]
    let maxDuration: TimeInterval
    @Binding var selectedBucketID: String?
    @State private var pinnedBucketID: String?
    @State private var isHoldSelecting = false

    private let chartHoldDuration = 0.18

    var body: some View {
        GeometryReader { chartProxy in
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(displayBuckets) { bucket in
                    VStack(spacing: 6) {
                        GeometryReader { barProxy in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(barColor(for: bucket))
                                    .frame(height: max(3, barProxy.size.height * CGFloat(bucket.duration / maxDuration)))
                                    .animation(.snappy(duration: 0.18), value: selectedBucketID)
                            }
                        }

                        Text(bucket.label)
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(bucket.id == selectedBucketID ? Color.blue : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        toggleBucket(at: value.location, width: chartProxy.size.width)
                    }
            )
            .simultaneousGesture(
                holdSelectionGesture(width: chartProxy.size.width)
            )
        }
        .frame(height: 150)
    }

    private func holdSelectionGesture(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: chartHoldDuration, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    beginHoldSelection()
                case .second(true, let drag?):
                    beginHoldSelection()
                    selectBucket(at: drag.location, width: width)
                default:
                    break
                }
            }
            .onEnded { _ in
                endHoldSelection()
            }
    }

    private func barColor(for bucket: UsageChartBucket) -> Color {
        guard let selectedBucketID else {
            return .blue
        }

        return selectedBucketID == bucket.id ? .blue : Color.blue.opacity(0.32)
    }

    private func selectBucket(at location: CGPoint, width: CGFloat) {
        guard let id = bucketID(at: location, width: width) else {
            return
        }

        if selectedBucketID != id {
            ReportHaptics.selectionChanged()
        }
        selectedBucketID = id
    }

    private func toggleBucket(at location: CGPoint, width: CGFloat) {
        guard let id = bucketID(at: location, width: width) else {
            return
        }

        let nextSelection = pinnedBucketID == id ? nil : id
        if selectedBucketID != nextSelection {
            ReportHaptics.selectionChanged()
        }
        pinnedBucketID = nextSelection
        selectedBucketID = nextSelection
    }

    private func beginHoldSelection() {
        guard !isHoldSelecting else {
            return
        }

        isHoldSelecting = true
        ReportHaptics.selectionChanged()
    }

    private func endHoldSelection() {
        guard isHoldSelecting else {
            return
        }

        isHoldSelecting = false
        selectedBucketID = pinnedBucketID
    }

    private func bucketID(at location: CGPoint, width: CGFloat) -> String? {
        let buckets = displayBuckets
        guard !buckets.isEmpty, width > 0 else {
            return nil
        }

        let index = min(
            buckets.count - 1,
            max(0, Int((location.x / width) * CGFloat(buckets.count)))
        )
        return buckets[index].id
    }

    private var displayBuckets: [UsageChartBucket] {
        guard !buckets.isEmpty else {
            return [
                UsageChartBucket(
                    id: "empty",
                    label: "--",
                    date: Date(),
                    start: Date(),
                    end: Date(),
                    duration: 0
                )
            ]
        }

        if buckets.count > 14 {
            return buckets.enumerated().compactMap { index, bucket in
                index.isMultiple(of: 2) ? bucket : nil
            }
        }

        return buckets
    }
}

@MainActor
private enum ReportHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func selectionChanged() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
}

private struct ReportMostUsedAppRow: View {
    let rank: Int
    let app: SharedAppUsage
    let maxDuration: TimeInterval

    private var ratio: CGFloat {
        CGFloat(min(1, max(0, app.duration / maxDuration)))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            ReportAppIcon(
                name: app.displayName,
                applicationTokenData: app.applicationTokenData,
                isWebDomain: app.isWebDomain
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Spacer(minLength: 8)

                    Text(ReportDurationFormatter.string(from: app.duration))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))

                        Capsule()
                            .fill(Color.blue.opacity(0.72))
                            .frame(width: max(6, proxy.size.width * ratio))
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

private struct ReportAppIcon: View {
    let name: String
    var applicationTokenData: Data? = nil
    var isWebDomain = false
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let token = applicationToken {
                Label(token)
                    .labelStyle(.iconOnly)
                    .frame(width: size, height: size)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
            } else if isWebDomain {
                webDomainIcon
            } else {
                fallbackIcon
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    private var webDomainIcon: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.secondary.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.9),
                            Color(red: 0.06, green: 0.62, blue: 0.52).opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initial)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var applicationToken: ApplicationToken? {
        guard let applicationTokenData else {
            return nil
        }

        return try? JSONDecoder().decode(ApplicationToken.self, from: applicationTokenData)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "A"
    }
}

private enum ReportDurationFormatter {
    static func string(from duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds > 0 && seconds < 60 {
            return "<1m"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}
