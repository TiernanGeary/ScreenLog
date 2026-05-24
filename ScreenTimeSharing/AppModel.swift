import CloudKit
import FamilyControls
import Foundation
import SwiftUI
import UserNotifications
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

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile
    @Published var appearanceMode: AppAppearanceMode
    @Published var selection: FamilyActivitySelection
    @Published var blockingSelection: FamilyActivitySelection
    @Published var blockingState: BlockingState
    @Published var localSnapshot: DailyUsageSnapshot?
    @Published var usageHistory: [DailyUsageSnapshot] = []
    @Published var hourlyUsageByDayID: [String: [TimeInterval]] = [:]
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var leaderboardWindow: LeaderboardWindow = .week
    @Published var cloudAvailability: CloudAvailability = .checking
    @Published var screenTimeAuthorization = "Not requested"
    @Published var message: String?
    @Published var isWorking = false
    @Published var hasCompletedOnboarding: Bool
    @Published private(set) var groupUnlockExpirations: [String: Date] = [:]
    @Published var pendingShieldFriendRequestGroupID: String?
    @Published var focusedFriendRequestLogID: String?

    let snapshotStore: CloudKitUsageSnapshotStore

    private let profileStore: LocalProfileStore
    private let selectionStore: FamilyActivitySelectionStore
    private let screenTimeProvider: ScreenTimeProvider
    private let widgetCacheWriter: AppGroupWidgetCacheWriter
    private let blockingStore: BlockingStateStore
    private let blockingEnforcementService: BlockingEnforcementService
    private let friendRequestNotificationService: FriendRequestNotificationService
    private let friendRequestPhotoStore: FriendRequestPhotoStore
    private let usageHistoryDefaults: UserDefaults?
    private let onboardingKey = "HasCompletedOnboarding.v1"
    private static let appearanceKey = "AppAppearanceMode.v1"
    #if DEBUG && targetEnvironment(simulator)
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
        friendRequestPhotoStore: FriendRequestPhotoStore = FriendRequestPhotoStore()
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
        self.usageHistoryDefaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)
        self.profile = profileStore.load()
        self.appearanceMode = AppAppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ""
        ) ?? .dark
        self.selection = selectionStore.load()
        self.blockingState = blockingStore.load()
        self.blockingSelection = FamilyActivitySelection()
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        self.screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        loadUsageHistory()
        expireStaleFriendRequests()
        loadPendingShieldFriendRequest()
        refreshLocalAccountabilityStats()
        syncFriendRequestNotifications()
        #if DEBUG && targetEnvironment(simulator)
        let demoNow = Date()
        seedDemoUsageHistory(now: demoNow)
        seedDemoFriends(now: demoNow, showsStatusMessage: false)
        #else
        self.localSnapshot = UsageStatsBuilder.snapshot(for: Date(), in: usageHistory)
            ?? usageHistory.sorted { $0.date > $1.date }.first
        #endif
    }

    var selectedActivityCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var selectedBlockingActivityCount: Int {
        blockingSelection.applicationTokens.count + blockingSelection.categoryTokens.count + blockingSelection.webDomainTokens.count
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

    func load() async {
        screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        expireStaleFriendRequests()
        loadPendingShieldFriendRequest()
        cloudAvailability = await snapshotStore.cloudAvailability()
        await reloadFriends()
        syncFriendRequestNotifications()
        syncBlockingEnforcement()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    #if DEBUG
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: onboardingKey)
        message = "Onboarding reset. Relaunch or continue through the setup flow again."
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
    }

    func friendRequestPhotoData(for request: BlockFriendRequest) -> Data? {
        guard let photoReference = request.photoReference else {
            return nil
        }

        return friendRequestPhotoStore.data(for: photoReference)
    }

    func persistSelection() {
        selectionStore.save(selection)
    }

    func saveSuggestedSocialBlockGroup() {
        guard !blockingSelection.isEmpty else {
            return
        }

        do {
            let now = Date()
            let selectionData = try BlockingSelectionCodec.encode(blockingSelection)
            let existingIndex = blockingState.groups.firstIndex {
                $0.name.localizedCaseInsensitiveCompare("Social") == .orderedSame
            }
            if let existingIndex {
                blockingState.groups[existingIndex].selectionData = selectionData
                blockingState.groups[existingIndex].isEnabled = true
                blockingState.groups[existingIndex].updatedAt = now
            } else {
                blockingState.groups.append(
                    BlockGroup(
                        id: "social",
                        name: "Social",
                        colorHex: "#E84855",
                        selectionData: selectionData,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }

            blockingState.lastUpdated = now
            try persistBlockingState()
            message = "Social block group saved."
        } catch {
            message = "Could not save block group: \(error.localizedDescription)"
        }
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

        guard canEditGroup(blockingState.groups[index], password: password) else {
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
        guard canEditGroup(group, password: password) else {
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
        saveBlockingStateWithStatus("Password reset started. You can reset it after 24 hours.")
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
        guard request.isReceived(by: profile.id), request.status == .pending else {
            message = "Only pending received requests can be approved."
            return false
        }

        let now = Date()
        blockingState.friendRequests[index] = request.resolving(
            as: .approved,
            at: now,
            approvedByFriendID: profile.id
        )
        friendRequestNotificationService.clearNotification(for: id)
        saveBlockingStateWithStatus("Request approved.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
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
        guard request.isReceived(by: profile.id), request.status == .pending else {
            message = "Only pending received requests can be denied."
            return false
        }

        blockingState.friendRequests[index] = request.resolving(as: .denied, at: Date())
        friendRequestNotificationService.clearNotification(for: id)
        saveBlockingStateWithStatus("Request denied.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
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
        guard request.isSent(by: profile.id), request.status == .approved else {
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

        guard BlockingStateResolver.group(for: request.groupID, in: blockingState) != nil else {
            message = "Block group no longer exists."
            return false
        }

        let duration = BlockingTimeLimitRange.snappedSeconds(request.requestedSeconds)
        blockingState.unblockSessions.insert(
            BlockUnblockSession(
                id: UUID().uuidString,
                groupID: request.groupID,
                durationSeconds: duration,
                startedAt: now,
                expiresAt: now.addingTimeInterval(duration)
            ),
            at: 0
        )
        blockingState.friendRequests[index] = request.collecting(at: now)
        saveBlockingStateWithStatus("Collected \(BlockingDisplayFormatter.durationLabel(duration)) of approved time.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
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
        cloudAvailability = await snapshotStore.cloudAvailability()

        let snapshot = await screenTimeProvider.loadTodayUsage(selection: selection, profile: profile)
        localSnapshot = snapshot
        persistUsageSnapshot(snapshot)

        guard snapshot.capability.allowsUpload else {
            message = snapshot.capability.reason ?? "Screen Time unavailable. No usage was uploaded."
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
        } catch {
            message = "CloudKit upload failed: \(error.localizedDescription)"
        }
    }

    func acceptShare(metadata: CKShare.Metadata) async {
        do {
            try await snapshotStore.acceptShare(metadata: metadata)
            message = "Friend share accepted."
            await reloadFriends()
        } catch {
            message = "Could not accept share: \(error.localizedDescription)"
        }
    }

    func reloadFriends() async {
        #if DEBUG && targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: demoFriendsKey) {
            seedDemoFriends()
            return
        }
        #endif

        do {
            let friends = try await snapshotStore.fetchFriendSummaries()
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
        pendingShieldFriendRequestGroupID = nil
    }

    private func loadPendingShieldFriendRequest(now: Date = Date()) {
        guard let groupID = usageHistoryDefaults?.string(forKey: BlockingFriendRequestIntentStore.groupIDKey) else {
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
        syncBlockingEnforcement()
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
            guard request.isReceived(by: profile.id) else {
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

        #if DEBUG && targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: demoFriendsKey) {
            seedDemoFriends()
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    func seedDemoScreenTime() {
        seedDemoUsageHistory()
        message = "Demo Screen Time added for simulator testing."
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
                message = "Demo friends added for simulator testing."
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
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let currentWeekMinutes = [421, 360, 238, 297, 312, 248, 184]
        let monthPatternMinutes = [510, 485, 462, 438, 506, 472, 449, 330, 300, 285, 260, 310, 275, 255, 290, 270]
        var snapshots: [DailyUsageSnapshot] = []
        var hourlyDurationsByDayID: [String: [TimeInterval]] = [:]
        var cursor = monthInterval.start
        var dayIndex = 0

        while cursor <= today {
            let minutes: Int
            if let currentWeek,
               currentWeek.contains(cursor),
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
