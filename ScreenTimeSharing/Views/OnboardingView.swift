import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    @State private var currentPage: Int = 0

    private let pages: [OnboardingPageContent] = [
        OnboardingPageContent(
            icon: "sparkles",
            title: "Welcome to Sharely",
            subtitle: "Share less screen. Live more real."
        ),
        OnboardingPageContent(
            icon: "bird.fill",
            title: "Free yourself from your screens",
            subtitle: "Reclaim your hours. Sharely helps you set limits that actually hold."
        ),
        OnboardingPageContent(
            icon: "person.2.fill",
            title: "Do it yourself, or hand it off",
            subtitle: "Manage your own screen time — or give a trusted friend the keys to keep you honest."
        ),
        OnboardingPageContent(
            icon: "camera.fill",
            title: "Earn it back",
            subtitle: "Send a picture to a friend to unlock an app. Embrace your real life."
        )
    ]

    private var lastPage: Int { pages.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPage(content: page, isActive: currentPage == index)
                            .tag(index)
                    }
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
            Text(currentPage < lastPage ? "Continue" : "Let's get started")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

private struct OnboardingPageContent {
    let icon: String
    let title: String
    let subtitle: String
}

private struct OnboardingPage: View {
    let content: OnboardingPageContent
    let isActive: Bool

    @State private var entered = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                Image(systemName: content.icon)
                    .font(.system(size: 110, weight: .light))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .nonRepeating, value: entered)
                    .phaseAnimator([1.0, 1.06]) { view, phase in
                        view.scaleEffect(phase)
                    } animation: { _ in
                        .easeInOut(duration: 1.6)
                    }
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(content.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.15), value: entered)

                    Text(content.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            guard nowActive else {
                entered = false
                return
            }

            entered = false
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }
}
