import CloudKit
import FamilyControls
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile
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

    let snapshotStore: CloudKitUsageSnapshotStore

    private let profileStore: LocalProfileStore
    private let selectionStore: FamilyActivitySelectionStore
    private let screenTimeProvider: ScreenTimeProvider
    private let widgetCacheWriter: AppGroupWidgetCacheWriter
    private let blockingStore: BlockingStateStore
    private let blockingEnforcementService: BlockingEnforcementService
    private let usageHistoryDefaults: UserDefaults?
    private let onboardingKey = "HasCompletedOnboarding.v1"
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
        blockingEnforcementService: BlockingEnforcementService = BlockingEnforcementService()
    ) {
        self.profileStore = profileStore
        self.selectionStore = selectionStore
        self.screenTimeProvider = screenTimeProvider
        self.snapshotStore = snapshotStore
        self.widgetCacheWriter = widgetCacheWriter
        self.blockingStore = blockingStore
        self.blockingEnforcementService = blockingEnforcementService
        self.usageHistoryDefaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)
        self.profile = profileStore.load()
        self.selection = selectionStore.load()
        self.blockingState = blockingStore.load()
        self.blockingSelection = FamilyActivitySelection()
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        self.screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        loadUsageHistory()
        refreshLocalAccountabilityStats()
        #if DEBUG
        seedDemoUsageHistory()
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

    func load() async {
        screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        cloudAvailability = await snapshotStore.cloudAvailability()
        await reloadFriends()
        syncBlockingEnforcement()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    func updateProfile(displayName: String? = nil, avatarColorHex: String? = nil) {
        if let displayName {
            profile.displayName = displayName
        }

        if let avatarColorHex {
            profile.avatarColorHex = avatarColorHex
        }

        profile.updatedAt = Date()
        profileStore.save(profile)
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
        message requestMessage: String
    ) -> Bool {
        guard let group = BlockingStateResolver.group(for: groupID, in: blockingState),
              group.friendRequestConfig.isEnabled else {
            message = "Friend requests are off for this group."
            return false
        }

        let now = Date()
        let request = BlockFriendRequest(
            id: UUID().uuidString,
            groupID: groupID,
            requestedSeconds: BlockingTimeLimitRange.snappedSeconds(seconds),
            selectedFriendIDs: selectedFriendIDs,
            message: requestMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now
        )

        blockingState.friendRequests.insert(request, at: 0)
        saveBlockingStateWithStatus("Friend request saved locally for this demo build.")
        refreshLocalAccountabilityStats()
        writeWidgetCacheSnapshot()
        return true
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
        #if DEBUG
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
                case .expired, .pending:
                    break
                }
            }

            return events
        }
        let friendRequestEvents = blockingState.friendRequests.flatMap { request -> [AccountabilityEvent] in
            var events = [
                AccountabilityEvent(
                    id: "\(request.id)-friend-requested",
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
                            id: "\(request.id)-friend-approved",
                            userID: profile.id,
                            kind: .extraTimeApproved,
                            occurredAt: resolvedAt,
                            seconds: request.requestedSeconds,
                            requestID: request.id,
                            actorUserID: request.selectedFriendIDs.first
                        )
                    )
                case .denied:
                    events.append(
                        AccountabilityEvent(
                            id: "\(request.id)-friend-denied",
                            userID: profile.id,
                            kind: .extraTimeDenied,
                            occurredAt: resolvedAt,
                            requestID: request.id,
                            actorUserID: request.selectedFriendIDs.first
                        )
                    )
                case .expired, .pending:
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

    func setLeaderboardWindow(_ window: LeaderboardWindow) {
        leaderboardWindow = window
        refreshLocalAccountabilityStats()

        #if DEBUG
        if UserDefaults.standard.bool(forKey: demoFriendsKey) {
            seedDemoFriends()
        }
        #endif
    }

    #if DEBUG
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

    func seedDemoFriends() {
        let now = Date()
        let friends = makeDemoFriends(now: now)
        let demo = makeDemoLeaderboard(now: now)
        friendSummaries = friends
        leaderboardEntries = demo.entries
        UserDefaults.standard.set(true, forKey: demoFriendsKey)

        do {
            try widgetCacheWriter.write(
                friends: friends,
                leaderboardEntries: leaderboardEntries,
                currentUserID: profile.id
            )
            message = "Demo friends added for simulator testing."
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
        let currentWeekMinutes = [421, 360, 238, 297, 22, 0, 0]
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
            ),
            AccountabilityEvent(
                id: "riley-emergency-1",
                userID: "demo-riley",
                kind: .emergencyUnlockUsed,
                occurredAt: now.addingTimeInterval(-90 * 60)
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
