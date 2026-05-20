import SwiftUI
import WidgetKit

struct FriendUsageEntry: TimelineEntry {
    let date: Date
    let friends: [FriendUsageSummary]
    let cacheDate: Date?
    let configuration: WidgetFriendConfigurationIntent
}

struct FriendUsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FriendUsageEntry {
        FriendUsageEntry(
            date: Date(),
            friends: [
                FriendUsageSummary(
                    id: "placeholder",
                    displayName: "Friend",
                    avatarColorHex: "#1B998B",
                    totalDuration: 7_200,
                    selectedAppDuration: 1_800,
                    capability: .aggregateOnly(),
                    lastUpdated: Date(),
                    isStale: false
                )
            ],
            cacheDate: Date(),
            configuration: WidgetFriendConfigurationIntent()
        )
    }

    func snapshot(for configuration: WidgetFriendConfigurationIntent, in context: Context) async -> FriendUsageEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: WidgetFriendConfigurationIntent, in context: Context) async -> Timeline<FriendUsageEntry> {
        Timeline(
            entries: [entry(for: configuration)],
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
    }

    private func entry(for configuration: WidgetFriendConfigurationIntent) -> FriendUsageEntry {
        let payload = WidgetCacheReader.payload()
        let selectedIDs = configuration.selectedFriendIDs
        let selectedFriends: [FriendUsageSummary]

        if selectedIDs.isEmpty {
            selectedFriends = Array(payload?.friends.prefix(4) ?? [])
        } else {
            selectedFriends = payload?.friends.filter { selectedIDs.contains($0.id) } ?? []
        }

        return FriendUsageEntry(
            date: Date(),
            friends: selectedFriends,
            cacheDate: payload?.generatedAt,
            configuration: configuration
        )
    }
}

struct FriendUsageWidget: Widget {
    let kind = "FriendUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetFriendConfigurationIntent.self,
            provider: FriendUsageTimelineProvider()
        ) { entry in
            FriendUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Friend Screen Time")
        .description("Compact friend cards for shared Screen Time snapshots.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct FriendUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FriendUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.friends.isEmpty {
                EmptyWidgetState()
            } else {
                header
                friendsGrid
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack {
            Text("Friends")
                .font(.headline)
            Spacer()
            Text(UsageFormatting.lastUpdated(entry.cacheDate, now: entry.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var friendsGrid: some View {
        let columns = family == .systemLarge ? 2 : 1
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(entry.friends.prefix(friendLimit)) { friend in
                FriendWidgetCard(friend: friend, compact: family == .systemSmall)
            }
        }
    }

    private var friendLimit: Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        default:
            return 4
        }
    }
}

private struct FriendWidgetCard: View {
    let friend: FriendUsageSummary
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: friend.avatarColorHex))
                .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
                .overlay {
                    Text(friend.displayName.initials)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(friend.displayName)
                        .font(compact ? .caption.bold() : .subheadline.bold())
                        .lineLimit(1)
                    if friend.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Text("Total \(UsageFormatting.duration(friend.totalDuration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(selectedLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectedLine: String {
        switch friend.capability.status {
        case .fullAppDetail:
            return "Selected \(UsageFormatting.duration(friend.selectedAppDuration))"
        case .aggregateOnly:
            return "Selected \(UsageFormatting.duration(friend.selectedAppDuration))"
        case .unavailable:
            return "Screen Time unavailable"
        }
    }
}

private struct EmptyWidgetState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.2.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open app to choose friends")
                .font(.headline)
                .lineLimit(2)
            Text("Accepted shares appear here after the app refreshes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

private extension String {
    var initials: String {
        let parts = split(separator: " ")
        let characters = parts.prefix(2).compactMap { $0.first }
        if characters.isEmpty, let first {
            return String(first).uppercased()
        }
        return String(characters).uppercased()
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
