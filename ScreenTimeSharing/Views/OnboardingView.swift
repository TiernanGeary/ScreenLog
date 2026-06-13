import AuthenticationServices
import AVFoundation
import PhotosUI
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    @State private var currentPage: Int = 0
    @State private var howItWorksStep: Int = 0
    @State private var avgScreenTime: Double = 4
    @State private var isAuthorizing = false
    @State private var screenTimeAuthorizationFailed = false
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var draftDisplayName = ""
    @State private var draftAvatarImageData: Data?
    @State private var hasLoadedProfileDraft = false
    @State private var isShowingProfilePhotoOptions = false
    @State private var isShowingProfilePhotoLibrary = false
    @State private var isShowingProfileCamera = false
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    @State private var profilePhotoCropItem: ProfilePhotoCropItem?
    #if canImport(UIKit)
    @State private var pendingProfileCameraImage: UIImage?
    #endif

    private let totalPages = 6
    private var lastPage: Int { totalPages - 1 }
    private var profilePage: Int { lastPage - 1 }

    private var trimmedDraftDisplayName: String {
        draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPrimaryDisabled: Bool {
        if currentPage == profilePage {
            return !model.isAuthenticated || trimmedDraftDisplayName.isEmpty
        }
        return false
    }

    private var primaryTitle: String {
        switch currentPage {
        case lastPage: return screenTimeAuthorizationFailed ? "Try Again" : "Let's Get Started!"
        case profilePage: return model.isAuthenticated ? "Save and Continue" : "Sign in to Continue"
        case 1: return "Get Started"
        default: return "Continue"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBar
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    TabView(selection: $currentPage) {
                        ScreenTimeSliderPage(hours: $avgScreenTime, isActive: currentPage == 0).tag(0)
                        WastedTimePage(screenTimeHours: avgScreenTime, isActive: currentPage == 1).tag(1)
                        FriendMonitorPage(isActive: currentPage == 2).tag(2)
                        HowItWorksPage(isActive: currentPage == 3, stepIndex: $howItWorksStep).tag(3)
                        AppleSignInProfilePage(
                            displayName: $draftDisplayName,
                            avatarImageData: draftAvatarImageData,
                            avatarColorHex: model.profile.avatarColorHex,
                            isAuthenticated: model.isAuthenticated,
                            isSigningIn: isSigningIn,
                            signInError: signInError,
                            isActive: currentPage == profilePage,
                            onSignIn: { performAppleSignIn() },
                            onPhotoTap: {
                                AppHaptics.buttonTap()
                                isShowingProfilePhotoOptions = true
                            }
                        )
                        .tag(profilePage)
                        FinalPage(
                            isActive: currentPage == lastPage,
                            showsAuthorizationError: screenTimeAuthorizationFailed
                        )
                        .tag(lastPage)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentPage)
                    .onChange(of: currentPage) { oldPage, newPage in
                        // Reset the inner step carousel whenever we leave or
                        // re-enter the How Deny works page.
                        if oldPage == howItWorksPage || newPage == howItWorksPage {
                            howItWorksStep = 0
                        }

                        guard oldPage == profilePage, newPage != profilePage else {
                            return
                        }

                        if trimmedDraftDisplayName.isEmpty, newPage > profilePage {
                            withAnimation { currentPage = profilePage }
                        } else if !trimmedDraftDisplayName.isEmpty {
                            saveProfileDraft()
                        }
                    }

                    primaryButton
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .disabled(isAuthorizing)
            .overlay {
                if isAuthorizing {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .photosPicker(
                isPresented: $isShowingProfilePhotoLibrary,
                selection: $selectedProfilePhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            #if canImport(UIKit)
            .fullScreenCover(
                isPresented: $isShowingProfileCamera,
                onDismiss: {
                    if let pendingProfileCameraImage {
                        profilePhotoCropItem = ProfilePhotoCropItem(image: pendingProfileCameraImage)
                        self.pendingProfileCameraImage = nil
                    }
                }
            ) {
                ProfileCameraPicker { image in
                    pendingProfileCameraImage = image
                    isShowingProfileCamera = false
                } onCancel: {
                    isShowingProfileCamera = false
                }
            }
            #endif
            .fullScreenCover(item: $profilePhotoCropItem) { item in
                ProfilePhotoCropView(image: item.image) { croppedImageData in
                    draftAvatarImageData = croppedImageData
                    profilePhotoCropItem = nil
                }
            }
            .confirmationDialog("Profile Photo", isPresented: $isShowingProfilePhotoOptions, titleVisibility: .visible) {
                #if canImport(UIKit)
                Button("Take Photo") {
                    AppHaptics.buttonTap()
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        model.message = "Camera is unavailable on this device."
                        return
                    }

                    isShowingProfileCamera = true
                }
                #endif

                Button("Choose from Library") {
                    AppHaptics.buttonTap()
                    isShowingProfilePhotoLibrary = true
                }

                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: loadProfileDraftIfNeeded)
            .onChange(of: selectedProfilePhotoItem) { _, item in
                loadSelectedProfilePhoto(item)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: currentPage)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: howItWorksStep)
        .accessibilityElement()
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("Step \(currentPage + 1) of \(totalPages)")
    }

    // Pages count as whole units; the How Deny works page additionally fills in
    // quarters as the user steps through its inner carousel.
    private var progressFraction: CGFloat {
        var completed = CGFloat(currentPage + 1)
        if currentPage == howItWorksPage {
            completed += CGFloat(howItWorksStep) / CGFloat(HowItWorksPage.stepCount)
            completed = min(completed, CGFloat(currentPage + 1) + 0.99)
        }
        return min(1, completed / CGFloat(totalPages))
    }

    private var primaryButton: some View {
        Button {
            if currentPage < lastPage {
                advanceFromCurrentPage()
            } else {
                Haptics.success()
                Task {
                    isAuthorizing = true
                    await model.requestScreenTimeAuthorization()

                    guard model.hasScreenTimeAuthorization else {
                        isAuthorizing = false
                        screenTimeAuthorizationFailed = true
                        return
                    }

                    screenTimeAuthorizationFailed = false
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    _ = await AVCaptureDevice.requestAccess(for: .video)
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
        .disabled(isPrimaryDisabled)
        .opacity(isPrimaryDisabled ? 0.52 : 1)
    }

    private let howItWorksPage = 3

    private func advanceFromCurrentPage() {
        // On the How Deny works page, Continue walks the inner step carousel
        // first; only the last step advances the whole flow.
        if currentPage == howItWorksPage, howItWorksStep < HowItWorksPage.stepCount - 1 {
            Haptics.tap()
            withAnimation { howItWorksStep += 1 }
            return
        }

        if currentPage == profilePage {
            saveProfileDraft()
        }

        Haptics.tap()
        withAnimation { currentPage += 1 }
    }

    private func performAppleSignIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        Task {
            do {
                _ = try await model.signInWithApple()
                draftDisplayName = model.profile.displayName == "Me" ? "" : model.profile.displayName
                draftAvatarImageData = model.profile.avatarImageData
                hasLoadedProfileDraft = true
            } catch {
                if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                    signInError = error.localizedDescription
                }
            }
            isSigningIn = false
        }
    }

    private func loadProfileDraftIfNeeded() {
        guard !hasLoadedProfileDraft else {
            return
        }

        hasLoadedProfileDraft = true
        draftDisplayName = model.profile.displayName == "Me" ? "" : model.profile.displayName
        draftAvatarImageData = model.profile.avatarImageData
    }

    private func saveProfileDraft() {
        guard !trimmedDraftDisplayName.isEmpty else {
            return
        }

        model.updateProfile(displayName: trimmedDraftDisplayName, avatarImageData: draftAvatarImageData)
    }

    private func loadSelectedProfilePhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    selectedProfilePhotoItem = nil
                }
                return
            }

            #if canImport(UIKit)
            guard let image = UIImage(data: data) else {
                await MainActor.run {
                    selectedProfilePhotoItem = nil
                }
                return
            }

            await MainActor.run {
                profilePhotoCropItem = ProfilePhotoCropItem(image: image)
                selectedProfilePhotoItem = nil
            }
            #else
            await MainActor.run {
                selectedProfilePhotoItem = nil
            }
            #endif
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
                Spacer(minLength: 16)

                Image("OnboardingScreenTime")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 190)
                    // Feathered edges: a blurred mask fades the artwork's white
                    // backdrop into the page so it doesn't read as a card.
                    .mask {
                        RoundedRectangle(cornerRadius: 48, style: .continuous)
                            .padding(18)
                            .blur(radius: 22)
                    }
                    .opacity(entered ? 1 : 0)
                    .scaleEffect(entered ? 1 : 0.92)
                    .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.05), value: entered)

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
    @State private var showsArt = false
    @State private var displayedWeek = 0
    @State private var displayedMonth = 0
    @State private var displayedYear = 0

    private var weekHours: Int { Int(screenTimeHours * 7) }
    private var monthHours: Int { Int(screenTimeHours * 30) }
    private var yearDays: Int { Int(screenTimeHours * 365 / 24) }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 16)

                // Mounted (invisibly) during the calculating beat so the asset
                // is already decoded; the pop then fires in the same instant as
                // the reveal instead of after a decode hiccup.
                Image("OnboardingWastedTime")
                    .resizable()
                    .scaledToFit()
                    .frame(height: showsArt ? 190 : 0)
                    .mask {
                        RoundedRectangle(cornerRadius: 48, style: .continuous)
                            .padding(18)
                            .blur(radius: 22)
                    }
                    .opacity(showsArt ? 1 : 0.01)
                    .scaleEffect(showsArt ? 1 : 0.92)

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
            showsArt = false
            displayedWeek = 0
            displayedMonth = 0
            displayedYear = 0
            guard nowActive else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeInOut(duration: 0.45)) {
                    isCalculating = false
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    showsArt = true
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

    var body: some View {
        ZStack {
            // The hero artwork ships on a white backdrop, so this page is
            // solid white (and pinned light) for a seamless blend.
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 80)

                    Image("OnboardingFriendMonitor")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 250)
                        .opacity(entered ? 1 : 0)
                        .scaleEffect(entered ? 1 : 0.9)
                        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.05), value: entered)

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
        // White-backdrop page reads as light regardless of system scheme.
        .environment(\.colorScheme, .light)
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

// MARK: - How it works (core request loop)

private struct HowItWorksPage: View {
    let isActive: Bool
    @Binding var stepIndex: Int

    @State private var entered = false

    static let stepCount = 4

    private let steps: [(image: String, title: String, detail: String)] = [
        ("OnboardingStepBlocked", "Your apps get blocked", "Pick the apps that waste your time and Deny locks you out."),
        ("OnboardingStepSelfie", "Ask with a selfie", "Want extra time? Snap a photo and choose how many minutes."),
        ("OnboardingStepFriend", "A friend decides", "They see your photo and approve or deny your request."),
        ("OnboardingStepUnlock", "Unlock on approval", "Approved minutes unlock the apps \u{2014} then they lock again.")
    ]

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 32)

            Text("How Deny works")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 14)
                .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)

            // One step per screen, swiped horizontally. No separate indicator:
            // the steps read as one beat of the outer flow.
            TabView(selection: $stepIndex) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 18) {
                        Image(step.image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 240)

                        Text(step.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text(step.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 28)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: stepIndex)
            .opacity(entered ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: entered)
        }
        // White-backdrop art: keep the page light like the friend-monitor page
        // so a dark-mode replay can't invert the text.
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
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

// MARK: - Profile setup

private struct ProfileSetupPage: View {
    @Binding var displayName: String
    let avatarImageData: Data?
    let avatarColorHex: String
    let isActive: Bool
    let onChangePhoto: () -> Void

    @FocusState private var isNameFocused: Bool
    @State private var entered = false

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var avatarInitials: String {
        trimmedDisplayName.isEmpty ? "?" : trimmedDisplayName.initials
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 56)

                VStack(spacing: 14) {
                    Button(action: onChangePhoto) {
                        ProfileAvatar(
                            imageData: avatarImageData,
                            colorHex: avatarColorHex,
                            initials: avatarInitials,
                            size: 118
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor, in: Circle())
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color(.systemBackground), lineWidth: 2)
                                }
                                .offset(x: 4, y: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set profile photo")

                    Text("Set up your profile")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("Friends will see this name and photo when you send invites or request time.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 14)
                .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)

                VStack(alignment: .leading, spacing: 9) {
                    Text("USERNAME")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField("Your name", text: $displayName)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .focused($isNameFocused)
                            .onSubmit {
                                isNameFocused = false
                            }

                        if !displayName.isEmpty {
                            Button {
                                AppHaptics.buttonTap()
                                displayName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear name")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                trimmedDisplayName.isEmpty
                                    ? Color.orange.opacity(0.50)
                                    : Color.primary.opacity(isNameFocused ? 0.28 : 0.12),
                                lineWidth: 1
                            )
                    }

                    if trimmedDisplayName.isEmpty {
                        Text("Add a name to continue.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 24)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 14)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .onTapGesture {
            isNameFocused = false
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else {
                isNameFocused = false
                return
            }

            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
                try? await Task.sleep(for: .milliseconds(260))
                isNameFocused = true
            }
        }
    }
}

// MARK: - Apple Sign In + Profile

private struct AppleSignInProfilePage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var displayName: String
    let avatarImageData: Data?
    let avatarColorHex: String
    let isAuthenticated: Bool
    let isSigningIn: Bool
    let signInError: String?
    let isActive: Bool
    let onSignIn: () -> Void
    let onPhotoTap: () -> Void

    @FocusState private var isNameFocused: Bool
    @State private var entered = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var debugSignInError: String?
    #endif

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var avatarInitials: String {
        trimmedDisplayName.isEmpty ? "?" : trimmedDisplayName.initials
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 56)

                if isAuthenticated {
                    profileEditor
                } else {
                    signInContent
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .onTapGesture {
            isNameFocused = false
        }
        .onChange(of: isActive, initial: true) { _, nowActive in
            entered = false
            guard nowActive else {
                isNameFocused = false
                return
            }
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                entered = true
            }
        }
    }

    private var signInContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)

            Text("Sign in with Apple")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Deny is built around your friends, so it needs an account.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)

            VStack(spacing: 10) {
                SignInBenefitRow(
                    icon: "person.2.fill",
                    text: "Friend requests and approvals are tied to your account"
                )
                SignInBenefitRow(
                    icon: "icloud.fill",
                    text: "Your data stays in sync through iCloud"
                )
                SignInBenefitRow(
                    icon: "arrow.counterclockwise",
                    text: "Recover everything when you switch devices"
                )
            }
            .padding(.horizontal, 8)

            SignInWithAppleButton(.signIn, onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            }, onCompletion: { _ in })
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .cornerRadius(14)
            .disabled(isSigningIn)
            .overlay {
                Button(action: onSignIn) {
                    Color.clear
                }
                .disabled(isSigningIn)
            }

            if isSigningIn {
                ProgressView()
                    .tint(.primary)
            }

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            #if DEBUG && targetEnvironment(simulator)
            Button("Debug: Simulator Sign-In") {
                debugSignInError = nil
                Task {
                    let success = await model.signInWithDebugAccount()
                    if !success {
                        debugSignInError = model.message
                    }
                }
            }
            .font(.footnote)
            .disabled(isSigningIn)

            if let debugSignInError {
                Text(debugSignInError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 14)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)
    }

    private var profileEditor: some View {
        VStack(spacing: 26) {
            VStack(spacing: 14) {
                Button(action: onPhotoTap) {
                    ProfileAvatar(
                        imageData: avatarImageData,
                        colorHex: avatarColorHex,
                        initials: avatarInitials,
                        size: 118
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(Color(.systemBackground), lineWidth: 2)
                            }
                            .offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set profile photo")

                Text("Set up your profile")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Friends will see this name and photo when you send invites or request time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 14)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: entered)

            VStack(alignment: .leading, spacing: 9) {
                Text("USERNAME")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    TextField("Your name", text: $displayName)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit { isNameFocused = false }

                    if !displayName.isEmpty {
                        Button {
                            AppHaptics.buttonTap()
                            displayName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            trimmedDisplayName.isEmpty
                                ? Color.orange.opacity(0.50)
                                : Color.primary.opacity(isNameFocused ? 0.28 : 0.12),
                            lineWidth: 1
                        )
                }

                if trimmedDisplayName.isEmpty {
                    Text("Add a name to continue.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 24)
            .opacity(entered ? 1 : 0)
            .offset(y: entered ? 0 : 14)
            .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)
        }
    }
}

private struct SignInBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Final page (animated gradient)

private struct FinalPage: View {
    let isActive: Bool
    let showsAuthorizationError: Bool

    @State private var entered = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)

                    Image("OnboardingAllSet")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 210)
                        .opacity(entered ? 1 : 0)
                        .scaleEffect(entered ? 1 : 0.9)
                        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.05), value: entered)

                    Text("You're all set")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.15), value: entered)

                    Text("Grant access below to finish setting up.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : 14)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: entered)

                    VStack(spacing: 10) {
                        FinalPermissionRow(
                            icon: "hourglass",
                            title: "Screen Time — Required",
                            detail: "Powers your usage stats and app blocking."
                        )
                        FinalPermissionRow(
                            icon: "bell.badge.fill",
                            title: "Notifications — Optional",
                            detail: "Know right away when friends request or approve time."
                        )
                        FinalPermissionRow(
                            icon: "camera.fill",
                            title: "Camera — Optional",
                            detail: "Time requests include a selfie so friends know it's really you."
                        )
                    }
                    .padding(.horizontal, 24)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 14)
                    .animation(.easeOut(duration: 0.5).delay(0.45), value: entered)

                    if showsAuthorizationError {
                        Text("Screen Time access is required to continue. Tap Try Again to re-request it.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Spacer(minLength: 20)
                }
            }
        }
        .environment(\.colorScheme, .light)
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

private struct FinalPermissionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
