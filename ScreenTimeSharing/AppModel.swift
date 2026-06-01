import CloudKit
import FamilyControls
import Foundation
import SwiftUI
@preconcurrency import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }

    var systemImage: String {
        switch self {
        case .dark:
            return "moon.fill"
        case .light:
            return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

struct FriendRequestPhotoStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupIdentifier)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = baseURL.appendingPathComponent("FriendRequestPhotos", isDirectory: true)
    }

    func saveJPEGData(_ data: Data, id: String = UUID().uuidString) throws -> BlockFriendRequestPhotoReference {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: url(for: id), options: [.atomic])
        return BlockFriendRequestPhotoReference(localIdentifier: id)
    }

    func data(for reference: BlockFriendRequestPhotoReference) -> Data? {
        try? Data(contentsOf: url(for: reference.localIdentifier))
    }

    func hasPhoto(id: String) -> Bool {
        fileManager.fileExists(atPath: url(for: id).path)
    }

    private func url(for id: String) -> URL {
        directoryURL.appendingPathComponent("\(id).jpg", isDirectory: false)
    }
}

#if canImport(UIKit)
enum FriendRequestDemoPhotoFactory {
    static func jpegData(
        name: String,
        background: (UIColor, UIColor),
        shirt: UIColor,
        expressionOffset: CGFloat
    ) -> Data? {
        let size = CGSize(width: 900, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let colors = [background.0.cgColor, background.1.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width * 0.12, y: 0),
                    end: CGPoint(x: size.width * 0.88, y: size.height),
                    options: []
                )
            }

            UIColor.white.withAlphaComponent(0.15).setFill()
            UIBezierPath(ovalIn: CGRect(x: -120, y: 80, width: 430, height: 430)).fill()
            UIBezierPath(ovalIn: CGRect(x: size.width - 260, y: 270, width: 360, height: 360)).fill()

            UIColor.black.withAlphaComponent(0.22).setFill()
            UIBezierPath(ovalIn: CGRect(x: 205, y: 720, width: 490, height: 560)).fill()

            shirt.setFill()
            UIBezierPath(roundedRect: CGRect(x: 130, y: 790, width: 640, height: 520), cornerRadius: 260).fill()

            UIColor(red: 0.86, green: 0.64, blue: 0.49, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 258, y: 276, width: 384, height: 446)).fill()

            UIColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 250, y: 230, width: 400, height: 230)).fill()
            UIBezierPath(roundedRect: CGRect(x: 222, y: 330, width: 110, height: 250), cornerRadius: 54).fill()
            UIBezierPath(roundedRect: CGRect(x: 570, y: 330, width: 105, height: 250), cornerRadius: 52).fill()

            UIColor.black.withAlphaComponent(0.78).setFill()
            UIBezierPath(ovalIn: CGRect(x: 355, y: 496, width: 34, height: 42)).fill()
            UIBezierPath(ovalIn: CGRect(x: 512, y: 496, width: 34, height: 42)).fill()

            UIColor.white.withAlphaComponent(0.72).setFill()
            UIBezierPath(ovalIn: CGRect(x: 365, y: 503, width: 10, height: 10)).fill()
            UIBezierPath(ovalIn: CGRect(x: 522, y: 503, width: 10, height: 10)).fill()

            UIColor(red: 0.68, green: 0.37, blue: 0.29, alpha: 1).setStroke()
            let mouth = UIBezierPath()
            mouth.lineWidth = 9
            mouth.lineCapStyle = .round
            mouth.move(to: CGPoint(x: 392, y: 612))
            mouth.addQuadCurve(
                to: CGPoint(x: 508, y: 612),
                controlPoint: CGPoint(x: 450, y: 646 + expressionOffset)
            )
            mouth.stroke()

            UIColor.white.withAlphaComponent(0.28).setFill()
            UIBezierPath(roundedRect: CGRect(x: 70, y: 70, width: 760, height: 90), cornerRadius: 45).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ]
            let text = "Please?"
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: 91),
                withAttributes: attributes
            )
        }

        return image.jpegData(compressionQuality: 0.86)
    }
}
#endif

private struct UsageHistorySignature: Equatable {
    let snapshotCount: Int
    let latestSnapshotUpdate: Date?
    let totalDuration: TimeInterval
    let hourlyDayCount: Int
    let hourlyDuration: TimeInterval
}

@MainActor
final class IncomingFriendShareInvite: Identifiable {
    let id: String
    let metadata: CKShare.Metadata
    let displayName: String
    let avatarImageData: Data?

    init(metadata: CKShare.Metadata) {
        self.metadata = metadata
        self.id = [
            metadata.share.recordID.zoneID.ownerName,
            metadata.share.recordID.zoneID.zoneName,
            metadata.share.recordID.recordName
        ].joined(separator: ":")
        self.displayName = Self.resolvedDisplayName(from: metadata)
        self.avatarImageData = Self.thumbnailImageData(from: metadata)
    }

    private static func resolvedDisplayName(from metadata: CKShare.Metadata) -> String {
        if let title = metadata.share[CKShare.SystemFieldKey.title] as? String,
           let name = nameFromShareTitle(title) {
            return name
        }

        if let nameComponents = metadata.ownerIdentity.nameComponents {
            let formattedName = PersonNameComponentsFormatter.localizedString(
                from: nameComponents,
                style: .medium,
                options: []
            )
            let trimmedName = formattedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                return trimmedName
            }
        }

        return "Friend"
    }

    private static func nameFromShareTitle(_ title: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = ["'s Screen Time", "’s Screen Time"]

        for suffix in suffixes where trimmedTitle.hasSuffix(suffix) {
            let name = String(trimmedTitle.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name.localizedCaseInsensitiveCompare("Me") != .orderedSame {
                return name
            }
        }

        return nil
    }

    private static func thumbnailImageData(from metadata: CKShare.Metadata) -> Data? {
        if let data = metadata.share[CKShare.SystemFieldKey.thumbnailImageData] as? Data {
            return data
        }

        if let data = metadata.share[CKShare.SystemFieldKey.thumbnailImageData] as? NSData {
            return data as Data
        }

        return nil
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile
    @Published var appearanceMode: AppAppearanceMode
    @Published var selection: FamilyActivitySelection
    @Published var blockingState: BlockingState
    @Published var localSnapshot: DailyUsageSnapshot?
    @Published var usageHistory: [DailyUsageSnapshot] = []
    @Published var hourlyUsageByDayID: [String: [TimeInterval]] = [:]
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var leaderboardWindow: LeaderboardWindow = .week
    @Published var cloudAvailability: CloudAvailability = .checking
    @Published var screenTimeAuthorization = "Not requested"
    @Published var screenTimeReportRefreshID = UUID()
    @Published var screenTimeReportStatus = "Waiting for Screen Time setup."
    @Published var screenTimeReportLastGeneratedAt: Date?
    @Published var message: String?
    @Published var isWorking = false
    @Published var hasCompletedOnboarding: Bool
    @Published private(set) var groupUnlockExpirations: [String: Date] = [:]
    @Published var pendingShieldFriendRequestGroupID: String?
    @Published var focusedFriendRequestLogID: String?
    @Published var pendingFriendShareInvite: IncomingFriendShareInvite?
    @Published var isAcceptingFriendShareInvite = false
    @Published var isAuthenticated: Bool

    let snapshotStore: CloudKitUsageSnapshotStore
    let subscriptionService: SubscriptionService
    let denyStartedAt: Date

    private let profileStore: LocalProfileStore
    private let appleSignInService: AppleSignInService
    private let selectionStore: FamilyActivitySelectionStore
    private let screenTimeProvider: ScreenTimeProvider
    private let widgetCacheWriter: AppGroupWidgetCacheWriter
    private let blockingStore: BlockingStateStore
    private let blockingEnforcementService: BlockingEnforcementService
    private let friendRequestNotificationService: FriendRequestNotificationService
    private let friendRequestPhotoStore: FriendRequestPhotoStore
    private let pushServerClient = PushServerClient()
    private var apnsDeviceToken: String?
    private let usageHistoryDefaults: UserDefaults?
    private let onboardingKey = "HasCompletedOnboarding.v1"
    private static let denyStartedAtKey = "DenyStartedAt.v1"
    private static let appearanceKey = "AppAppearanceMode.v1"
    private var isSyncingFriendRequests = false
    #if DEBUG
    private let demoFriendsKey = "UsesDemoFriends.v1"
    #endif

    init(
        profileStore: LocalProfileStore = LocalProfileStore(),
        selectionStore: FamilyActivitySelectionStore = FamilyActivitySelectionStore(),
        screenTimeProvider: ScreenTimeProvider = DeviceActivityScreenTimeProvider(),
        snapshotStore: CloudKitUsageSnapshotStore = CloudKitUsageSnapshotStore(),
        widgetCacheWriter: AppGroupWidgetCacheWriter = AppGroupWidgetCacheWriter(),
        blockingStore: BlockingStateStore = BlockingStateStore(),
        blockingEnforcementService: BlockingEnforcementService = BlockingEnforcementService(),
        friendRequestNotificationService: FriendRequestNotificationService = FriendRequestNotificationService(),
        friendRequestPhotoStore: FriendRequestPhotoStore = FriendRequestPhotoStore(),
        appleSignInService: AppleSignInService = AppleSignInService(),
        subscriptionService: SubscriptionService = SubscriptionService()
    ) {
        self.profileStore = profileStore
        self.selectionStore = selectionStore
        self.screenTimeProvider = screenTimeProvider
        self.snapshotStore = snapshotStore
        self.widgetCacheWriter = widgetCacheWriter
        self.blockingStore = blockingStore
        self.blockingEnforcementService = blockingEnforcementService
        self.friendRequestNotificationService = friendRequestNotificationService
        self.friendRequestPhotoStore = friendRequestPhotoStore
        self.appleSignInService = appleSignInService
        self.subscriptionService = subscriptionService
        self.isAuthenticated = KeychainAppleID.load() != nil
        let sharedDefaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)
        let loadedProfile = profileStore.load()
        self.usageHistoryDefaults = sharedDefaults
        self.profile = loadedProfile
        let storedDenyStartedAt = UserDefaults.standard.object(forKey: Self.denyStartedAtKey) as? Date
        let denyStartedAt = storedDenyStartedAt ?? Date()
        self.denyStartedAt = denyStartedAt
        if storedDenyStartedAt == nil {
            UserDefaults.standard.set(denyStartedAt, forKey: Self.denyStartedAtKey)
        }
        ScreenTimeReportStorage.saveProfileID(loadedProfile.id, defaults: sharedDefaults)
        self.appearanceMode = AppAppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ""
        ) ?? .dark
        self.selection = selectionStore.load()
        self.blockingState = blockingStore.load()
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        self.screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        self.screenTimeReportLastGeneratedAt = sharedDefaults?.object(
            forKey: ScreenTimeReportStorage.lastGeneratedAtKey
        ) as? Date
        self.screenTimeReportStatus = Self.screenTimeReportStatusLabel(
            authorization: self.screenTimeAuthorization,
            defaults: sharedDefaults
        )
        loadUsageHistory()
        expireStaleFriendRequests()
        loadPendingShieldFriendRequest()
        refreshLocalAccountabilityStats()
        syncFriendRequestNotifications()
        #if DEBUG && targetEnvironment(simulator)
        let demoNow = Date()
        seedDemoUsageHistory(now: demoNow)
        #else
        self.localSnapshot = UsageStatsBuilder.snapshot(for: Date(), in: usageHistory)
            ?? usageHistory.sorted { $0.date > $1.date }.first
        #endif
    }

    var selectedActivityCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var hasScreenTimeAuthorization: Bool {
        Self.isScreenTimeAuthorizationApproved(screenTimeAuthorization)
    }

    var hasCompletedScreenTimeReport: Bool {
        screenTimeReportLastGeneratedAt != nil || !usageHistory.isEmpty
    }

    var activeBlockingRulesCount: Int {
        BlockingStateResolver.enabledGroups(in: blockingState).count
    }

    var pendingBlockRequestCount: Int {
        BlockingStateResolver.pendingRequests(in: blockingState).count
            + BlockingStateResolver.pendingFriendRequests(in: blockingState).count
    }

    var pendingShieldFriendRequestGroup: BlockGroup? {
        guard let pendingShieldFriendRequestGroupID else {
            return nil
        }

        return blockingState.groups.first { group in
            group.id == pendingShieldFriendRequestGroupID
                && group.isEnabled
                && group.friendRequestConfig.isEnabled
        }
    }

    private var currentFriendIdentityIDs: Set<String> {
        [profile.id, "profile-\(profile.id)"]
    }

    func load() async {
        screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        expireStaleFriendRequests()
        loadPendingShieldFriendRequest()
        await subscriptionService.checkEntitlements()
        await subscriptionService.loadProducts()
        cloudAvailability = await snapshotStore.cloudAvailability()
        await snapshotStore.ensureSubscriptions()
        await migrateLegacyFriendRequestRecords()
        await publishProfileUpdateToCloud()
        await reloadFriends()
        await syncFriendRequests()
        syncFriendRequestNotifications()
        syncBlockingEnforcement()
        requestScreenTimeReportRefresh()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    func signInWithApple() async throws -> AppleCredential {
        let credential = try await appleSignInService.signIn()

        if let existingProfile = try? await snapshotStore.fetchExistingProfile(id: credential.userID) {
            profileStore.restoreProfile(existingProfile, appleUserID: credential.userID)
            profile = existingProfile
        } else {
            profile = profileStore.load(appleUserID: credential.userID)
            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter.localizedString(
                    from: fullName,
                    style: .medium,
                    options: []
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != "Me" {
                    profile.displayName = name
                    profile.updatedAt = Date()
                    profileStore.save(profile)
                }
            }
        }

        isAuthenticated = true
        // Persist the Apple identifier to CloudKit so this profile can be
        // recovered by `fetchExistingProfile(id:)` on reinstall or a new device.
        await publishProfileUpdateToCloud()
        return credential
    }

    func checkExistingSession() async {
        guard let appleUserID = await appleSignInService.checkExistingCredential() else {
            isAuthenticated = false
            return
        }

        if let existingProfile = try? await snapshotStore.fetchExistingProfile(id: appleUserID) {
            profileStore.restoreProfile(existingProfile, appleUserID: appleUserID)
            profile = existingProfile
        } else {
            profile = profileStore.load(appleUserID: appleUserID)
        }

        isAuthenticated = true
        // Backfill the Apple identifier on the cloud profile for sessions created
        // before recovery existed, so the field is queryable on next reinstall.
        if profile.appleUserID == nil {
            profile.appleUserID = appleUserID
            profileStore.save(profile)
        }
        await publishProfileUpdateToCloud()
    }

    #if DEBUG
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: onboardingKey)
        message = "Onboarding reset. Relaunch or continue through the setup flow again."
    }
    #endif

    #if DENY_INTERNAL_DEBUG
    /// Debug-only full reset: wipes this device's local identity + accepted
    /// shares AND the user's CloudKit data, then drops back to onboarding. Use to
    /// clear corrupted legacy state (drifted profile IDs, stale channels) so a
    /// fresh re-invite starts from a clean slate. Both devices should run this.
    func resetAccountForDebugging() async {
        isWorking = true
        defer { isWorking = false }

        await snapshotStore.resetAllCloudData()

        profileStore.clearAll()
        friendSummaries = []
        leaderboardEntries = []
        blockingState.friendRequests = []
        try? persistBlockingState()

        UserDefaults.standard.set(false, forKey: onboardingKey)
        isAuthenticated = false
        hasCompletedOnboarding = false
        profile = profileStore.load()
        message = "Account reset. Re-onboard, then re-invite your friend on both devices."
    }
    #endif

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        guard appearanceMode != mode else {
            return
        }

        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceKey)
    }

    func updateProfile(displayName: String? = nil, avatarColorHex: String? = nil, avatarImageData: Data? = nil) {
        if let displayName {
            profile.displayName = displayName
        }

        if let avatarColorHex {
            profile.avatarColorHex = avatarColorHex
        }

        if let avatarImageData {
            profile.avatarImageData = avatarImageData
        }

        profile.updatedAt = Date()
        profileStore.save(profile)
        ScreenTimeReportStorage.saveProfileID(profile.id, defaults: usageHistoryDefaults)
        Task {
            await publishProfileUpdateToCloud()
        }
    }

    func friendRequestPhotoData(for request: BlockFriendRequest) -> Data? {
        guard let photoReference = request.photoReference else {
            return nil
        }

        return friendRequestPhotoStore.data(for: photoReference)
    }

    func persistSelection() {
        selectionStore.save(selection)
        requestScreenTimeReportRefresh()
    }

    func requestScreenTimeReportRefresh() {
        refreshScreenTimeReportStatus()
        screenTimeReportRefreshID = UUID()
    }

    func refreshScreenTimeReportStatus() {
        screenTimeReportLastGeneratedAt = usageHistoryDefaults?.object(
            forKey: ScreenTimeReportStorage.lastGeneratedAtKey
        ) as? Date
        screenTimeReportStatus = Self.screenTimeReportStatusLabel(
            authorization: screenTimeAuthorization,
            defaults: usageHistoryDefaults
        )
    }

    @discardableResult
    func reloadUsageHistoryFromSharedStorage() -> Bool {
        let previousHistorySignature = usageHistorySignature()
        let previousSnapshotID = localSnapshot?.id
        let previousLastUpdated = localSnapshot?.lastUpdated
        loadUsageHistory()
        refreshLocalSnapshotFromHistory()

        let didChange = usageHistorySignature() != previousHistorySignature
            || localSnapshot?.id != previousSnapshotID
            || localSnapshot?.lastUpdated != previousLastUpdated
        refreshScreenTimeReportStatus()
        if didChange {
            message = "Screen Time updated."
            writeWidgetCacheSnapshot()
        }
        return didChange
    }

    private func usageHistorySignature() -> UsageHistorySignature {
        UsageHistorySignature(
            snapshotCount: usageHistory.count,
            latestSnapshotUpdate: usageHistory.map(\.lastUpdated).max(),
            totalDuration: usageHistory.reduce(TimeInterval(0)) { partial, snapshot in
                partial + max(0, snapshot.totalDuration ?? 0)
            },
            hourlyDayCount: hourlyUsageByDayID.count,
            hourlyDuration: hourlyUsageByDayID.values.reduce(TimeInterval(0)) { partial, values in
                partial + values.reduce(TimeInterval(0)) { $0 + max(0, $1) }
            }
        )
    }

    func addDailyAllowanceRule(groupID: String, seconds: TimeInterval) {
        updateGroupMode(
            groupID: groupID,
            mode: .timeLimit(
                limitSeconds: BlockingTimeLimitRange.snappedSeconds(seconds),
                days: BlockWeekday.everyDay
            ),
            status: "Time limit updated."
        )
    }

    func addScheduledRule(
        groupID: String,
        days: [BlockWeekday],
        startMinute: Int,
        endMinute: Int
    ) {
        updateGroupMode(
            groupID: groupID,
            mode: .scheduled(
                startMinute: startMinute,
                endMinute: endMinute,
                days: BlockRuleKind.normalizedDays(days)
            ),
            status: "Schedule updated."
        )
    }

    @discardableResult
    func toggleBlockGroup(_ group: BlockGroup, password: String? = nil) -> Bool {
        guard let index = blockingState.groups.firstIndex(where: { $0.id == group.id }) else {
            return false
        }

        guard canVerifyGroupPassword(blockingState.groups[index], password: password) else {
            message = "Enter this group password before changing it."
            return false
        }

        blockingState.groups[index].isEnabled.toggle()
        blockingState.groups[index].updatedAt = Date()
        saveBlockingStateWithStatus("Block group updated.")
        return true
    }

    func toggleBlockRule(_ rule: BlockRule) {
        guard let index = blockingState.rules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }

        blockingState.rules[index].isEnabled.toggle()
        blockingState.rules[index].updatedAt = Date()
        saveBlockingStateWithStatus("Block rule updated.")
    }

    func deleteBlockRule(_ rule: BlockRule) {
        blockingState.rules.removeAll { $0.id == rule.id }
        saveBlockingStateWithStatus("Block rule deleted.")
    }

    func requestExtraTime(groupID: String, seconds: TimeInterval) {
        let now = Date()
        let request = BlockRequest(
            id: UUID().uuidString,
            groupID: groupID,
            requestedSeconds: seconds,
            status: .pending,
            createdAt: now
        )

        blockingState.requests.insert(request, at: 0)
        saveBlockingStateWithStatus("Extra-time request logged.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
    }

    @discardableResult
    func upsertBlockGroup(_ group: BlockGroup, password: String?) -> Bool {
        guard group.mode.isValid else {
            message = "Pick a valid blocking schedule or time limit."
            return false
        }

        guard let selection = try? BlockingSelectionCodec.decode(group.selectionData),
              !selection.isEmpty else {
            message = "Choose at least one app, category, or website."
            return false
        }

        let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            message = "Name this block group."
            return false
        }

        var copy = group
        copy.name = trimmedName
        let now = Date()

        if let index = blockingState.groups.firstIndex(where: { $0.id == group.id }) {
            let existing = blockingState.groups[index]
            guard canEditGroup(existing, password: password) else {
                message = "Enter this group password before editing it."
                return false
            }

            copy.createdAt = existing.createdAt
            copy.updatedAt = now
            if let password, !password.isEmpty {
                copy.password = BlockingPasswordHasher.makePassword(password, now: now)
                copy.passwordReset = nil
                unlockGroup(id: copy.id, now: now)
            } else {
                copy.password = existing.password
                copy.passwordReset = existing.passwordReset
            }

            if copy.password == nil {
                message = "Set a password for this group before saving."
                return false
            }

            blockingState.groups[index] = copy
        } else {
            guard let password, !password.isEmpty else {
                message = "Set a password for this group before saving."
                return false
            }

            copy.id = copy.id.isEmpty ? UUID().uuidString : copy.id
            copy.createdAt = now
            copy.updatedAt = now
            copy.password = BlockingPasswordHasher.makePassword(password, now: now)
            copy.passwordReset = nil
            blockingState.groups.append(copy)
            unlockGroup(id: copy.id, now: now)
        }

        blockingState.rules.removeAll { $0.groupID == copy.id }
        saveBlockingStateWithStatus("Block group saved.")
        return true
    }

    @discardableResult
    func deleteBlockGroup(_ group: BlockGroup, password: String? = nil) -> Bool {
        guard canVerifyGroupPassword(group, password: password) else {
            message = "Enter this group password before deleting it."
            return false
        }

        blockingState.groups.removeAll { $0.id == group.id }
        blockingState.rules.removeAll { $0.groupID == group.id }
        blockingState.requests.removeAll { $0.groupID == group.id }
        blockingState.friendRequests.removeAll { $0.groupID == group.id }
        blockingState.unblockSessions.removeAll { $0.groupID == group.id }
        groupUnlockExpirations[group.id] = nil
        saveBlockingStateWithStatus("Block group deleted.")
        return true
    }

    @discardableResult
    func verifyPassword(for group: BlockGroup, password: String) -> Bool {
        guard let storedPassword = group.password,
              BlockingPasswordHasher.verify(password, against: storedPassword) else {
            message = "That password did not match."
            return false
        }

        unlockGroup(id: group.id)
        message = "Group unlocked for 5 minutes."
        return true
    }

    func isGroupUnlocked(_ group: BlockGroup) -> Bool {
        purgeExpiredGroupUnlocks()
        return groupUnlockExpirations[group.id, default: .distantPast] > Date()
    }

    func requestPasswordReset(for group: BlockGroup) {
        guard let index = blockingState.groups.firstIndex(where: { $0.id == group.id }) else {
            return
        }

        blockingState.groups[index].passwordReset = BlockPasswordResetState(requestedAt: Date())
        saveBlockingStateWithStatus("Password reset started. You can reset it after 1 minute.")
    }

    @discardableResult
    func completePasswordReset(for group: BlockGroup, newPassword: String) -> Bool {
        guard let index = blockingState.groups.firstIndex(where: { $0.id == group.id }) else {
            return false
        }

        guard let reset = blockingState.groups[index].passwordReset,
              reset.isAvailable() else {
            message = "Password reset is not available yet."
            return false
        }

        guard !newPassword.isEmpty else {
            message = "Enter a new password."
            return false
        }

        let now = Date()
        blockingState.groups[index].password = BlockingPasswordHasher.makePassword(newPassword, now: now)
        blockingState.groups[index].passwordReset = nil
        blockingState.groups[index].updatedAt = now
        unlockGroup(id: group.id, now: now)
        saveBlockingStateWithStatus("Group password reset.")
        return true
    }

    @discardableResult
    func startLocalUnblock(groupID: String, seconds: TimeInterval) -> Bool {
        guard let group = BlockingStateResolver.group(for: groupID, in: blockingState),
              group.unblockConfig.isEnabled else {
            message = "Limited unblocks are off for this group."
            return false
        }

        guard BlockingStateResolver.remainingUnblocks(for: groupID, in: blockingState) > 0 else {
            message = "No limited unblocks left today."
            return false
        }

        let duration = min(
            BlockingTimeLimitRange.snappedSeconds(seconds),
            group.unblockConfig.maxDurationSeconds
        )
        let now = Date()
        blockingState.unblockSessions.insert(
            BlockUnblockSession(
                id: UUID().uuidString,
                groupID: groupID,
                selectionData: group.selectionData,
                durationSeconds: duration,
                startedAt: now,
                expiresAt: now.addingTimeInterval(duration)
            ),
            at: 0
        )
        saveBlockingStateWithStatus("Unblocked \(group.name) for \(BlockingDisplayFormatter.durationLabel(duration)).")
        return true
    }

    @discardableResult
    func requestFriendTime(
        groupID: String,
        seconds: TimeInterval,
        selectedFriendIDs: [String],
        message requestMessage: String,
        photoJPEGData: Data?
    ) -> Bool {
        guard let group = BlockingStateResolver.group(for: groupID, in: blockingState),
              group.friendRequestConfig.isEnabled else {
            message = "Friend requests are off for this group."
            return false
        }

        guard !selectedFriendIDs.isEmpty else {
            message = "Choose at least one friend."
            return false
        }

        guard let photoJPEGData, !photoJPEGData.isEmpty else {
            message = "Take a photo before sending the request."
            return false
        }

        let photoReference: BlockFriendRequestPhotoReference
        do {
            photoReference = try friendRequestPhotoStore.saveJPEGData(photoJPEGData)
        } catch {
            message = "Could not save request photo: \(error.localizedDescription)"
            return false
        }

        let now = Date()
        let request = BlockFriendRequest(
            id: UUID().uuidString,
            groupID: groupID,
            requestedSeconds: BlockingTimeLimitRange.snappedSeconds(seconds),
            selectedFriendIDs: selectedFriendIDs,
            message: requestMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            requesterID: profile.id,
            requesterDisplayName: profile.displayName == "Me" ? "You" : profile.displayName,
            createdAt: now,
            photoReference: photoReference
        )

        blockingState.friendRequests.insert(request, at: 0)
        clearPendingShieldFriendRequest()
        saveBlockingStateWithStatus("Friend request sent.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
        let senderName = profile.displayName == "Me" ? "A friend" : profile.displayName
        sendPushNotification(
            toProfileIDs: selectedFriendIDs,
            title: "New time request",
            body: "\(senderName) is asking you to approve extra time.",
            requestID: request.id
        )
        Task {
            await publishFriendRequestToCloud(request, photoData: photoJPEGData)
        }
        return true
    }

    @discardableResult
    func approveFriendRequest(id: String) -> Bool {
        expireStaleFriendRequests()
        guard let index = blockingState.friendRequests.firstIndex(where: { $0.id == id }) else {
            message = "Request not found."
            return false
        }

        let request = blockingState.friendRequests[index]
        guard request.isReceived(byAny: currentFriendIdentityIDs), request.status == .pending else {
            message = "Only pending received requests can be approved."
            return false
        }

        let now = Date()
        let resolvedRequest = request.resolving(
            as: .approved,
            at: now,
            approvedByFriendID: profile.id
        )
        blockingState.friendRequests[index] = resolvedRequest
        friendRequestNotificationService.clearNotification(for: id)
        saveBlockingStateWithStatus("Request approved.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
        let approverName = profile.displayName == "Me" ? "Your friend" : profile.displayName
        sendPushNotification(
            toProfileIDs: [resolvedRequest.requesterID].compactMap { $0 },
            title: "Request approved",
            body: "\(approverName) approved your time request. Tap to collect.",
            requestID: resolvedRequest.id
        )
        Task {
            await publishFriendRequestUpdateToCloud(resolvedRequest)
        }
        return true
    }

    @discardableResult
    func denyFriendRequest(id: String) -> Bool {
        expireStaleFriendRequests()
        guard let index = blockingState.friendRequests.firstIndex(where: { $0.id == id }) else {
            message = "Request not found."
            return false
        }

        let request = blockingState.friendRequests[index]
        guard request.isReceived(byAny: currentFriendIdentityIDs), request.status == .pending else {
            message = "Only pending received requests can be denied."
            return false
        }

        let resolvedRequest = request.resolving(as: .denied, at: Date())
        blockingState.friendRequests[index] = resolvedRequest
        friendRequestNotificationService.clearNotification(for: id)
        saveBlockingStateWithStatus("Request denied.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
        let denierName = profile.displayName == "Me" ? "Your friend" : profile.displayName
        sendPushNotification(
            toProfileIDs: [resolvedRequest.requesterID].compactMap { $0 },
            title: "Request denied",
            body: "\(denierName) denied your time request.",
            requestID: resolvedRequest.id
        )
        Task {
            await publishFriendRequestUpdateToCloud(resolvedRequest)
        }
        return true
    }

    @discardableResult
    func collectFriendRequest(id: String) -> Bool {
        expireStaleFriendRequests()
        guard let index = blockingState.friendRequests.firstIndex(where: { $0.id == id }) else {
            message = "Request not found."
            return false
        }

        let request = blockingState.friendRequests[index]
        guard request.isSent(byAny: currentFriendIdentityIDs), request.status == .approved else {
            message = "Only approved sent requests can be collected."
            return false
        }

        let now = Date()
        if let collectionExpiresAt = request.collectionExpiresAt, now >= collectionExpiresAt {
            blockingState.friendRequests[index] = request.expiringIfNeeded(now: now)
            saveBlockingStateWithStatus("Approved request expired.")
            refreshLocalAccountabilityStats()
            writeWidgetCacheSnapshot()
            return false
        }

        guard let group = BlockingStateResolver.group(for: request.groupID, in: blockingState) else {
            message = "Block group no longer exists."
            return false
        }

        let duration = BlockingTimeLimitRange.snappedSeconds(request.requestedSeconds)
        blockingState.unblockSessions.insert(
            BlockUnblockSession(
                id: UUID().uuidString,
                groupID: request.groupID,
                selectionData: group.selectionData,
                durationSeconds: duration,
                startedAt: now,
                expiresAt: now.addingTimeInterval(duration)
            ),
            at: 0
        )
        let collectedRequest = request.collecting(at: now)
        blockingState.friendRequests[index] = collectedRequest
        saveBlockingStateWithStatus("Collected \(BlockingDisplayFormatter.durationLabel(duration)) of approved time.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
        Task {
            await publishFriendRequestUpdateToCloud(collectedRequest)
        }
        return true
    }

    @discardableResult
    func expireStaleFriendRequests(now: Date = Date()) -> Bool {
        let updatedRequests = blockingState.friendRequests.map { $0.expiringIfNeeded(now: now) }
        guard updatedRequests != blockingState.friendRequests else {
            return false
        }

        blockingState.friendRequests = updatedRequests
        saveBlockingStateWithStatus("Expired old friend requests.")
        refreshLocalAccountabilityStats()
        syncFriendRequestNotifications()
        writeWidgetCacheSnapshot()
        return true
    }

    func openFriendRequestLog(requestID: String) {
        friendRequestNotificationService.clearNotification(for: requestID)
        focusedFriendRequestLogID = requestID
    }

    func clearFocusedFriendRequestLog() {
        focusedFriendRequestLogID = nil
    }

    func requestScreenTimeAuthorization() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await screenTimeProvider.requestAuthorization()
            screenTimeAuthorization = screenTimeProvider.authorizationLabel()
            requestScreenTimeReportRefresh()
            message = "Screen Time authorization updated."
        } catch {
            screenTimeAuthorization = screenTimeProvider.authorizationLabel()
            message = "Screen Time authorization failed: \(error.localizedDescription)"
        }
    }

    func refreshAndPublish() async {
        isWorking = true
        defer { isWorking = false }

        persistSelection()
        screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        if !hasScreenTimeAuthorization {
            do {
                try await screenTimeProvider.requestAuthorization()
                screenTimeAuthorization = screenTimeProvider.authorizationLabel()
            } catch {
                screenTimeAuthorization = screenTimeProvider.authorizationLabel()
                message = "Screen Time authorization failed: \(error.localizedDescription)"
                screenTimeReportStatus = message ?? "Screen Time authorization failed."
                return
            }
        }

        cloudAvailability = await snapshotStore.cloudAvailability()
        message = "Refreshing Screen Time reports..."
        requestScreenTimeReportRefresh()
        try? await Task.sleep(for: .seconds(2))
        reloadUsageHistoryFromSharedStorage()

        let snapshot = await screenTimeProvider.loadTodayUsage(selection: selection, profile: profile)
        localSnapshot = snapshot
        if snapshot.capability.allowsUpload {
            persistUsageSnapshot(snapshot)
        }

        guard snapshot.capability.allowsUpload else {
            message = "Screen Time reports refreshed. Home and Stats load directly from iOS Screen Time."
            refreshScreenTimeReportStatus()
            return
        }

        guard cloudAvailability.allowsCloudWrites else {
            message = "\(cloudAvailability.label). Snapshot was not uploaded."
            return
        }

        do {
            try await snapshotStore.publish(profile: profile, snapshot: snapshot)
            message = "Usage snapshot uploaded."
            await reloadFriends()
            await syncFriendRequests()
        } catch {
            message = "CloudKit upload failed: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    func bootstrapCloudKitDevelopmentSchema() async {
        isWorking = true
        defer { isWorking = false }

        cloudAvailability = await snapshotStore.cloudAvailability()
        guard cloudAvailability.allowsCloudWrites else {
            message = "\(cloudAvailability.label). Could not bootstrap schema."
            return
        }

        do {
            try await snapshotStore.bootstrapDevelopmentSchema(profile: profile)
            message = "CloudKit Development schema bootstrapped."
        } catch {
            message = "CloudKit schema bootstrap failed: \(error.localizedDescription)"
        }
    }
    #endif

    func presentFriendShareInvite(metadata: CKShare.Metadata) {
        pendingFriendShareInvite = IncomingFriendShareInvite(metadata: metadata)
    }

    func presentFriendShareInvite(url: URL) async {
        do {
            let metadata = try await snapshotStore.shareMetadata(for: url)
            presentFriendShareInvite(metadata: metadata)
        } catch {
            message = "Could not open friend invite: \(error.localizedDescription)"
        }
    }

    func dismissFriendShareInvite() {
        pendingFriendShareInvite = nil
    }

    func acceptFriendShareInvite(_ invite: IncomingFriendShareInvite) async {
        isAcceptingFriendShareInvite = true
        defer {
            isAcceptingFriendShareInvite = false
        }

        let accepted = await acceptShare(metadata: invite.metadata)
        if accepted, pendingFriendShareInvite?.id == invite.id {
            pendingFriendShareInvite = nil
        }
    }

    @discardableResult
    func acceptShare(metadata: CKShare.Metadata) async -> Bool {
        do {
            try await snapshotStore.acceptShare(metadata: metadata)
            do {
                try await snapshotStore.publishAcceptedShareMirrors(profile: profile, snapshot: localSnapshot)
            } catch {
                message = "Friend accepted. Your profile will sync back after iCloud is ready."
            }
            message = "Friend share accepted."
            await reloadFriends()
            await syncFriendRequests()
            return true
        } catch {
            message = "Could not accept share: \(error.localizedDescription)"
            return false
        }
    }

    func reloadFriends() async {
        do {
            let friends = try await snapshotStore.fetchFriendSummaries(for: profile)
            friendSummaries = friends
            leaderboardEntries = []
            refreshLocalAccountabilityStats()
            try widgetCacheWriter.write(
                friends: friends,
                leaderboardEntries: leaderboardEntries,
                currentUserID: profile.id
            )
        } catch {
            message = "Could not refresh friends: \(error.localizedDescription)"
        }
    }

    /// Invoked when a CloudKit push wakes the app (foreground or background): pull
    /// the latest friends + requests so the existing notification logic posts the
    /// approve/deny/new-request alerts even when the app wasn't open.
    func handleRemoteChange() async {
        await reloadFriends()
        await syncFriendRequests()
    }

    /// Stores the APNs device token and registers it with the push server against
    /// this user's profile, so friends can trigger alert pushes to this device.
    func registerPushDeviceToken(_ token: String) {
        apnsDeviceToken = token
        let profileID = profile.id
        Task {
            await pushServerClient.register(profileID: profileID, deviceToken: token)
        }
    }

    /// Sends an alert push (via the push server) to each recipient of an event,
    /// so they're notified even if their app is force-quit.
    private func sendPushNotification(toProfileIDs: [String], title: String, body: String, requestID: String?) {
        let recipients = Set(toProfileIDs.filter { !$0.isEmpty && $0 != profile.id })
        guard !recipients.isEmpty else {
            return
        }

        Task { [pushServerClient] in
            for recipient in recipients {
                await pushServerClient.notify(
                    toProfileID: recipient,
                    title: title,
                    body: body,
                    requestID: requestID
                )
            }
        }
    }

    func syncFriendRequests() async {
        guard !isSyncingFriendRequests else {
            return
        }

        isSyncingFriendRequests = true
        defer {
            isSyncingFriendRequests = false
        }

        do {
            let knownRequestIDs = Set(blockingState.friendRequests.map(\.id))
            let previousStatusByID = Dictionary(
                blockingState.friendRequests.map { ($0.id, $0.status) },
                uniquingKeysWith: { current, _ in current }
            )
            let cloudRequests = try await snapshotStore.fetchFriendRequests(
                knownRequestIDs: knownRequestIDs
            ) { [friendRequestPhotoStore] id, data in
                try friendRequestPhotoStore.saveJPEGData(data, id: id)
            }
            guard mergeCloudFriendRequests(cloudRequests) else {
                return
            }
            try persistBlockingState()
            refreshLocalAccountabilityStats()
            syncFriendRequestNotifications()
            notifySentRequestStatusChanges(previousStatusByID: previousStatusByID)
            writeWidgetCacheSnapshot()
        } catch {
            message = "Could not sync friend requests: \(error.localizedDescription)"
        }
    }

    /// Fires a local notification on the requester's device when one of their
    /// sent requests transitions into approved/denied after a cloud sync.
    private func notifySentRequestStatusChanges(previousStatusByID: [String: BlockRequestStatus]) {
        for request in blockingState.friendRequests {
            guard request.isSent(byAny: currentFriendIdentityIDs),
                  request.status == .approved || request.status == .denied,
                  previousStatusByID[request.id] != request.status else {
                continue
            }

            friendRequestNotificationService.scheduleStatusUpdateNotification(
                for: request,
                groupName: groupName(forNotification: request.groupID)
            )
        }
    }

    private func publishFriendRequestToCloud(_ request: BlockFriendRequest, photoData: Data?) async {
        let availability = await snapshotStore.cloudAvailability()
        cloudAvailability = availability
        guard availability.allowsCloudWrites else {
            message = "\(availability.label). Friend request saved only on this device."
            return
        }

        do {
            let report = try await snapshotStore.publishFriendRequestDiagnostic(request, profile: profile, photoData: photoData)
            if report.deliveredCount == 0 {
                func shorten(_ ids: [String]) -> String {
                    ids.isEmpty ? "none" : ids.map { String($0.prefix(6)) }.joined(separator: ",")
                }
                message = "Couldn't deliver. target=[\(shorten(report.targetFriendIDs))] ownedChannels=[\(shorten(report.ownedChannelFriendIDs))] acceptedShares(\(report.sharedZoneCount))=[\(shorten(report.acceptedShareOwnerIDs))]"
            }
        } catch {
            message = "Friend request saved locally. Cloud sync failed: \(error.localizedDescription)"
        }
    }

    private func publishFriendRequestUpdateToCloud(_ request: BlockFriendRequest) async {
        let availability = await snapshotStore.cloudAvailability()
        cloudAvailability = availability
        guard availability.allowsCloudWrites else {
            return
        }

        do {
            try await snapshotStore.updateFriendRequest(request)
        } catch {
            message = "Request updated locally. Cloud sync failed: \(error.localizedDescription)"
        }
    }

    private func publishProfileUpdateToCloud() async {
        let availability = await snapshotStore.cloudAvailability()
        cloudAvailability = availability
        guard availability.allowsCloudWrites else {
            return
        }

        do {
            try await snapshotStore.publishProfile(profile)
        } catch {
            message = "Profile saved locally. Cloud sync failed: \(error.localizedDescription)"
        }
    }

    private static let legacyMigrationKey = "DidMigrateLegacyFriendRequests.v1"

    private func migrateLegacyFriendRequestRecords() async {
        guard !UserDefaults.standard.bool(forKey: Self.legacyMigrationKey),
              cloudAvailability.allowsCloudWrites else {
            return
        }

        do {
            try await snapshotStore.migrateLegacyFriendRequests(profile: profile)
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationKey)
        } catch {
            // Non-fatal — will retry next launch
        }
    }

    @discardableResult
    private func mergeCloudFriendRequests(_ cloudRequests: [BlockFriendRequest]) -> Bool {
        guard !cloudRequests.isEmpty else {
            return false
        }

        var mergedByID = Dictionary(uniqueKeysWithValues: blockingState.friendRequests.map { ($0.id, $0) })
        for cloudRequest in cloudRequests {
            if let localRequest = mergedByID[cloudRequest.id] {
                mergedByID[cloudRequest.id] = mergedFriendRequest(local: localRequest, cloud: cloudRequest)
            } else {
                mergedByID[cloudRequest.id] = cloudRequest
            }
        }

        let mergedRequests = mergedByID.values.sorted { lhs, rhs in
            friendRequestSortDate(lhs) > friendRequestSortDate(rhs)
        }
        guard mergedRequests != blockingState.friendRequests else {
            return false
        }

        blockingState.friendRequests = mergedRequests
        return true
    }

    private func mergedFriendRequest(local: BlockFriendRequest, cloud: BlockFriendRequest) -> BlockFriendRequest {
        let localDate = friendRequestSortDate(local)
        let cloudDate = friendRequestSortDate(cloud)
        var merged = cloudDate >= localDate ? cloud : local

        if merged.photoReference == nil {
            merged.photoReference = local.photoReference ?? cloud.photoReference
        }

        return merged
    }

    private func friendRequestSortDate(_ request: BlockFriendRequest) -> Date {
        request.collectedAt ?? request.resolvedAt ?? request.createdAt
    }

    private func updateGroupMode(groupID: String, mode: BlockGroupMode, status: String) {
        guard let index = blockingState.groups.firstIndex(where: { $0.id == groupID }) else {
            message = "Create a block group first."
            return
        }

        guard mode.isValid else {
            message = "That blocking mode is not valid."
            return
        }

        blockingState.groups[index].mode = mode
        blockingState.groups[index].updatedAt = Date()
        blockingState.rules.removeAll { $0.groupID == groupID }
        saveBlockingStateWithStatus(status)
    }

    private func canEditGroup(_ group: BlockGroup, password: String?) -> Bool {
        purgeExpiredGroupUnlocks()

        guard let storedPassword = group.password else {
            return password?.isEmpty == false
        }

        if groupUnlockExpirations[group.id, default: .distantPast] > Date() {
            return true
        }

        guard let password, !password.isEmpty else {
            return false
        }

        let didVerify = BlockingPasswordHasher.verify(password, against: storedPassword)
        if didVerify {
            unlockGroup(id: group.id)
        }
        return didVerify
    }

    private func canVerifyGroupPassword(_ group: BlockGroup, password: String?) -> Bool {
        guard let currentGroup = blockingState.groups.first(where: { $0.id == group.id }),
              let storedPassword = currentGroup.password else {
            return false
        }

        guard let password, !password.isEmpty else {
            return false
        }

        return BlockingPasswordHasher.verify(password, against: storedPassword)
    }

    private func unlockGroup(id: String, now: Date = Date()) {
        groupUnlockExpirations[id] = now.addingTimeInterval(5 * 60)
    }

    private func purgeExpiredGroupUnlocks() {
        let now = Date()
        groupUnlockExpirations = groupUnlockExpirations.filter { $0.value > now }
    }

    func clearPendingShieldFriendRequest() {
        usageHistoryDefaults?.removeObject(forKey: BlockingFriendRequestIntentStore.groupIDKey)
        usageHistoryDefaults?.removeObject(forKey: BlockingFriendRequestIntentStore.createdAtKey)
        usageHistoryDefaults?.synchronize()
        pendingShieldFriendRequestGroupID = nil
    }

    func refreshPendingShieldFriendRequest() {
        loadPendingShieldFriendRequest()
    }

    func openPendingShieldFriendRequestFromNotification(groupID: String?) {
        loadPendingShieldFriendRequest(preferredGroupID: groupID)
        if pendingShieldFriendRequestGroupID == nil {
            message = "That request is no longer available."
        }
    }

    private func loadPendingShieldFriendRequest(now: Date = Date(), preferredGroupID: String? = nil) {
        guard let groupID = usageHistoryDefaults?.string(forKey: BlockingFriendRequestIntentStore.groupIDKey) else {
            pendingShieldFriendRequestGroupID = nil
            return
        }

        if let preferredGroupID,
           preferredGroupID != groupID {
            pendingShieldFriendRequestGroupID = nil
            return
        }

        let createdAt = usageHistoryDefaults?.object(forKey: BlockingFriendRequestIntentStore.createdAtKey) as? Date
        if let createdAt,
           now.timeIntervalSince(createdAt) > BlockingFriendRequestIntentStore.expirationSeconds {
            clearPendingShieldFriendRequest()
            return
        }

        guard blockingState.groups.contains(where: { group in
            group.id == groupID && group.isEnabled && group.friendRequestConfig.isEnabled
        }) else {
            clearPendingShieldFriendRequest()
            return
        }

        pendingShieldFriendRequestGroupID = groupID
    }

    private func persistBlockingState() throws {
        blockingState.lastUpdated = Date()
        try blockingStore.save(blockingState)
        Task.detached { @MainActor [weak self] in
            self?.syncBlockingEnforcement()
        }
    }

    private func saveBlockingStateWithStatus(_ status: String) {
        do {
            try persistBlockingState()
            message = status
        } catch {
            message = "Could not save blocking settings: \(error.localizedDescription)"
        }
    }

    private func syncBlockingEnforcement() {
        do {
            try blockingEnforcementService.syncMonitoring(for: blockingState)
        } catch {
            message = "Could not update blocking monitors: \(error.localizedDescription)"
        }
    }

    private func loadUsageHistory() {
        guard let data = usageHistoryDefaults?.data(forKey: UsageHistoryCodec.storageKey),
              let payload = try? UsageHistoryCodec.decode(data) else {
            usageHistory = []
            hourlyUsageByDayID = [:]
            return
        }

        usageHistory = payload.snapshots
        hourlyUsageByDayID = payload.hourlyDurationsByDayID
    }

    private func refreshLocalSnapshotFromHistory(now: Date = Date()) {
        localSnapshot = UsageStatsBuilder.snapshot(for: now, in: usageHistory)
            ?? usageHistory.sorted { $0.date > $1.date }.first
    }

    private static func screenTimeReportStatusLabel(
        authorization: String,
        defaults: UserDefaults?
    ) -> String {
        guard isScreenTimeAuthorizationApproved(authorization) else {
            return "Screen Time is \(authorization.lowercased())."
        }

        if let error = defaults?.string(forKey: ScreenTimeReportStorage.lastErrorKey), !error.isEmpty {
            return "Screen Time report error: \(error)"
        }

        if let lastGeneratedAt = defaults?.object(forKey: ScreenTimeReportStorage.lastGeneratedAtKey) as? Date {
            if let summary = defaults?.string(forKey: ScreenTimeReportStorage.lastSummaryKey) {
                return "\(UsageFormatting.lastUpdated(lastGeneratedAt)) (\(summary))"
            }

            return UsageFormatting.lastUpdated(lastGeneratedAt)
        }

        return "Live reports ready for all activity."
    }

    private static func isScreenTimeAuthorizationApproved(_ authorization: String) -> Bool {
        authorization.localizedCaseInsensitiveCompare("Approved") == .orderedSame
            || authorization.localizedCaseInsensitiveContains("approved")
    }

    private func persistUsageSnapshot(_ snapshot: DailyUsageSnapshot) {
        usageHistory = UsageHistoryCodec.upserting(snapshot, into: usageHistory)
        persistUsageHistory()
    }

    private func persistUsageHistory() {
        do {
            let payload = UsageHistoryPayload(
                snapshots: usageHistory,
                hourlyDurationsByDayID: hourlyUsageByDayID
            )
            let data = try UsageHistoryCodec.encode(payload)
            usageHistoryDefaults?.set(data, forKey: UsageHistoryCodec.storageKey)
        } catch {
            message = "Could not save local Screen Time history: \(error.localizedDescription)"
        }
    }

    private func refreshLocalAccountabilityStats() {
        let otherEntries = leaderboardEntries.filter { $0.userID != profile.id }
        let legacyEvents = blockingState.requests.flatMap { request -> [AccountabilityEvent] in
            var events = [
                AccountabilityEvent(
                    id: "\(request.id)-requested",
                    userID: profile.id,
                    kind: .extraTimeRequested,
                    occurredAt: request.createdAt,
                    seconds: request.requestedSeconds,
                    requestID: request.id
                )
            ]

            if let resolvedAt = request.resolvedAt {
                switch request.status {
                case .approved:
                    events.append(
                        AccountabilityEvent(
                            id: "\(request.id)-approved",
                            userID: profile.id,
                            kind: .extraTimeApproved,
                            occurredAt: resolvedAt,
                            seconds: request.requestedSeconds,
                            requestID: request.id
                        )
                    )
                case .denied:
                    events.append(
                        AccountabilityEvent(
                            id: "\(request.id)-denied",
                            userID: profile.id,
                            kind: .extraTimeDenied,
                            occurredAt: resolvedAt,
                            requestID: request.id
                        )
                    )
                case .expired, .pending, .collected:
                    break
                }
            }

            return events
        }
        let friendRequestEvents = blockingState.friendRequests.flatMap { request -> [AccountabilityEvent] in
            let requesterID = request.requesterID ?? profile.id
            var events = [
                AccountabilityEvent(
                    id: "\(request.id)-friend-requested",
                    userID: requesterID,
                    kind: .extraTimeRequested,
                    occurredAt: request.createdAt,
                    seconds: request.requestedSeconds,
                    requestID: request.id
                )
            ]

            if let resolvedAt = request.resolvedAt {
                switch request.status {
                case .approved, .collected:
                    events.append(
                        AccountabilityEvent(
                            id: "\(request.id)-friend-approved",
                            userID: requesterID,
                            kind: .extraTimeApproved,
                            occurredAt: resolvedAt,
                            seconds: request.requestedSeconds,
                            requestID: request.id,
                            actorUserID: request.approvedByFriendID ?? request.selectedFriendIDs.first
                        )
                    )
                case .denied:
                    events.append(
                        AccountabilityEvent(
                            id: "\(request.id)-friend-denied",
                            userID: requesterID,
                            kind: .extraTimeDenied,
                            occurredAt: resolvedAt,
                            requestID: request.id,
                            actorUserID: request.selectedFriendIDs.first
                        )
                    )
                case .expired:
                    if let approvedByFriendID = request.approvedByFriendID {
                        events.append(
                            AccountabilityEvent(
                                id: "\(request.id)-friend-approved",
                                userID: requesterID,
                                kind: .extraTimeApproved,
                                occurredAt: resolvedAt,
                                seconds: request.requestedSeconds,
                                requestID: request.id,
                                actorUserID: approvedByFriendID
                            )
                        )
                    }
                case .pending:
                    break
                }
            }

            return events
        }
        let events = legacyEvents + friendRequestEvents

        guard !events.isEmpty else {
            leaderboardEntries = otherEntries
            return
        }

        let participant = AccountabilityParticipant(
            id: profile.id,
            displayName: profile.displayName == "Me" ? "You" : profile.displayName,
            avatarColorHex: profile.avatarColorHex
        )
        guard let entry = LeaderboardBuilder.entries(
            participants: [participant],
            events: events,
            window: leaderboardWindow
        ).first else {
            leaderboardEntries = otherEntries
            return
        }

        leaderboardEntries = [entry] + otherEntries
    }

    private func writeWidgetCacheSnapshot() {
        do {
            try widgetCacheWriter.write(
                friends: friendSummaries,
                leaderboardEntries: leaderboardEntries,
                currentUserID: profile.id
            )
        } catch {
            message = "Could not update widget cache: \(error.localizedDescription)"
        }
    }

    private func syncFriendRequestNotifications() {
        for request in blockingState.friendRequests {
            guard request.isReceived(byAny: currentFriendIdentityIDs) else {
                continue
            }

            if request.status == .pending {
                friendRequestNotificationService.scheduleNotification(
                    for: request,
                    groupName: groupName(forNotification: request.groupID)
                )
            } else {
                friendRequestNotificationService.clearNotification(for: request.id)
            }
        }
    }

    private func groupName(forNotification groupID: String) -> String {
        blockingState.groups.first { $0.id == groupID }?.name ?? "restricted app"
    }

    func setLeaderboardWindow(_ window: LeaderboardWindow) {
        leaderboardWindow = window
        refreshLocalAccountabilityStats()
    }

    #if DEBUG
    func seedDemoScreenTime() {
        seedDemoUsageHistory()
        message = "Demo Screen Time added for debug testing."
    }

    private func seedDemoUsageHistory(now: Date = Date()) {
        let payload = makeDemoUsageHistory(now: now)
        usageHistory = payload.snapshots
        hourlyUsageByDayID = payload.hourlyDurationsByDayID
        localSnapshot = UsageStatsBuilder.snapshot(for: now, in: usageHistory) ?? makeDemoScreenTimeSnapshot(now: now)
        persistUsageHistory()
    }

    func seedDemoFriends(now: Date = Date(), showsStatusMessage: Bool = true) {
        let friends = makeDemoFriends(now: now)
        let demo = makeDemoLeaderboard(now: now)
        friendSummaries = friends
        leaderboardEntries = demo.entries
        UserDefaults.standard.set(true, forKey: demoFriendsKey)
        seedDemoFriendRequests(now: now)
        refreshLocalAccountabilityStats()

        do {
            try widgetCacheWriter.write(
                friends: friends,
                leaderboardEntries: leaderboardEntries,
                currentUserID: profile.id
            )
            if showsStatusMessage {
                message = "Demo friends added for debug testing."
            }
        } catch {
            message = "Could not write demo widget cache: \(error.localizedDescription)"
        }
    }

    func clearDemoFriends() {
        friendSummaries = []
        leaderboardEntries = []
        refreshLocalAccountabilityStats()
        UserDefaults.standard.set(false, forKey: demoFriendsKey)

        do {
            try widgetCacheWriter.write(friends: [], leaderboardEntries: leaderboardEntries, currentUserID: profile.id)
            message = "Demo friends cleared."
        } catch {
            message = "Could not clear demo widget cache: \(error.localizedDescription)"
        }
    }

    private func makeDemoFriends(now: Date) -> [FriendUsageSummary] {
        [
            FriendUsageSummary(
                id: "demo-sam",
                displayName: "Sam Lee",
                avatarColorHex: "#1B998B",
                totalDuration: 5 * 3_600 + 22 * 60,
                selectedAppDuration: 1 * 3_600 + 14 * 60,
                capability: .fullAppDetail,
                lastUpdated: now.addingTimeInterval(-8 * 60),
                isStale: false
            ),
            FriendUsageSummary(
                id: "demo-maya",
                displayName: "Maya Chen",
                avatarColorHex: "#E84855",
                totalDuration: 3 * 3_600 + 46 * 60,
                selectedAppDuration: 42 * 60,
                capability: .aggregateOnly(reason: "App detail unavailable"),
                lastUpdated: now.addingTimeInterval(-22 * 60),
                isStale: false
            ),
            FriendUsageSummary(
                id: "demo-jordan",
                displayName: "Jordan Kim",
                avatarColorHex: "#6A4C93",
                totalDuration: nil,
                selectedAppDuration: nil,
                capability: .unavailable(reason: "Screen Time unavailable"),
                lastUpdated: now.addingTimeInterval(-35 * 60),
                isStale: false
            ),
            FriendUsageSummary(
                id: "demo-riley",
                displayName: "Riley Park",
                avatarColorHex: "#F18F01",
                totalDuration: 7 * 3_600 + 9 * 60,
                selectedAppDuration: 2 * 3_600 + 3 * 60,
                capability: .aggregateOnly(reason: "Selected-app total only"),
                lastUpdated: now.addingTimeInterval(-2 * 3_600),
                isStale: true
            )
        ]
    }

    private func seedDemoFriendRequests(now: Date) {
        guard let groupID = ensureDemoRequestGroup(now: now) else {
            return
        }

        let approvedAt = now.addingTimeInterval(-12 * 60)
        let collectedAt = now.addingTimeInterval(-94 * 60)
        let samPhoto = demoPhotoReference(
            id: "demo-photo-sam-please",
            name: "Sam",
            background: (
                UIColor(red: 0.24, green: 0.47, blue: 0.86, alpha: 1),
                UIColor(red: 0.06, green: 0.09, blue: 0.18, alpha: 1)
            ),
            shirt: UIColor(red: 0.10, green: 0.55, blue: 0.48, alpha: 1),
            expressionOffset: 18
        )
        let mayaPhoto = demoPhotoReference(
            id: "demo-photo-maya-please",
            name: "Maya",
            background: (
                UIColor(red: 0.86, green: 0.25, blue: 0.32, alpha: 1),
                UIColor(red: 0.32, green: 0.13, blue: 0.27, alpha: 1)
            ),
            shirt: UIColor(red: 0.95, green: 0.54, blue: 0.18, alpha: 1),
            expressionOffset: 28
        )
        let rileyPhoto = demoPhotoReference(
            id: "demo-photo-riley-please",
            name: "Riley",
            background: (
                UIColor(red: 0.18, green: 0.55, blue: 0.72, alpha: 1),
                UIColor(red: 0.12, green: 0.19, blue: 0.28, alpha: 1)
            ),
            shirt: UIColor(red: 0.42, green: 0.32, blue: 0.68, alpha: 1),
            expressionOffset: 10
        )
        let mePhoto = demoPhotoReference(
            id: "demo-photo-me-please",
            name: "Me",
            background: (
                UIColor(red: 0.34, green: 0.44, blue: 0.38, alpha: 1),
                UIColor(red: 0.08, green: 0.11, blue: 0.12, alpha: 1)
            ),
            shirt: UIColor(red: 0.18, green: 0.34, blue: 0.58, alpha: 1),
            expressionOffset: 22
        )
        let demoRequestIDs: Set<String> = [
            "demo-received-friend-request",
            "demo-request-received-pending",
            "demo-request-received-pending-maya",
            "demo-request-received-denied",
            "demo-request-received-approved",
            "demo-request-sent-pending",
            "demo-request-sent-approved",
            "demo-request-sent-collected"
        ]
        let requests = [
            BlockFriendRequest(
                id: "demo-request-received-pending",
                groupID: groupID,
                requestedSeconds: 10 * 60,
                selectedFriendIDs: [profile.id],
                message: "Can you approve a quick check-in?",
                requesterID: "demo-sam",
                requesterDisplayName: "Sam Lee",
                createdAt: now.addingTimeInterval(-9 * 60),
                photoReference: samPhoto
            ),
            BlockFriendRequest(
                id: "demo-request-received-pending-maya",
                groupID: groupID,
                requestedSeconds: 20 * 60,
                selectedFriendIDs: [profile.id],
                message: "I swear I only need to answer one DM.",
                requesterID: "demo-maya",
                requesterDisplayName: "Maya Chen",
                createdAt: now.addingTimeInterval(-24 * 60),
                photoReference: mayaPhoto
            ),
            BlockFriendRequest(
                id: "demo-request-received-denied",
                groupID: groupID,
                requestedSeconds: 30 * 60,
                selectedFriendIDs: [profile.id],
                message: "Wanted a little more YouTube time.",
                requesterID: "demo-riley",
                requesterDisplayName: "Riley Park",
                status: .denied,
                createdAt: now.addingTimeInterval(-55 * 60),
                resolvedAt: now.addingTimeInterval(-47 * 60),
                photoReference: rileyPhoto
            ),
            BlockFriendRequest(
                id: "demo-request-received-approved",
                groupID: groupID,
                requestedSeconds: 15 * 60,
                selectedFriendIDs: [profile.id],
                message: "Please let this one through.",
                requesterID: "demo-riley",
                requesterDisplayName: "Riley Park",
                approvedByFriendID: profile.id,
                status: .approved,
                createdAt: now.addingTimeInterval(-42 * 60),
                resolvedAt: now.addingTimeInterval(-36 * 60),
                approvedExpiresAt: BlockFriendRequestLifecycle.approvedExpirationDate(approvedAt: now.addingTimeInterval(-36 * 60)),
                photoReference: rileyPhoto
            ),
            BlockFriendRequest(
                id: "demo-request-sent-pending",
                groupID: groupID,
                requestedSeconds: 15 * 60,
                selectedFriendIDs: ["demo-maya"],
                message: "Need a few minutes to reply.",
                requesterID: profile.id,
                requesterDisplayName: profile.displayName == "Me" ? "You" : profile.displayName,
                createdAt: now.addingTimeInterval(-6 * 60),
                photoReference: mePhoto
            ),
            BlockFriendRequest(
                id: "demo-request-sent-approved",
                groupID: groupID,
                requestedSeconds: 20 * 60,
                selectedFriendIDs: ["demo-sam"],
                message: "Finishing a conversation.",
                requesterID: profile.id,
                requesterDisplayName: profile.displayName == "Me" ? "You" : profile.displayName,
                approvedByFriendID: "demo-sam",
                status: .approved,
                createdAt: now.addingTimeInterval(-18 * 60),
                resolvedAt: approvedAt,
                approvedExpiresAt: BlockFriendRequestLifecycle.approvedExpirationDate(approvedAt: approvedAt),
                photoReference: mePhoto
            ),
            BlockFriendRequest(
                id: "demo-request-sent-collected",
                groupID: groupID,
                requestedSeconds: 10 * 60,
                selectedFriendIDs: ["demo-maya"],
                message: "",
                requesterID: profile.id,
                requesterDisplayName: profile.displayName == "Me" ? "You" : profile.displayName,
                approvedByFriendID: "demo-maya",
                status: .collected,
                createdAt: now.addingTimeInterval(-2 * 3_600),
                resolvedAt: now.addingTimeInterval(-105 * 60),
                collectedAt: collectedAt,
                approvedExpiresAt: BlockFriendRequestLifecycle.approvedExpirationDate(approvedAt: now.addingTimeInterval(-105 * 60)),
                photoReference: mePhoto
            )
        ]

        blockingState.friendRequests.removeAll { demoRequestIDs.contains($0.id) }
        blockingState.friendRequests.insert(contentsOf: requests, at: 0)
        try? persistBlockingState()
        syncFriendRequestNotifications()
    }

    private func ensureDemoRequestGroup(now: Date) -> String? {
        if let group = blockingState.groups.first(where: { $0.isEnabled && $0.friendRequestConfig.isEnabled }) {
            return group.id
        }

        if let index = blockingState.groups.firstIndex(where: { $0.id == "demo-social-requests" }) {
            blockingState.groups[index].isEnabled = true
            blockingState.groups[index].friendRequestConfig = BlockFriendRequestConfig(isEnabled: true)
            blockingState.groups[index].updatedAt = now
            return blockingState.groups[index].id
        }

        guard let selectionData = try? BlockingSelectionCodec.encode(FamilyActivitySelection()) else {
            return nil
        }

        blockingState.groups.insert(
            BlockGroup(
                id: "demo-social-requests",
                name: "Social",
                colorHex: "#E84855",
                selectionData: selectionData,
                isEnabled: true,
                mode: .timeLimit(limitSeconds: 30 * 60, days: BlockWeekday.everyDay),
                friendRequestConfig: BlockFriendRequestConfig(isEnabled: true),
                password: BlockingPasswordHasher.makePassword("demo", now: now),
                createdAt: now,
                updatedAt: now
            ),
            at: 0
        )
        return "demo-social-requests"
    }

    private func demoPhotoReference(
        id: String,
        name: String,
        background: (UIColor, UIColor),
        shirt: UIColor,
        expressionOffset: CGFloat
    ) -> BlockFriendRequestPhotoReference? {
        if friendRequestPhotoStore.hasPhoto(id: id) {
            return BlockFriendRequestPhotoReference(localIdentifier: id)
        }

        guard let data = FriendRequestDemoPhotoFactory.jpegData(
            name: name,
            background: background,
            shirt: shirt,
            expressionOffset: expressionOffset
        ) else {
            return nil
        }

        return try? friendRequestPhotoStore.saveJPEGData(data, id: id)
    }

    private func makeDemoScreenTimeSnapshot(
        now: Date,
        totalDuration: TimeInterval = 5 * 3_600 + 42 * 60,
        pickupCount: Int = 74,
        appRows: [SharedAppUsage]? = nil,
        lastUpdated: Date? = nil
    ) -> DailyUsageSnapshot {
        let calendar = Calendar.current
        let interval = UsageDateBoundary.dayInterval(containing: now, calendar: calendar)
        return DailyUsageSnapshot(
            id: UsageDateBoundary.snapshotID(profileID: profile.id, date: now, calendar: calendar),
            ownerProfileID: profile.id,
            date: interval.start,
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            totalDuration: totalDuration,
            selectedAppDuration: max(0, totalDuration * 0.58),
            pickupCount: pickupCount,
            appRows: appRows ?? makeDemoAppRows(totalDuration: totalDuration),
            lastUpdated: lastUpdated ?? Date().addingTimeInterval(-6 * 60),
            capability: .fullAppDetail
        )
    }

    private func makeDemoUsageHistory(now: Date) -> UsageHistoryPayload {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else {
            let snapshot = makeDemoScreenTimeSnapshot(now: now)
            return UsageHistoryPayload(snapshots: [snapshot])
        }

        let today = calendar.startOfDay(for: now)
        let currentWeek = UsageStatsBuilder.periodInterval(for: .week, containing: now, calendar: calendar)
        let currentWeekMinutes = [421, 360, 238, 297, 312, 248, 184]
        let monthPatternMinutes = [510, 485, 462, 438, 506, 472, 449, 330, 300, 285, 260, 310, 275, 255, 290, 270]
        var snapshots: [DailyUsageSnapshot] = []
        var hourlyDurationsByDayID: [String: [TimeInterval]] = [:]
        var cursor = monthInterval.start
        var dayIndex = 0

        while cursor <= today {
            let minutes: Int
            if currentWeek.contains(cursor),
               let offset = calendar.dateComponents([.day], from: currentWeek.start, to: cursor).day,
               currentWeekMinutes.indices.contains(offset) {
                minutes = currentWeekMinutes[offset]
            } else {
                minutes = monthPatternMinutes[dayIndex % monthPatternMinutes.count]
            }

            let totalDuration = TimeInterval(minutes * 60)
            let pickupCount = demoPickupCount(totalMinutes: minutes, dayIndex: dayIndex)
            let isToday = calendar.isDate(cursor, inSameDayAs: now)
            let snapshot = makeDemoScreenTimeSnapshot(
                now: cursor,
                totalDuration: totalDuration,
                pickupCount: pickupCount,
                appRows: makeDemoAppRows(totalDuration: totalDuration),
                lastUpdated: isToday ? now.addingTimeInterval(-6 * 60) : cursor.addingTimeInterval(22 * 3_600)
            )
            snapshots.append(snapshot)
            hourlyDurationsByDayID[UsageDateBoundary.localDayKey(date: cursor, calendar: calendar)] = demoHourlyDurations(
                totalDuration: totalDuration,
                dayIndex: dayIndex
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
            dayIndex += 1
        }

        return UsageHistoryPayload(snapshots: snapshots.sorted { $0.date > $1.date }, hourlyDurationsByDayID: hourlyDurationsByDayID)
    }

    private func demoPickupCount(totalMinutes: Int, dayIndex: Int) -> Int {
        guard totalMinutes > 0 else {
            return 0
        }

        return max(1, Int(Double(totalMinutes) / 5.8) + (dayIndex % 5))
    }

    private func demoHourlyDurations(totalDuration: TimeInterval, dayIndex: Int) -> [TimeInterval] {
        guard totalDuration > 30 * 60 else {
            var durations = Array(repeating: TimeInterval(0), count: 24)
            durations[0] = totalDuration
            return durations
        }

        var weights = Array(repeating: 0.0, count: 24)
        for hour in 7...23 {
            let wave = Double((hour + dayIndex) % 6 + 1)
            let eveningBoost = hour >= 18 ? 1.65 : 1.0
            weights[hour] = wave * eveningBoost
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return Array(repeating: TimeInterval(0), count: 24)
        }

        return weights.map { totalDuration * ($0 / totalWeight) }
    }

    private func makeDemoAppRows(totalDuration: TimeInterval) -> [SharedAppUsage] {
        let definitions: [(String, String, String, Double)] = [
            ("demo-tiktok", "TikTok", "com.zhiliaoapp.musically", 0.34),
            ("demo-instagram", "Instagram", "com.burbn.instagram", 0.25),
            ("demo-youtube", "YouTube", "com.google.ios.youtube", 0.18),
            ("demo-reddit", "Reddit", "com.reddit.Reddit", 0.11),
            ("demo-safari", "Safari", "com.apple.mobilesafari", 0.07),
            ("demo-messages", "Messages", "com.apple.MobileSMS", 0.05)
        ]

        return definitions.compactMap { id, displayName, bundleIdentifier, share in
            let duration = (totalDuration * share).rounded(.down)
            guard duration >= 60 else {
                return nil
            }

            return SharedAppUsage(
                id: id,
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                duration: duration
            )
        }
    }

    private func makeDemoLeaderboard(now: Date) -> (participants: [AccountabilityParticipant], events: [AccountabilityEvent], entries: [LeaderboardEntry]) {
        let me = AccountabilityParticipant(
            id: profile.id,
            displayName: profile.displayName == "Me" ? "You" : profile.displayName,
            avatarColorHex: profile.avatarColorHex
        )
        let participants = [
            AccountabilityParticipant(id: "demo-maya", displayName: "Maya Chen", avatarColorHex: "#E84855"),
            AccountabilityParticipant(id: "demo-sam", displayName: "Sam Lee", avatarColorHex: "#1B998B"),
            me,
            AccountabilityParticipant(id: "demo-riley", displayName: "Riley Park", avatarColorHex: "#F18F01")
        ]
        let events = demoAccountabilityEvents(now: now, meID: profile.id)
        let entries = LeaderboardBuilder.entries(
            participants: participants,
            events: events,
            window: leaderboardWindow,
            now: now
        )
        return (participants, events, entries)
    }

    private func demoAccountabilityEvents(now: Date, meID: String) -> [AccountabilityEvent] {
        var events: [AccountabilityEvent] = [
            AccountabilityEvent(
                id: "sam-request-1",
                userID: "demo-sam",
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-45 * 60),
                seconds: 10 * 60,
                requestID: "sam-req-1"
            ),
            AccountabilityEvent(
                id: "sam-approved-1",
                userID: "demo-sam",
                kind: .extraTimeApproved,
                occurredAt: now.addingTimeInterval(-40 * 60),
                seconds: 10 * 60,
                requestID: "sam-req-1",
                actorUserID: "demo-maya"
            ),
            AccountabilityEvent(
                id: "me-request-1",
                userID: meID,
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-80 * 60),
                seconds: 15 * 60,
                requestID: "me-req-1"
            ),
            AccountabilityEvent(
                id: "me-request-2",
                userID: meID,
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-20 * 60),
                seconds: 30 * 60,
                requestID: "me-req-2"
            ),
            AccountabilityEvent(
                id: "me-approved-1",
                userID: meID,
                kind: .extraTimeApproved,
                occurredAt: now.addingTimeInterval(-74 * 60),
                seconds: 15 * 60,
                requestID: "me-req-1",
                actorUserID: "demo-sam"
            ),
            AccountabilityEvent(
                id: "me-denied-2",
                userID: meID,
                kind: .extraTimeDenied,
                occurredAt: now.addingTimeInterval(-16 * 60),
                requestID: "me-req-2",
                actorUserID: "demo-maya"
            ),
            AccountabilityEvent(
                id: "riley-request-1",
                userID: "demo-riley",
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-130 * 60),
                seconds: 45 * 60,
                requestID: "riley-req-1"
            ),
            AccountabilityEvent(
                id: "riley-request-2",
                userID: "demo-riley",
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-2 * 3_600),
                seconds: 35 * 60,
                requestID: "riley-req-2"
            )
        ]

        let streaks: [(String, Int)] = [
            ("demo-maya", 5),
            ("demo-sam", 3),
            (meID, 1)
        ]

        for (userID, dayCount) in streaks {
            for offset in 0..<dayCount {
                if let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) {
                    events.append(
                        AccountabilityEvent(
                            id: "\(userID)-streak-\(offset)",
                            userID: userID,
                            kind: .underLimitDayCompleted,
                            occurredAt: date
                        )
                    )
                }
            }
        }

        return events
    }
    #endif
}

struct FriendRequestNotificationService {
    static let categoryIdentifier = "friend-time-request"
    static let requestIDUserInfoKey = "friendRequestID"

    private let defaults: UserDefaults
    private let notifiedRequestIDsKey = "NotifiedFriendRequestIDs.v1"
    private let notifiedStatusKey = "NotifiedFriendRequestStatusIDs.v1"

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func scheduleNotification(for request: BlockFriendRequest, groupName: String) {
        guard request.status == .pending,
              rememberNotification(for: request.id) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        let sender = request.requesterDisplayName ?? "A friend"
        let duration = BlockingDisplayFormatter.durationLabel(request.requestedSeconds)
        content.title = "\(sender) requests extra time"
        content.body = "\(duration) for \(groupName). Tap to review."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.requestIDUserInfoKey: request.id]

        let notificationRequest = UNNotificationRequest(
            identifier: notificationIdentifier(for: request.id),
            content: content,
            trigger: nil
        )

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                return
            }

            center.add(notificationRequest)
        }
    }

    func clearNotification(for requestID: String) {
        let identifier = notificationIdentifier(for: requestID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Notifies the original requester when a friend approves or denies their
    /// sent request. De-duplicated per (request, event) so it fires only once.
    func scheduleStatusUpdateNotification(for request: BlockFriendRequest, groupName: String) {
        let event: String
        let title: String
        let body: String
        switch request.status {
        case .approved:
            event = "approved"
            title = "Request approved"
            let duration = BlockingDisplayFormatter.durationLabel(request.requestedSeconds)
            body = "Collect \(duration) for \(groupName) before it expires."
        case .denied:
            event = "denied"
            title = "Request denied"
            body = "Your time request for \(groupName) was denied."
        default:
            return
        }

        guard rememberStatusNotification(for: request.id, event: event) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.requestIDUserInfoKey: request.id]

        let notificationRequest = UNNotificationRequest(
            identifier: "\(notificationIdentifier(for: request.id))-\(event)",
            content: content,
            trigger: nil
        )

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else {
                return
            }

            center.add(notificationRequest)
        }
    }

    private func rememberStatusNotification(for requestID: String, event: String) -> Bool {
        let key = "\(requestID)#\(event)"
        var keys = Set(defaults.stringArray(forKey: notifiedStatusKey) ?? [])
        guard !keys.contains(key) else {
            return false
        }

        keys.insert(key)
        defaults.set(Array(keys), forKey: notifiedStatusKey)
        return true
    }

    private func rememberNotification(for requestID: String) -> Bool {
        var requestIDs = Set(defaults.stringArray(forKey: notifiedRequestIDsKey) ?? [])
        guard !requestIDs.contains(requestID) else {
            return false
        }

        requestIDs.insert(requestID)
        defaults.set(Array(requestIDs), forKey: notifiedRequestIDsKey)
        return true
    }

    private func notificationIdentifier(for requestID: String) -> String {
        "friend-time-request-\(requestID)"
    }
}
