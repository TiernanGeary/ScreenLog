import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingSettings: Bool
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

    private var friendEntries: [LeaderboardEntry] {
        model.leaderboardEntries.filter { $0.userID != model.profile.id }
    }

    private var personalEntry: LeaderboardEntry? {
        StatsBoardBuilder.entry(for: model.profile.id, in: model.leaderboardEntries)
    }

    private var mostExtraEntries: [LeaderboardEntry] {
        StatsBoardBuilder.mostExtraRequested(entries: friendEntries)
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

                AppSection("Friends") {
                    StatsBoardCard(
                        entries: Array(mostExtraEntries.prefix(4)),
                        addDemoAction: {
                            #if DEBUG
                            model.seedDemoFriends()
                            #endif
                        }
                    )
                }
            }
            .navigationTitle("Stats")
            .settingsToolbar(isShowingSettings: $isShowingSettings)
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
    @Binding var selection: StatsRange
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases) { range in
                Button {
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
                .fill(Color.white.opacity(0.72))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.86), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 7)
        }
        .animation(.snappy(duration: 0.22), value: selection)
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

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct UsageBarChart: View {
    let range: StatsRange
    let buckets: [UsageChartBucket]
    @Binding var selectedBucketID: String?
    @State private var isPressSelectionActive = false
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

                                selectBucket(at: value.location, proxy: proxy, geometry: geometry)
                            }
                            .onEnded { _ in
                                clearPressSelection()
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: chartHoldDuration, maximumDistance: .infinity)
                            .onEnded { _ in
                                isPressSelectionActive = true
                                if let pendingGestureLocation {
                                    selectBucket(at: pendingGestureLocation, proxy: proxy, geometry: geometry)
                                }
                            }
                    )
            }
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

    private func selectBucket(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        let xPosition = location.x - plotFrame.origin.x
        guard xPosition >= 0, xPosition <= plotFrame.width else {
            selectedBucketID = nil
            return
        }

        guard let bucketID = proxy.value(atX: xPosition, as: String.self),
              buckets.contains(where: { $0.id == bucketID }) else {
            selectedBucketID = nil
            return
        }

        selectedBucketID = bucketID
    }

    private func clearPressSelection() {
        isPressSelectionActive = false
        pendingGestureLocation = nil
        selectedBucketID = nil
    }
}

private struct StatsBoardCard: View {
    let entries: [LeaderboardEntry]
    let addDemoAction: () -> Void

    var body: some View {
        AppCard {
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No friend stats yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    #if DEBUG
                    Button(action: addDemoAction) {
                        Label("Add Demo Stats", systemImage: "person.3.sequence")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    #endif
                }
                .appCardRow()
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    StatsBoardRow(rank: index + 1, entry: entry)
                        .appCardRow(verticalPadding: 8)

                    if index < entries.count - 1 {
                        AppCardDivider()
                    }
                }
            }
        }
    }
}

private struct StatsBoardRow: View {
    let rank: Int
    let entry: LeaderboardEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            Avatar(colorHex: entry.avatarColorHex, initials: entry.displayName.initials)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            Text(UsageFormatting.duration(entry.requestedExtraSeconds))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
    }

    private var subtitle: String {
        "\(entry.requestCount) asks · \(entry.emergencyUnlockCount) emergency"
    }
}
