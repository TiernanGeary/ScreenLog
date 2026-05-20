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
                .onAppear {
                    CloudKitShareAcceptanceCenter.shared.handler = { metadata in
                        Task {
                            await model.acceptShare(metadata: metadata)
                        }
                    }
                }
                .task {
                    await model.load()
                }
        }
    }
}
