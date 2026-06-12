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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Explicitly request alert permission up front. registerForRemoteNotifications()
        // returns an APNs token even without alert permission, so a server *alert*
        // push is silently dropped by iOS unless the user has authorized alerts.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Forward the token to the push server so it can send alert pushes that
        // arrive even when the app is force-quit.
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
        Task { @MainActor in
            await RemoteChangeCenter.shared.handleRemoteChange()
            completionHandler(.newData)
        }
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

