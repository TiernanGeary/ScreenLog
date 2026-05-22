import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool
    @Binding var isShowingBlockingActivityPicker: Bool

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
                        isShowingBlockingActivityPicker: $isShowingBlockingActivityPicker
                    )
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
        capability?.reason ?? "Refresh after selecting apps."
    }
}

private struct BlockingOverviewCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingBlockingActivityPicker: Bool
    @State private var newGroupDraft: BlockGroupDraft?
    @State private var viewedGroup: BlockGroup?
    @State private var isShowingBlockingSettings = false

    private var groups: [BlockGroup] {
        model.blockingState.groups
    }

    var body: some View {
        AppCard {
            if groups.isEmpty {
                startBlockingButton
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        AppCardDivider()
                    }

                    Button {
                        AppHaptics.buttonTap()
                        viewedGroup = group
                    } label: {
                        blockGroupRow(group)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                AppCardDivider()

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

                    Spacer()

                    Button {
                        AppHaptics.buttonTap()
                        isShowingBlockingSettings = true
                    } label: {
                        Label("Manage", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                .appCardRow(verticalPadding: 14)
            }
        }
        .sheet(isPresented: $isShowingBlockingSettings) {
            NavigationStack {
                BlockingSettingsView(onShowBlockingActivityPicker: {
                    isShowingBlockingSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isShowingBlockingActivityPicker = true
                    }
                })
            }
        }
        .sheet(item: $viewedGroup) { group in
            BlockGroupConfigurationView(groupID: group.id)
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

    private func blockGroupRow(_ group: BlockGroup) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: group.colorHex))
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

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .appCardRow(verticalPadding: 12)
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

struct FriendApprovalRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let group: BlockGroup
    @State private var requestedMinutes = 15
    @State private var isShowingMinutePicker = false
    @State private var selectedFriendIDs: Set<String> = []
    @State private var message = ""

    private let minuteOptions = [5, 10, 15, 20, 30, 45, 60]

    private var friends: [FriendChoice] {
        if model.friendSummaries.isEmpty {
            return [
                FriendChoice(id: "demo-sam", name: "Sam", avatarColorHex: "#1B998B"),
                FriendChoice(id: "demo-maya", name: "Maya", avatarColorHex: "#E84855")
            ]
        }

        return model.friendSummaries.map {
            FriendChoice(id: $0.id, name: $0.displayName, avatarColorHex: $0.avatarColorHex)
        }
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
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
            .navigationTitle("Request Time")
            .safeAreaInset(edge: .bottom) {
                sendButton
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

    private var canSendRequest: Bool {
        !selectedFriendIDs.isEmpty
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
            message: message
        ) {
            AppHaptics.buttonTap()
            dismiss()
        }
    }
}

private struct FriendChoice: Identifiable {
    let id: String
    let name: String
    let avatarColorHex: String
}

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
