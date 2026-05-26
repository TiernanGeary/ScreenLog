import Foundation
import ManagedSettings

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
            completionHandler(queued ? .screenLogOpenParentalControlsApp : .none)
        @unknown default:
            completionHandler(.none)
        }
    }
}

private extension ShieldActionResponse {
    // Xcode 16.4's iOS 18.5 SDK does not expose the named case yet. Apple's newer
    // SDK documents this as `openParentalControlsApp`, after `defer`.
    static var screenLogOpenParentalControlsApp: ShieldActionResponse {
        ShieldActionResponse(rawValue: 3) ?? .close
    }
}

private enum ShieldFriendRequestIntentStore {
    private static let suiteName = "group.com.jdco.ScreenLog"
    private static let friendRequestGroupIDKey = "BlockingShieldFriendRequestGroupID.v1"
    private static let pendingGroupIDKey = "PendingShieldFriendRequestGroupID.v1"
    private static let pendingCreatedAtKey = "PendingShieldFriendRequestCreatedAt.v1"

    nonisolated(unsafe) private static let defaults: UserDefaults? =
        UserDefaults(suiteName: suiteName)

    static func queueFriendRequestDraft() -> Bool {
        defaults?.synchronize()

        guard let groupID = friendRequestGroupID() else {
            return false
        }

        defaults?.set(groupID, forKey: pendingGroupIDKey)
        defaults?.set(Date(), forKey: pendingCreatedAtKey)
        defaults?.synchronize()
        return true
    }

    private static func friendRequestGroupID() -> String? {
        let trimmed = defaults?
            .string(forKey: friendRequestGroupIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
