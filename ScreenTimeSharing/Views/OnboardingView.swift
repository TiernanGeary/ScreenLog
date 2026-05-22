import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Screen Time Sharing")
                            .font(.largeTitle.bold())
                        Text("Share selected app usage with chosen friends. Nothing is uploaded until Screen Time, app selection, iCloud, and sharing are set up.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        ConsentRow(
                            icon: "checkmark.shield",
                            title: "Shared",
                            bodyText: "Display name, avatar color, today's total, selected-app total, and per-app rows only when Apple grants app detail access."
                        )
                        ConsentRow(
                            icon: "hand.raised",
                            title: "Not shared",
                            bodyText: "Unselected apps, notification contents, messages, web content, and any fake or estimated usage."
                        )
                        ConsentRow(
                            icon: "icloud",
                            title: "CloudKit only",
                            bodyText: "Friend access uses iCloud sharing records. There is no custom server in this beta."
                        )
                    }

                    VStack(spacing: 12) {
                        OnboardingActionRow(
                            title: "Screen Time",
                            value: model.screenTimeAuthorization,
                            systemImage: "hourglass",
                            actionTitle: "Authorize"
                        ) {
                            Task {
                                await model.requestScreenTimeAuthorization()
                            }
                        }

                        OnboardingActionRow(
                            title: "Selected activities",
                            value: "\(model.selectedActivityCount)",
                            systemImage: "app.badge",
                            actionTitle: "Choose"
                        ) {
                            isShowingActivityPicker = true
                        }

                        OnboardingActionRow(
                            title: "iCloud",
                            value: model.cloudAvailability.label,
                            systemImage: "person.crop.circle.badge.checkmark",
                            actionTitle: "Check"
                        ) {
                            Task {
                                await model.load()
                            }
                        }
                    }

                    Button {
                        AppHaptics.buttonTap()
                        model.completeOnboarding()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(20)
            }
            .background(AppBackground())
        }
    }
}

private struct ConsentRow: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 16, opacity: 0.72)
    }
}

private struct OnboardingActionRow: View {
    let title: String
    let value: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(actionTitle) {
                AppHaptics.buttonTap()
                action()
            }
                .buttonStyle(.bordered)
        }
        .padding(14)
        .appSurface(cornerRadius: 16, opacity: 0.74)
    }
}
