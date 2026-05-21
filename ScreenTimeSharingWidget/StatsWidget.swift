import SwiftUI
import WidgetKit

struct StatsWidgetEntry: TimelineEntry {
    let date: Date
    let generatedAt: Date?
    let currentUserID: String?
    let entries: [LeaderboardEntry]
}

struct StatsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsWidgetEntry {
        let now = Date()
        return StatsWidgetEntry(
            date: now,
            generatedAt: now,
            currentUserID: "you",
            entries: [
                LeaderboardEntry(
                    id: "you",
                    userID: "you",
                    displayName: "You",
                    avatarColorHex: "#6A4C93",
                    requestedExtraSeconds: 15 * 60,
                    approvedExtraSeconds: 15 * 60,
                    requestCount: 1,
                    deniedCount: 0,
                    emergencyUnlockCount: 0,
                    settingsResetCount: 0,
                    currentStreakDays: 2,
                    lastUpdated: now
                ),
                LeaderboardEntry(
                    id: "maya",
                    userID: "maya",
                    displayName: "Maya",
                    avatarColorHex: "#E84855",
                    requestedExtraSeconds: 0,
                    approvedExtraSeconds: 0,
                    requestCount: 0,
                    deniedCount: 0,
                    emergencyUnlockCount: 0,
                    settingsResetCount: 0,
                    currentStreakDays: 5,
                    lastUpdated: now
                ),
                LeaderboardEntry(
                    id: "sam",
                    userID: "sam",
                    displayName: "Sam",
                    avatarColorHex: "#1B998B",
                    requestedExtraSeconds: 10 * 60,
                    approvedExtraSeconds: 10 * 60,
                    requestCount: 1,
                    deniedCount: 0,
                    emergencyUnlockCount: 0,
                    settingsResetCount: 0,
                    currentStreakDays: 3,
                    lastUpdated: now
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsWidgetEntry>) -> Void) {
        completion(
            Timeline(
                entries: [entry()],
                policy: .after(Date().addingTimeInterval(30 * 60))
            )
        )
    }

    private func entry() -> StatsWidgetEntry {
        let payload = WidgetCacheReader.payload()
        return StatsWidgetEntry(
            date: Date(),
            generatedAt: payload?.generatedAt,
            currentUserID: payload?.currentUserID,
            entries: payload?.leaderboardEntries ?? []
        )
    }
}

struct StatsWidget: Widget {
    let kind = "StatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsTimelineProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Stats")
        .description("Shows your weekly extra-time stats and friend boards.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct StatsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatsWidgetEntry

    private var currentEntry: LeaderboardEntry? {
        guard let currentUserID = entry.currentUserID else {
            return nil
        }

        return StatsBoardBuilder.entry(for: currentUserID, in: entry.entries)
    }

    private var friendEntries: [LeaderboardEntry] {
        guard let currentUserID = entry.currentUserID else {
            return entry.entries
        }

        return entry.entries.filter { $0.userID != currentUserID }
    }

    private var bestControlEntries: [LeaderboardEntry] {
        StatsBoardBuilder.bestControl(entries: friendEntries)
    }

    private var mostExtraEntries: [LeaderboardEntry] {
        StatsBoardBuilder.mostExtraRequested(entries: friendEntries)
    }

    var body: some View {
        Group {
            if entry.entries.isEmpty {
                emptyState
            } else {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    mediumView
                default:
                    largeView
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PersonalWidgetStats(entry: currentEntry)
            Spacer(minLength: 0)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            PersonalWidgetStats(entry: currentEntry, compact: true)
            Divider()
            board(title: "Best Control", entries: Array(bestControlEntries.prefix(2)), metric: .bestControl)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PersonalWidgetStats(entry: currentEntry, compact: true)
            Divider()
            board(title: "Best Control", entries: Array(bestControlEntries.prefix(3)), metric: .bestControl)
            Divider()
            board(title: "Most Extra", entries: Array(mostExtraEntries.prefix(3)), metric: .mostExtraRequested)
        }
    }

    private var header: some View {
        HStack {
            Text("Stats")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Text(UsageFormatting.lastUpdated(entry.generatedAt, now: entry.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func board(title: String, entries: [LeaderboardEntry], metric: StatsWidgetBoardMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("No friend stats yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                    StatsWidgetRow(rank: index + 1, entry: item, metric: metric)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No stats yet")
                .font(.headline)
            Text("Open ScreenLog to start accountability.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PersonalWidgetStats: View {
    let entry: LeaderboardEntry?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            Text("This Week")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(UsageFormatting.duration(entry?.requestedExtraSeconds))
                .font(compact ? .headline.bold().monospacedDigit() : .title.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(entry?.requestCount ?? 0) asks · \(entry?.currentStreakDays ?? 0)d streak")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private enum StatsWidgetBoardMetric {
    case bestControl
    case mostExtraRequested
}

private struct StatsWidgetRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let metric: StatsWidgetBoardMetric

    var body: some View {
        HStack(spacing: 7) {
            Text("\(rank)")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .leading)

            Circle()
                .fill(Color(hex: entry.avatarColorHex))
                .frame(width: 20, height: 20)
                .overlay {
                    Text(entry.displayName.initials)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(UsageFormatting.duration(entry.requestedExtraSeconds))
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var subtitle: String {
        switch metric {
        case .bestControl:
            return "\(entry.requestCount) asks · \(entry.currentStreakDays)d"
        case .mostExtraRequested:
            return "\(entry.requestCount) asks"
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
