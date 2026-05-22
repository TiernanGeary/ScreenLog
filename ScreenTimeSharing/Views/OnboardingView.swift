import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool

    @State private var currentPage: Int = 0

    private let lastPage = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    WelcomePage().tag(0)
                    HowItWorksPage().tag(1)
                    PrivacyPage().tag(2)
                    SetupPage(isShowingActivityPicker: $isShowingActivityPicker).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                pageIndicator
                    .padding(.top, 8)

                primaryButton
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
            }
            .toolbar {
                if currentPage < lastPage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") {
                            withAnimation { currentPage = lastPage }
                        }
                    }
                }
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0...lastPage, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == currentPage ? 22 : 8, height: 8)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            if currentPage < lastPage {
                withAnimation { currentPage += 1 }
            } else {
                model.completeOnboarding()
            }
        } label: {
            Label(
                currentPage < lastPage ? "Continue" : "Get Started",
                systemImage: "arrow.right"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 110, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Welcome to ScreenLog")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("Share what you're spending time on — with the friends you choose.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct HowItWorksPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works")
                        .font(.largeTitle.bold())
                    Text("Three quick ideas before you set things up.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 16) {
                    FeatureRow(
                        icon: "checklist",
                        title: "You pick what counts",
                        bodyText: "Choose the apps, categories, and websites you want to share. Everything else stays private."
                    )

                    FeatureRow(
                        icon: "person.2.fill",
                        title: "Friends see your totals",
                        bodyText: "Today's screen time and per-app rows show up on your friends' dashboards and home-screen widgets."
                    )

                    FeatureRow(
                        icon: "icloud.fill",
                        title: "Powered by iCloud sharing",
                        bodyText: "Sharing rides on your iCloud account. No custom server, no accounts to create."
                    )
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct PrivacyPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your privacy")
                        .font(.largeTitle.bold())
                    Text("Nothing is uploaded until you finish setup and pick what to share.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    ConsentRow(
                        icon: "checkmark.shield.fill",
                        tint: .green,
                        title: "Shared",
                        bodyText: "Display name, avatar color, today's total, your selected-app total, and per-app rows when Apple grants detail access."
                    )

                    ConsentRow(
                        icon: "hand.raised.fill",
                        tint: .orange,
                        title: "Not shared",
                        bodyText: "Unselected apps, notification contents, messages, web content, and any fake or estimated usage."
                    )

                    ConsentRow(
                        icon: "icloud.fill",
                        tint: .blue,
                        title: "CloudKit only",
                        bodyText: "Friend access uses iCloud sharing records. There is no custom server in this beta."
                    )
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct SetupPage: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set things up")
                        .font(.largeTitle.bold())
                    Text("Grant permissions and choose what to share. You can change these any time in Settings.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    OnboardingActionRow(
                        title: "Screen Time",
                        value: model.screenTimeAuthorization,
                        systemImage: "hourglass",
                        actionTitle: "Authorize"
                    ) {
                        Task { await model.requestScreenTimeAuthorization() }
                    }

                    OnboardingActionRow(
                        title: "Selected activities",
                        value: "\(model.selectedActivityCount) selected",
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
                        Task { await model.load() }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Reusable rows

private struct FeatureRow: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConsentRow: View {
    let icon: String
    let tint: Color
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
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
                Text(title).font(.headline)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
