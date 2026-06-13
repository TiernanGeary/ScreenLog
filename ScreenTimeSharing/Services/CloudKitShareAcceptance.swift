import CloudKit
import UIKit
import UserNotifications

@MainActor
final class RemoteChangeCenter {
    static let shared = RemoteChangeCenter()

    var handler: (() async -> Void)?

    var deviceTokenHandler: ((String) -> Void)? {
        didSet {
            if let pendingDeviceToken {
                deviceTokenHandler?(pendingDeviceToken)
            }
        }
    }

    private var pendingDeviceToken: String?

    func handleRemoteChange() async {
        await handler?()
    }

    func receiveDeviceToken(_ token: String) {
        pendingDeviceToken = token
        deviceTokenHandler?(token)
    }
}

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
        // Notification authorization is requested during onboarding's final page,
        // coordinated with Screen Time and camera, instead of ambushing the user at
        // launch. Still register for remote notifications so we have an APNs token;
        // iOS only delivers *alert* pushes once the user has authorized them (which
        // onboarding handles), while silent CloudKit pushes work regardless.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit manages its own token; we also forward it to the push server
        // so it can send alert pushes that arrive even when the app is force-quit.
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            RemoteChangeCenter.shared.receiveDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        // Non-fatal: push just won't arrive; the app still syncs on launch/foreground.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            await RemoteChangeCenter.shared.handleRemoteChange()
            completionHandler(.newData)
        }
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
