import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ScreenLogShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(
            copy: ShieldCopy.make(
                itemName: application.localizedDisplayName
            )
        )
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            copy: ShieldCopy.make(
                itemName: application.localizedDisplayName
            )
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(
            copy: ShieldCopy.make(
                itemName: "this website"
            )
        )
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            copy: ShieldCopy.make(
                itemName: "this website"
            )
        )
    }

    private func configuration(copy: ShieldCopy) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: nil,
            title: ShieldConfiguration.Label(
                text: copy.title,
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: copy.subtitle,
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: copy.primaryButton,
                color: .white
            ),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: copy.secondaryButton,
                color: copy.isFriendRequestEnabled ? .systemBlue : .tertiaryLabel
            )
        )
    }
}

private struct ShieldCopy {
    let title: String
    let subtitle: String
    let primaryButton: String
    let secondaryButton: String
    let isFriendRequestEnabled: Bool

    static func make(itemName: String?) -> ShieldCopy {
        let restrictedItemName = normalizedItemName(itemName)
        let friendRequestGroupID = ShieldRuntimeDefaults.friendRequestGroupID()
        let pendingGroupID = ShieldRuntimeDefaults.pendingFriendRequestGroupID()

        if let friendRequestGroupID,
           friendRequestGroupID == pendingGroupID {
            return ShieldCopy(
                title: "Request ready",
                subtitle: "Open ScreenLog to take your photo request for \(restrictedItemName).",
                primaryButton: "OK",
                secondaryButton: "Open ScreenLog",
                isFriendRequestEnabled: true
            )
        }

        let hasFriendRequest = friendRequestGroupID != nil
        return ShieldCopy(
            title: "Restricted",
            subtitle: "You cannot use \(restrictedItemName) because it is restricted.",
            primaryButton: "OK",
            secondaryButton: hasFriendRequest ? "Request time from friends" : "Friend request disabled",
            isFriendRequestEnabled: hasFriendRequest
        )
    }

    private static func normalizedItemName(_ itemName: String?) -> String {
        let trimmed = itemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "this app" : trimmed
    }
}

private enum ShieldRuntimeDefaults {
    private static let suiteName = "group.com.jdco.ScreenLog"
    private static let friendRequestGroupIDKey = "BlockingShieldFriendRequestGroupID.v1"
    private static let pendingGroupIDKey = "PendingShieldFriendRequestGroupID.v1"
    private static let pendingCreatedAtKey = "PendingShieldFriendRequestCreatedAt.v1"
    private static let pendingExpirationSeconds: TimeInterval = 10 * 60

    nonisolated(unsafe) private static let defaults: UserDefaults? =
        UserDefaults(suiteName: suiteName)

    static func friendRequestGroupID() -> String? {
        normalizedGroupID(defaults?.string(forKey: friendRequestGroupIDKey))
    }

    static func pendingFriendRequestGroupID(now: Date = Date()) -> String? {
        guard let groupID = normalizedGroupID(defaults?.string(forKey: pendingGroupIDKey)) else {
            return nil
        }

        let createdAt = defaults?.object(forKey: pendingCreatedAtKey) as? Date
        if let createdAt,
           now.timeIntervalSince(createdAt) <= pendingExpirationSeconds {
            return groupID
        }

        return nil
    }

    private static func normalizedGroupID(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
