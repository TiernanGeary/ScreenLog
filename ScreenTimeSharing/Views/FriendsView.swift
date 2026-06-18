import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum FriendLeaderboardMode: String, CaseIterable {
    case usage
    case requests

    var label: String {
        switch self {
        case .usage:
            return "Screen Time"
        case .requests:
            return "Requests"
        }
    }
}

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedLeaderboardMode: FriendLeaderboardMode = .usage
    @State private var isShowingShareSheet = false

    private var leaderboardEntries: [LeaderboardEntry] {
        switch selectedLeaderboardMode {
        case .usage:
            return model.usageLeaderboardEntries
        case .requests:
            return StatsBoardBuilder.mostExtraRequested(entries: model.leaderboardEntries)
        }
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Leaderboard") {
                    VStack(alignment: .leading, spacing: 10) {
                        FriendLeaderboardModeSelector(selection: $selectedLeaderboardMode)

                        FriendLeaderboardCard(entries: leaderboardEntries, mode: selectedLeaderboardMode)
                    }
                }

                AppSection("Friend Usage") {
                    if model.friendSummaries.isEmpty {
                        AppCard {
                            ContentUnavailableView(
                                "No Friends Yet",
                                systemImage: "person.2.slash",
                                description: Text("Invite a friend or accept their invite to start sharing requests.")
                            )
                            .appCardRow(verticalPadding: 16)
                        }
                    } else {
                        AppCard {
                            ForEach(Array(model.friendSummaries.enumerated()), id: \.element.id) { index, friend in
                                FriendSummaryRow(friend: friend)
                                    .appCardRow(verticalPadding: 8)

                                if index < model.friendSummaries.count - 1 {
                                    AppCardDivider()
                                }
                            }
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
            .sheet(isPresented: $isShowingShareSheet) {
                InviteFriendsSheet()
            }
        }
    }

    private func refreshFriends() async {
        await model.reloadFriends()
        await model.syncFriendRequests()
    }
}

private struct FriendLeaderboardModeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: FriendLeaderboardMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FriendLeaderboardMode.allCases, id: \.self) { mode in
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
}

private struct FriendLeaderboardCard: View {
    let entries: [LeaderboardEntry]
    let mode: FriendLeaderboardMode

    private var maxMetricSeconds: TimeInterval {
        entries
            .map { max(0, metricSeconds(for: $0)) }
            .max() ?? 0
    }

    private func metricSeconds(for entry: LeaderboardEntry) -> TimeInterval {
        switch mode {
        case .usage:
            return entry.usageSeconds ?? 0
        case .requests:
            return entry.requestedExtraSeconds
        }
    }

    private var emptyStateText: String {
        switch mode {
        case .usage:
            return "No friend stats yet"
        case .requests:
            return "No time requests today"
        }
    }

    var body: some View {
        AppCard {
            if entries.isEmpty {
                Text(emptyStateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                .appCardRow()
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    FriendLeaderboardRow(
                        rank: index + 1,
                        entry: entry,
                        metricSeconds: metricSeconds(for: entry),
                        maxMetricSeconds: maxMetricSeconds,
                        mode: mode
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
    let metricSeconds: TimeInterval
    let maxMetricSeconds: TimeInterval
    let mode: FriendLeaderboardMode

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

                    Text(
                        mode == .usage && entry.usageSeconds == nil
                            ? "--"
                            : UsageFormatting.duration(metricSeconds)
                    )
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                }

                FriendLeaderboardBar(
                    value: metricSeconds,
                    maxValue: maxMetricSeconds,
                    colorHex: entry.avatarColorHex
                )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
    }

    private var subtitle: String? {
        guard mode == .requests else {
            return nil
        }

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
                Text(friend.displayName)
                    .font(.headline)

                Label(
                    friend.totalDuration == nil ? "--" : UsageFormatting.duration(friend.totalDuration),
                    systemImage: "clock"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
