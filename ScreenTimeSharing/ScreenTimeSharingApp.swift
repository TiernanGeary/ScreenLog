import CloudKit
import SwiftUI
import UIKit

@main
struct ScreenTimeSharingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.appearanceMode.colorScheme)
                .onAppear {
                    CloudKitShareAcceptanceCenter.shared.handler = { metadata in
                        Task {
                            await model.acceptShare(metadata: metadata)
                        }
                    }
                    FriendRequestNotificationCenter.shared.handler = { requestID in
                        model.openFriendRequestLog(requestID: requestID)
                    }
                }
                .task {
                    await model.load()
                }
        }
    }
}
