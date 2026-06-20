import AuthenticationServices
import AVFoundation
import FamilyControls
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
    @State private var didStartFirstBlock = false
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

    private let totalPages = 8
    private var lastPage: Int { totalPages - 1 }
    private var profilePage: Int { 4 }
    private var permissionsPage: Int { 5 }
    private var blockPage: Int { permissionsPage + 1 }

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
        case permissionsPage: return screenTimeAuthorizationFailed ? "Try Again" : "Let's Get Started!"
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
                            isActive: currentPage == permissionsPage,
                            showsAuthorizationError: screenTimeAuthorizationFailed
                        )
                        .tag(permissionsPage)
                        BlockSetupPage(onStarted: {
                            didStartFirstBlock = true
                            withAnimation { currentPage = 7 }
                        })
                        .tag(6)
                        InviteFriendsOnboardingPage(isActive: currentPage == 7, onFinish: {
                            model.completeOnboarding()
                        })
                        .tag(7)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentPage)
                    .onChange(of: currentPage) { oldPage, newPage in
                        // Reset the inner step carousel whenever we leave or
                        // re-enter the How Deny works page.
                        if oldPage == howItWorksPage || newPage == howItWorksPage {
                            howItWorksStep = 0
                        }

                        #if !(DEBUG && targetEnvironment(simulator))
                        // Skipped in the simulator (Screen Time auth can't be
                        // granted there) so block setup is reachable for testing.
                        if newPage > permissionsPage && !model.hasScreenTimeAuthorization {
                            withAnimation { currentPage = permissionsPage }
                            return
                        }
                        #endif
                        if newPage > blockPage && !didStartFirstBlock {
                            withAnimation { currentPage = blockPage }
                            return
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

                    if currentPage <= permissionsPage {
                        primaryButton
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                    }
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
            if currentPage == permissionsPage {
                Haptics.success()
                Task {
                    #if DEBUG && targetEnvironment(simulator)
                    // The simulator can't satisfy the Family Controls passcode
                    // prompt, so skip the Screen Time gate to reach block setup
                    // for testing/screenshots. Never compiled into release.
                    screenTimeAuthorizationFailed = false
                    isAuthorizing = false
                    model.requestScreenTimeReportRefresh()
                    withAnimation { currentPage = 6 }
                    return
                    #endif
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
                    model.requestScreenTimeReportRefresh()
                    withAnimation { currentPage = 6 }
                }
            } else {
                advanceFromCurrentPage()
            }
        } label: {
            Text(primaryTitle)
                .onboardingPrimaryButton(disabled: isPrimaryDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isPrimaryDisabled)
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

private extension View {
    /// Filled accent button matching the main app's primary action style.
    func onboardingPrimaryButton(disabled: Bool = false) -> some View {
        font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor))
            .appRoundedButtonHitArea(cornerRadius: 16)
            .opacity(disabled ? 0.52 : 1)
    }

    /// Tinted secondary button (e.g. Back) matching the app's accent styling.
    func onboardingSecondaryButton() -> some View {
        font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Color.accentColor)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            .appRoundedButtonHitArea(cornerRadius: 16)
    }
}

private struct BlockSetupPage: View {
    @EnvironmentObject private var model: AppModel
    var onStarted: () -> Void

    private enum Step: Int, CaseIterable {
        case apps, mode, configure, password
    }

    @State private var step: Step = .apps
    @State private var selection = FamilyActivitySelection()
    @State private var isShowingPicker = false
    @State private var modeChoice: BlockGroupModeChoice = .scheduled
    @State private var limitMinutes = 30
    @State private var startDate = BlockSetupPage.date(forMinute: 22 * 60)
    @State private var endDate = BlockSetupPage.date(forMinute: 7 * 60)
    @State private var selectedDays: Set<BlockWeekday> = Set(BlockWeekday.everyDay)
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isStarting = false
    @State private var startError: String?

    private var selectedCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    private var configuredMode: BlockGroupMode {
        let days = selectedDays.isEmpty ? BlockWeekday.everyDay : selectedDays.sorted()
        switch modeChoice {
        case .timeLimit:
            return .timeLimit(limitSeconds: TimeInterval(limitMinutes * 60), days: days)
        case .scheduled:
            return .scheduled(
                startMinute: Self.minute(from: startDate),
                endMinute: Self.minute(from: endDate),
                days: days)
        }
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdvance: Bool {
        switch step {
        case .apps:
            #if DEBUG && targetEnvironment(simulator)
            return true // FamilyActivityPicker has no apps to select in the simulator
            #else
            return OnboardingBlock.meetsMinimumSelection(
                appCount: selection.applicationTokens.count,
                categoryCount: selection.categoryTokens.count,
                webCount: selection.webDomainTokens.count)
            #endif
        case .mode:
            return true
        case .configure:
            return configuredMode.isValid
        case .password:
            return !trimmedPassword.isEmpty && password == confirmPassword && !isStarting
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    stepContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            navButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $selection)
                    .navigationTitle("Blocked Apps")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingPicker = false }
                        }
                    }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(stepImageName)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .transition(.opacity)
                .id(step)

            Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var stepImageName: String {
        switch step {
        case .apps: return "OnboardingBlockApps"
        case .mode: return "OnboardingBlockMode"
        case .configure: return "OnboardingBlockConfigure"
        case .password: return "OnboardingBlockPassword"
        }
    }

    private var title: String {
        switch step {
        case .apps: return "Pick what to block"
        case .mode: return "How should it block?"
        case .configure: return modeChoice == .timeLimit ? "Set your daily limit" : "Set your schedule"
        case .password: return "Lock it with a password"
        }
    }

    private var subtitle: String {
        switch step {
        case .apps:
            return "Choose the apps, categories, or websites you lose the most time to. You can add more later."
        case .mode:
            return "Two ways to take control. You can change this anytime in Settings."
        case .configure:
            return modeChoice == .timeLimit
                ? "Once you hit your daily limit, the apps lock for the rest of the day."
                : "The apps stay blocked during the hours you choose."
        case .password:
            return "You'll need this to lift or edit the block — so you can't just turn it off in a weak moment."
        }
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .apps:
            appsStep
        case .mode:
            modeStep
        case .configure:
            configureStep
        case .password:
            passwordStep
        }
    }

    private var appsStep: some View {
        AppCard {
            Button {
                AppHaptics.buttonTap()
                isShowingPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose apps & websites")
                            .font(.subheadline.weight(.semibold))
                        Text("\(selectedCount) selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .appCardRow()
            }
            .buttonStyle(.plain)
        }
    }

    private var modeStep: some View {
        VStack(spacing: 12) {
            ModeChoiceCard(
                title: "Daily time limit",
                detail: "Allow yourself a set amount of time per day, then lock the apps.",
                systemImage: "hourglass",
                isSelected: modeChoice == .timeLimit
            ) {
                AppHaptics.selectionChanged()
                modeChoice = .timeLimit
            }

            ModeChoiceCard(
                title: "Schedule",
                detail: "Block the apps during set hours — like overnight or during work.",
                systemImage: "calendar",
                isSelected: modeChoice == .scheduled
            ) {
                AppHaptics.selectionChanged()
                modeChoice = .scheduled
            }
        }
    }

    @ViewBuilder
    private var configureStep: some View {
        VStack(spacing: 10) {
            AppCard {
                if modeChoice == .timeLimit {
                    DurationWheelPicker(minutes: $limitMinutes)
                        .appCardRow(verticalPadding: 14)
                } else {
                    DatePicker("Block from", selection: $startDate, displayedComponents: .hourAndMinute)
                        .appCardRow()
                    AppCardDivider()
                    DatePicker("Until", selection: $endDate, displayedComponents: .hourAndMinute)
                        .appCardRow()
                }

                AppCardDivider()

                RepeatDaysPicker(selectedDays: $selectedDays)
                    .appCardRow()
            }

            if !configuredMode.isValid {
                Text(modeChoice == .scheduled
                     ? "Pick a start and end time and at least one day."
                     : "Pick at least one day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var passwordStep: some View {
        AppCard {
            SecureField("Password", text: $password)
                .textContentType(.newPassword)
                .appCardRow()
            AppCardDivider()
            SecureField("Confirm password", text: $confirmPassword)
                .textContentType(.newPassword)
                .appCardRow()
        }
        .onChange(of: password) { startError = nil }
        .onChange(of: confirmPassword) { startError = nil }
    }

    // MARK: Navigation

    private var navButtons: some View {
        VStack(spacing: 8) {
            if let feedback = feedbackMessage {
                Text(feedback)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            HStack(spacing: 12) {
                if step != .apps {
                    Button {
                        AppHaptics.buttonTap()
                        back()
                    } label: {
                        Text("Back").onboardingSecondaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                }

                Button {
                    advance()
                } label: {
                    Group {
                        if isStarting {
                            ProgressView().tint(.white)
                        } else {
                            Text(step == .password ? "Start blocking" : "Continue")
                        }
                    }
                    .onboardingPrimaryButton(disabled: !canAdvance)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            }
        }
    }

    /// A visible reason the user can't continue (or why starting failed), so
    /// nothing fails silently.
    private var feedbackMessage: String? {
        if let startError {
            return startError
        }
        if step == .password, !canAdvance {
            if trimmedPassword.isEmpty {
                return "Enter a password to continue."
            }
            if password != confirmPassword {
                return "Passwords don't match."
            }
        }
        return nil
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation { step = previous }
    }

    private func advance() {
        guard canAdvance else { return }
        if step == .password {
            isStarting = true
            Task { await start() }
        } else if let next = Step(rawValue: step.rawValue + 1) {
            AppHaptics.buttonTap()
            withAnimation { step = next }
        }
    }

    @MainActor
    private func start() async {
        defer { isStarting = false }
        startError = nil
        #if !(DEBUG && targetEnvironment(simulator))
        if !model.hasScreenTimeAuthorization {
            await model.requestScreenTimeAuthorization()
            guard model.hasScreenTimeAuthorization else {
                startError = "Screen Time access is required to start blocking. Enable it and try again."
                return
            }
        }
        #endif
        guard let data = try? BlockingSelectionCodec.encode(selection) else {
            startError = "Couldn't save your app selection. Please try again."
            return
        }
        let group = OnboardingBlock.makeFirstBlockGroup(
            id: UUID().uuidString,
            name: "My First Block",
            selectionData: data,
            mode: configuredMode)
        if model.upsertBlockGroup(group, password: password) {
            Haptics.success()
            onStarted()
            return
        }
        // upsertBlockGroup failed — surface the reason instead of doing nothing.
        #if DEBUG && targetEnvironment(simulator)
        // The simulator's app picker is empty, so the block can't actually be
        // created; continue so the rest of onboarding stays testable.
        onStarted()
        #else
        startError = model.message ?? "Couldn't start blocking. Check your apps and password, then try again."
        #endif
    }

    // MARK: Minute <-> Date helpers (schedule pickers)

    private static func date(forMinute minute: Int) -> Date {
        let comps = DateComponents(hour: minute / 60, minute: minute % 60)
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func minute(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

private struct ModeChoiceCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InviteFriendsOnboardingPage: View {
    @EnvironmentObject private var model: AppModel
    var isActive: Bool
    var onFinish: () -> Void

    @State private var invite: CreatedInvite?
    @State private var isGenerating = false
    @State private var didFail = false
    @State private var didCopy = false

    private var shareText: String? {
        guard let invite else { return nil }
        return OnboardingInvite.shareMessage(
            displayName: model.profile.displayName,
            appStoreURL: AppConfiguration.appStoreURL,
            inviteURL: invite.url)
    }

    var body: some View {
        VStack(spacing: 20) {
            Image("OnboardingInviteFriend")
                .resizable()
                .scaledToFit()
                .frame(height: 180)

            Text("You're all set — invite a friend")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Deny works best with a friend keeping you honest. Send them your link — it installs the app and connects you automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let invite, let shareText {
                linkBox(invite.url.absoluteString)

                ShareLink(item: shareText) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .onboardingPrimaryButton()
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { Haptics.success() })

                Button {
                    copyLink(invite.url.absoluteString)
                } label: {
                    Label(didCopy ? "Copied!" : "Copy link", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .onboardingSecondaryButton()
                }
                .buttonStyle(.plain)
            } else if isGenerating {
                ProgressView().padding(.vertical, 8)
            } else if didFail {
                Button {
                    Task { await generate() }
                } label: {
                    Text("Try again").onboardingSecondaryButton()
                }
                .buttonStyle(.plain)
            }

            Button("Maybe later") {
                AppHaptics.buttonTap()
                onFinish()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .onChange(of: isActive) { _, nowActive in
            if nowActive { Task { await generate() } }
        }
        .task {
            if isActive { await generate() }
        }
    }

    private func linkBox(_ link: String) -> some View {
        Text(link)
            .font(.footnote.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    private func copyLink(_ link: String) {
        AppHaptics.success()
        #if canImport(UIKit)
        UIPasteboard.general.string = link
        #endif
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { didCopy = false }
        }
    }

    @MainActor
    private func generate() async {
        guard invite == nil, !isGenerating else { return }
        isGenerating = true
        didFail = false
        defer { isGenerating = false }
        if let created = try? await model.createInvite() {
            invite = created
        } else {
            didFail = true
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
