import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppCard {
                    Picker("Window", selection: leaderboardWindowBinding) {
                        ForEach(LeaderboardWindow.allCases, id: \.self) { window in
                            Text(window.label).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .appCardRow(verticalPadding: 10)
                }

                if model.leaderboardEntries.isEmpty {
                    AppCard {
                        ContentUnavailableView(
                            "No Requests Yet",
                            systemImage: "trophy",
                            description: Text("Extra-time requests will rank here from least to most requested.")
                        )
                        .appCardRow(verticalPadding: 12)

                        #if DEBUG
                        AppCardDivider()

                        Button {
                            model.seedDemoFriends()
                        } label: {
                            Label("Add Demo Leaderboard", systemImage: "person.3.sequence")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        #endif
                    }
                } else {
                    AppSection("Least Extra Time Requested") {
                        AppCard {
                            ForEach(Array(model.leaderboardEntries.enumerated()), id: \.element.id) { index, entry in
                                LeaderboardRow(rank: index + 1, entry: entry)
                                    .appCardRow(verticalPadding: 8)

                                if index < model.leaderboardEntries.count - 1 {
                                    AppCardDivider()
                                }
                            }
                        }
                    }

                    AppSection("Scoring") {
                        AppCard {
                            Label("Lower requested time ranks higher.", systemImage: "arrow.down.circle")
                                .appCardRow()
                            AppCardDivider()
                            Label("Emergency unlocks break ties.", systemImage: "exclamationmark.triangle")
                                .appCardRow()
                            AppCardDivider()
                            Label("Streaks reward staying under limit.", systemImage: "flame")
                                .appCardRow()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Leaderboard")
        }
    }

    private var leaderboardWindowBinding: Binding<LeaderboardWindow> {
        Binding(
            get: { model.leaderboardWindow },
            set: { model.setLeaderboardWindow($0) }
        )
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            Avatar(colorHex: entry.avatarColorHex, initials: entry.displayName.initials)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(UsageFormatting.duration(entry.requestedExtraSeconds))
                        .font(.headline.monospacedDigit())
                }

                HStack(spacing: 12) {
                    Label("\(entry.requestCount) asks", systemImage: "hand.raised")
                    Label("\(entry.currentStreakDays)d streak", systemImage: "flame")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if entry.emergencyUnlockCount > 0 || entry.deniedCount > 0 {
                    HStack(spacing: 12) {
                        if entry.emergencyUnlockCount > 0 {
                            Label("\(entry.emergencyUnlockCount) emergency", systemImage: "exclamationmark.triangle")
                        }

                        if entry.deniedCount > 0 {
                            Label("\(entry.deniedCount) denied", systemImage: "xmark.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
