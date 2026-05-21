import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool
    @State private var isShowingShareSheet = false
    var onShowActivityPicker: (() -> Void)?
    var onShowBlockingActivityPicker: (() -> Void)?

    private let avatarColors = ["#1B998B", "#2E86AB", "#E84855", "#6A4C93", "#F18F01", "#2F4858"]

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                AppSection("Profile") {
                    AppCard {
                        TextField(
                            "Display name",
                            text: Binding(
                                get: { model.profile.displayName },
                                set: { model.updateProfile(displayName: $0) }
                            )
                        )
                        .appCardRow()

                        AppCardDivider()

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
                        .appCardRow()
                    }
                }

                AppSection("Sharing") {
                    AppCard {
                        Button {
                            isShowingShareSheet = true
                        } label: {
                            Label("Invite Friends", systemImage: "square.and.arrow.up")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        AppCardDivider()

                        Button {
                            if let onShowActivityPicker {
                                onShowActivityPicker()
                            } else {
                                isShowingActivityPicker = true
                            }
                        } label: {
                            Label("Change Selected Apps", systemImage: "app.badge")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }

                AppSection("Blocking") {
                    AppCard {
                        NavigationLink {
                            BlockingSettingsView(onShowBlockingActivityPicker: onShowBlockingActivityPicker)
                        } label: {
                            Label("Manage Block Groups", systemImage: "lock.shield")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }

                AppSection("Readiness") {
                    AppCard {
                        LabeledContent("Screen Time", value: model.screenTimeAuthorization)
                            .appCardRow()
                        AppCardDivider()
                        LabeledContent("iCloud", value: model.cloudAvailability.label)
                            .appCardRow()
                        AppCardDivider()
                        LabeledContent("Widget cache", value: "\(model.friendSummaries.count) friends")
                            .appCardRow()
                    }
                }

                #if DEBUG
                AppSection("Simulator Demo") {
                    AppCard {
                        Button {
                            model.seedDemoScreenTime()
                        } label: {
                            Label("Add Demo Screen Time", systemImage: "iphone.gen3")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        AppCardDivider()

                        Button {
                            model.seedDemoFriends()
                        } label: {
                            Label("Add Demo Friends", systemImage: "person.2.badge.plus")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        AppCardDivider()

                        Button(role: .destructive) {
                            model.clearDemoFriends()
                        } label: {
                            Label("Clear Demo Friends", systemImage: "trash")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
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
