import Foundation

enum AppConfiguration {
    static let appGroupIdentifier = ScreenTimeReportStorage.appGroupSuiteName
    static let cloudKitContainerIdentifier = "iCloud.com.jdco.ScreenTimeSharing"
    static let defaultAvatarColor = "#1B998B"
    static let avatarFallbackColors = ["#1B998B", "#2E86AB", "#E84855", "#6A4C93", "#F18F01", "#2F4858"]

    static let subscriptionProductIDs: Set<String> = [
        "com.jdco.deny.subscription.monthly",
        "com.jdco.deny.subscription.yearly"
    ]

    static func randomAvatarColorHex() -> String {
        avatarFallbackColors.randomElement() ?? defaultAvatarColor
    }
}
