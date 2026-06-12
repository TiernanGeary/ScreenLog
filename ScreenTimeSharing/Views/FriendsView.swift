import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("friends.boardMode") private var boardMode: FriendBoardMode = .activity
    @AppStorage("friends.leaderboardWindow") private var selectedLeaderboardWindow: LeaderboardWindow = .week
    @State private var isShowingShareSheet = false

    private var leaderboardEntries: [LeaderboardEntry] {
        let friendEntries = model.leaderboardEntries.filter { $0.userID != model.profile.id }
        return StatsBoardBuilder.mostExtraRequested(entries: friendEntries)
    }

    private var activityRows: [FriendUsageSummary] {
        FriendBoardBuilder.activityRows(model.friendSummaries)
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Friends") {
                    VStack(alignment: .leading, spacing: 10) {
                        syncStatusRow

                        FriendBoardModePicker(selection: $boardMode)

                        if boardMode == .leaderboard {
                            FriendLeaderboardWindowSelector(selection: $selectedLeaderboardWindow)

                            FriendLeaderboardCard(entries: leaderboardEntries)
                        } else {
                            activityCard
                        }
                    }
                }
            }
            .refreshable {
                AppHaptics.selectionChanged()
                await refreshFriends()
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.buttonTap()
                        isShowingShareSheet = true
                    } label: {
                        Label("Invite Friends", systemImage: "person.crop.circle.badge.plus")
                    }
                    .accessibilityLabel("Invite Friends")
                }
            }
            .onAppear {
                model.setLeaderboardWindow(selectedLeaderboardWindow)
            }
            .onChange(of: selectedLeaderboardWindow) { _, newWindow in
                model.setLeaderboardWindow(newWindow)
            }
            .sheet(isPresented: $isShowingShareSheet) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
        }
    }

    private var syncStatusRow: some View {
        HStack(spacing: 8) {
            Text(UsageFormatting.lastUpdated(model.friendsLastSyncedAt))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                AppHaptics.buttonTap()
                Task { await refreshFriends() }
            } label: {
                if model.isSyncingFriends {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isSyncingFriends)
            .accessibilityLabel("Sync friends now")
        }
    }

    private var activityCard: some View {
        AppCard {
            if activityRows.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2.slash",
                    description: Text("Invite a friend or accept their invite to start sharing requests.")
                )
                .appCardRow(verticalPadding: 16)
            } else {
                ForEach(Array(activityRows.enumerated()), id: \.element.id) { index, friend in
                    FriendSummaryRow(friend: friend)
                        .appCardRow(verticalPadding: 8)

                    if index < activityRows.count - 1 {
                        AppCardDivider()
                    }
                }
            }
        }
    }

    private func refreshFriends() async {
        await model.reloadFriends()
        await model.syncFriendRequests()
    }
}

private enum FriendBoardMode: String, CaseIterable {
    case activity
    case leaderboard

    var label: String {
        switch self {
        case .activity:
            return "Activity"
        case .leaderboard:
            return "Leaderboard"
        }
    }
}

private struct FriendBoardModePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: FriendBoardMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FriendBoardMode.allCases, id: \.self) { mode in
                Button {
                    if selection != mode {
                        AppHaptics.selectionChanged()
                    }
                    selection = mode
                } label: {
                    Text(mode.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(selection == mode ? .white : .primary)
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selected-friend-board-mode", in: namespace)
                                    .shadow(color: Color.blue.opacity(0.18), radius: 7, x: 0, y: 3)
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

private extension FriendFreshness {
    var indicatorColor: Color {
        switch self {
        case .fresh:
            return .green
        case .aging:
            return .yellow
        case .stale:
            return .orange
        case .missing:
            return Color.secondary
        }
    }
}

private struct FriendLeaderboardWindowSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: LeaderboardWindow
    @Namespace private var namespace

    private let visibleWindows: [LeaderboardWindow] = [.week, .allTime]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleWindows, id: \.self) { window in
                Button {
                    if selection != window {
                        AppHaptics.selectionChanged()
                    }
                    selection = window
                } label: {
                    Text(shortLabel(for: window))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(selection == window ? .white : .primary)
                        .background {
                            if selection == window {
                                Capsule()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selected-leaderboard-window", in: namespace)
                                    .shadow(color: Color.blue.opacity(0.18), radius: 7, x: 0, y: 3)
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

    private func shortLabel(for window: LeaderboardWindow) -> String {
        switch window {
        case .today:
            return "Today"
        case .week:
            return "This Week"
        case .month:
            return "Month"
        case .allTime:
            return "All"
        }
    }
}

private struct FriendLeaderboardCard: View {
    let entries: [LeaderboardEntry]

    private var maxRequestedExtraSeconds: TimeInterval {
        entries
            .map { max(0, $0.requestedExtraSeconds) }
            .max() ?? 0
    }

    var body: some View {
        AppCard {
            if entries.isEmpty {
                Text("No friend stats yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .appCardRow()
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    FriendLeaderboardRow(
                        rank: index + 1,
                        entry: entry,
                        maxRequestedExtraSeconds: maxRequestedExtraSeconds
                    )
                    .appCardRow(verticalPadding: 10)

                    if index < entries.count - 1 {
                        AppCardDivider()
                    }
                }
            }
        }
    }
}

private struct FriendLeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let maxRequestedExtraSeconds: TimeInterval

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 40, alignment: .center)

            ProfileAvatar(
                imageData: entry.avatarImageData,
                colorHex: entry.avatarColorHex,
                initials: entry.displayName.initials,
                size: 40
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(UsageFormatting.duration(entry.requestedExtraSeconds))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                FriendLeaderboardBar(
                    value: entry.requestedExtraSeconds,
                    maxValue: maxRequestedExtraSeconds,
                    colorHex: entry.avatarColorHex
                )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let lastUpdated = entry.lastUpdated {
                    Text(UsageFormatting.lastUpdated(lastUpdated))
                        .font(.caption2)
                        .foregroundStyle(FriendFreshness.tier(lastUpdated: lastUpdated).indicatorColor)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [entry.requestCount == 1 ? "1 request" : "\(entry.requestCount) requests"]

        if entry.approvedExtraSeconds > 0 {
            parts.append("\(UsageFormatting.duration(entry.approvedExtraSeconds)) approved")
        }

        if entry.deniedCount > 0 {
            parts.append(entry.deniedCount == 1 ? "1 denied" : "\(entry.deniedCount) denied")
        }

        return parts.joined(separator: " · ")
    }
}

private struct FriendLeaderboardBar: View {
    let value: TimeInterval
    let maxValue: TimeInterval
    let colorHex: String

    private var progress: CGFloat {
        guard maxValue > 0 else {
            return 0
        }

        return min(1, max(0, value / maxValue))
    }

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))

                if fillWidth > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: colorHex),
                                    Color(hex: colorHex).opacity(0.68)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, fillWidth))
                }
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Requested extra time")
        .accessibilityValue(UsageFormatting.duration(value))
    }
}

struct FriendSummaryRow: View {
    let friend: FriendUsageSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProfileAvatar(
                imageData: friend.avatarImageData,
                colorHex: friend.avatarColorHex,
                initials: friend.displayName.initials,
                size: 44
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(friend.displayName)
                        .font(.headline)

                    Spacer(minLength: 8)

                    Text(UsageFormatting.lastUpdated(friend.lastUpdated))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FriendFreshness.tier(lastUpdated: friend.lastUpdated).indicatorColor)
                }

                HStack(spacing: 12) {
                    Label(UsageFormatting.duration(friend.totalDuration), systemImage: "clock")
                    Label(UsageFormatting.duration(friend.selectedAppDuration), systemImage: "app")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
