import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingSettings: Bool

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                if model.friendSummaries.isEmpty {
                    AppCard {
                        ContentUnavailableView(
                            "No Friends Yet",
                            systemImage: "person.2.slash",
                            description: Text("Accept a CloudKit share or invite a friend from Settings.")
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

                AppCard {
                    Button {
                        Task {
                            await model.reloadFriends()
                        }
                    } label: {
                        Label("Refresh Friends", systemImage: "arrow.clockwise")
                            .appCardRow()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .navigationTitle("Friends")
            .settingsToolbar(isShowingSettings: $isShowingSettings)
        }
    }
}

struct FriendSummaryRow: View {
    let friend: FriendUsageSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(colorHex: friend.avatarColorHex, initials: friend.displayName.initials)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(friend.displayName)
                        .font(.headline)

                    if friend.isStale {
                        Text("Stale")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 12) {
                    Label(UsageFormatting.duration(friend.totalDuration), systemImage: "clock")
                    Label(UsageFormatting.duration(friend.selectedAppDuration), systemImage: "app")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text("\(UsageFormatting.capabilityLabel(friend.capability)) · \(UsageFormatting.lastUpdated(friend.lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}
