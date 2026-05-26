import FamilyControls
import ManagedSettings
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    private var engagementSummary: HomeEngagementSummary {
        HomeEngagementBuilder.summary(history: model.usageHistory)
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                TodayScreenTimeCard(
                    snapshot: model.localSnapshot,
                    usesLiveReport: model.hasScreenTimeAuthorization,
                    hasLoadedLiveReport: model.hasCompletedScreenTimeReport
                )

                if shouldShowHomeROICard(engagementSummary) {
                    HomeROICard(
                        summary: engagementSummary,
                        snapshot: model.localSnapshot
                    )
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                }

                AppSection("Blocking") {
                    BlockingOverviewCard()
                }

#if DEBUG
                AppSection("Developer Preview") {
                    BlockingDeveloperToolsCard()
                }
#endif

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
            .animation(.snappy(duration: 0.22), value: shouldShowHomeROICard(engagementSummary))
            .onAppear {
                model.reloadUsageHistoryFromSharedStorage()
            }
            .overlay {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
    }

    private func shouldShowHomeROICard(_ summary: HomeEngagementSummary) -> Bool {
        switch summary.baselineStatus {
        case .ready:
            return summary.comparisonDayCount > 0
        case .building, .unavailable:
            return false
        }
    }
}

private struct TodayScreenTimeCard: View {
    let snapshot: DailyUsageSnapshot?
    let usesLiveReport: Bool
    let hasLoadedLiveReport: Bool
    @State private var didReleaseLiveReportFallback = false

    private var topApps: [SharedAppUsage] {
        Array(
            (snapshot?.appRows ?? [])
                .sorted { lhs, rhs in
                    if lhs.duration != rhs.duration {
                        return lhs.duration > rhs.duration
                    }

                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                .prefix(8)
        )
    }

    var body: some View {
        if usesLiveReport {
            liveReportContent
        } else {
            fallbackContent
        }
    }

    private var liveReportContent: some View {
        ZStack {
            HomeCard(cornerRadius: 24) {
                ScreenTimeLiveTodayReport()
                    .frame(minHeight: 156)
                    .appCardRow(verticalPadding: 14)
            }
            .opacity(shouldShowLiveReport ? 1 : 0)
            .scaleEffect(shouldShowLiveReport ? 1 : 0.98)

            if !shouldShowLiveReport {
                TodaySummaryLoadingScroll()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.24), value: shouldShowLiveReport)
        .task(id: hasLoadedLiveReport) {
            await releaseLiveReportAfterFallbackDelayIfNeeded()
        }
        .onChange(of: hasLoadedLiveReport) { _, hasLoaded in
            if hasLoaded {
                didReleaseLiveReportFallback = true
            }
        }
    }

    private var fallbackContent: some View {
        HomeCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
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

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
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
            .appCardRow(verticalPadding: 18)
        }
    }

    private var shouldShowLiveReport: Bool {
        hasLoadedLiveReport || hasSnapshotData || didReleaseLiveReportFallback
    }

    private var hasSnapshotData: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.totalDuration != nil
            || snapshot.pickupCount != nil
            || !snapshot.appRows.isEmpty
    }

    private var pickupLabel: String {
        guard let pickupCount = snapshot?.pickupCount else {
            return "--"
        }

        return "\(pickupCount)"
    }

    private func releaseLiveReportAfterFallbackDelayIfNeeded() async {
        guard !shouldShowLiveReport else {
            return
        }

        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            didReleaseLiveReportFallback = true
        }
    }
}

private struct TodaySummaryLoadingScroll: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading today's Screen Time")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        TodayLoadingTile(width: index == 0 ? 176 : 148)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading today's Screen Time")
    }
}

private struct TodayLoadingTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(placeholderColor)
                .frame(width: width * 0.52, height: 11)

            Capsule()
                .fill(placeholderColor.opacity(0.82))
                .frame(width: width * 0.76, height: 28)

            Capsule()
                .fill(placeholderColor.opacity(0.68))
                .frame(width: width * 0.44, height: 10)
        }
        .frame(width: width, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: colorScheme == .dark ? .secondarySystemGroupedBackground : .systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.8)
                }
        )
    }

    private var placeholderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.11)
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
                .font(.system(size: 40, weight: .bold).monospacedDigit())
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
        HomeCard(cornerRadius: 26) {
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
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
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
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
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
                .font(.system(size: 40, weight: .bold))
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

private struct HomeCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
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
                .fill(Color(uiColor: colorScheme == .dark ? .secondarySystemGroupedBackground : .systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.86), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.055), radius: 22, x: 0, y: 10)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.035), radius: 14, x: 0, y: 7)
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
                usesWarmGradient: true
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
    var usesWarmGradient = false

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
            .foregroundStyle(primaryAccentStyle)
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
            .foregroundStyle(secondaryAccentStyle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: warmGlowColor, radius: usesWarmGradient ? 5 : 0, x: 0, y: 2)
    }

    private var primaryAccentStyle: AnyShapeStyle {
        if usesWarmGradient {
            return AnyShapeStyle(Self.warmGradient)
        }

        return AnyShapeStyle(accentColor)
    }

    private var secondaryAccentStyle: AnyShapeStyle {
        if usesWarmGradient {
            return AnyShapeStyle(Self.mutedWarmGradient)
        }

        return AnyShapeStyle(accentColor.opacity(0.78))
    }

    private var warmGlowColor: Color {
        usesWarmGradient ? Color(red: 1.0, green: 0.50, blue: 0.12).opacity(0.16) : .clear
    }

    private static var warmGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.24, blue: 0.14),
                Color(red: 1.0, green: 0.73, blue: 0.22)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static var mutedWarmGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.24, blue: 0.14).opacity(0.84),
                Color(red: 1.0, green: 0.73, blue: 0.22).opacity(0.84)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 0.7)
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
    @Environment(\.colorScheme) private var colorScheme
    let app: SharedAppUsage

    var body: some View {
        HStack(spacing: 10) {
            AppUsageIcon(
                name: app.displayName,
                applicationTokenData: app.applicationTokenData,
                showsContainer: false
            )

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
                .fill(tileBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tileBorder, lineWidth: 0.7)
        }
    }

    private var tileBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color.white.opacity(0.58)
    }

    private var tileBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82)
    }
}

private struct TopAppEmptyTile: View {
    @Environment(\.colorScheme) private var colorScheme
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
                .fill(tileBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tileBorder, lineWidth: 0.7)
        }
    }

    private var tileBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color.white.opacity(0.58)
    }

    private var tileBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82)
    }

    private var emptyTitle: String {
        if capability?.allowsPerAppRows == false {
            return "App detail unavailable"
        }

        return "No app detail yet"
    }

    private var emptySubtitle: String {
        capability?.reason ?? "Open apps, then refresh."
    }
}

private struct BlockingOverviewCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var newGroupDraft: BlockGroupDraft?
    @State private var viewedGroup: BlockGroup?
    @State private var unblockConfirmationGroup: BlockGroup?

    private var groups: [BlockGroup] {
        model.blockingState.groups
    }

    private var activeGroups: [BlockGroup] {
        groups.filter(\.isEnabled)
    }

    private var inactiveGroups: [BlockGroup] {
        groups.filter { !$0.isEnabled }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                AppCard {
                startBlockingButton
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !activeGroups.isEmpty {
                        blockGroupSection("Active", groups: activeGroups)
                    }

                    if !inactiveGroups.isEmpty {
                        blockGroupSection("Inactive", groups: inactiveGroups, isMuted: true)
                    }

                    AppCard {
                        HStack(spacing: 12) {
                            Button {
                                AppHaptics.buttonTap()
                                newGroupDraft = BlockGroupDraft()
                            } label: {
                                Label("New Group", systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        .appCardRow(verticalPadding: 14)
                    }
                }
            }
        }
        .sheet(item: $viewedGroup) { group in
            BlockGroupConfigurationView(groupID: group.id)
        }
        .sheet(item: $unblockConfirmationGroup) { group in
            UnblockConfirmationView(groupID: group.id)
        }
        .sheet(item: $newGroupDraft) { draft in
            NavigationStack {
                BlockGroupEditorView(initialDraft: draft) { group, password in
                    let didSave = model.upsertBlockGroup(group, password: password)
                    if didSave {
                        newGroupDraft = nil
                    }
                    return didSave
                }
            }
        }
    }

    private var startBlockingButton: some View {
        Button {
            AppHaptics.buttonTap()
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
    }

    private func blockGroupSection(
        _ title: String,
        groups: [BlockGroup],
        isMuted: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 18)

            AppCard {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        AppCardDivider()
                    }

                    blockGroupRow(group, isMuted: isMuted)
                }
            }
        }
    }

    private func blockGroupRow(_ group: BlockGroup, isMuted: Bool = false) -> some View {
        HStack(spacing: 12) {
            Button {
                openGroup(group)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(isMuted ? Color.secondary.opacity(0.36) : Color(hex: group.colorHex))
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(group.isEnabled ? "Blocking enabled" : "Blocking paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isMuted {
                unblockButton(for: group)
            }

            Button {
                openGroup(group)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(group.name) settings")
        }
        .appCardRow(verticalPadding: 12)
        .saturation(isMuted ? 0 : 1)
        .opacity(isMuted ? 0.62 : 1)
    }

    private func openGroup(_ group: BlockGroup) {
        AppHaptics.buttonTap()
        viewedGroup = group
    }

    private func unblockButton(for group: BlockGroup) -> some View {
        let totalUnblocks = group.unblockConfig.isEnabled ? group.unblockConfig.unblocksPerDay : 0
        let remainingUnblocks = BlockingStateResolver.remainingUnblocks(
            for: group.id,
            in: model.blockingState
        )
        let hasActiveUnblock = BlockingStateResolver.activeUnblockSessions(in: model.blockingState)
            .contains { $0.groupID == group.id }
        let isDisabled = totalUnblocks == 0 || remainingUnblocks == 0 || hasActiveUnblock

        return Button {
            AppHaptics.buttonTap()
            unblockConfirmationGroup = group
        } label: {
            Text("Unblock \(remainingUnblocks)/\(totalUnblocks)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isDisabled ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? Color.secondary : Color.accentColor)
        .disabled(isDisabled)
        .accessibilityLabel("Unblock \(group.name), \(remainingUnblocks) of \(totalUnblocks) left today")
    }

}

private struct UnblockConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let groupID: String

    private var group: BlockGroup? {
        model.blockingState.groups.first { $0.id == groupID }
    }

    private var selection: FamilyActivitySelection? {
        guard let group else {
            return nil
        }

        return try? BlockingSelectionCodec.decode(group.selectionData)
    }

    private var applicationTokens: [ApplicationToken] {
        Array(selection?.applicationTokens ?? [])
    }

    private var categoryTokens: [ActivityCategoryToken] {
        Array(selection?.categoryTokens ?? [])
    }

    private var webDomainTokens: [WebDomainToken] {
        Array(selection?.webDomainTokens ?? [])
    }

    private var hasSelectionItems: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                if let group {
                    header(for: group)

                    AppSection("Apps to Unblock") {
                        AppCard {
                            selectedItemsList
                        }
                    }

                    AppSection("Duration") {
                        AppCard {
                            durationRow(for: group)
                        }
                    }
                } else {
                    AppCard {
                        Text("This block group is no longer available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .appCardRow()
                    }
                }
            }
            .navigationTitle("Confirm Unblock")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let group {
                    bottomButton(for: group)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
        }
    }

    private func header(for group: BlockGroup) -> some View {
        AppCard(cornerRadius: 24, opacity: 0.78) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color(hex: group.colorHex))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "lock.open.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text("Stop blocking this group temporarily.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }
            .appCardRow(verticalPadding: 16)
        }
    }

    @ViewBuilder
    private var selectedItemsList: some View {
        if hasSelectionItems {
            VStack(spacing: 0) {
                ForEach(Array(applicationTokens.enumerated()), id: \.element) { index, token in
                    if index > 0 {
                        AppCardDivider()
                    }
                    tokenRow(token, fallbackTitle: "App", detail: "App")
                }

                ForEach(Array(categoryTokens.enumerated()), id: \.element) { index, token in
                    if !applicationTokens.isEmpty || index > 0 {
                        AppCardDivider()
                    }
                    tokenRow(token, fallbackTitle: "Category", detail: "Category")
                }

                ForEach(Array(webDomainTokens.enumerated()), id: \.element) { index, token in
                    if !applicationTokens.isEmpty || !categoryTokens.isEmpty || index > 0 {
                        AppCardDivider()
                    }
                    tokenRow(token, fallbackTitle: "Website", detail: "Website")
                }
            }
        } else {
            Label("No apps selected", systemImage: "app.badge")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .appCardRow()
        }
    }

    private func tokenRow(_ token: ApplicationToken, fallbackTitle: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 34, height: 34)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .appCardRow(verticalPadding: 11)
        .accessibilityLabel(fallbackTitle)
    }

    private func tokenRow(_ token: ActivityCategoryToken, fallbackTitle: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .appCardRow(verticalPadding: 11)
        .accessibilityLabel(fallbackTitle)
    }

    private func tokenRow(_ token: WebDomainToken, fallbackTitle: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .appCardRow(verticalPadding: 11)
        .accessibilityLabel(fallbackTitle)
    }

    private func durationRow(for group: BlockGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("Unblock duration")
                .font(.subheadline)

            Spacer(minLength: 12)

            Text(BlockingDisplayFormatter.fullDurationLabel(group.unblockConfig.maxDurationSeconds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .appCardRow(verticalPadding: 12)
    }

    private func bottomButton(for group: BlockGroup) -> some View {
        Button {
            if model.startLocalUnblock(groupID: group.id, seconds: group.unblockConfig.maxDurationSeconds) {
                AppHaptics.buttonTap()
                dismiss()
            } else {
                AppHaptics.selectionChanged()
            }
        } label: {
            Text("Stop Blocking")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

#if DEBUG
private struct BlockingDeveloperToolsCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingDummyBlockedApp = false

    private var firstGroup: BlockGroup? {
        model.blockingState.groups.first
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hammer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Debug-only tools")
                            .font(.subheadline.weight(.semibold))
                        Text("Hidden from release builds. Use this to preview the blocked-app screen in the simulator.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Button {
                    AppHaptics.buttonTap()
                    isShowingDummyBlockedApp = true
                } label: {
                    DummyBlockedAppRow(title: "Preview Blocked App")
                }
                .buttonStyle(.plain)
            }
            .appCardRow(verticalPadding: 14)
        }
        .sheet(isPresented: $isShowingDummyBlockedApp) {
            DummyBlockedAppPreviewView(group: firstGroup)
        }
    }
}

private struct DummyBlockedAppRow: View {
    @Environment(\.colorScheme) private var colorScheme
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
                .fill(rowBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: 0.7)
        }
    }

    private var rowBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color.white.opacity(0.58)
    }

    private var rowBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.86)
    }
}

private struct DummyBlockedAppPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let group: BlockGroup?
    @State private var friendRequestGroup: BlockGroup?

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                VStack(spacing: 18) {
                    DummyAppIcon(size: 74)

                    VStack(spacing: 8) {
                        Text("Restricted")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("You cannot use Dummy App because it is restricted.")
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
                    Button {
                        AppHaptics.buttonTap()
                        dismiss()
                    } label: {
                        Text("OK")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .appCardRow(verticalPadding: 10)

                    AppCardDivider()

                    friendRequestButton
                }
            }
            .navigationTitle("Blocked App")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $friendRequestGroup) { group in
                FriendApprovalRequestView(group: group)
            }
        }
    }

    @ViewBuilder
    private var friendRequestButton: some View {
        if let group, group.friendRequestConfig.isEnabled {
            Button {
                AppHaptics.buttonTap()
                friendRequestGroup = group
            } label: {
                Text("Request time from friends")
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
            .appCardRow(verticalPadding: 10)
        } else {
            Button {
            } label: {
                Text("Friend request disabled")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.gray.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(true)
            .appCardRow(verticalPadding: 10)
        }
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

private enum FriendApprovalRequestStep {
    case capture
    case review
    case details
}

struct FriendApprovalRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let group: BlockGroup
    @State private var requestStep: FriendApprovalRequestStep = .capture
    @State private var requestedMinutes = 15
    @State private var isShowingMinutePicker = false
    @State private var selectedFriendIDs: Set<String> = []
    @State private var selectedPhotoData: Data?
    @State private var message = ""

    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]

    private var friends: [FriendChoice] {
        #if DEBUG && targetEnvironment(simulator)
        if model.friendSummaries.isEmpty {
            return [
                FriendChoice(id: "demo-sam", name: "Sam", avatarColorHex: "#1B998B"),
                FriendChoice(id: "demo-maya", name: "Maya", avatarColorHex: "#E84855")
            ]
        }
        #endif

        return model.friendSummaries.map {
            FriendChoice(id: $0.id, name: $0.displayName, avatarColorHex: $0.avatarColorHex)
        }
    }

    var body: some View {
        NavigationStack {
            requestStepContent
                .navigationTitle(navigationTitle)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingMinutePicker) {
                NavigationStack {
                    RequestMinuteCarouselPicker(minutes: $requestedMinutes, options: minuteOptions)
                        .navigationTitle("Minutes")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var navigationTitle: String {
        switch requestStep {
        case .capture:
            return "Take Pleading Photo"
        case .review:
            return "Photo"
        case .details:
            return "Request Time"
        }
    }

    private var canSendRequest: Bool {
        !selectedFriendIDs.isEmpty && selectedPhotoData != nil
    }

    @ViewBuilder
    private var requestStepContent: some View {
        switch requestStep {
        case .capture:
            captureStep
        case .review:
            reviewStep
        case .details:
            detailsStep
        }
    }

    @ViewBuilder
    private var captureStep: some View {
        #if canImport(UIKit)
        FriendRequestCameraCaptureView { image in
            acceptCapturedPhoto(image)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        #else
        AppScreenScroll(backgroundStyle: .white) {
            AppCard {
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera.fill",
                    description: Text("Photo requests need camera access on an iPhone.")
                )
                .appCardRow(verticalPadding: 24)
            }
        }
        #endif
    }

    @ViewBuilder
    private var reviewStep: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if let selectedPhotoData, let image = requestImage(from: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            } else {
                AppCard {
                    ContentUnavailableView(
                        "Photo Not Ready",
                        systemImage: "camera.fill",
                        description: Text("Retake the photo to continue.")
                    )
                    .appCardRow(verticalPadding: 24)
                }
            }
        }
    }

    private var detailsStep: some View {
        AppScreenScroll(backgroundStyle: .white) {
            AppSection("Photo") {
                AppCard {
                    compactPhotoPreview
                        .appCardRow(verticalPadding: 12)
                }
            }

            AppSection("Request") {
                AppCard {
                    Button {
                        AppHaptics.buttonTap()
                        isShowingMinutePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(RequestMinuteFormatting.label(requestedMinutes))
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .appCardRow()
                    }
                    .buttonStyle(.plain)

                    AppCardDivider()

                    TextField("Optional message", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                        .appCardRow()
                }
            }

            AppSection("Friends") {
                AppCard {
                    if friends.isEmpty {
                        ContentUnavailableView(
                            "No Friends Yet",
                            systemImage: "person.2.slash",
                            description: Text("Invite a friend before sending a time request.")
                        )
                        .appCardRow(verticalPadding: 16)
                    } else {
                        ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 {
                                AppCardDivider()
                            }
                            Button {
                                AppHaptics.selectionChanged()
                                if selectedFriendIDs.contains(friend.id) {
                                    selectedFriendIDs.remove(friend.id)
                                } else {
                                    selectedFriendIDs.insert(friend.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(colorHex: friend.avatarColorHex, initials: friend.name.initials)
                                        .frame(width: 44, height: 44)

                                    Text(friend.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)

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
        }
    }

    @ViewBuilder
    private var compactPhotoPreview: some View {
        HStack(spacing: 12) {
            if let selectedPhotoData, let image = requestImage(from: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 62, height: 78)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pleading photo")
                    .font(.subheadline.weight(.semibold))
                Text("Included with this request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Retake") {
                returnToCamera()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch requestStep {
        case .capture:
            EmptyView()
        case .review:
            reviewButtons
        case .details:
            sendButton
        }
    }

    private var reviewButtons: some View {
        HStack(spacing: 12) {
            Button {
                returnToCamera()
            } label: {
                Text("Retake")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }

            Button {
                AppHaptics.buttonTap()
                requestStep = .details
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor)
            }
            .disabled(selectedPhotoData == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private var sendButton: some View {
        VStack(spacing: 0) {
            Button {
                sendRequest()
            } label: {
                Text("Send Request")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSendRequest ? Color.white : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(canSendRequest ? Color.accentColor : Color.secondary.opacity(0.18))
            }
            .disabled(!canSendRequest)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func sendRequest() {
        guard canSendRequest else {
            return
        }

        if model.requestFriendTime(
            groupID: group.id,
            seconds: TimeInterval(requestedMinutes * 60),
            selectedFriendIDs: Array(selectedFriendIDs),
            message: message,
            photoJPEGData: selectedPhotoData
        ) {
            AppHaptics.buttonTap()
            dismiss()
        }
    }

    #if canImport(UIKit)
    private func acceptCapturedPhoto(_ image: UIImage) {
        if let data = image.requestPhotoJPEGData() {
            selectedPhotoData = data
            requestStep = .review
            AppHaptics.buttonTap()
        } else {
            model.message = "Could not prepare that photo."
        }
    }

    private func returnToCamera() {
        AppHaptics.buttonTap()
        selectedPhotoData = nil
        requestStep = .capture
    }

    private func requestImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
    #else
    private func returnToCamera() {
        model.message = "Camera is unavailable on this device."
    }
    #endif
}

private struct FriendChoice: Identifiable {
    let id: String
    let name: String
    let avatarColorHex: String
}

#if canImport(UIKit)
private struct FriendRequestCameraCaptureView: UIViewControllerRepresentable {
    let showsCloseButton: Bool
    let onCancel: (() -> Void)?
    let onImage: (UIImage) -> Void

    init(
        showsCloseButton: Bool = false,
        onCancel: (() -> Void)? = nil,
        onImage: @escaping (UIImage) -> Void
    ) {
        self.showsCloseButton = showsCloseButton
        self.onCancel = onCancel
        self.onImage = onImage
    }

    func makeUIViewController(context: Context) -> FriendRequestCameraViewController {
        FriendRequestCameraViewController(
            showsCloseButton: showsCloseButton,
            onCapture: { image in
                onImage(image)
            },
            onCancel: {
                onCancel?()
            }
        )
    }

    func updateUIViewController(_ uiViewController: FriendRequestCameraViewController, context: Context) {}
}

private final class FriendRequestBeautyRenderer: @unchecked Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let detector = CIDetector(
        ofType: CIDetectorTypeFace,
        context: nil,
        options: [CIDetectorAccuracy: CIDetectorAccuracyLow]
    )
    private let lock = NSLock()
    private var cachedFaceRect: CGRect?

    func retouchedImage(from image: UIImage) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }

        guard let input = CIImage(image: image) else {
            return nil
        }

        let orientedInput = input.oriented(forExifOrientation: Int32(image.imageOrientation.cgImagePropertyOrientation.rawValue))
        let previousFaceRect = cachedFaceRect
        cachedFaceRect = nil
        let output = subtlyRetouchedImage(orientedInput, shouldRefreshFace: true)
        cachedFaceRect = previousFaceRect

        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private func subtlyRetouchedImage(_ image: CIImage, shouldRefreshFace: Bool) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image
        }

        if shouldRefreshFace {
            cachedFaceRect = largestFaceRect(in: image)
        }

        guard let faceRect = cachedFaceRect else {
            return image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: 0.006,
                    kCIInputSaturationKey: 1.01,
                    kCIInputContrastKey: 0.995
                ]
            )
        }

        let smoothed = image
            .applyingFilter(
                "CINoiseReduction",
                parameters: [
                    "inputNoiseLevel": 0.038,
                    "inputSharpness": 0.34
                ]
            )
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: 0.012,
                    kCIInputSaturationKey: 1.018,
                    kCIInputContrastKey: 0.988
                ]
            )

        let mask = faceBlendMask(for: faceRect, in: extent)
        return smoothed
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: mask
                ]
            )
            .cropped(to: extent)
    }

    private func largestFaceRect(in image: CIImage) -> CGRect? {
        let faces = detector?
            .features(in: image)
            .compactMap { feature -> CGRect? in
                guard let face = feature as? CIFaceFeature else {
                    return nil
                }

                return face.bounds
            } ?? []

        return faces.max { first, second in
            first.width * first.height < second.width * second.height
        }
    }

    private func faceBlendMask(for faceRect: CGRect, in extent: CGRect) -> CIImage {
        let expandedFaceRect = faceRect.insetBy(dx: -faceRect.width * 0.22, dy: -faceRect.height * 0.16)
        let center = CGPoint(x: expandedFaceRect.midX, y: expandedFaceRect.midY)
        let innerRadius = max(expandedFaceRect.width, expandedFaceRect.height) * 0.22
        let outerRadius = max(expandedFaceRect.width, expandedFaceRect.height) * 0.68
        let mask = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: center.x, y: center.y),
                "inputRadius0": innerRadius,
                "inputRadius1": outerRadius,
                "inputColor0": CIColor(red: 0.48, green: 0.48, blue: 0.48, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            ]
        )?.outputImage

        return (mask ?? CIImage(color: .black)).cropped(to: extent)
    }
}

private final class FriendRequestCameraViewController: UIViewController, @preconcurrency AVCapturePhotoCaptureDelegate {
    private let onCapture: (UIImage) -> Void
    private let onCancel: (() -> Void)?
    private let showsCloseButton: Bool
    private let selfieLightIdleAlpha: CGFloat = 0.72
    private let selfieLightCaptureAlpha: CGFloat = 0.92
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private lazy var beautyRenderer = FriendRequestBeautyRenderer()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var activeInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .front
    private var isConfigured = false
    private var isCaptureInFlight = false
    private var isSelfieLightEnabled = false
    private var brightnessBeforeSelfieLight: CGFloat?
    private var capturePreviewAspectRatio: CGFloat?

    private let previewView = UIView()
    private let closeButton = UIButton(type: .system)
    private let selfieLightButton = UIButton(type: .system)
    private let selfieLightOverlayView = UIView()
    private let flipButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .custom)
    private let shutterInnerView = UIView()
    private let unavailableView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let unavailableTitleLabel = UILabel()
    private let unavailableDetailLabel = UILabel()
    private let focusRingView = UIView()

    init(
        showsCloseButton: Bool,
        onCapture: @escaping (UIImage) -> Void,
        onCancel: (() -> Void)?
    ) {
        self.showsCloseButton = showsCloseButton
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
        requestAccessAndConfigureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreSelfieLight()
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureInterface() {
        view.backgroundColor = .black

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.backgroundColor = .black
        previewView.clipsToBounds = true
        view.addSubview(previewView)

        selfieLightOverlayView.translatesAutoresizingMaskIntoConstraints = false
        selfieLightOverlayView.backgroundColor = .white
        selfieLightOverlayView.alpha = 0
        selfieLightOverlayView.isUserInteractionEnabled = false
        view.addSubview(selfieLightOverlayView)

        configureRoundIconButton(closeButton, systemName: "xmark", pointSize: 18)
        closeButton.isHidden = !showsCloseButton
        closeButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        view.addSubview(closeButton)

        configureRoundIconButton(selfieLightButton, systemName: "bolt.slash.fill", pointSize: 20)
        selfieLightButton.addTarget(self, action: #selector(toggleSelfieLight), for: .touchUpInside)
        view.addSubview(selfieLightButton)

        configureRoundIconButton(flipButton, systemName: "arrow.triangle.2.circlepath.camera", pointSize: 21)
        flipButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        view.addSubview(flipButton)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        shutterButton.layer.cornerRadius = 42
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.layer.borderWidth = 5
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)

        shutterInnerView.translatesAutoresizingMaskIntoConstraints = false
        shutterInnerView.backgroundColor = .white
        shutterInnerView.isUserInteractionEnabled = false
        shutterInnerView.layer.cornerRadius = 28
        shutterButton.addSubview(shutterInnerView)

        unavailableView.translatesAutoresizingMaskIntoConstraints = false
        unavailableView.layer.cornerRadius = 22
        unavailableView.clipsToBounds = true
        unavailableView.isHidden = true
        view.addSubview(unavailableView)

        unavailableTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        unavailableTitleLabel.font = .preferredFont(forTextStyle: .headline)
        unavailableTitleLabel.textColor = .white
        unavailableTitleLabel.textAlignment = .center
        unavailableView.contentView.addSubview(unavailableTitleLabel)

        unavailableDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        unavailableDetailLabel.font = .preferredFont(forTextStyle: .footnote)
        unavailableDetailLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        unavailableDetailLabel.textAlignment = .center
        unavailableDetailLabel.numberOfLines = 3
        unavailableView.contentView.addSubview(unavailableDetailLabel)

        focusRingView.frame = CGRect(x: 0, y: 0, width: 78, height: 78)
        focusRingView.layer.borderColor = UIColor.white.cgColor
        focusRingView.layer.borderWidth = 1.5
        focusRingView.layer.cornerRadius = 39
        focusRingView.alpha = 0
        focusRingView.isUserInteractionEnabled = false
        previewView.addSubview(focusRingView)

        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focusPreview(_:)))
        previewView.addGestureRecognizer(focusTap)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            selfieLightOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selfieLightOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selfieLightOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            selfieLightOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 46),
            closeButton.heightAnchor.constraint(equalToConstant: 46),

            selfieLightButton.trailingAnchor.constraint(equalTo: flipButton.leadingAnchor, constant: -12),
            selfieLightButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            selfieLightButton.widthAnchor.constraint(equalToConstant: 46),
            selfieLightButton.heightAnchor.constraint(equalToConstant: 46),

            flipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            flipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            flipButton.widthAnchor.constraint(equalToConstant: 46),
            flipButton.heightAnchor.constraint(equalToConstant: 46),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutterButton.widthAnchor.constraint(equalToConstant: 84),
            shutterButton.heightAnchor.constraint(equalToConstant: 84),

            shutterInnerView.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            shutterInnerView.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            shutterInnerView.widthAnchor.constraint(equalToConstant: 56),
            shutterInnerView.heightAnchor.constraint(equalToConstant: 56),

            unavailableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unavailableView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            unavailableView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            unavailableView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            unavailableView.widthAnchor.constraint(lessThanOrEqualToConstant: 320),

            unavailableTitleLabel.topAnchor.constraint(equalTo: unavailableView.contentView.topAnchor, constant: 22),
            unavailableTitleLabel.leadingAnchor.constraint(equalTo: unavailableView.contentView.leadingAnchor, constant: 20),
            unavailableTitleLabel.trailingAnchor.constraint(equalTo: unavailableView.contentView.trailingAnchor, constant: -20),

            unavailableDetailLabel.topAnchor.constraint(equalTo: unavailableTitleLabel.bottomAnchor, constant: 8),
            unavailableDetailLabel.leadingAnchor.constraint(equalTo: unavailableView.contentView.leadingAnchor, constant: 20),
            unavailableDetailLabel.trailingAnchor.constraint(equalTo: unavailableView.contentView.trailingAnchor, constant: -20),
            unavailableDetailLabel.bottomAnchor.constraint(equalTo: unavailableView.contentView.bottomAnchor, constant: -22)
        ])
    }

    private func configureRoundIconButton(_ button: UIButton, systemName: String, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        button.layer.cornerRadius = 23
        button.layer.borderWidth = 0.8
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor

        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: configuration), for: .normal)
    }

    private func updateSelfieLightButton() {
        let isFrontCamera = currentPosition == .front
        selfieLightButton.isHidden = !isFrontCamera
        selfieLightButton.isEnabled = isFrontCamera && !isCaptureInFlight

        let imageName = isSelfieLightEnabled ? "bolt.fill" : "bolt.slash.fill"
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        selfieLightButton.setImage(UIImage(systemName: imageName, withConfiguration: configuration), for: .normal)
        selfieLightButton.backgroundColor = isSelfieLightEnabled
            ? UIColor.white.withAlphaComponent(0.84)
            : UIColor.black.withAlphaComponent(0.34)
        selfieLightButton.tintColor = isSelfieLightEnabled ? .black : .white
    }

    private func requestAccessAndConfigureCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera(position: currentPosition)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] isGranted in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    if isGranted {
                        self.configureCamera(position: self.currentPosition)
                    } else {
                        self.showUnavailable(
                            title: "Camera Access Off",
                            detail: "Enable camera access to send a photo request."
                        )
                    }
                }
            }
        case .denied, .restricted:
            showUnavailable(
                title: "Camera Access Off",
                detail: "Enable camera access to send a photo request."
            )
        @unknown default:
            showUnavailable(
                title: "Camera Unavailable",
                detail: "Try again after reopening the app."
            )
        }
    }

    private func configureCamera(position: AVCaptureDevice.Position) {
        do {
            try configureSession(position: position)
            if !session.isRunning {
                session.startRunning()
            }

            attachPreviewRendererIfNeeded()
            setCaptureControlsEnabled(true)
            updateSelfieLightButton()
            unavailableView.isHidden = true
        } catch {
            showUnavailable(
                title: "Camera Unavailable",
                detail: "This device cannot start a camera preview."
            )
        }
    }

    private func configureSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let activeInput {
            session.removeInput(activeInput)
        }

        guard let device = cameraDevice(position: position) else {
            session.commitConfiguration()
            throw FriendRequestCameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw FriendRequestCameraError.cannotAddInput
        }

        session.addInput(input)
        activeInput = input
        currentPosition = position

        if !isConfigured {
            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw FriendRequestCameraError.cannotAddOutput
            }

            session.addOutput(photoOutput)

            isConfigured = true
        }

        session.commitConfiguration()
        updateOutputConnections()
    }

    private func attachPreviewRendererIfNeeded() {
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewView.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
        }

        previewLayer?.frame = previewView.bounds
        updateOutputConnections()
    }

    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func showUnavailable(title: String, detail: String) {
        unavailableTitleLabel.text = title
        unavailableDetailLabel.text = detail
        unavailableView.isHidden = false
        setCaptureControlsEnabled(false)
    }

    private func setCaptureControlsEnabled(_ isEnabled: Bool) {
        shutterButton.isEnabled = isEnabled
        flipButton.isEnabled = isEnabled
        selfieLightButton.isEnabled = isEnabled && currentPosition == .front
        shutterButton.alpha = isEnabled ? 1 : 0.38
        flipButton.alpha = isEnabled ? 1 : 0.38
        selfieLightButton.alpha = isEnabled ? 1 : 0.38
    }

    private func updateOutputConnections() {
        configureVideoConnection(previewLayer?.connection)
        configureVideoConnection(photoOutput.connection(with: .video))
        updateSelfieLightButton()
    }

    private func configureVideoConnection(_ connection: AVCaptureConnection?) {
        guard let connection else {
            return
        }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = currentPosition == .front
        }
    }

    @objc private func cancelCapture() {
        onCancel?()
    }

    @objc private func switchCamera() {
        guard !isCaptureInFlight else {
            return
        }

        AppHaptics.selectionChanged()
        let nextPosition: AVCaptureDevice.Position = currentPosition == .front ? .back : .front
        if nextPosition != .front {
            isSelfieLightEnabled = false
            restoreSelfieLight()
        }
        configureCamera(position: nextPosition)
    }

    @objc private func toggleSelfieLight() {
        guard currentPosition == .front, !isCaptureInFlight else {
            return
        }

        AppHaptics.selectionChanged()
        isSelfieLightEnabled.toggle()
        updateSelfieLightButton()
        if isSelfieLightEnabled {
            turnOnSelfieLight()
        } else {
            restoreSelfieLight()
        }
    }

    @objc private func capturePhoto() {
        guard !isCaptureInFlight, isConfigured else {
            return
        }

        capturePreviewAspectRatio = currentPreviewAspectRatio()
        isCaptureInFlight = true
        setCaptureControlsEnabled(false)
        UIView.animate(withDuration: 0.10, animations: {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }, completion: { _ in
            UIView.animate(withDuration: 0.14) {
                self.shutterButton.transform = .identity
            }
        })

        if currentPosition == .front, isSelfieLightEnabled {
            prepareSelfieLightForCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.performPhotoCapture()
            }
        } else {
            performPhotoCapture()
        }
    }

    private func performPhotoCapture() {
        let settings = AVCapturePhotoSettings()
        if let connection = photoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = currentPosition == .front
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func turnOnSelfieLight() {
        if brightnessBeforeSelfieLight == nil {
            brightnessBeforeSelfieLight = UIScreen.main.brightness
        }

        UIScreen.main.brightness = 1
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            self.selfieLightOverlayView.alpha = self.selfieLightIdleAlpha
        }
    }

    private func prepareSelfieLightForCapture() {
        if brightnessBeforeSelfieLight == nil {
            brightnessBeforeSelfieLight = UIScreen.main.brightness
        }

        UIScreen.main.brightness = 1
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            self.selfieLightOverlayView.alpha = self.selfieLightCaptureAlpha
        }
    }

    private func restoreSelfieLight() {
        if let brightnessBeforeSelfieLight {
            UIScreen.main.brightness = brightnessBeforeSelfieLight
            self.brightnessBeforeSelfieLight = nil
        }

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
            self.selfieLightOverlayView.alpha = 0
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        {
            let retouchedImage = beautyRenderer.retouchedImage(from: image) ?? image
            let finalImage = retouchedImage.croppedToFillAspectRatio(capturePreviewAspectRatio) ?? retouchedImage
            DispatchQueue.main.async {
                self.restoreSelfieLight()
                self.onCapture(finalImage)
            }
            return
        }

        DispatchQueue.main.async {
            self.restoreSelfieLight()
            self.isCaptureInFlight = false
            self.setCaptureControlsEnabled(true)
            self.updateSelfieLightButton()
            self.showUnavailable(
                title: "Photo Failed",
                detail: "Try taking the photo again."
            )
        }
    }

    private func currentPreviewAspectRatio() -> CGFloat? {
        let size = previewView.bounds.size
        guard size.width > 1, size.height > 1 else {
            return nil
        }

        return size.width / size.height
    }

    @objc private func focusPreview(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: previewView)
        animateFocusRing(at: point)

        guard let previewLayer, let device = activeInput?.device else {
            return
        }

        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            return
        }
    }

    private func animateFocusRing(at point: CGPoint) {
        focusRingView.center = point
        focusRingView.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.focusRingView.alpha = 1
            self.focusRingView.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.24, delay: 0.28, options: [.curveEaseIn]) {
                self.focusRingView.alpha = 0
            }
        }
    }

    private enum FriendRequestCameraError: Error {
        case noCamera
        case cannotAddInput
        case cannotAddOutput
    }
}

private extension UIImage.Orientation {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch self {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}

private extension UIImage {
    func croppedToFillAspectRatio(_ targetAspectRatio: CGFloat?) -> UIImage? {
        guard let targetAspectRatio,
              targetAspectRatio > 0,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let source = normalizedForDrawing()
        let sourceAspectRatio = source.size.width / source.size.height
        guard abs(sourceAspectRatio - targetAspectRatio) > 0.01 else {
            return source
        }

        var cropRect = CGRect(origin: .zero, size: source.size)
        if sourceAspectRatio > targetAspectRatio {
            cropRect.size.width = source.size.height * targetAspectRatio
            cropRect.origin.x = (source.size.width - cropRect.size.width) / 2
        } else {
            cropRect.size.height = source.size.width / targetAspectRatio
            cropRect.origin.y = (source.size.height - cropRect.size.height) / 2
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = source.scale
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        return renderer.image { _ in
            source.draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
        }
    }

    private func normalizedForDrawing() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func requestPhotoJPEGData(maxPixel: CGFloat = 1_400, compressionQuality: CGFloat = 0.82) -> Data? {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxPixel else {
            return jpegData(compressionQuality: compressionQuality)
        }

        let scale = maxPixel / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}
#endif

private struct RequestMinuteCarouselPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var minutes: Int
    let options: [Int]

    var body: some View {
        VStack(spacing: 14) {
            Picker("Minutes", selection: $minutes) {
                ForEach(options, id: \.self) { option in
                    Text(RequestMinuteFormatting.label(option))
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 210)
            .clipped()
            .onChange(of: minutes) {
                AppHaptics.selectionChanged()
            }
        }
        .padding(.horizontal, 24)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    AppHaptics.buttonTap()
                    dismiss()
                }
            }
        }
    }
}

private enum RequestMinuteFormatting {
    static func label(_ minutes: Int) -> String {
        "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
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
    @Environment(\.colorScheme) private var colorScheme
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
                .fill(tileBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tileBorder, lineWidth: 0.7)
        }
    }

    private var tileBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color.white.opacity(0.58)
    }

    private var tileBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82)
    }
}
