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
                OnboardingView()
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

    var body: some View {
        TabView {
            DashboardView(isShowingActivityPicker: $isShowingActivityPicker)
                .tabItem {
                    Label("Today", systemImage: "clock")
                }

            FriendsView()
                .tabItem {
                    Label("Friends", systemImage: "person.2")
                }

            SettingsView(isShowingActivityPicker: $isShowingActivityPicker)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
