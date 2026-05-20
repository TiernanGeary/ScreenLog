import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    .padding(.vertical, 6)
                }

                Section("Setup") {
                    StatusLine(title: "Selected activities", value: "\(model.selectedActivityCount)")
                    StatusLine(title: "iCloud", value: model.cloudAvailability.label)
                    StatusLine(
                        title: "Capability",
                        value: model.localSnapshot.map { UsageFormatting.capabilityLabel($0.capability) } ?? "No snapshot yet"
                    )
                }

                Section {
                    Button {
                        isShowingActivityPicker = true
                    } label: {
                        Label("Choose Apps", systemImage: "app.badge")
                    }

                    Button {
                        Task {
                            await model.requestScreenTimeAuthorization()
                        }
                    } label: {
                        Label("Authorize Screen Time", systemImage: "hourglass")
                    }

                    Button {
                        Task {
                            await model.refreshAndPublish()
                        }
                    } label: {
                        Label("Refresh and Upload", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isWorking)
                }

                if let message = model.message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
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
