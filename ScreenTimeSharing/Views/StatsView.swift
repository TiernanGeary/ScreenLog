import Charts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRange: StatsRange = .day
    @State private var selectedDate = Date()
    @State private var selectedChartBucketID: String?

    private var summary: UsageStatsSummary {
        model.usageStatsCache.summary(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory,
            hourlyDurationsByDayID: model.hourlyUsageByDayID
        )
    }

    private var chartBuckets: [UsageChartBucket] {
        model.usageStatsCache.chartBuckets(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory,
            hourlyDurationsByDayID: model.hourlyUsageByDayID
        )
    }

    private var selectedChartBucket: UsageChartBucket? {
        guard let selectedChartBucketID else {
            return nil
        }

        return chartBuckets.first { $0.id == selectedChartBucketID }
    }

    private var selectedChartSnapshot: DailyUsageSnapshot? {
        guard let selectedChartBucket else {
            return nil
        }

        return UsageStatsBuilder.snapshot(for: selectedChartBucket.date, in: statsHistory)
    }

    private var personalEntry: LeaderboardEntry? {
        StatsBoardBuilder.entry(for: model.profile.id, in: model.leaderboardEntries)
    }

    private var appUsageRows: [SharedAppUsage] {
        model.usageStatsCache.appUsageRows(
            range: selectedRange,
            selectedDate: selectedDate,
            history: statsHistory
        )
    }

    private var currentReportKey: StatsReportKey {
        StatsReportKey(range: selectedRange, selectedDate: selectedDate)
    }

    private var statsHistory: [DailyUsageSnapshot] {
        guard let snapshot = model.localSnapshot, snapshot.hasScreenTimeData else {
            return model.usageHistory
        }

        return UsageHistoryCodec.upserting(snapshot, into: model.usageHistory)
    }

    private var shouldShowLiveStatsFallback: Bool {
        model.hasScreenTimeAuthorization
            && !summary.hasScreenTimeData
            && appUsageRows.isEmpty
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                statsContent
            }
            .navigationTitle("Stats")
            .onAppear {
                model.setLeaderboardWindow(selectedRange.leaderboardWindow)
                primeStatsReport()
            }
            .onChange(of: selectedRange) { _, newRange in
                model.setLeaderboardWindow(newRange.leaderboardWindow)
                if newRange == .day {
                    selectedDate = Date()
                }
                selectedChartBucketID = nil
                primeStatsReport()
            }
            .onChange(of: selectedDate) {
                selectedChartBucketID = nil
                primeStatsReport()
            }
        }
    }

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                StatsRangeSelector(selection: $selectedRange)

                if selectedRange == .day {
                    DayDateStrip(selectedDate: $selectedDate)
                } else {
                    PeriodNavigator(
                        range: selectedRange,
                        selectedDate: $selectedDate,
                        title: summary.periodLabel
                    )
                }
            }

            if shouldShowLiveStatsFallback {
                liveStatsFallback
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    UsageSummaryCard(
                        summary: summary,
                        selectedBucket: selectedChartBucket,
                        selectedPickupCount: selectedChartSnapshot?.pickupCount,
                        requestCount: personalEntry?.requestCount ?? 0
                    )
                }

                UsageChartSection(
                    range: selectedRange,
                    buckets: chartBuckets,
                    selectedBucketID: $selectedChartBucketID
                )

                MostUsedAppsSection(
                    range: selectedRange,
                    apps: appUsageRows,
                    hasScreenTimeData: summary.hasScreenTimeData
                )
            }
        }
    }

    private func primeStatsReport() {
        model.reloadUsageHistoryFromSharedStorage()
        model.requestScreenTimeReportRefresh()
    }

    private var liveStatsFallback: some View {
        AppCard(cornerRadius: 24, opacity: 0.78) {
            ScreenTimeLiveStatsReport(
                range: currentReportKey.range,
                selectedDate: currentReportKey.selectedDate
            )
            .frame(height: liveReportLoaderHeight(for: currentReportKey.range))
            .allowsHitTesting(false)
            .appCardRow(verticalPadding: 14)
        }
        .allowsHitTesting(false)
    }

    private func liveReportLoaderHeight(for range: StatsRange) -> CGFloat {
        switch range {
        case .day:
            return 560
        case .week, .month:
            return 580
        }
    }
}

private extension DailyUsageSnapshot {
    var hasScreenTimeData: Bool {
        (totalDuration ?? 0) > 0
            || pickupCount != nil
            || !appRows.isEmpty
    }
}

private struct StatsReportKey: Hashable, Identifiable {
    let range: StatsRange
    let selectedDate: Date

    var id: String {
        "\(range.rawValue)-\(selectedDate.timeIntervalSinceReferenceDate)"
    }

    init(range: StatsRange, selectedDate: Date, calendar: Calendar = .current) {
        self.range = range
        self.selectedDate = UsageStatsBuilder.periodInterval(
            for: range,
            containing: selectedDate,
            calendar: calendar
        ).start
    }
}

private struct StatsRangeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: StatsRange
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases) { range in
                Button {
                    if selection != range {
                        AppHaptics.selectionChanged()
                    }
                    selection = range
                } label: {
                    Text(range.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(selection == range ? .white : .primary)
                        .background {
                            if selection == range {
                                Capsule()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selected-stats-range", in: namespace)
                                    .shadow(color: Color.blue.opacity(0.20), radius: 8, x: 0, y: 3)
                            }
                        }
                        .appCapsuleButtonHitArea()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(backgroundColor)
                .overlay {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 14, x: 0, y: 7)
        }
        .animation(.snappy(duration: 0.22), value: selection)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.085, blue: 0.10)
            : Color.white.opacity(0.72)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.86)
    }
}

private struct PeriodNavigator: View {
    let range: StatsRange
    @Binding var selectedDate: Date
    let title: String

    private var canMoveForward: Bool {
        UsageStatsBuilder.canNavigateForward(range: range, selectedDate: selectedDate)
    }

    var body: some View {
        HStack {
            Button {
                AppHaptics.buttonTap()
                move(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.white)
                    .background(Color.blue, in: Circle())
                    .shadow(color: Color.blue.opacity(0.14), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous \(range.label)")

            Spacer()

            Text(title)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer()

            Button {
                AppHaptics.buttonTap()
                move(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .frame(width: 30, height: 30)
                    .foregroundStyle(canMoveForward ? Color.white : Color.secondary.opacity(0.7))
                    .background(canMoveForward ? Color.blue : Color.secondary.opacity(0.16), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(canMoveForward ? Color.clear : Color.secondary.opacity(0.18), lineWidth: 0.7)
                    }
                    .shadow(color: Color.blue.opacity(canMoveForward ? 0.14 : 0), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveForward)
            .accessibilityLabel("Next \(range.label)")
        }
        .padding(.horizontal, 2)
        .frame(height: 42)
    }

    private func move(_ value: Int) {
        guard let newDate = UsageStatsBuilder.date(
            byMoving: range,
            value: value,
            from: selectedDate
        ) else {
            return
        }

        selectedDate = newDate
    }
}

private struct DayDateStrip: View {
    @Binding var selectedDate: Date
    private let calendar = Calendar.current

    private var dates: [Date] {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    DayDateChip(
                        date: date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
                    ) {
                        if !calendar.isDate(date, inSameDayAs: selectedDate) {
                            AppHaptics.selectionChanged()
                        }
                        selectedDate = date
                    }
                    .frame(width: 42)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
    }
}

private struct DayDateChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(weekday)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)

                Text(dayNumber)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 30, height: 30)
                    .background(dayBackground, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(dayBorder, lineWidth: 0.8)
                    }
                    .shadow(color: dayShadow, radius: isSelected ? 6 : 0, x: 0, y: 3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var dayBackground: Color {
        if isSelected {
            return .blue
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.74)
    }

    private var dayBorder: Color {
        if isSelected {
            return Color.white.opacity(colorScheme == .dark ? 0.12 : 0.24)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.86)
    }

    private var dayShadow: Color {
        guard isSelected else {
            return .clear
        }

        return Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

private struct UsageSummaryCard: View {
    let summary: UsageStatsSummary
    let selectedBucket: UsageChartBucket?
    let selectedPickupCount: Int?
    let requestCount: Int

    var body: some View {
        AppCard(cornerRadius: 24, opacity: 0.78) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headerLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(primaryDuration)
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .rollingNumberTransition(value: primaryDuration)

                    Text(primaryCaption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if summary.range == .day {
                    HStack(spacing: 22) {
                        SummaryValueBlock(title: "Pickups", value: pickupText)
                        SummaryValueBlock(title: "Requests", value: "\(requestCount)")
                    }
                } else {
                    HStack(spacing: 22) {
                        SummaryValueBlock(title: "Screen Time", value: UsageFormatting.duration(metricScreenTime))
                        SummaryValueBlock(title: "Pickups", value: pickupText)
                        SummaryValueBlock(title: "Requests", value: "\(requestCount)")
                    }
                }
            }
            .appCardRow(verticalPadding: 14)
        }
    }

    private var primaryDuration: String {
        if let selectedBucket, summary.range == .day {
            return UsageFormatting.duration(selectedBucket.duration)
        }

        switch summary.range {
        case .day:
            return UsageFormatting.duration(summary.totalDuration)
        case .month, .week:
            return UsageFormatting.duration(summary.dailyAverageDuration)
        }
    }

    private var primaryCaption: String {
        if selectedBucket != nil, summary.range == .day {
            return "Screen Time"
        }

        return summary.range == .day ? "Screen Time" : "Daily Average"
    }

    private var pickupText: String {
        if selectedBucket != nil {
            guard let selectedPickupCount else {
                return "Unavailable"
            }

            return "\(selectedPickupCount)"
        }

        guard let pickupTotal = summary.pickupTotal else {
            return "Unavailable"
        }

        return "\(pickupTotal)"
    }

    private var metricScreenTime: TimeInterval {
        selectedBucket?.duration ?? summary.totalDuration
    }

    private var headerLabel: String {
        guard let selectedBucket else {
            return summary.dateRangeLabel
        }

        switch summary.range {
        case .day:
            return "\(summary.dateRangeLabel) · \(selectedBucket.label)"
        case .month, .week:
            return selectionDateLabel(for: selectedBucket)
        }
    }

    private func selectionDateLabel(for bucket: UsageChartBucket) -> String {
        switch summary.range {
        case .month, .week:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: bucket.date)
        case .day:
            return bucket.label
        }
    }
}

private struct SummaryValueBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .rollingNumberTransition(value: value)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func rollingNumberTransition(value: String) -> some View {
        contentTransition(.numericText())
            .animation(.snappy(duration: 0.24), value: value)
    }
}

private struct UsageChartSection: View {
    let range: StatsRange
    let buckets: [UsageChartBucket]
    @Binding var selectedBucketID: String?

    var body: some View {
        AppCard(cornerRadius: 24, opacity: 0.78) {
            UsageBarChart(
                range: range,
                buckets: buckets,
                selectedBucketID: $selectedBucketID
            )
                .appCardRow(verticalPadding: 14)
        }
    }
}

private struct MostUsedAppsSection: View {
    let range: StatsRange
    let apps: [SharedAppUsage]
    let hasScreenTimeData: Bool

    private var maxDuration: TimeInterval {
        max(1, apps.map(\.duration).max() ?? 1)
    }

    var body: some View {
        AppSection("Most Used") {
            AppCard {
                if apps.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "app.dashed",
                        description: Text(emptyDescription)
                    )
                    .appCardRow(verticalPadding: 16)
                } else {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        MostUsedAppRow(
                            rank: index + 1,
                            app: app,
                            maxDuration: maxDuration
                        )
                        .appCardRow(verticalPadding: 9)

                        if index < apps.count - 1 {
                            AppCardDivider()
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var emptyTitle: String {
        hasScreenTimeData ? "No app detail" : "No usage yet"
    }

    private var emptyDescription: String {
        if hasScreenTimeData {
            return "App and website rows are unavailable for this \(range.label.lowercased())."
        }

        return "Usage appears after Apple provides Screen Time data."
    }
}

private struct MostUsedAppRow: View {
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

            AppUsageIcon(
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

                    Text(UsageFormatting.duration(app.duration))
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

private struct UsageBarChart: View {
    let range: StatsRange
    let buckets: [UsageChartBucket]
    @Binding var selectedBucketID: String?
    @State private var isPressSelectionActive = false
    @State private var pinnedBucketID: String?

    private let chartHoldDuration = 0.18

    private var maxDuration: TimeInterval {
        let observed = buckets.map(\.duration).max() ?? 0
        let minimum: TimeInterval = range == .day ? 3_600 : 4 * 3_600
        let roundedHours = ceil(max(observed, minimum) / 3_600)
        return max(1, roundedHours) * 3_600
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.id),
                    y: .value("Screen Time", bucket.duration)
                )
                .foregroundStyle(barColor(for: bucket))
                .cornerRadius(cornerRadius)
                .annotation(position: .top, alignment: .center) {
                    if range == .week, bucket.duration > 0 {
                        Text(UsageFormatting.duration(bucket.duration))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                }
            }

            if let selectedBucket {
                RuleMark(x: .value("Selected", selectedBucket.id))
                    .foregroundStyle(Color.blue.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .chartYScale(domain: 0...maxDuration)
        .chartXAxis {
            AxisMarks(values: buckets.map(\.id)) { value in
                AxisValueLabel {
                    Text(axisLabel(forID: value.as(String.self)))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, maxDuration / 2, maxDuration]) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel {
                    Text(UsageFormatting.duration(value.as(Double.self) ?? 0))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                chartInteractionOverlay(proxy: proxy, geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onChange(of: selectedBucketID) { _, newValue in
            guard !isPressSelectionActive else {
                return
            }

            pinnedBucketID = newValue
        }
        .onChange(of: buckets.map(\.id)) { _, bucketIDs in
            guard let pinnedBucketID, !bucketIDs.contains(pinnedBucketID) else {
                return
            }

            self.pinnedBucketID = nil
            selectedBucketID = nil
        }
        .frame(height: range == .week ? 178 : 154)
    }

    private var cornerRadius: CGFloat {
        range == .month ? 3 : 6
    }

    private var selectedBucket: UsageChartBucket? {
        guard let selectedBucketID else {
            return nil
        }

        return buckets.first { $0.id == selectedBucketID }
    }

    private func barColor(for bucket: UsageChartBucket) -> Color {
        if selectedBucketID == nil || selectedBucketID == bucket.id {
            return .blue
        }

        return Color.blue.opacity(0.34)
    }

    private func axisLabel(forID id: String?) -> String {
        guard let id,
              let index = buckets.firstIndex(where: { $0.id == id }) else {
            return ""
        }

        let bucket = buckets[index]
        switch range {
        case .month:
            let day = Calendar.current.component(.day, from: bucket.date)
            return day == 1 || (day - 1).isMultiple(of: 7) ? bucket.label : ""
        case .week:
            return bucket.label
        case .day:
            if buckets.count <= 1 {
                return bucket.label
            }

            return index.isMultiple(of: 6) ? bucket.label : ""
        }
    }

    @ViewBuilder
    private func chartInteractionOverlay(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        #if canImport(UIKit)
        ScrollFriendlyChartInteractionOverlay(
            minimumPressDuration: chartHoldDuration,
            onTap: { location in
                togglePinnedSelection(at: location, proxy: proxy, geometry: geometry)
            },
            onPressChanged: { location in
                beginPressSelection()
                updatePressSelection(at: location, proxy: proxy, geometry: geometry)
            },
            onPressEnded: {
                endPressSelection()
            }
        )
        #else
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        togglePinnedSelection(at: value.location, proxy: proxy, geometry: geometry)
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: chartHoldDuration, maximumDistance: 12)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            beginPressSelection()
                        case .second(true, let drag?):
                            beginPressSelection()
                            updatePressSelection(at: drag.location, proxy: proxy, geometry: geometry)
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        endPressSelection()
                    }
            )
        #endif
    }

    private func bucketID(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> String? {
        guard let plotFrameAnchor = proxy.plotFrame else {
            return nil
        }

        let plotFrame = geometry[plotFrameAnchor]
        let xPosition = location.x - plotFrame.origin.x
        guard xPosition >= 0, xPosition <= plotFrame.width else {
            return nil
        }

        guard let bucketID = proxy.value(atX: xPosition, as: String.self),
              buckets.contains(where: { $0.id == bucketID }) else {
            return nil
        }

        return bucketID
    }

    private func updatePressSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let bucketID = bucketID(at: location, proxy: proxy, geometry: geometry)
        if selectedBucketID != bucketID {
            AppHaptics.selectionChanged()
        }
        selectedBucketID = bucketID
    }

    private func togglePinnedSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let bucketID = bucketID(at: location, proxy: proxy, geometry: geometry) else {
            if selectedBucketID != nil {
                AppHaptics.selectionChanged()
            }
            pinnedBucketID = nil
            selectedBucketID = nil
            return
        }

        let nextBucketID = pinnedBucketID == bucketID ? nil : bucketID
        if selectedBucketID != nextBucketID {
            AppHaptics.selectionChanged()
        }
        pinnedBucketID = nextBucketID
        selectedBucketID = nextBucketID
    }

    private func endPressSelection() {
        guard isPressSelectionActive else {
            return
        }

        isPressSelectionActive = false
        selectedBucketID = pinnedBucketID
    }

    private func beginPressSelection() {
        guard !isPressSelectionActive else {
            return
        }

        isPressSelectionActive = true
        AppHaptics.buttonTap()
    }
}

#if canImport(UIKit)
private struct ScrollFriendlyChartInteractionOverlay: UIViewRepresentable {
    let minimumPressDuration: TimeInterval
    let onTap: (CGPoint) -> Void
    let onPressChanged: (CGPoint) -> Void
    let onPressEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onPressChanged: onPressChanged,
            onPressEnded: onPressEnded
        )
    }

    func makeUIView(context: Context) -> ChartGestureHostView {
        let view = ChartGestureHostView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.coordinator = context.coordinator
        context.coordinator.minimumPressDuration = minimumPressDuration
        return view
    }

    func updateUIView(_ uiView: ChartGestureHostView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onPressChanged = onPressChanged
        context.coordinator.onPressEnded = onPressEnded
        context.coordinator.minimumPressDuration = minimumPressDuration
        context.coordinator.installGesturesIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: ChartGestureHostView, coordinator: Coordinator) {
        coordinator.removeGestures()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void
        var onPressChanged: (CGPoint) -> Void
        var onPressEnded: () -> Void
        var minimumPressDuration: TimeInterval = 0.18
        private weak var hostView: UIView?
        private weak var gestureTargetView: UIView?
        private var tapGesture: UITapGestureRecognizer?
        private var pressGesture: UILongPressGestureRecognizer?

        init(
            onTap: @escaping (CGPoint) -> Void,
            onPressChanged: @escaping (CGPoint) -> Void,
            onPressEnded: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onPressChanged = onPressChanged
            self.onPressEnded = onPressEnded
        }

        func installGesturesIfNeeded(from hostView: UIView) {
            self.hostView = hostView

            guard let targetView = hostView.enclosingScrollView else {
                return
            }

            if gestureTargetView === targetView {
                pressGesture?.minimumPressDuration = minimumPressDuration
                return
            }

            removeGestures()
            gestureTargetView = targetView

            let tapGesture = UITapGestureRecognizer(
                target: self,
                action: #selector(handleTap(_:))
            )
            tapGesture.cancelsTouchesInView = false
            tapGesture.delaysTouchesBegan = false
            tapGesture.delegate = self

            let pressGesture = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handlePress(_:))
            )
            pressGesture.minimumPressDuration = minimumPressDuration
            pressGesture.allowableMovement = 12
            pressGesture.cancelsTouchesInView = false
            pressGesture.delaysTouchesBegan = false
            pressGesture.delegate = self

            targetView.addGestureRecognizer(tapGesture)
            targetView.addGestureRecognizer(pressGesture)

            self.tapGesture = tapGesture
            self.pressGesture = pressGesture
        }

        func removeGestures() {
            if let tapGesture {
                gestureTargetView?.removeGestureRecognizer(tapGesture)
            }

            if let pressGesture {
                gestureTargetView?.removeGestureRecognizer(pressGesture)
            }

            tapGesture = nil
            pressGesture = nil
            gestureTargetView = nil
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let location = chartLocation(for: recognizer) else {
                return
            }

            onTap(location)
        }

        @objc func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            guard let location = chartLocation(for: recognizer) else {
                return
            }

            switch recognizer.state {
            case .began, .changed:
                onPressChanged(location)
            case .ended, .cancelled, .failed:
                onPressEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let hostView else {
                return false
            }

            let location = touch.location(in: hostView)
            return hostView.bounds.contains(location)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            chartLocation(for: gestureRecognizer) != nil
        }

        private func chartLocation(for recognizer: UIGestureRecognizer) -> CGPoint? {
            guard let hostView else {
                return nil
            }

            let location = recognizer.location(in: hostView)
            guard hostView.bounds.contains(location) else {
                return nil
            }

            return location
        }
    }
}

private final class ChartGestureHostView: UIView {
    weak var coordinator: ScrollFriendlyChartInteractionOverlay.Coordinator?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        coordinator?.installGesturesIfNeeded(from: self)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        if let scrollView = self as? UIScrollView {
            return scrollView
        }

        return superview?.enclosingScrollView
    }
}
#endif
