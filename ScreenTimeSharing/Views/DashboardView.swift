import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppCard(cornerRadius: 24, opacity: 0.74) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center) {
                            Avatar(colorHex: model.profile.avatarColorHex, initials: model.profile.initials)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.profile.displayName)
                                    .font(.title2.bold())
                                Text(model.screenTimeAuthorization)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        SnapshotMetrics(snapshot: model.localSnapshot)
                    }
                    .appCardRow(verticalPadding: 16)
                }

                AppSection("Setup") {
                    AppCard {
                        StatusLine(title: "Selected activities", value: "\(model.selectedActivityCount)")
                            .appCardRow()
                        AppCardDivider()
                        StatusLine(title: "iCloud", value: model.cloudAvailability.label)
                            .appCardRow()
                        AppCardDivider()
                        StatusLine(
                            title: "Capability",
                            value: model.localSnapshot.map { UsageFormatting.capabilityLabel($0.capability) } ?? "No snapshot yet"
                        )
                        .appCardRow()
                    }
                }

                AppCard {
                    Button {
                        isShowingActivityPicker = true
                    } label: {
                        Label("Choose Apps", systemImage: "app.badge")
                            .appCardRow()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)

                    AppCardDivider()

                    Button {
                        Task {
                            await model.requestScreenTimeAuthorization()
                        }
                    } label: {
                        Label("Authorize Screen Time", systemImage: "hourglass")
                            .appCardRow()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)

                    AppCardDivider()

                    Button {
                        Task {
                            await model.refreshAndPublish()
                        }
                    } label: {
                        Label("Refresh and Upload", systemImage: "arrow.clockwise")
                            .appCardRow()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(model.isWorking)
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
            .navigationTitle("Today")
            .overlay {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
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

private struct StatusLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
