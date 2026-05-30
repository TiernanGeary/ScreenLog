import CloudKit
import SwiftUI
import UIKit

@main
struct ScreenTimeSharingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appearanceMode.colorScheme)
                .onAppear {
                    CloudKitShareAcceptanceCenter.shared.handler = { metadata in
                        model.presentFriendShareInvite(metadata: metadata)
                    }
                    FriendRequestNotificationCenter.shared.handler = { requestID in
                        model.openFriendRequestLog(requestID: requestID)
                    }
                    ShieldFriendRequestNotificationCenter.shared.handler = { groupID in
                        model.openPendingShieldFriendRequestFromNotification(groupID: groupID)
                    }
                }
                .onOpenURL { url in
                    guard url.host()?.localizedCaseInsensitiveContains("icloud.com") == true else {
                        return
                    }

                    Task {
                        await model.presentFriendShareInvite(url: url)
                    }
                }
                .task {
                    // Restore an existing Apple session (and backfill its cloud
                    // recovery key) before load() publishes/syncs the profile,
                    // so recovery wins any race with a freshly created profile.
                    await model.checkExistingSession()
                    await model.load()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else {
                        return
                    }

                    while !Task.isCancelled {
                        await model.syncFriendRequests()
                        try? await Task.sleep(for: .seconds(15))
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else {
                        return
                    }

                    model.reloadUsageHistoryFromSharedStorage()
                    model.requestScreenTimeReportRefresh()
                    model.refreshPendingShieldFriendRequest()
                    Task {
                        await model.syncFriendRequests()
                    }
                }
        }
    }
}
