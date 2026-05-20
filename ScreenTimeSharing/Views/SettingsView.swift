import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool
    @State private var isShowingShareSheet = false

    private let avatarColors = ["#1B998B", "#2E86AB", "#E84855", "#6A4C93", "#F18F01", "#2F4858"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField(
                        "Display name",
                        text: Binding(
                            get: { model.profile.displayName },
                            set: { model.updateProfile(displayName: $0) }
                        )
                    )

                    HStack {
                        Text("Avatar color")
                        Spacer()
                        ForEach(avatarColors, id: \.self) { color in
                            Button {
                                model.updateProfile(avatarColorHex: color)
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if color == model.profile.avatarColorHex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use color \(color)")
                        }
                    }
                }

                Section("Sharing") {
                    Button {
                        isShowingShareSheet = true
                    } label: {
                        Label("Invite Friends", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isShowingActivityPicker = true
                    } label: {
                        Label("Change Selected Apps", systemImage: "app.badge")
                    }
                }

                Section("Readiness") {
                    LabeledContent("Screen Time", value: model.screenTimeAuthorization)
                    LabeledContent("iCloud", value: model.cloudAvailability.label)
                    LabeledContent("Widget cache", value: "\(model.friendSummaries.count) friends")
                }

                #if DEBUG
                Section("Simulator Demo") {
                    Button {
                        model.seedDemoFriends()
                    } label: {
                        Label("Add Demo Friends", systemImage: "person.2.badge.plus")
                    }

                    Button(role: .destructive) {
                        model.clearDemoFriends()
                    } label: {
                        Label("Clear Demo Friends", systemImage: "trash")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $isShowingShareSheet) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
        }
    }
}
