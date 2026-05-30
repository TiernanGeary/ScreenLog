import CloudKit
import UIKit
import UserNotifications

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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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
final class FriendRequestNotificationCenter {
    static let shared = FriendRequestNotificationCenter()

    var handler: ((String) -> Void)? {
        didSet {
            flush()
        }
    }

    private var pendingRequestIDs: [String] = []

    func receive(requestID: String) {
        pendingRequestIDs.append(requestID)
        flush()
    }

    private func flush() {
        guard let handler else {
            return
        }

        let pending = pendingRequestIDs
        pendingRequestIDs.removeAll()
        pending.forEach(handler)
    }
}

struct ShieldFriendRequestNotificationService {
    static let categoryIdentifier = "shield-friend-time-request"
    static let groupIDUserInfoKey = "shieldFriendRequestGroupID"
}

@MainActor
final class ShieldFriendRequestNotificationCenter {
    static let shared = ShieldFriendRequestNotificationCenter()

    var handler: ((String?) -> Void)? {
        didSet {
            flush()
        }
    }

    private var pendingGroupIDs: [String?] = []

    func receive(groupID: String?) {
        pendingGroupIDs.append(groupID)
        flush()
    }

    private func flush() {
        guard let handler else {
            return
        }

        let pending = pendingGroupIDs
        pendingGroupIDs.removeAll()
        pending.forEach(handler)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.content.categoryIdentifier == FriendRequestNotificationService.categoryIdentifier
            || notification.request.content.categoryIdentifier == ShieldFriendRequestNotificationService.categoryIdentifier else {
            return []
        }

        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.notification.request.content.categoryIdentifier == ShieldFriendRequestNotificationService.categoryIdentifier {
            let groupID = response.notification.request.content.userInfo[
                ShieldFriendRequestNotificationService.groupIDUserInfoKey
            ] as? String
            await MainActor.run {
                ShieldFriendRequestNotificationCenter.shared.receive(groupID: groupID)
            }
            return
        }

        guard let requestID = response.notification.request.content.userInfo[FriendRequestNotificationService.requestIDUserInfoKey] as? String else {
            return
        }

        await MainActor.run {
            FriendRequestNotificationCenter.shared.receive(requestID: requestID)
        }
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
