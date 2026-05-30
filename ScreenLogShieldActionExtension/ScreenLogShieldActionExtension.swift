import Foundation
import ManagedSettings
@preconcurrency import UserNotifications

final class ScreenLogShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, completionHandler: completionHandler)
    }

    private func handle(
        action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            let queued = ShieldFriendRequestIntentStore.queueFriendRequestDraft()
            if queued {
                ShieldFriendRequestIntentStore.scheduleOpenAppNotification()
            }
            completionHandler(queued ? .close : .none)
        @unknown default:
            completionHandler(.none)
        }
    }
}

private enum ShieldFriendRequestIntentStore {
    private static let suiteName = "group.com.jdco.ScreenLog"
    private static let friendRequestGroupIDKey = "BlockingShieldFriendRequestGroupID.v1"
    private static let pendingGroupIDKey = "PendingShieldFriendRequestGroupID.v1"
    private static let pendingCreatedAtKey = "PendingShieldFriendRequestCreatedAt.v1"
    private static let notificationCategoryIdentifier = "shield-friend-time-request"
    private static let notificationGroupIDUserInfoKey = "shieldFriendRequestGroupID"

    nonisolated(unsafe) private static let defaults: UserDefaults? =
        UserDefaults(suiteName: suiteName)

    nonisolated(unsafe) private static var lastQueuedGroupID: String?

    static func queueFriendRequestDraft() -> Bool {
        defaults?.synchronize()

        guard let groupID = friendRequestGroupID() else {
            return false
        }

        lastQueuedGroupID = groupID
        defaults?.set(groupID, forKey: pendingGroupIDKey)
        defaults?.set(Date(), forKey: pendingCreatedAtKey)
        defaults?.synchronize()
        return true
    }

    static func scheduleOpenAppNotification() {
        guard let groupID = lastQueuedGroupID ?? friendRequestGroupID() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Request time from friends"
        content.body = "Tap to open deny and take your pleading photo."
        content.sound = .default
        content.categoryIdentifier = notificationCategoryIdentifier
        content.userInfo = [notificationGroupIDUserInfoKey: groupID]

        let request = UNNotificationRequest(
            identifier: "shield-friend-time-request-\(groupID)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else {
                        return
                    }
                    center.add(request)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private static func friendRequestGroupID() -> String? {
        let trimmed = defaults?
            .string(forKey: friendRequestGroupIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
