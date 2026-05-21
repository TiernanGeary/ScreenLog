import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool
    @Binding var isShowingBlockingActivityPicker: Bool
    @Binding var isShowingSettings: Bool

    var body: some View {
        NavigationStack {
            AppScreenScroll {
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

private struct HomeROICard: View {
    let summary: HomeEngagementSummary
    let snapshot: DailyUsageSnapshot?

    var body: some View {
        AppCard(cornerRadius: 26, opacity: 0.78) {
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
                Text("Time won back")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 9) {
                    Text(UsageFormatting.duration(abs(summary.netSavedDuration)))
                        .font(.system(size: 46, weight: .black, design: .default).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    Text(summary.netSavedDuration >= 0 ? "won back" : "over baseline")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(summary.netSavedDuration >= 0 ? Color.accentColor : Color(red: 0.86, green: 0.24, blue: 0.22))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

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

            HStack(alignment: .top, spacing: 12) {
                HomeProofMetric(
                    title: "Today",
                    value: UsageFormatting.duration(snapshot?.totalDuration),
                    systemImage: "iphone"
                )
                HomeProofMetric(
                    title: "Pickups",
                    value: pickupLabel,
                    systemImage: "hand.tap"
                )
            }
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

private struct HomeProofRow: View {
    let summary: HomeEngagementSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HomeProofMetric(
                title: "Screen time",
                value: percentLabel(summary.screenTimePercentChange),
                systemImage: "iphone"
            )
            HomeProofMetric(
                title: "Pickups",
                value: percentLabel(summary.pickupPercentChange),
                systemImage: "hand.tap"
            )
            HomeProofMetric(
                title: "Streak",
                value: dayLabel(summary.beatBaselineStreakDays),
                systemImage: "flame"
            )
        }
    }

    private func percentLabel(_ percent: Double?) -> String {
        guard let percent else {
            return "No data"
        }

        let rounded = Int(abs(percent).rounded())
        if percent >= 0 {
            return "\(rounded)% down"
        }

        return "\(rounded)% up"
    }

    private func dayLabel(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}

private struct HomeProofMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
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
            .foregroundStyle(.secondary)
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
            }
        }
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
