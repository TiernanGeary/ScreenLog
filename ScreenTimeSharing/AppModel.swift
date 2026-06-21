import FamilyControls
import Foundation
import Supabase
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
final class AppModel: ObservableObject {
    @Published var profile: UserProfile
    @Published var appearanceMode: AppAppearanceMode
    @Published var selection: FamilyActivitySelection
    @Published var blockingState: BlockingState
    @Published var localSnapshot: DailyUsageSnapshot?
    @Published var usageHistory: [DailyUsageSnapshot] = []
    @Published var hourlyUsageByDayID: [String: [TimeInterval]] = [:]
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var myGroups: [FriendGroupSummary] = []
    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var leaderboardWindow: LeaderboardWindow = .today
    @Published var cloudAvailability: BackendAvailability = .checking
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
    @Published var pendingIncomingInvite: IncomingInvite?
    @Published var pendingIncomingGroupInvite: PeekedGroupInvite?
    @Published var isRedeemingInvite = false
    @Published var isDeletingAccount = false
    @Published var isAuthenticated: Bool

    let snapshotStore: SupabaseSnapshotStore
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
    private let appGroupDefaults: UserDefaults?
    private let usageHistoryDefaults: UserDefaults?
    private let onboardingKey = "HasCompletedOnboarding.v1"
    private static let denyStartedAtKey = "DenyStartedAt.v1"
    private static let appearanceKey = "AppAppearanceMode.v1"
    private var isSyncingFriendRequests = false
    private var pendingConfiguredGroupIDs: Set<String> = []
    private var pendingGroupCollectRequestIDs: Set<String> = []
    private var poolGroupSlots: [String: Int] = [:]
    #if DEBUG
    private let demoFriendsKey = "UsesDemoFriends.v1"
    #endif

    init(
        profileStore: LocalProfileStore = LocalProfileStore(),
        selectionStore: FamilyActivitySelectionStore = FamilyActivitySelectionStore(),
        screenTimeProvider: ScreenTimeProvider = DeviceActivityScreenTimeProvider(),
        snapshotStore: SupabaseSnapshotStore = SupabaseSnapshotStore(),
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
        self.appGroupDefaults = sharedDefaults
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
        ) ?? .light
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

    var poolGroupSlotAssignments: [(slot: Int, groupID: String, selection: FamilyActivitySelection)] {
        myGroups.compactMap { group -> (slot: Int, groupID: String, selection: FamilyActivitySelection)? in
            let blockGroupID = "group.\(group.id)"
            guard let slot = poolGroupSlots[group.id],
                  let blockGroup = blockingState.groups.first(where: { $0.id == blockGroupID }),
                  let selection = try? BlockingSelectionCodec.decode(blockGroup.selectionData),
                  !selection.isEmpty else {
                return nil
            }

            return (slot: slot, groupID: group.id, selection: selection)
        }
        .sorted { $0.slot < $1.slot }
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
        await publishProfileUpdateToCloud()
        await loadMyGroups()
        await publishSnapshotIfNeeded()
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
        // The Supabase auth user UUID (stable for this Apple ID) becomes the
        // canonical profile ID, so reinstalls and new devices land on the same
        // identity without any local mapping.
        let userID = try await snapshotStore.signIn(with: credential)

        if let serverProfile = try? await snapshotStore.fetchOwnProfile(),
           !serverProfile.displayName.isEmpty {
            profile = serverProfile
        } else {
            profile.id = userID
            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter.localizedString(
                    from: fullName,
                    style: .medium,
                    options: []
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != "Me" {
                    profile.displayName = name
                }
            }
            profile.updatedAt = Date()
        }

        profile.appleUserID = credential.userID
        profileStore.save(profile)
        adoptProfileID()
        isAuthenticated = true
        await publishProfileUpdateToCloud()
        return credential
    }

    func checkExistingSession() async {
        guard let userID = await snapshotStore.restoreSession() else {
            isAuthenticated = false
            return
        }

        if let serverProfile = try? await snapshotStore.fetchOwnProfile(),
           !serverProfile.displayName.isEmpty {
            profile = serverProfile
        } else if profile.id != userID {
            profile.id = userID
            profile.updatedAt = Date()
        }

        profileStore.save(profile)
        adoptProfileID()
        isAuthenticated = true
        await publishProfileUpdateToCloud()
    }

    func signOut() async {
        await snapshotStore.signOut()
        isAuthenticated = false
        message = "Signed out."
    }

    /// Permanently deletes the account server-side, then wipes local identity
    /// and drops back to onboarding. Returns false (with a message) when the
    /// server-side deletion fails, so the UI can keep the account intact.
    @discardableResult
    func deleteAccount() async -> Bool {
        isWorking = true
        isDeletingAccount = true
        defer {
            isWorking = false
            isDeletingAccount = false
        }

        do {
            try await snapshotStore.deleteAccount()
        } catch {
            message = "Could not delete your account: \(error.localizedDescription)"
            return false
        }

        profileStore.clearAll()
        friendSummaries = []
        leaderboardEntries = []
        blockingState.friendRequests = []
        try? persistBlockingState()

        UserDefaults.standard.set(false, forKey: onboardingKey)
        isAuthenticated = false
        hasCompletedOnboarding = false
        profile = profileStore.load()
        message = "Your account and data were deleted."
        return true
    }

    #if DEBUG
    private static let debugAuthIndexKey = "DebugAuthIndex.v1"

    /// Simulator/testing backdoor: signs in to a pre-provisioned Supabase
    /// account so two simulators can connect as friends. The account index is
    /// derived from the simulator's device name (stable, and distinct across
    /// different simulator models) and persisted for relaunches.
    @discardableResult
    func signInWithDebugAccount() async -> Bool {
        let index: Int
        if let stored = UserDefaults.standard.object(forKey: Self.debugAuthIndexKey) as? Int {
            index = stored
        } else {
            index = Self.stableHash(UIDevice.current.name) % 10
            UserDefaults.standard.set(index, forKey: Self.debugAuthIndexKey)
        }

        do {
            let userID = try await snapshotStore.signInWithDebugAccount(index: index)
            if let serverProfile = try? await snapshotStore.fetchOwnProfile(),
               !serverProfile.displayName.isEmpty {
                profile = serverProfile
            } else {
                profile.id = userID
                if profile.displayName == "Me" {
                    profile.displayName = "Sim \(index)"
                }
                profile.updatedAt = Date()
            }
            profileStore.save(profile)
            adoptProfileID()
            isAuthenticated = true
            await publishProfileUpdateToCloud()
            return true
        } catch {
            message = "Debug sign-in failed: \(error.localizedDescription)"
            return false
        }
    }

    private static func stableHash(_ value: String) -> Int {
        var hash = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
    #endif

    /// Re-stamps the (possibly new) profile ID everywhere it lives outside this
    /// model: the app-group storage the Screen Time extensions read, and the
    /// push server registration (the APNs token usually arrives before sign-in,
    /// registered under the pre-auth placeholder ID).
    private func adoptProfileID() {
        ScreenTimeReportStorage.saveProfileID(profile.id, defaults: usageHistoryDefaults)
        if let apnsDeviceToken {
            let profileID = profile.id
            Task { [pushServerClient] in
                await pushServerClient.register(profileID: profileID, deviceToken: apnsDeviceToken)
            }
        }
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
    func deleteBlockGroup(
        _ group: BlockGroup,
        password: String? = nil,
        forceForGroupBlock: Bool = false
    ) -> Bool {
        if !(forceForGroupBlock && group.id.hasPrefix("group.")) {
            guard canVerifyGroupPassword(group, password: password) else {
                message = "Enter this group password before deleting it."
                return false
            }
        }

        blockingState.groups.removeAll { $0.id == group.id }
        blockingState.rules.removeAll { $0.groupID == group.id }
        blockingState.requests.removeAll { $0.groupID == group.id }
        blockingState.friendRequests.removeAll { $0.groupID == group.id }
        blockingState.unblockSessions.removeAll { $0.groupID == group.id }
        blockingState.poolExhaustionOverrides.removeAll { $0.groupID == group.id }
        groupUnlockExpirations[group.id] = nil
        saveBlockingStateWithStatus("Block group deleted.")
        return true
    }

    @MainActor
    @discardableResult
    func adoptGroupBlock(
        groupID: String,
        limitSeconds: Int,
        selection: FamilyActivitySelection
    ) async -> Bool {
        if !hasScreenTimeAuthorization {
            await requestScreenTimeAuthorization()
            guard hasScreenTimeAuthorization else {
                return false
            }
        }

        guard let data = try? BlockingSelectionCodec.encode(selection) else {
            message = "Could not save your app selection."
            return false
        }

        let password = GroupBlock.generatePassword()
        let group = GroupBlock.makeBlockGroup(
            id: "group.\(groupID)",
            name: "Group limit",
            selectionData: data,
            limitSeconds: BlockingTimeLimitRange.snappedSeconds(TimeInterval(limitSeconds))
        )
        guard upsertBlockGroup(group, password: password) else {
            return false
        }

        guard GroupBlockPasswordStore.save(password, groupID: groupID) else {
            _ = deleteBlockGroup(group, forceForGroupBlock: true)
            message = "Could not save your group block password."
            return false
        }
        do {
            try await snapshotStore.setMemberConfigured(groupID: groupID, configured: true)
        } catch {
            pendingConfiguredGroupIDs.insert(groupID)
        }
        return true
    }

    @MainActor
    @discardableResult
    func adoptGroupPoolBlock(
        groupID: String,
        poolSeconds: Int,
        selection: FamilyActivitySelection
    ) async -> Bool {
        await adoptGroupBlock(
            groupID: groupID,
            limitSeconds: poolSeconds,
            selection: selection
        )
    }

    func removeGroupBlock(groupID: String) {
        let blockGroupID = "group.\(groupID)"
        let hadOverride = blockingState.poolExhaustionOverrides.contains { $0.groupID == blockGroupID }
        if let group = blockingState.groups.first(where: { $0.id == blockGroupID }) {
            _ = deleteBlockGroup(group, forceForGroupBlock: true)
        }
        blockingState.poolExhaustionOverrides.removeAll { $0.groupID == blockGroupID }
        GroupBlockPasswordStore.delete(groupID: groupID)
        if hadOverride {
            do {
                try persistBlockingState()
            } catch {
                message = "Could not save blocking settings: \(error.localizedDescription)"
            }
        }
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
            photoReference: photoReference,
            groupAppNames: topAppNames(in: group)
        )

        blockingState.friendRequests.insert(request, at: 0)
        clearPendingShieldFriendRequest()
        saveBlockingStateWithStatus("Friend request sent.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
        let senderName = profile.displayName == "Me" ? "A friend" : profile.displayName
        let durationLabel = BlockingDisplayFormatter.durationLabel(request.requestedSeconds)
        let pushBody = "\(senderName) is asking for \(durationLabel) in \(group.name). Tap to review."
        Task {
            // Only alert recipients once the request actually reached the
            // backend — otherwise they get a push for a request they can't see.
            let published = await publishFriendRequestToCloud(request, photoData: photoJPEGData)
            if published {
                sendPushNotification(
                    toProfileIDs: selectedFriendIDs,
                    title: "New time request",
                    body: pushBody,
                    requestID: request.id
                )
            }
        }
        return true
    }

    @discardableResult
    @MainActor
    func requestGroupTime(
        socialGroupID: String,
        seconds: TimeInterval,
        message requestMessage: String,
        photoJPEGData: Data?
    ) async -> Bool {
        let availability = await snapshotStore.cloudAvailability()
        cloudAvailability = availability
        guard availability.allowsCloudWrites else {
            message = "\(availability.label). Group request was not sent."
            return false
        }

        do {
            let requestID = UUID().uuidString.lowercased()
            let photoPath = try await uploadGroupRequestPhoto(photoJPEGData, requestID: requestID)
            let createdRequestID = try await snapshotStore.sendGroupTimeRequest(
                requestID: requestID,
                socialGroupID: socialGroupID,
                blockGroupID: "group.\(socialGroupID)",
                seconds: Int(seconds),
                message: requestMessage.trimmingCharacters(in: .whitespacesAndNewlines),
                photoPath: photoPath
            )
            await syncFriendRequests()

            let recipientIDs = await groupRequestRecipientIDs(
                requestID: createdRequestID,
                socialGroupID: socialGroupID
            )
            let senderName = profile.displayName == "Me" ? "A group member" : profile.displayName
            let durationLabel = BlockingDisplayFormatter.durationLabel(TimeInterval(Int(seconds)))
            let groupName = friendGroupName(socialGroupID: socialGroupID)
            sendPushNotification(
                toProfileIDs: recipientIDs,
                title: "New group time request",
                body: "\(senderName) is asking for \(durationLabel) in \(groupName). Tap to review.",
                requestID: createdRequestID
            )
            message = "Group request sent."
            return true
        } catch {
            message = "Could not send group request: \(error.localizedDescription)"
            return false
        }
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

        if request.socialGroupID != nil {
            Task {
                let didRespond = await respondGroupFriendRequest(
                    requestID: id,
                    approve: true,
                    approvedByFriendID: profile.id
                )
                if didRespond {
                    friendRequestNotificationService.clearNotification(for: id)
                }
            }
            return true
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

        if request.socialGroupID != nil {
            Task {
                let didRespond = await respondGroupFriendRequest(
                    requestID: id,
                    approve: false,
                    approvedByFriendID: nil
                )
                if didRespond {
                    friendRequestNotificationService.clearNotification(for: id)
                }
            }
            return true
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
        if collectedRequest.socialGroupID == nil {
            Task {
                await publishFriendRequestUpdateToCloud(collectedRequest)
            }
        } else {
            let requestID = collectedRequest.id
            Task {
                do {
                    try await snapshotStore.collectGroupTimeRequest(requestID: requestID)
                } catch {
                    pendingGroupCollectRequestIDs.insert(requestID)
                }
            }
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

        var snapshot = await screenTimeProvider.loadTodayUsage(selection: selection, profile: profile)
        #if DEBUG && targetEnvironment(simulator)
        // The simulator produces no real Screen Time, so fall back to the
        // seeded demo snapshot — lets two sims exercise friend usage sharing.
        if !snapshot.capability.allowsUpload,
           let demoSnapshot = UsageStatsBuilder.snapshot(for: Date(), in: usageHistory),
           demoSnapshot.capability.allowsUpload {
            snapshot = demoSnapshot
        }
        #endif
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
            if profile.shareStatus != .sharing {
                profile.shareStatus = .sharing
                profile.updatedAt = Date()
                profileStore.save(profile)
            }
            try await snapshotStore.publish(profile: profile, snapshot: snapshot)
            message = "Usage snapshot uploaded."
            await reloadFriends()
            await syncFriendRequests()
        } catch {
            message = "Upload failed: \(error.localizedDescription)"
        }
    }

    /// Mints a shareable invite code for the current user. Inviting a friend
    /// is consent to share usage with them, so it also enables sharing.
    func createInvite() async throws -> CreatedInvite {
        let invite = try await snapshotStore.createInvite()
        await enableSharingIfNeeded()
        return invite
    }

    func loadMyGroups() async {
        do {
            myGroups = try await snapshotStore.getMyGroups()
            cleanupDroppedGroupBlocks()
        } catch {
            message = "Could not refresh groups: \(error.localizedDescription)"
        }
        await retryPendingConfiguredGroups()
        await retryPendingGroupCollects()
        assignPoolGroupSlots()
    }

    private func assignPoolGroupSlots() {
        let poolGroups = myGroups.filter { $0.mode == .pool }
        let assignedGroups = Array(poolGroups.prefix(5))

        poolGroupSlots = Dictionary(
            uniqueKeysWithValues: assignedGroups.enumerated().map { index, group in
                (group.id, index)
            }
        )

        for slot in 0..<5 {
            let groupBlockID = assignedGroups.indices.contains(slot)
                ? "group.\(assignedGroups[slot].id)"
                : nil
            ScreenTimeReportStorage.setPoolSlotAssignment(
                slot,
                groupBlockID: groupBlockID,
                defaults: appGroupDefaults
            )
        }

        if poolGroups.count > assignedGroups.count {
            print(
                "ScreenLog: \(poolGroups.count - assignedGroups.count) pool group(s) exceed the 5-slot usage-report cap and will use whole-device fallback."
            )
        }
    }

    private func cleanupDroppedGroupBlocks() {
        let liveIDs = Set(myGroups.map(\.id))
        let droppedGroupIDs = blockingState.groups.compactMap { group -> String? in
            guard group.id.hasPrefix("group.") else {
                return nil
            }
            let socialGroupID = String(group.id.dropFirst(6))
            return liveIDs.contains(socialGroupID) ? nil : socialGroupID
        }

        for groupID in droppedGroupIDs {
            removeGroupBlock(groupID: groupID)
        }

        let originalCount = blockingState.poolExhaustionOverrides.count
        blockingState.poolExhaustionOverrides.removeAll { override in
            override.groupID.hasPrefix("group.")
                && !liveIDs.contains(String(override.groupID.dropFirst(6)))
        }
        guard blockingState.poolExhaustionOverrides.count != originalCount else {
            return
        }

        do {
            try persistBlockingState()
        } catch {
            message = "Could not save blocking settings: \(error.localizedDescription)"
        }
    }

    private func retryPendingConfiguredGroups() async {
        let liveIDs = Set(myGroups.map(\.id))
        for groupID in Array(pendingConfiguredGroupIDs) where liveIDs.contains(groupID) {
            do {
                try await snapshotStore.setMemberConfigured(groupID: groupID, configured: true)
                pendingConfiguredGroupIDs.remove(groupID)
            } catch {
                // Non-fatal: retried after the next group refresh.
            }
        }
    }

    private func retryPendingGroupCollects() async {
        for requestID in Array(pendingGroupCollectRequestIDs) {
            do {
                try await snapshotStore.collectGroupTimeRequest(requestID: requestID)
                pendingGroupCollectRequestIDs.remove(requestID)
            } catch {
                // Non-fatal: retried after the next group refresh.
            }
        }
    }

    @discardableResult
    func createGroup(
        name: String,
        mode: GroupMode,
        appNames: [String],
        limitSeconds: Int,
        approvalsRequired: Int
    ) async -> CreatedGroup? {
        let errs = GroupConfigValidation.errors(
            mode: mode,
            appNames: appNames,
            limitSeconds: limitSeconds,
            approvalsRequired: approvalsRequired
        )
        guard errs.isEmpty else {
            message = errs.joined(separator: " ")
            return nil
        }

        do {
            let g = try await snapshotStore.createGroup(
                name: name,
                mode: mode,
                appNames: GroupAppNames.normalize(appNames),
                limitSeconds: limitSeconds,
                approvalsRequired: approvalsRequired,
                timeZone: TimeZone.current.identifier
            )
            await loadMyGroups()
            return g
        } catch {
            message = "Could not create group: \(error.localizedDescription)"
            return nil
        }
    }

    /// Friends can only read this user's snapshots while the profile is marked
    /// sharing (enforced server-side). Connecting with a friend or uploading
    /// usage is the consent that turns it on.
    private func enableSharingIfNeeded() async {
        guard profile.shareStatus != .sharing else {
            return
        }

        profile.shareStatus = .sharing
        profile.updatedAt = Date()
        profileStore.save(profile)
        await publishProfileUpdateToCloud()
    }

    func presentIncomingGroupInvite(code: String) async {
        if let invite = try? await snapshotStore.peekGroupInvite(code: code) {
            pendingIncomingGroupInvite = invite
        } else {
            pendingIncomingGroupInvite = PeekedGroupInvite(
                code: code,
                groupID: "",
                groupName: "Group",
                ownerDisplayName: "Friend",
                mode: .perMember
            )
        }
    }

    @discardableResult
    func redeemPendingGroupInvite() async -> Bool {
        guard let invite = pendingIncomingGroupInvite else {
            return false
        }

        do {
            let redeemed = try await snapshotStore.redeemGroupInvite(code: invite.code)
            message = "You joined \(redeemed.groupName)."
            await loadMyGroups()
            if pendingIncomingGroupInvite?.code == invite.code {
                pendingIncomingGroupInvite = nil
            }
            return true
        } catch {
            message = "Could not join group: \(error.localizedDescription)"
            return false
        }
    }

    func dismissIncomingGroupInvite() {
        pendingIncomingGroupInvite = nil
    }

    /// Shows the accept sheet for an invite code arriving via deep link,
    /// resolving the inviter's name when the code is valid.
    func presentIncomingInvite(code: String) async {
        if let invite = try? await snapshotStore.peekInvite(code: code) {
            pendingIncomingInvite = invite
        } else {
            pendingIncomingInvite = IncomingInvite(
                code: code,
                inviterDisplayName: "Friend",
                inviterAvatarColorHex: nil
            )
        }
    }

    func dismissIncomingInvite() {
        pendingIncomingInvite = nil
    }

    func redeemPendingInvite() async {
        guard let invite = pendingIncomingInvite else {
            return
        }

        isRedeemingInvite = true
        defer {
            isRedeemingInvite = false
        }

        let redeemed = await redeemInvite(code: invite.code)
        if redeemed, pendingIncomingInvite?.code == invite.code {
            pendingIncomingInvite = nil
        }
    }

    @discardableResult
    func redeemInvite(code: String) async -> Bool {
        do {
            let redeemed = try await snapshotStore.redeemInvite(code: code)
            message = "You're now connected with \(redeemed.inviterDisplayName)."
            await enableSharingIfNeeded()
            await reloadFriends()
            await syncFriendRequests()

            // Push to the inviter we just connected with, so they're alerted
            // even if their app is closed.
            let inviterName = profile.displayName == "Me" ? "A friend" : profile.displayName
            sendPushNotification(
                toProfileIDs: [redeemed.inviterProfileID],
                title: "New friend",
                body: "\(inviterName) added you as a friend on deny.",
                requestID: nil
            )
            return true
        } catch {
            message = "Could not add friend: \(error.localizedDescription)"
            return false
        }
    }

    func leaveGroup(_ groupID: String) async {
        do {
            try await snapshotStore.leaveGroup(groupID: groupID)
            removeGroupBlock(groupID: groupID)
            await loadMyGroups()
        } catch {
            message = "Could not leave group: \(error.localizedDescription)"
        }
    }

    func removeGroupMember(groupID: String, userID: String) async {
        do {
            try await snapshotStore.removeGroupMember(groupID: groupID, userID: userID)
            await loadMyGroups()
        } catch {
            message = "Could not remove group member: \(error.localizedDescription)"
        }
    }

    func deleteGroup(_ groupID: String) async {
        do {
            try await snapshotStore.deleteGroup(groupID: groupID)
            removeGroupBlock(groupID: groupID)
            await loadMyGroups()
        } catch {
            message = "Could not delete group: \(error.localizedDescription)"
        }
    }

    func loadGroupDetail(groupID: String) async -> GroupDetail? {
        try? await snapshotStore.getGroup(groupID: groupID)
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

    /// Invoked when a push wakes the app (foreground or background): pull
    /// the latest friends + requests so the existing notification logic posts the
    /// approve/deny/new-request alerts even when the app wasn't open.
    func handleRemoteChange() async {
        await loadMyGroups()
        await reloadFriends()
        await syncFriendRequests()
        await syncGroupPools()
    }

    private var lastSnapshotPublishAt: Date?

    /// Publishes today's snapshot automatically (launch/foreground/poll),
    /// throttled to every 10 minutes, so friends see fresh usage without the
    /// user ever tapping a manual refresh. Visibility to friends is still
    /// gated server-side by the sharing consent flag.
    func publishSnapshotIfNeeded(now: Date = Date()) async {
        guard isAuthenticated else {
            return
        }
        if let lastSnapshotPublishAt, now.timeIntervalSince(lastSnapshotPublishAt) < 600 {
            return
        }

        var snapshot = localSnapshot
        #if DEBUG && targetEnvironment(simulator)
        if snapshot?.capability.allowsUpload != true {
            snapshot = UsageStatsBuilder.snapshot(for: now, in: usageHistory)
        }
        #endif
        guard let snapshot, snapshot.capability.allowsUpload else {
            return
        }
        guard await snapshotStore.cloudAvailability().allowsCloudWrites else {
            return
        }

        do {
            try await snapshotStore.publish(profile: profile, snapshot: snapshot)
            lastSnapshotPublishAt = now
            for group in myGroups where group.mode == .pool {
                let selectedAppSeconds = await selectedAppSecondsForPoolGroup(group)
                if let state = try? await snapshotStore.reportGroupUsage(
                    groupID: group.id,
                    selectedAppSeconds: selectedAppSeconds
                ) {
                    applyPoolState(group, state, allowBroadcast: true)
                }
            }
        } catch {
            // Non-fatal: retried on the next poll cycle.
        }
    }

    private func selectedAppSecondsForPoolGroup(_ group: FriendGroupSummary) async -> Int {
        let blockGroupID = "group.\(group.id)"
        guard let blockGroup = blockingState.groups.first(where: { $0.id == blockGroupID }),
              let groupSelection = try? BlockingSelectionCodec.decode(blockGroup.selectionData),
              !groupSelection.isEmpty else {
            return 0
        }

        if let slot = poolGroupSlots[group.id] {
            let dayKey = UsageDateBoundary.localDayKey(date: Date(), calendar: .current)
            return ScreenTimeReportStorage.groupUsageSlot(
                slot,
                groupBlockID: blockGroupID,
                dayKey: dayKey,
                defaults: appGroupDefaults
            )
        }

        let groupSnapshot = await screenTimeProvider.loadTodayUsage(selection: groupSelection, profile: profile)
        return Int(groupSnapshot.selectedAppDuration ?? 0)
    }

    func syncGroupPools() async {
        for group in myGroups where group.mode == .pool {
            if let state = try? await snapshotStore.getGroupPoolState(groupID: group.id) {
                applyPoolState(group, state, allowBroadcast: false)
            }
        }
    }

    private func applyPoolState(_ group: FriendGroupSummary, _ state: GroupPoolState, allowBroadcast: Bool) {
        let blockGroupID = "group.\(group.id)"
        let now = Date()
        var didChange = false
        var shouldNotifyPoolExhausted = false

        let expiredCount = blockingState.poolExhaustionOverrides.count
        blockingState.poolExhaustionOverrides.removeAll {
            $0.groupID == blockGroupID && now >= $0.resetsAt
        }
        didChange = blockingState.poolExhaustionOverrides.count != expiredCount
        let existing = blockingState.poolExhaustionOverrides.first { $0.groupID == blockGroupID }
        let hadActiveOverride = existing?.isActive(now: now) == true

        if state.exhausted {
            let resetsAt = nextOwnerTimeZoneMidnight(
                after: now,
                timeZoneIdentifier: group.ownerTimeZone
            )

            if let index = blockingState.poolExhaustionOverrides.firstIndex(where: { $0.groupID == blockGroupID }) {
                if blockingState.poolExhaustionOverrides[index].resetsAt != resetsAt {
                    blockingState.poolExhaustionOverrides[index].resetsAt = resetsAt
                    didChange = true
                }
            } else {
                let override = PoolExhaustionOverride(
                    groupID: blockGroupID,
                    exhaustedAt: now,
                    resetsAt: resetsAt
                )
                blockingState.poolExhaustionOverrides.append(override)
                didChange = true
            }
            shouldNotifyPoolExhausted = !hadActiveOverride
        } else {
            if let existing, now.timeIntervalSince(existing.exhaustedAt) < 30 {
                if didChange {
                    do {
                        try persistBlockingState()
                    } catch {
                        message = "Could not save blocking settings: \(error.localizedDescription)"
                    }
                }
                return
            }
            let originalCount = blockingState.poolExhaustionOverrides.count
            blockingState.poolExhaustionOverrides.removeAll { $0.groupID == blockGroupID }
            didChange = didChange || blockingState.poolExhaustionOverrides.count != originalCount
        }

        guard didChange else {
            return
        }

        do {
            try persistBlockingState()
        } catch {
            message = "Could not save blocking settings: \(error.localizedDescription)"
        }

        if allowBroadcast && shouldNotifyPoolExhausted {
            notifyGroupMembersPoolExhausted(groupID: group.id)
        }
    }

    private func notifyGroupMembersPoolExhausted(groupID: String) {
        let currentUserID = profile.id
        Task { @MainActor [weak self] in
            guard let self, let detail = await self.loadGroupDetail(groupID: groupID) else {
                return
            }
            let recipients = Set(
                detail.members
                    .map(\.userID)
                    .filter { !$0.isEmpty && $0.caseInsensitiveCompare(currentUserID) != .orderedSame }
            )
            for recipient in recipients {
                await self.pushServerClient.notifyPoolExhausted(toProfileID: recipient, groupID: groupID)
            }
        }
    }

    private func nextOwnerTimeZoneMidnight(after now: Date, timeZoneIdentifier: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let dayKey = GroupPool.dayKey(now: now, timeZoneIdentifier: timeZoneIdentifier)
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }

        guard parts.count == 3 else {
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(24 * 60 * 60)
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]

        guard let todayStart = calendar.date(from: components),
              let nextStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(24 * 60 * 60)
        }

        return nextStart
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

    private func uploadGroupRequestPhoto(_ photoData: Data?, requestID: String) async throws -> String? {
        guard let photoData, !photoData.isEmpty else {
            return nil
        }

        _ = try friendRequestPhotoStore.saveJPEGData(photoData, id: requestID)
        let client = SupabaseClientProvider.shared
        let session = try await client.auth.session
        let uid = session.user.id
        let path = "\(uid.uuidString.lowercased())/\(requestID.lowercased()).jpg"
        try await client.storage.from("request-photos").upload(
            path,
            data: photoData,
            options: FileOptions(contentType: "image/jpeg")
        )
        return path
    }

    private func groupRequestRecipientIDs(requestID: String, socialGroupID: String) async -> [String] {
        if let request = blockingState.friendRequests.first(where: { $0.id == requestID }) {
            return request.selectedFriendIDs
        }

        guard let detail = try? await snapshotStore.getGroup(groupID: socialGroupID) else {
            return []
        }

        return detail.members.map(\.userID)
    }

    private func friendGroupName(socialGroupID: String) -> String {
        myGroups.first { $0.id == socialGroupID }?.name ?? "your group"
    }

    private func respondGroupFriendRequest(
        requestID: String,
        approve: Bool,
        approvedByFriendID: String?
    ) async -> Bool {
        let availability = await snapshotStore.cloudAvailability()
        cloudAvailability = availability
        guard availability.allowsCloudWrites else {
            message = "\(availability.label). Request was not updated."
            return false
        }

        do {
            let statusRaw = try await snapshotStore.respondGroupTimeRequest(
                requestID: requestID,
                approve: approve
            )
            let requesterID = blockingState.friendRequests.first { $0.id == requestID }?.requesterID
            updateLocalGroupFriendRequest(
                requestID: requestID,
                statusRaw: statusRaw,
                approve: approve,
                approvedByFriendID: approvedByFriendID
            )
            if BlockRequestStatus(rawValue: statusRaw) == .approved {
                let approverName = profile.displayName == "Me" ? "Your friend" : profile.displayName
                sendPushNotification(
                    toProfileIDs: [requesterID].compactMap { $0 },
                    title: "Request approved",
                    body: "\(approverName) approved your time request. Tap to collect.",
                    requestID: requestID
                )
            }
            await syncFriendRequests()
            return true
        } catch {
            message = "Could not update group request: \(error.localizedDescription)"
            return false
        }
    }

    private func updateLocalGroupFriendRequest(
        requestID: String,
        statusRaw: String,
        approve: Bool,
        approvedByFriendID: String?
    ) {
        guard let status = BlockRequestStatus(rawValue: statusRaw),
              let index = blockingState.friendRequests.firstIndex(where: { $0.id == requestID }) else {
            return
        }

        var request = blockingState.friendRequests[index]
        request.status = status
        if status == .approved {
            request.approvedByFriendID = approvedByFriendID ?? request.approvedByFriendID
        } else if status == .denied {
            request.approvedByFriendID = nil
        }
        blockingState.friendRequests[index] = request
        saveBlockingStateWithStatus(groupResponseStatusMessage(status: status, approve: approve))
        refreshLocalAccountabilityStats()
        syncFriendRequestNotifications()
        writeWidgetCacheSnapshot()
    }

    private func groupResponseStatusMessage(status: BlockRequestStatus, approve: Bool) -> String {
        switch status {
        case .approved:
            return "Request approved."
        case .denied:
            return "Request denied."
        case .pending:
            return approve ? "Approval recorded." : "Request updated."
        case .expired, .collected:
            return "Request updated."
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
            writeWidgetCacheSnapshot()
        } catch {
            message = "Could not sync friend requests: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func publishFriendRequestToCloud(_ request: BlockFriendRequest, photoData: Data?) async -> Bool {
        let availability = await snapshotStore.cloudAvailability()
        cloudAvailability = availability
        guard availability.allowsCloudWrites else {
            message = "\(availability.label). Friend request saved only on this device."
            return false
        }

        do {
            let report = try await snapshotStore.publishFriendRequestDiagnostic(request, profile: profile, photoData: photoData)
            if report.deliveredCount == 0 {
                func shorten(_ ids: [String]) -> String {
                    ids.isEmpty ? "none" : ids.map { String($0.prefix(6)) }.joined(separator: ",")
                }
                message = "Couldn't deliver to [\(shorten(report.targetFriendIDs))]. Make sure you're still connected as friends."
                return false
            }
            return true
        } catch {
            message = "Friend request saved locally. Cloud sync failed: \(error.localizedDescription)"
            return false
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

    /// Backstop for timed unblocks: re-syncs enforcement whenever the app
    /// returns to the foreground so the shield re-applies if an unblock window
    /// has expired. Expired sessions are already excluded from exemptions by the
    /// isActive(now:) filter, so we must NOT delete them here — the daily unblock
    /// allowance is counted from sessions started today, and removing them would
    /// reset that counter.
    func reapplyBlockingOnForeground() {
        syncBlockingEnforcement()
        Task {
            await loadMyGroups()
            await syncGroupPools()
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

        // Rank yourself AND your friends: requests you're a party to already
        // carry events attributed to whoever sent them, so friends' stats are
        // computable from data the server lets you see. Only people who
        // actually requested time appear on the request leaderboard.
        var participants = [
            AccountabilityParticipant(
                id: profile.id,
                displayName: profile.displayName == "Me" ? "You" : profile.displayName,
                avatarColorHex: profile.avatarColorHex,
                avatarImageData: profile.avatarImageData
            )
        ]
        participants += friendSummaries.map { friend in
            AccountabilityParticipant(
                id: friend.id,
                displayName: friend.displayName,
                avatarColorHex: friend.avatarColorHex,
                avatarImageData: friend.avatarImageData
            )
        }

        let participantIDs = Set(participants.map(\.id))
        let preservedEntries = otherEntries.filter { !participantIDs.contains($0.userID) }
        leaderboardEntries = LeaderboardBuilder.entries(
            participants: participants,
            events: events,
            window: leaderboardWindow
        )
        .filter { $0.requestCount > 0 || $0.requestedExtraSeconds > 0 }
        + preservedEntries
    }

    /// Today's screen-time leaderboard: you and your friends ranked by usage
    /// (least time wins), built from the same data the friend list shows.
    var usageLeaderboardEntries: [LeaderboardEntry] {
        var entries = [
            LeaderboardEntry(
                id: "usage-\(profile.id)",
                userID: profile.id,
                displayName: profile.displayName == "Me" ? "You" : profile.displayName,
                avatarColorHex: profile.avatarColorHex,
                avatarImageData: profile.avatarImageData,
                requestedExtraSeconds: 0,
                approvedExtraSeconds: 0,
                requestCount: 0,
                deniedCount: 0,
                emergencyUnlockCount: 0,
                settingsResetCount: 0,
                currentStreakDays: 0,
                lastUpdated: localSnapshot?.lastUpdated,
                usageSeconds: localSnapshot?.totalDuration
            )
        ]
        entries += friendSummaries.map { friend in
            LeaderboardEntry(
                id: "usage-\(friend.id)",
                userID: friend.id,
                displayName: friend.displayName,
                avatarColorHex: friend.avatarColorHex,
                avatarImageData: friend.avatarImageData,
                requestedExtraSeconds: 0,
                approvedExtraSeconds: 0,
                requestCount: 0,
                deniedCount: 0,
                emergencyUnlockCount: 0,
                settingsResetCount: 0,
                currentStreakDays: 0,
                lastUpdated: friend.lastUpdated,
                usageSeconds: friend.totalDuration
            )
        }
        return entries.sorted {
            ($0.usageSeconds ?? .greatestFiniteMagnitude) < ($1.usageSeconds ?? .greatestFiniteMagnitude)
        }
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

    /// Clears delivered request notifications once a request resolves. New
    /// requests and status changes are announced by the push server alone —
    /// local duplicates were removed when alert pushes became guaranteed.
    private func syncFriendRequestNotifications() {
        for request in blockingState.friendRequests {
            guard request.isReceived(byAny: currentFriendIdentityIDs),
                  request.status != .pending else {
                continue
            }

            friendRequestNotificationService.clearNotification(for: request.id)
        }
    }

    private func groupName(forNotification groupID: String) -> String {
        blockingState.groups.first { $0.id == groupID }?.name ?? "restricted app"
    }

    /// Resolves the requester's most-used apps inside a block group by matching
    /// the group's app tokens against locally stored usage rows. Returns
    /// display names only — tokens never leave this device.
    private func topAppNames(in group: BlockGroup, limit: Int = 3) -> [String]? {
        guard let selection = try? BlockingSelectionCodec.decode(group.selectionData) else {
            return nil
        }

        let encoder = JSONEncoder()
        let groupTokenData = Set(selection.applicationTokens.compactMap { try? encoder.encode($0) })

        #if DEBUG && targetEnvironment(simulator)
        // Simulator groups have no real app tokens; fall back to overall top
        // apps from the (demo) usage history so the feature is testable.
        let matchesGroup: (SharedAppUsage) -> Bool = { row in
            groupTokenData.isEmpty
                || row.applicationTokenData.map(groupTokenData.contains) == true
        }
        #else
        guard !groupTokenData.isEmpty else {
            return nil
        }
        let matchesGroup: (SharedAppUsage) -> Bool = { row in
            row.applicationTokenData.map(groupTokenData.contains) == true
        }
        #endif

        struct AppTotal {
            var displayName: String
            var bundleIdentifier: String?
            var duration: TimeInterval = 0
        }

        var totalsByKey: [String: AppTotal] = [:]
        for snapshot in usageHistory {
            for row in snapshot.appRows where matchesGroup(row) {
                let key = row.bundleIdentifier ?? row.displayName
                var total = totalsByKey[key] ?? AppTotal(
                    displayName: row.displayName,
                    bundleIdentifier: row.bundleIdentifier
                )
                total.duration += max(0, row.duration)
                totalsByKey[key] = total
            }
        }

        guard !totalsByKey.isEmpty else {
            return nil
        }

        // Reported screen time can be noisy, so well-known attention sinks
        // outrank raw duration; within each tier, sort by measured usage.
        return totalsByKey.values
            .sorted { lhs, rhs in
                let lhsKnown = Self.isKnownDistractor(name: lhs.displayName, bundleID: lhs.bundleIdentifier)
                let rhsKnown = Self.isKnownDistractor(name: rhs.displayName, bundleID: rhs.bundleIdentifier)
                if lhsKnown != rhsKnown {
                    return lhsKnown
                }
                return lhs.duration > rhs.duration
            }
            .prefix(limit)
            .map(\.displayName)
    }

    private static let distractorBundleIDs: Set<String> = [
        "com.zhiliaoapp.musically",      // TikTok
        "com.burbn.instagram",           // Instagram
        "com.google.ios.youtube",        // YouTube
        "com.toyopagroup.picaboo",       // Snapchat
        "com.atebits.tweetie2",          // X / Twitter
        "com.facebook.facebook",         // Facebook
        "com.reddit.reddit",             // Reddit
        "tv.twitch",                     // Twitch
        "com.hammerandchisel.discord",   // Discord
        "com.netflix.netflix"            // Netflix
    ]

    private static let distractorNames: Set<String> = [
        "tiktok", "instagram", "youtube", "snapchat", "x", "twitter",
        "facebook", "reddit", "twitch", "discord", "netflix", "threads",
        "tumblr", "pinterest"
    ]

    private static func isKnownDistractor(name: String, bundleID: String?) -> Bool {
        if let bundleID, distractorBundleIDs.contains(bundleID.lowercased()) {
            return true
        }
        return distractorNames.contains(
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
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

    /// Simulator-only: creates an enabled block group with friend requests on,
    /// since FamilyActivityPicker has no apps to select in the simulator.
    func seedDemoBlockGroup() {
        guard let groupID = ensureDemoRequestGroup(now: Date()) else {
            message = "Could not create the demo block group."
            return
        }

        try? persistBlockingState()
        syncBlockingEnforcement()
        let name = blockingState.groups.first { $0.id == groupID }?.name ?? "Social"
        message = "Demo block group \"\(name)\" ready — friend time requests enabled."
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
    private let notifiedFriendsKey = "NotifiedFriendIDs.v1"

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

    /// Posts a local notification the first time we observe a given friend, so
    /// both sides learn the friendship connected. De-duplicated per friend ID.
    func scheduleFriendAddedNotification(friendID: String, friendName: String) {
        guard rememberFriendAdded(friendID) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "New friend"
        let name = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = name.isEmpty || name == "Friend"
            ? "You're now connected with a new friend on deny."
            : "\(name) is now your friend on deny."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier

        let notificationRequest = UNNotificationRequest(
            identifier: "friend-added-\(friendID)",
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

    private func rememberFriendAdded(_ friendID: String) -> Bool {
        var ids = Set(defaults.stringArray(forKey: notifiedFriendsKey) ?? [])
        guard !ids.contains(friendID) else {
            return false
        }

        ids.insert(friendID)
        defaults.set(Array(ids), forKey: notifiedFriendsKey)
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
