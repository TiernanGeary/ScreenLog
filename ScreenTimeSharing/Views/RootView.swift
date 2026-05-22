import FamilyControls
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingActivityPicker = false
    @State private var isShowingBlockingActivityPicker = false

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                AppTabs(
                    isShowingActivityPicker: $isShowingActivityPicker,
                    isShowingBlockingActivityPicker: $isShowingBlockingActivityPicker
                )
            } else {
                OnboardingView(isShowingActivityPicker: $isShowingActivityPicker)
            }
        }
        .sheet(isPresented: $isShowingActivityPicker, onDismiss: model.persistSelection) {
            NavigationStack {
                FamilyActivityPicker(selection: $model.selection)
                    .navigationTitle("Selected Apps")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                AppHaptics.buttonTap()
                                model.persistSelection()
                                isShowingActivityPicker = false
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $isShowingBlockingActivityPicker, onDismiss: model.saveSuggestedSocialBlockGroup) {
            NavigationStack {
                FamilyActivityPicker(selection: $model.blockingSelection)
                    .navigationTitle("Social Block Group")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                AppHaptics.buttonTap()
                                model.saveSuggestedSocialBlockGroup()
                                isShowingBlockingActivityPicker = false
                            }
                        }
                    }
            }
        }
        .sheet(
            item: Binding<BlockGroup?>(
                get: { model.pendingShieldFriendRequestGroup },
                set: { newValue in
                    if newValue == nil {
                        model.clearPendingShieldFriendRequest()
                    }
                }
            )
        ) { group in
            FriendApprovalRequestView(group: group)
        }
    }
}

private struct AppTabs: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isShowingActivityPicker: Bool
    @Binding var isShowingBlockingActivityPicker: Bool
    @State private var selection: AppTab = .today
    @State private var highlightedFeedRequestID: String?

    private var requestFeedAttentionCount: Int {
        model.blockingState.friendRequests.filter { request in
            (request.isReceived(by: model.profile.id) && request.status == .pending)
                || (request.isSent(by: model.profile.id) && request.status == .approved)
        }.count
    }

    var body: some View {
        ZStack {
            selectedView
                .id(selection)
                .transition(.opacity)
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
            if newSelection != .feed {
                highlightedFeedRequestID = nil
            }
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selection {
        case .today:
            DashboardView(
                isShowingActivityPicker: $isShowingActivityPicker,
                isShowingBlockingActivityPicker: $isShowingBlockingActivityPicker
            )
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
            SettingsView(
                isShowingActivityPicker: $isShowingActivityPicker,
                onShowActivityPicker: {
                    isShowingActivityPicker = true
                },
                onShowBlockingActivityPicker: {
                    isShowingBlockingActivityPicker = true
                }
            )
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
