import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool
    @Binding var isShowingBlockingActivityPicker: Bool
    @Binding var isShowingSettings: Bool

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                TodayScreenTimeCard(snapshot: model.localSnapshot)

                HomeROICard(
                    summary: HomeEngagementBuilder.summary(history: model.usageHistory),
                    snapshot: model.localSnapshot
                )

                AppSection("Blocking") {
                    BlockingOverviewCard(
                        isShowingBlockingActivityPicker: $isShowingBlockingActivityPicker,
                        isShowingSettings: $isShowingSettings
                    )
                }

                if let message = model.message {
                    AppCard {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .appCardRow(verticalPadding: 10)
                    }
                }
            }
            .navigationTitle("Home")
            .settingsToolbar(isShowingSettings: $isShowingSettings)
            .overlay {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
    }
}

private struct TodayScreenTimeCard: View {
    let snapshot: DailyUsageSnapshot?

    var body: some View {
        TintedHomeCard(
            cornerRadius: 24,
            colors: [
                Color(red: 0.91, green: 0.97, blue: 1.0),
                Color(red: 0.98, green: 0.99, blue: 1.0),
                Color.white.opacity(0.90)
            ],
            shadowColor: Color(red: 0.12, green: 0.46, blue: 0.86).opacity(0.08)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(alignment: .top, spacing: 14) {
                    TodayMetricColumn(
                        title: "Screen time",
                        value: UsageFormatting.duration(snapshot?.totalDuration),
                        systemImage: "iphone",
                        accentColor: Color.blue
                    )

                    TodayMetricColumn(
                        title: "Pickups",
                        value: pickupLabel,
                        systemImage: "hand.tap",
                        accentColor: Color(red: 0.08, green: 0.58, blue: 0.50)
                    )
                }
            }
            .appCardRow(verticalPadding: 14)
        }
    }

    private var pickupLabel: String {
        guard let pickupCount = snapshot?.pickupCount else {
            return "--"
        }

        return "\(pickupCount)"
    }
}

private struct TodayMetricColumn: View {
    let title: String
    let value: String
    let systemImage: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(accentColor)
            .lineLimit(1)

            Text(value)
                .font(.system(size: 44, weight: .black, design: .default).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeROICard: View {
    let summary: HomeEngagementSummary
    let snapshot: DailyUsageSnapshot?

    var body: some View {
        TintedHomeCard(
            cornerRadius: 26,
            colors: [
                Color(red: 0.94, green: 1.0, blue: 0.98),
                Color(red: 0.95, green: 0.98, blue: 1.0),
                Color.white.opacity(0.90)
            ],
            shadowColor: Color(red: 0.08, green: 0.52, blue: 0.48).opacity(0.075)
        ) {
            VStack(alignment: .leading, spacing: 18) {
                switch summary.baselineStatus {
                case .ready:
                    readyContent
                case .building(let daysCollected, let requiredDays):
                    buildingContent(daysCollected: daysCollected, requiredDays: requiredDays)
                case .unavailable:
                    unavailableContent
                }
            }
            .appCardRow(verticalPadding: 16)
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(summary.netSavedDuration >= 0 ? "Time won back" : "Over baseline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(UsageFormatting.duration(abs(summary.netSavedDuration)))
                    .font(.system(size: 46, weight: .black, design: .default).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Text(readySubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HomeProofRow(summary: summary)

            if let topImprovement = summary.topImprovement {
                HomeTopImprovementRow(improvement: topImprovement)
            }
        }
    }

    private func buildingContent(daysCollected: Int, requiredDays: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Time won back")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    Text("\(daysCollected)/\(requiredDays)")
                        .font(.system(size: 46, weight: .black, design: .default).monospacedDigit())
                        .lineLimit(1)

                    Text("baseline days")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text("Keep ScreenLog running for \(max(0, requiredDays - daysCollected)) more days to calculate saved time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HomeProofMetric(
                title: "Pickups",
                value: pickupLabel,
                systemImage: "hand.tap"
            )
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time won back")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Unavailable")
                .font(.system(size: 40, weight: .black, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(snapshot?.capability.reason ?? "Authorize Screen Time and refresh to start tracking ROI.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var readySubtitle: String {
        if summary.comparisonDayCount == 0 {
            return "Baseline ready. New days will start growing your ROI."
        }

        return "Compared with your first 7-day baseline."
    }

    private var pickupLabel: String {
        guard let pickupCount = snapshot?.pickupCount else {
            return "Unavailable"
        }

        return "\(pickupCount)"
    }
}

private struct TintedHomeCard<Content: View>: View {
    let cornerRadius: CGFloat
    let colors: [Color]
    let shadowColor: Color
    let content: Content

    init(
        cornerRadius: CGFloat,
        colors: [Color],
        shadowColor: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.colors = colors
        self.shadowColor = shadowColor
        self.content = content()
    }

    var body: some View {
        AppCardRows {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.86), lineWidth: 0.8)
                }
                .shadow(color: shadowColor, radius: 22, x: 0, y: 10)
                .shadow(color: Color.black.opacity(0.035), radius: 14, x: 0, y: 7)
        }
    }
}

private struct HomeProofRow: View {
    let summary: HomeEngagementSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HomeProofMetric(
                title: "Screen time",
                value: percentLabel(summary.screenTimePercentChange),
                systemImage: "iphone",
                valueSystemImage: percentTrendIcon(summary.screenTimePercentChange),
                accentColor: percentColor(summary.screenTimePercentChange)
            )
            HomeProofMetric(
                title: "Streak",
                value: dayLabel(summary.beatBaselineStreakDays),
                systemImage: "flame",
                accentColor: Color(red: 0.96, green: 0.48, blue: 0.10)
            )
        }
    }

    private func percentLabel(_ percent: Double?) -> String {
        guard let percent else {
            return "No data"
        }

        let rounded = Int(abs(percent).rounded())
        return "\(rounded)%"
    }

    private func dayLabel(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func percentTrendIcon(_ percent: Double?) -> String? {
        guard let percent else {
            return nil
        }

        return percent >= 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func percentColor(_ percent: Double?) -> Color {
        guard let percent else {
            return .primary
        }

        if percent >= 0 {
            return Color(red: 0.08, green: 0.58, blue: 0.32)
        }

        return Color(red: 0.86, green: 0.24, blue: 0.22)
    }
}

private struct HomeProofMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var valueSystemImage: String?
    var accentColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()

                if let valueSystemImage {
                    Image(systemName: valueSystemImage)
                        .font(.subheadline.weight(.black))
                }
            }
            .foregroundStyle(accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.66)

            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(accentColor.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeTopImprovementRow: View {
    let improvement: HomeTopImprovement

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.right.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(improvement.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(improvementSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.74), lineWidth: 0.7)
        }
    }

    private var improvementSubtitle: String {
        if let percent = improvement.percentChange {
            return "\(UsageFormatting.duration(improvement.savedDuration)) saved, \(Int(abs(percent).rounded()))% lower"
        }

        return "\(UsageFormatting.duration(improvement.savedDuration)) saved"
    }
}

private struct ScreenTimeSummaryCard: View {
    let snapshot: DailyUsageSnapshot?

    private var topApps: [SharedAppUsage] {
        (snapshot?.appRows ?? [])
            .sorted { lhs, rhs in
                if lhs.duration != rhs.duration {
                    return lhs.duration > rhs.duration
                }

                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    var body: some View {
        AppCard(cornerRadius: 24, opacity: 0.76) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    SummaryMetricTile(
                        title: "Screen time",
                        value: UsageFormatting.duration(snapshot?.totalDuration),
                        systemImage: "iphone"
                    )
                    SummaryMetricTile(
                        title: "Pickups",
                        value: pickupLabel,
                        systemImage: "hand.tap"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top apps")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            if topApps.isEmpty {
                                TopAppEmptyTile(capability: snapshot?.capability)
                            } else {
                                ForEach(topApps) { app in
                                    TopAppUsageTile(app: app)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .appCardRow(verticalPadding: 14)
        }
    }

    private var pickupLabel: String {
        guard let pickupCount = snapshot?.pickupCount else {
            return "Unavailable"
        }

        return "\(pickupCount)"
    }
}

private struct SummaryMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .default).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct TopAppUsageTile: View {
    let app: SharedAppUsage

    var body: some View {
        HStack(spacing: 10) {
            AppUsageIcon(name: app.displayName)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(UsageFormatting.duration(app.duration))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(width: 160, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 0.7)
        }
    }
}

private struct TopAppEmptyTile: View {
    let capability: ScreenTimeCapability?

    var body: some View {
        HStack(spacing: 10) {
            AppUsageIcon(name: "Apps")

            VStack(alignment: .leading, spacing: 4) {
                Text(emptyTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(emptySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 230, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 0.7)
        }
    }

    private var emptyTitle: String {
        if capability?.allowsPerAppRows == false {
            return "App detail unavailable"
        }

        return "No app detail yet"
    }

    private var emptySubtitle: String {
        capability?.reason ?? "Refresh after selecting apps."
    }
}

private struct AppUsageIcon: View {
    let name: String

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(iconGradient)
            .frame(width: 42, height: 42)
            .overlay {
                Text(initial)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "A"
        }

        return String(first).uppercased()
    }

    private var iconGradient: LinearGradient {
        let palette: [(Color, Color)] = [
            (Color(red: 0.10, green: 0.60, blue: 0.55), Color(red: 0.12, green: 0.42, blue: 0.78)),
            (Color(red: 0.91, green: 0.30, blue: 0.33), Color(red: 0.94, green: 0.55, blue: 0.15)),
            (Color(red: 0.42, green: 0.30, blue: 0.62), Color(red: 0.18, green: 0.46, blue: 0.72)),
            (Color(red: 0.18, green: 0.48, blue: 0.34), Color(red: 0.78, green: 0.56, blue: 0.18))
        ]
        let index = abs(name.hashValue) % palette.count
        let colors = palette[index]

        return LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct BlockingOverviewCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingBlockingActivityPicker: Bool
    @Binding var isShowingSettings: Bool
    @State private var friendRequestGroup: BlockGroup?
    @State private var newGroupDraft: BlockGroupDraft?
    @State private var isShowingDummyBlockedApp = false

    private var firstGroup: BlockGroup? {
        model.blockingState.groups.first
    }

    var body: some View {
        AppCard {
            if let firstGroup {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: firstGroup.colorHex))
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(firstGroup.name)
                                .font(.headline)
                            Text(firstGroup.isEnabled ? "Blocking enabled" : "Blocking paused")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Manage block group")
                    }

                    HStack(spacing: 10) {
                        MetricTile(title: "Groups", value: "\(model.activeBlockingRulesCount)")
                        MetricTile(title: modeMetricTitle, value: modeMetricValue)
                        MetricTile(title: "Requests", value: "\(model.pendingBlockRequestCount)")
                    }

                    Text(firstGroup.mode.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if firstGroup.unblockConfig.isEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(remainingUnblocks(for: firstGroup)) limited unblocks left today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                unblockButton("5m", seconds: 5 * 60, group: firstGroup)
                                unblockButton("15m", seconds: 15 * 60, group: firstGroup)
                                unblockButton("30m", seconds: 30 * 60, group: firstGroup)
                            }
                        }
                    } else {
                        Text("Limited local unblocks are off for this group.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if firstGroup.friendRequestConfig.isEnabled {
                        Button {
                            friendRequestGroup = firstGroup
                        } label: {
                            Label("Request friend approval", systemImage: "person.2.badge.gearshape")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }

#if DEBUG
                    Button {
                        isShowingDummyBlockedApp = true
                    } label: {
                        DummyBlockedAppRow(title: "Open Dummy Blocked App")
                    }
                    .buttonStyle(.plain)
#endif

                    HStack(spacing: 12) {
                        Button {
                            newGroupDraft = BlockGroupDraft()
                        } label: {
                            Label("New Group", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        Spacer()

                        Button {
                            isShowingSettings = true
                        } label: {
                            Label("Manage", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
                .appCardRow(verticalPadding: 16)
            } else {
                Button {
                    newGroupDraft = BlockGroupDraft()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2.weight(.semibold))
                        Text("Start New Blocking")
                            .font(.headline)
                        Spacer()
                    }
                    .appCardRow(verticalPadding: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

#if DEBUG
                AppCardDivider()

                Button {
                    isShowingDummyBlockedApp = true
                } label: {
                    DummyBlockedAppRow(title: "Preview Blocked App")
                        .appCardRow(verticalPadding: 14)
                }
                .buttonStyle(.plain)
#endif
            }
        }
#if DEBUG
        .sheet(isPresented: $isShowingDummyBlockedApp) {
            DummyBlockedAppPreviewView(group: firstGroup)
        }
#endif
        .sheet(item: $friendRequestGroup) { group in
            FriendApprovalRequestView(group: group)
        }
        .sheet(item: $newGroupDraft) { draft in
            NavigationStack {
                BlockGroupEditorView(initialDraft: draft) { group, password in
                    if model.upsertBlockGroup(group, password: password) {
                        newGroupDraft = nil
                    }
                }
            }
        }
    }

    private var modeMetricTitle: String {
        guard let firstGroup else {
            return "Mode"
        }

        switch firstGroup.mode {
        case .scheduled:
            return "Schedule"
        case .timeLimit:
            return "Limit"
        }
    }

    private var modeMetricValue: String {
        guard let firstGroup else {
            return "--"
        }

        switch firstGroup.mode {
        case .scheduled:
            return "On"
        case .timeLimit(let seconds, _):
            return BlockingDisplayFormatter.durationLabel(seconds)
        }
    }

    private func remainingUnblocks(for group: BlockGroup) -> Int {
        BlockingStateResolver.remainingUnblocks(for: group.id, in: model.blockingState)
    }

    private func unblockButton(_ title: String, seconds: TimeInterval, group: BlockGroup) -> some View {
        Button {
            _ = model.startLocalUnblock(groupID: group.id, seconds: seconds)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.64))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(remainingUnblocks(for: group) == 0 || seconds > group.unblockConfig.maxDurationSeconds)
        .opacity(remainingUnblocks(for: group) == 0 || seconds > group.unblockConfig.maxDurationSeconds ? 0.45 : 1)
    }
}

#if DEBUG
private struct DummyBlockedAppRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            DummyAppIcon(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("Developer preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.86), lineWidth: 0.7)
        }
    }
}

private struct DummyBlockedAppPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let group: BlockGroup?
    @State private var friendRequestGroup: BlockGroup?
    @State private var localStatus: String?

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                VStack(spacing: 18) {
                    DummyAppIcon(size: 74)

                    VStack(spacing: 8) {
                        Text("Dummy App is blocked")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 18)
                .padding(.bottom, 8)

                AppCard {
                    if let group {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: group.colorHex))
                                .frame(width: 12, height: 12)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.name)
                                    .font(.headline)
                                Text(group.mode.label)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .appCardRow()

                        if group.unblockConfig.isEnabled || group.friendRequestConfig.isEnabled {
                            AppCardDivider()
                            actionRows(for: group)
                        } else {
                            AppCardDivider()
                            Text("No unblock options are enabled for this group.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .appCardRow()
                        }
                    } else {
                        Text("Create a block group to connect this preview to real unblock and friend request settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .appCardRow()
                    }
                }

                if let localStatus {
                    Text(localStatus)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Blocked App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $friendRequestGroup) { group in
                FriendApprovalRequestView(group: group)
            }
        }
    }

    private var subtitle: String {
        guard let group else {
            return "This is a local preview of the blocked-app screen."
        }

        switch (group.unblockConfig.isEnabled, group.friendRequestConfig.isEnabled) {
        case (true, true):
            return "Open ScreenLog for a limited unblock or to request friend approval."
        case (true, false):
            return "Open ScreenLog for a limited unblock."
        case (false, true):
            return "Open ScreenLog to request friend approval."
        case (false, false):
            return "This group is blocked by your current ScreenLog settings."
        }
    }

    @ViewBuilder
    private func actionRows(for group: BlockGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if group.unblockConfig.isEnabled {
                VStack(alignment: .leading, spacing: 9) {
                    Text("\(remainingUnblocks(for: group)) limited unblocks left today")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        unblockButton("5m", seconds: 5 * 60, group: group)
                        unblockButton("15m", seconds: 15 * 60, group: group)
                        unblockButton("30m", seconds: 30 * 60, group: group)
                    }
                }
            }

            if group.friendRequestConfig.isEnabled {
                Button {
                    friendRequestGroup = group
                } label: {
                    Label("Request friend approval", systemImage: "person.2.badge.gearshape")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .appCardRow()
    }

    private func remainingUnblocks(for group: BlockGroup) -> Int {
        BlockingStateResolver.remainingUnblocks(for: group.id, in: model.blockingState)
    }

    private func unblockButton(_ title: String, seconds: TimeInterval, group: BlockGroup) -> some View {
        let isDisabled = remainingUnblocks(for: group) == 0 || seconds > group.unblockConfig.maxDurationSeconds

        return Button {
            if model.startLocalUnblock(groupID: group.id, seconds: seconds) {
                localStatus = "Dummy App would open for \(BlockingDisplayFormatter.durationLabel(seconds))."
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

private struct DummyAppIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.49, blue: 0.95),
                        Color(red: 0.08, green: 0.65, blue: 0.55),
                        Color(red: 0.96, green: 0.58, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(red: 0.08, green: 0.49, blue: 0.95).opacity(0.18), radius: 14, x: 0, y: 7)
    }
}
#endif

private struct FriendApprovalRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let group: BlockGroup
    @State private var requestedMinutes = 15
    @State private var selectedFriendIDs: Set<String> = []
    @State private var message = ""

    private var friends: [FriendChoice] {
        if model.friendSummaries.isEmpty {
            return [
                FriendChoice(id: "demo-sam", name: "Sam"),
                FriendChoice(id: "demo-maya", name: "Maya")
            ]
        }

        return model.friendSummaries.map { FriendChoice(id: $0.id, name: $0.displayName) }
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                AppSection("Request") {
                    AppCard {
                        Picker("Minutes", selection: $requestedMinutes) {
                            Text("5m").tag(5)
                            Text("15m").tag(15)
                            Text("30m").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .appCardRow()

                        AppCardDivider()

                        TextField("Message", text: $message, axis: .vertical)
                            .lineLimit(2...4)
                            .appCardRow()
                    }
                }

                AppSection("Friends") {
                    AppCard {
                        ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 {
                                AppCardDivider()
                            }
                            Button {
                                if selectedFriendIDs.contains(friend.id) {
                                    selectedFriendIDs.remove(friend.id)
                                } else {
                                    selectedFriendIDs.insert(friend.id)
                                }
                            } label: {
                                HStack {
                                    Text(friend.name)
                                    Spacer()
                                    Image(systemName: selectedFriendIDs.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedFriendIDs.contains(friend.id) ? Color.accentColor : Color.secondary)
                                }
                                .appCardRow()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Friend Approval")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        if model.requestFriendTime(
                            groupID: group.id,
                            seconds: TimeInterval(requestedMinutes * 60),
                            selectedFriendIDs: Array(selectedFriendIDs),
                            message: message
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(selectedFriendIDs.isEmpty)
                }
            }
        }
    }
}

private struct FriendChoice: Identifiable {
    let id: String
    let name: String
}

private struct SnapshotMetrics: View {
    let snapshot: DailyUsageSnapshot?

    var body: some View {
        HStack(spacing: 12) {
            MetricTile(title: "Today", value: UsageFormatting.duration(snapshot?.totalDuration))
            MetricTile(title: "Selected", value: UsageFormatting.duration(snapshot?.selectedAppDuration))
        }

        Text(UsageFormatting.lastUpdated(snapshot?.lastUpdated))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 0.7)
        }
    }
}
