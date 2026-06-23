import AuthenticationServices
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsLaunchSplash = true
    @State private var launchSplashOpacity = 1.0
    @State private var isRedeemingGroupInvite = false

    var body: some View {
        ZStack {
            Group {
                if !model.hasCompletedOnboarding {
                    OnboardingView()
                } else if !model.isAuthenticated {
                    // Existing users who finished onboarding before Sign in with
                    // Apple shipped: prompt once so their profile gets a recovery
                    // key. Their data is preserved (same profile ID).
                    SignInGateView()
                } else {
                    AppTabs()
                }
            }

            // Hidden: drives per-group pool usage measurement while foreground.
            GroupPoolUsageReporters()

            if showsLaunchSplash {
                LaunchSplashView()
                    .opacity(launchSplashOpacity)
                    .zIndex(10)
            }
        }
        .task {
            await fadeOutLaunchSplash()
        }
        .sheet(item: activeSheetBinding) { sheet in
            switch sheet {
            case .groupInvite(let invite):
                GroupShareInviteView(
                    invite: invite,
                    isAccepting: isRedeemingGroupInvite,
                    onAccept: {
                        Task {
                            isRedeemingGroupInvite = true
                            defer { isRedeemingGroupInvite = false }
                            await model.redeemPendingGroupInvite()
                        }
                    },
                    onCancel: {
                        model.dismissIncomingGroupInvite()
                    }
                )
                .interactiveDismissDisabled(isRedeemingGroupInvite)
            case .friendInvite(let invite):
                FriendShareInviteView(
                    invite: invite,
                    isAccepting: model.isRedeemingInvite,
                    onAccept: {
                        Task {
                            await model.redeemPendingInvite()
                        }
                    },
                    onCancel: {
                        model.dismissIncomingInvite()
                    }
                )
                .interactiveDismissDisabled(model.isRedeemingInvite)
            case .shieldRequest(let group):
                FriendApprovalRequestView(group: group)
            }
        }
    }

    private var activeSheetBinding: Binding<RootSheet?> {
        Binding(
            get: { activeSheet },
            set: { newValue in
                if newValue == nil {
                    dismissActiveSheet()
                }
            }
        )
    }

    private var activeSheet: RootSheet? {
        if let invite = model.pendingIncomingGroupInvite {
            return .groupInvite(invite)
        }

        if let invite = model.pendingIncomingInvite {
            return .friendInvite(invite)
        }

        if let group = model.pendingShieldFriendRequestGroup {
            return .shieldRequest(group)
        }

        return nil
    }

    private func dismissActiveSheet() {
        if model.pendingIncomingGroupInvite != nil {
            model.dismissIncomingGroupInvite()
        } else if model.pendingIncomingInvite != nil {
            model.dismissIncomingInvite()
        } else if model.pendingShieldFriendRequestGroup != nil {
            model.clearPendingShieldFriendRequest()
        }
    }

    private func fadeOutLaunchSplash() async {
        guard showsLaunchSplash, launchSplashOpacity == 1 else {
            return
        }

        try? await Task.sleep(nanoseconds: 750_000_000)
        guard !Task.isCancelled else {
            return
        }

        withAnimation(.easeInOut(duration: 1.8)) {
            launchSplashOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 1_850_000_000)
        guard !Task.isCancelled else {
            return
        }

        showsLaunchSplash = false
    }
}

private enum RootSheet: Identifiable {
    case groupInvite(PeekedGroupInvite)
    case friendInvite(IncomingInvite)
    case shieldRequest(BlockGroup)

    var id: String {
        switch self {
        case .groupInvite(let invite):
            return "group-invite.\(invite.code)"
        case .friendInvite(let invite):
            return "friend-invite.\(invite.code)"
        case .shieldRequest(let group):
            return "shield.\(group.id)"
        }
    }
}

private struct SignInGateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSigningIn = false
    @State private var signInError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text("Sign in to continue")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Connect your Apple ID so you can recover this account on a new device. Your existing data stays exactly as it is.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            Spacer()

            SignInWithAppleButton(.signIn, onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            }, onCompletion: { _ in })
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .cornerRadius(14)
            .disabled(isSigningIn)
            .overlay {
                Button(action: performSignIn) {
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
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            #if DEBUG && targetEnvironment(simulator)
            Button("Debug: Simulator Sign-In") {
                isSigningIn = true
                signInError = nil
                Task {
                    let success = await model.signInWithDebugAccount()
                    if !success {
                        signInError = model.message
                    }
                    isSigningIn = false
                }
            }
            .font(.footnote)
            .disabled(isSigningIn)
            #endif
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private func performSignIn() {
        guard !isSigningIn else {
            return
        }

        isSigningIn = true
        signInError = nil
        Task {
            do {
                _ = try await model.signInWithApple()
            } catch {
                if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                    signInError = error.localizedDescription
                }
            }
            isSigningIn = false
        }
    }
}

private struct FriendShareInviteView: View {
    let invite: IncomingInvite
    let isAccepting: Bool
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 18)

                ProfileAvatar(
                    imageData: nil,
                    colorHex: invite.inviterAvatarColorHex ?? AppConfiguration.defaultAvatarColor,
                    initials: invite.inviterDisplayName.initials,
                    size: 116
                )

                VStack(spacing: 8) {
                    Text(invite.inviterDisplayName)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("wants to share Screen Time with you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 18)

                Button(action: onAccept) {
                    HStack(spacing: 10) {
                        if isAccepting {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isAccepting ? "Accepting" : "Accept Friend Request")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAccepting)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Friend Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now", action: onCancel)
                        .disabled(isAccepting)
                }
            }
        }
    }
}

private struct LaunchSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundColor

            Image("DenyWordmark")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 148)
                .accessibilityLabel("deny")
        }
        .ignoresSafeArea()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }
}

private struct AppTabs: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: AppTab = .today
    @State private var visitedTabs: Set<AppTab> = [.today]
    @State private var highlightedFeedRequestID: String?

    private var requestFeedAttentionCount: Int {
        model.blockingState.friendRequests.filter { request in
            (request.isReceived(byAny: currentFriendIdentityIDs) && request.status == .pending)
                || (request.isSent(byAny: currentFriendIdentityIDs) && request.status == .approved)
        }.count
    }

    private var currentFriendIdentityIDs: Set<String> {
        [model.profile.id, "profile-\(model.profile.id)"]
    }

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if visitedTabs.contains(tab) {
                    tabView(for: tab)
                        .opacity(selection == tab ? 1 : 0)
                        .allowsHitTesting(selection == tab)
                        .accessibilityHidden(selection != tab)
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: selection)
        .safeAreaInset(edge: .bottom) {
            GlassTabBar(selection: $selection, feedBadgeCount: requestFeedAttentionCount)
        }
        .onAppear {
            if let requestID = model.focusedFriendRequestLogID {
                presentFriendRequestLog(requestID: requestID)
                model.clearFocusedFriendRequestLog()
            }
        }
        .onChange(of: model.focusedFriendRequestLogID) { _, requestID in
            guard let requestID else {
                return
            }

            presentFriendRequestLog(requestID: requestID)
            model.clearFocusedFriendRequestLog()
        }
        .onChange(of: selection) { _, newSelection in
            visitedTabs.insert(newSelection)
            if newSelection != .feed {
                highlightedFeedRequestID = nil
            }
        }
    }

    @ViewBuilder
    private func tabView(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            DashboardView()
        case .stats:
            StatsView()
        case .feed:
            NavigationStack {
                RequestFeedView(
                    highlightedFriendRequestID: highlightedFeedRequestID,
                    showsDoneButton: false
                )
            }
        case .friends:
            FriendsView()
        case .settings:
            SettingsView()
        }
    }

    private func presentFriendRequestLog(requestID: String) {
        highlightedFeedRequestID = requestID
        selection = .feed
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case today
    case stats
    case feed
    case friends
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Home"
        case .stats:
            return "Stats"
        case .feed:
            return "Feed"
        case .friends:
            return "Friends"
        case .settings:
            return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            return "house"
        case .stats:
            return "chart.bar.fill"
        case .feed:
            return "tray.full"
        case .friends:
            return "person.2"
        case .settings:
            return "person.crop.circle"
        }
    }
}

private struct GlassTabBar: View {
    @Binding var selection: AppTab
    let feedBadgeCount: Int
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                GlassTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    badgeCount: tab == .feed ? feedBadgeCount : 0,
                    namespace: indicatorNamespace
                ) {
                    if selection != tab {
                        AppHaptics.selectionChanged()
                    }
                    selection = tab
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background {
            LiquidGlassCapsule(strength: .base)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

private struct GlassTabButton: View {
    @EnvironmentObject private var model: AppModel
    let tab: AppTab
    let isSelected: Bool
    let badgeCount: Int
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    icon
                        .frame(width: tab == .settings ? 24 : 20, height: 22)

                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(minWidth: 15, minHeight: 15)
                            .padding(.horizontal, 1.5)
                            .background(Color.red, in: Capsule())
                            .offset(x: 9, y: -6)
                    }
                }
                .frame(width: 32, height: 22)

                Text(tab.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if isSelected {
                    LiquidGlassCapsule(strength: .selected)
                        .matchedGeometryEffect(id: "selected-tab", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var icon: some View {
        if tab == .settings {
            ProfileTabIcon(
                imageData: model.profile.avatarImageData,
                colorHex: model.profile.avatarColorHex,
                initials: model.profile.displayName.initials,
                isSelected: isSelected
            )
        } else if tab == .stats {
            IncreasingBarsIcon(isSelected: isSelected)
        } else {
            Image(systemName: tab.systemImage)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(size: 16, weight: isSelected ? .bold : .semibold))
        }
    }
}

private struct ProfileTabIcon: View {
    let imageData: Data?
    let colorHex: String
    let initials: String
    let isSelected: Bool

    var body: some View {
        ProfileAvatar(
            imageData: imageData,
            colorHex: colorHex,
            initials: initials,
            size: 22
        )
        .overlay {
            Circle()
                .strokeBorder(isSelected ? Color.primary.opacity(0.20) : Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color(hex: colorHex).opacity(isSelected ? 0.12 : 0.0), radius: 5, y: 2)
    }
}

private struct IncreasingBarsIcon: View {
    let isSelected: Bool
    private let heights: [CGFloat] = [7, 10, 13, 16]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.4) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                bar(height: height)
            }
        }
        .frame(width: 20, height: 19, alignment: .bottom)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bar(height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1.4, style: .continuous)
        if isSelected {
            shape
                .frame(width: 3.4, height: height)
        } else {
            shape
                .stroke(lineWidth: 1.35)
                .frame(width: 3.4, height: height)
        }
    }
}

private struct LiquidGlassCapsule: View {
    enum Strength {
        case base
        case cell
        case selected
    }

    let strength: Strength

    var body: some View {
        Capsule()
            .fill(material)
            .overlay {
                Capsule()
                    .fill(innerGlow)
                    .blendMode(.screen)
                    .opacity(glowOpacity)
            }
            .overlay {
                Capsule()
                    .strokeBorder(borderGradient, lineWidth: borderWidth)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }

    private var material: Material {
        switch strength {
        case .base:
            return .ultraThinMaterial
        case .cell:
            return .thinMaterial
        case .selected:
            return .regularMaterial
        }
    }

    private var innerGlow: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(strength == .selected ? 0.42 : 0.26),
                .white.opacity(0.06),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(strength == .selected ? 0.62 : 0.38),
                .white.opacity(0.12),
                .black.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderWidth: CGFloat {
        switch strength {
        case .base:
            return 0.7
        case .cell:
            return 0.55
        case .selected:
            return 0.85
        }
    }

    private var glowOpacity: Double {
        switch strength {
        case .base:
            return 0.45
        case .cell:
            return 0.6
        case .selected:
            return 0.78
        }
    }

    private var shadowOpacity: Double {
        switch strength {
        case .base:
            return 0.13
        case .cell:
            return 0.05
        case .selected:
            return 0.16
        }
    }

    private var shadowRadius: CGFloat {
        switch strength {
        case .base:
            return 24
        case .cell:
            return 8
        case .selected:
            return 16
        }
    }

    private var shadowY: CGFloat {
        switch strength {
        case .base:
            return 12
        case .cell:
            return 3
        case .selected:
            return 7
        }
    }
}
