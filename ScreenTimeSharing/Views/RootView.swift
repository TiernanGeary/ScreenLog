import FamilyControls
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingActivityPicker = false

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                AppTabs(isShowingActivityPicker: $isShowingActivityPicker)
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
                                model.persistSelection()
                                isShowingActivityPicker = false
                            }
                        }
                    }
            }
        }
    }
}

private struct AppTabs: View {
    @Binding var isShowingActivityPicker: Bool
    @State private var selection: AppTab = .today

    var body: some View {
        ZStack {
            selectedView
                .id(selection)
                .transition(.opacity)
        }
        .animation(.snappy(duration: 0.22), value: selection)
        .safeAreaInset(edge: .bottom) {
            GlassTabBar(selection: $selection)
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selection {
        case .today:
            DashboardView(isShowingActivityPicker: $isShowingActivityPicker)
        case .friends:
            FriendsView()
        case .leaders:
            LeaderboardView()
        case .settings:
            SettingsView(isShowingActivityPicker: $isShowingActivityPicker)
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case today
    case friends
    case leaders
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .friends:
            return "Friends"
        case .leaders:
            return "Leaders"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            return "clock"
        case .friends:
            return "person.2"
        case .leaders:
            return "trophy"
        case .settings:
            return "gearshape"
        }
    }
}

private struct GlassTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                GlassTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    namespace: indicatorNamespace
                ) {
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
    let tab: AppTab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: 16, weight: isSelected ? .bold : .semibold))
                    .frame(width: 20, height: 19)

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
