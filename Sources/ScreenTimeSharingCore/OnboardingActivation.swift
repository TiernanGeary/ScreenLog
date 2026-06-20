import Foundation

public enum OnboardingInvite {
    /// Share text for the onboarding invite step. Includes BOTH the App Store
    /// install link (for friends who don't have the app) and the deny:// invite
    /// link (taps auto-connect once installed). Manual code is intentionally omitted.
    public static func shareMessage(displayName: String?,
                                    appStoreURL: URL,
                                    inviteURL: URL) -> String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespaces)
        let who = (trimmed?.isEmpty == false && trimmed != "Me") ? trimmed! : "me"
        return """
        I'm using Deny to take back control of my screen time. Get it: \
        \(appStoreURL.absoluteString)
        Then tap to add \(who): \(inviteURL.absoluteString)
        """
    }
}

public enum OnboardingBlock {
    /// Onboarding requires at least one app/category/web selection before the
    /// user can start their first block.
    public static func meetsMinimumSelection(appCount: Int,
                                             categoryCount: Int,
                                             webCount: Int) -> Bool {
        (appCount + categoryCount + webCount) >= 1
    }
}

extension OnboardingBlock {
    /// Builds the onboarding "first block" with the mode the user configured
    /// during setup (time limit or schedule). The caller passes the resulting
    /// group to AppModel.upsertBlockGroup(_:password:), which persists and
    /// immediately enforces it.
    public static func makeFirstBlockGroup(id: String,
                                           name: String,
                                           selectionData: Data,
                                           mode: BlockGroupMode = .defaultTimeLimit) -> BlockGroup {
        let now = Date()
        return BlockGroup(
            id: id,
            name: name,
            colorHex: "#E84855",
            selectionData: selectionData,
            isEnabled: true,
            mode: mode,
            createdAt: now,
            updatedAt: now
        )
    }
}
