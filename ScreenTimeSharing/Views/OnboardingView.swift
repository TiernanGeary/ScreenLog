import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    @State private var currentPage: Int = 0
    @State private var age: Double = 25
    @State private var avgScreenTime: Double = 4
    @State private var isAuthorizing = false

    private let totalPages = 5
    private var lastPage: Int { totalPages - 1 }

    private var primaryTitle: String {
        switch currentPage {
        case lastPage: return "Let's Get Started!"
        case 2: return "Get Started"
        default: return "Continue"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    TabView(selection: $currentPage) {
                        AgeSliderPage(age: $age, isActive: currentPage == 0).tag(0)
                        ScreenTimeSliderPage(hours: $avgScreenTime, isActive: currentPage == 1).tag(1)
                        WastedTimePage(screenTimeHours: avgScreenTime, isActive: currentPage == 2).tag(2)
                        FriendMonitorPage(isActive: currentPage == 3).tag(3)
                        FinalPage(isActive: currentPage == 4).tag(4)
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
            }
            .toolbar {
                if currentPage < lastPage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") {
                            Haptics.tap()
                            withAnimation { currentPage = lastPage }
                        }
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .disabled(isAuthorizing)
            .overlay {
                if isAuthorizing {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0...lastPage, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == currentPage ? 18 : 6, height: 6)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }

    private var primaryButton: some View {
        Button {
            if currentPage < lastPage {
                Haptics.tap()
                withAnimation { currentPage += 1 }
            } else {
                Haptics.success()
                Task {
                    isAuthorizing = true
                    await model.requestScreenTimeAuthorization()
                    isAuthorizing = false
                    model.completeOnboarding()
                    model.requestScreenTimeReportRefresh()
                }
            }
        } label: {
            Text(primaryTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - Age slider

private struct AgeSliderPage: View {
    @Binding var age: Double
    let isActive: Bool

    @State private var entered = false

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                Spacer(minLength: 60)

                Text("How old are you?")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 14)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)

                Text("\(Int(age))")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: age)
                    .opacity(entered ? 1 : 0)
                    .scaleEffect(entered ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.25), value: entered)

                Slider(value: $age, in: 0...100, step: 1)
                    .tint(.accentColor)
                    .padding(.horizontal, 32)
                    .opacity(entered ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.4), value: entered)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }
}

// MARK: - Screen-time slider

private struct ScreenTimeSliderPage: View {
    @Binding var hours: Double
    let isActive: Bool

    @State private var entered = false

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                Spacer(minLength: 60)

                Text("Your daily screen time?")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 14)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)

                VStack(spacing: 6) {
                    Text("\(Int(hours))")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.tint)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: hours)
                    Text(Int(hours) == 1 ? "hour" : "hours")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .opacity(entered ? 1 : 0)
                .scaleEffect(entered ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.25), value: entered)

                Slider(value: $hours, in: 0...24, step: 1)
                    .tint(.accentColor)
                    .padding(.horizontal, 32)
                    .opacity(entered ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.4), value: entered)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }
}

// MARK: - Wasted time result

private struct WastedTimePage: View {
    let screenTimeHours: Double
    let isActive: Bool

    @State private var isCalculating = true
    @State private var displayedWeek = 0
    @State private var displayedMonth = 0
    @State private var displayedYear = 0

    private var weekHours: Int { Int(screenTimeHours * 7) }
    private var monthHours: Int { Int(screenTimeHours * 30) }
    private var yearDays: Int { Int(screenTimeHours * 365 / 24) }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                Text(isCalculating ? "Calculating your time…" : "Time you'll never get back")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .contentTransition(.opacity)

                if isCalculating {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.accentColor)
                        .frame(height: 240)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 14) {
                        WastedRow(label: "Per week", value: "\(displayedWeek) hrs")
                        WastedRow(label: "Per month", value: "\(displayedMonth) hrs")
                        WastedRow(label: "Per year", value: "\(displayedYear) days")
                    }
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 20)
            }
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            isCalculating = true
            displayedWeek = 0
            displayedMonth = 0
            displayedYear = 0
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeInOut(duration: 0.45)) {
                    isCalculating = false
                }
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.9)) { displayedWeek = weekHours }
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.9)) { displayedMonth = monthHours }
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.9)) { displayedYear = yearDays }
            }
        }
    }
}

private struct WastedRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.system(.title2, design: .rounded).bold())
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
        }
        .padding(18)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Friend monitor (with background "photos")

private struct FriendMonitorPage: View {
    let isActive: Bool

    @State private var entered = false

    private let bgIcons: [(symbol: String, x: CGFloat, y: CGFloat, size: CGFloat, rotation: Double, opacity: Double)] = [
        ("person.crop.circle.fill", 0.12, 0.14, 90, -18, 0.18),
        ("camera.fill", 0.82, 0.10, 64, 14, 0.16),
        ("heart.fill", 0.18, 0.78, 70, -8, 0.18),
        ("sparkles", 0.85, 0.72, 78, 22, 0.20),
        ("hand.thumbsup.fill", 0.72, 0.40, 56, -10, 0.14),
        ("person.2.fill", 0.10, 0.46, 70, 8, 0.15)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.pink.opacity(0.10), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ForEach(Array(bgIcons.enumerated()), id: \.offset) { _, item in
                    Image(systemName: item.symbol)
                        .font(.system(size: item.size, weight: .regular))
                        .foregroundStyle(.tint)
                        .opacity(item.opacity)
                        .rotationEffect(.degrees(item.rotation))
                        .position(x: item.x * proxy.size.width, y: item.y * proxy.size.height)
                }

                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 80)

                        Image(systemName: "person.line.dotted.person.fill")
                            .font(.system(size: 96, weight: .light))
                            .foregroundStyle(.tint)
                            .symbolEffect(.bounce, options: .nonRepeating, value: entered)

                        Text("Let a friend monitor you")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .opacity(entered ? 1 : 0)
                            .offset(y: entered ? 0 : 14)
                            .animation(.easeOut(duration: 0.5).delay(0.15), value: entered)

                        Text("Willpower alone rarely works. Hand the keys to someone who'll keep you honest.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .opacity(entered ? 1 : 0)
                            .offset(y: entered ? 0 : 14)
                            .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }
}

// MARK: - Final page (animated gradient)

private struct FinalPage: View {
    let isActive: Bool

    @State private var entered = false

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let x = (sin(t * 0.45) + 1) / 2
                let y = (cos(t * 0.6) + 1) / 2

                LinearGradient(
                    colors: [Color.accentColor.opacity(0.5), Color.purple.opacity(0.45), Color.pink.opacity(0.4)],
                    startPoint: UnitPoint(x: x, y: y),
                    endPoint: UnitPoint(x: 1 - x, y: 1 - y)
                )
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 26) {
                    Spacer(minLength: 80)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 120, weight: .light))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, options: .nonRepeating, value: entered)
                        .phaseAnimator([1.0, 1.06]) { view, phase in
                            view.scaleEffect(phase)
                        } animation: { _ in
                            .easeInOut(duration: 1.6)
                        }

                    Text("You're all set")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.15), value: entered)

                    Text("Tap below and grant Screen Time access to start sharing with friends.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)

                    Spacer(minLength: 20)
                }
            }
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }
}
