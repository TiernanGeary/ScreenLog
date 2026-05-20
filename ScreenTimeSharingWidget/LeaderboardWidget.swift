import SwiftUI
import WidgetKit

struct LeaderboardWidgetEntry: TimelineEntry {
    let date: Date
    let generatedAt: Date?
    let entries: [LeaderboardEntry]
}

struct LeaderboardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LeaderboardWidgetEntry {
        LeaderboardWidgetEntry(
            date: Date(),
            generatedAt: Date(),
            entries: [
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
                    lastUpdated: Date()
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
                    lastUpdated: Date()
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LeaderboardWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LeaderboardWidgetEntry>) -> Void) {
        completion(
            Timeline(
                entries: [entry()],
                policy: .after(Date().addingTimeInterval(30 * 60))
            )
        )
    }

    private func entry() -> LeaderboardWidgetEntry {
        let payload = WidgetCacheReader.payload()
        return LeaderboardWidgetEntry(
            date: Date(),
            generatedAt: payload?.generatedAt,
            entries: payload?.leaderboardEntries ?? []
        )
    }
}

struct LeaderboardWidget: Widget {
    let kind = "LeaderboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LeaderboardTimelineProvider()) { entry in
            LeaderboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Extra Time Board")
        .description("Ranks your group by least extra screen time requested.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct LeaderboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LeaderboardWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.entries.isEmpty {
                emptyState
            } else {
                header
                rows
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack {
            Text("Extra Time")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Text(UsageFormatting.lastUpdated(entry.generatedAt, now: entry.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            ForEach(Array(entry.entries.prefix(rowLimit).enumerated()), id: \.element.id) { index, item in
                LeaderboardWidgetRow(rank: index + 1, entry: item, compact: family == .systemSmall)
            }
        }
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 4
        default:
            return 6
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "trophy")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No requests yet")
                .font(.headline)
            Text("Open ScreenLog to start a group.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LeaderboardWidgetRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)

            Circle()
                .fill(Color(hex: entry.avatarColorHex))
                .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                .overlay {
                    Text(entry.displayName.initials)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(compact ? .caption.bold() : .subheadline.bold())
                    .lineLimit(1)
                Text("\(entry.requestCount) asks · \(entry.currentStreakDays)d streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(UsageFormatting.duration(entry.requestedExtraSeconds))
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
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
