import Charts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRange: StatsRange = .week
    @State private var selectedDate = Date()
    @State private var selectedChartBucketID: String?

    private var summary: UsageStatsSummary {
        UsageStatsBuilder.summary(
            range: selectedRange,
            selectedDate: selectedDate,
            history: model.usageHistory
        )
    }

    private var chartBuckets: [UsageChartBucket] {
        UsageStatsBuilder.chartBuckets(
            range: selectedRange,
            selectedDate: selectedDate,
            history: model.usageHistory,
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

        return UsageStatsBuilder.snapshot(for: selectedChartBucket.date, in: model.usageHistory)
    }

    private var personalEntry: LeaderboardEntry? {
        StatsBoardBuilder.entry(for: model.profile.id, in: model.leaderboardEntries)
    }

    private var appUsageRows: [SharedAppUsage] {
        UsageStatsBuilder.appUsageRows(
            range: selectedRange,
            selectedDate: selectedDate,
            history: model.usageHistory
        )
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
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
            .navigationTitle("Stats")
            .onAppear {
                model.setLeaderboardWindow(selectedRange.leaderboardWindow)
            }
            .onChange(of: selectedRange) { _, newRange in
                model.setLeaderboardWindow(newRange.leaderboardWindow)
                if newRange == .day {
                    selectedDate = Date()
                }
                selectedChartBucketID = nil
            }
            .onChange(of: selectedDate) {
                selectedChartBucketID = nil
            }
        }
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
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color.white.opacity(0.72)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.86)
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
                    .foregroundStyle(canMoveForward ? Color.primary : Color.secondary.opacity(0.7))
                    .background(Color.white.opacity(canMoveForward ? 0.82 : 0.52), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.86), lineWidth: 0.7)
                    }
                    .shadow(color: Color.black.opacity(canMoveForward ? 0.05 : 0), radius: 6, x: 0, y: 3)
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
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [selectedDate]
        }

        let today = calendar.startOfDay(for: Date())
        var result: [Date] = []
        var cursor = week.start
        while cursor < week.end, cursor <= today {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return result
    }

    var body: some View {
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
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 42)
        .frame(maxWidth: .infinity)
    }
}

private struct DayDateChip: View {
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
                    .background(isSelected ? Color.blue : Color.white.opacity(0.74), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.86), lineWidth: 0.8)
                    }
                    .shadow(color: Color.black.opacity(isSelected ? 0.05 : 0.035), radius: 6, x: 0, y: 3)
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

                    Text(primaryDuration)
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .rollingNumberTransition(value: primaryDuration)

                    Text(primaryCaption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
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
        AppSection("Most Used Apps") {
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
        }
    }

    private var emptyTitle: String {
        hasScreenTimeData ? "No app detail" : "No usage yet"
    }

    private var emptyDescription: String {
        if hasScreenTimeData {
            return "App-level rows are unavailable for this \(range.label.lowercased())."
        }

        return "Refresh Screen Time after usage is available."
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

            AppUsageIcon(name: app.displayName)

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
    @State private var pendingGestureLocation: CGPoint?

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
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                pendingGestureLocation = value.location
                                guard isPressSelectionActive else {
                                    return
                                }

                                updatePressSelection(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                endPressSelection()
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                togglePinnedSelection(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: chartHoldDuration, maximumDistance: .infinity)
                            .onEnded { _ in
                                isPressSelectionActive = true
                                AppHaptics.buttonTap()
                                if let pendingGestureLocation {
                                    updatePressSelection(at: pendingGestureLocation, proxy: proxy, geometry: geometry)
                                }
                            }
                    )
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
            pendingGestureLocation = nil
            return
        }

        isPressSelectionActive = false
        pendingGestureLocation = nil
        selectedBucketID = pinnedBucketID
    }
}
