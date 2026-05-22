import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.friendSummaries.isEmpty {
                    ContentUnavailableView(
                        "No Friends Yet",
                        systemImage: "person.2.slash",
                        description: Text("Accept a CloudKit share or invite a friend from Settings.")
                    )
                } else {
                    Section {
                        ForEach(model.friendSummaries) { friend in
                            FriendSummaryRow(friend: friend)
                        }
                    }
                }

                Section {
                    Button {
                        Haptics.tap()
                        Task {
                            await model.reloadFriends()
                        }
                    } label: {
                        Label("Refresh Friends", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Friends")
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
