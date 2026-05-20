import CloudKit
import UIKit

@MainActor
final class CloudKitShareAcceptanceCenter {
    static let shared = CloudKitShareAcceptanceCenter()

    var handler: ((CKShare.Metadata) -> Void)? {
        didSet {
            flush()
        }
    }

    private var pendingMetadata: [CKShare.Metadata] = []

    func receive(_ metadata: CKShare.Metadata) {
        pendingMetadata.append(metadata)
        flush()
    }

    private func flush() {
        guard let handler else {
            return
        }

        let pending = pendingMetadata
        pendingMetadata.removeAll()
        pending.forEach(handler)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareAcceptingSceneDelegate.self
        return configuration
    }
}

@MainActor
final class ShareAcceptingSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            CloudKitShareAcceptanceCenter.shared.receive(metadata)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudKitShareAcceptanceCenter.shared.receive(cloudKitShareMetadata)
    }
}
