import Foundation

enum AppConfiguration {
    static let appGroupIdentifier = WidgetCacheCodec.suiteName
    static let cloudKitContainerIdentifier = "iCloud.com.jdco.ScreenTimeSharing"
    static let defaultAvatarColor = "#1B998B"
    static let avatarFallbackColors = ["#1B998B", "#2E86AB", "#E84855", "#6A4C93", "#F18F01", "#2F4858"]

    static func randomAvatarColorHex() -> String {
        avatarFallbackColors.randomElement() ?? defaultAvatarColor
    }
}
