import Foundation
import Testing
@testable import ScreenTimeSharingCore

@Test func blockingStateRoundTripsWithSelectionDataAndRequests() throws {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let group = BlockGroup(
        id: "social",
        name: "Social",
        colorHex: "#E84855",
        selectionData: Data([1, 2, 3]),
        createdAt: now,
        updatedAt: now
    )
    let rule = BlockRule(
        id: "weekday-bedtime",
        groupID: group.id,
        kind: .scheduledWindow(days: [.monday, .friday], startMinute: 22 * 60, endMinute: 7 * 60),
        createdAt: now,
        updatedAt: now
    )
    let request = BlockRequest(
        id: "request-1",
        groupID: group.id,
        requestedSeconds: 15 * 60,
        status: .pending,
        createdAt: now
    )
    let state = BlockingState(groups: [group], rules: [rule], requests: [request], lastUpdated: now)

    let data = try BlockingStoreCodec.encode(state)
    let decoded = try BlockingStoreCodec.decode(data)

    #expect(decoded == state)
    #expect(decoded.groups.first?.selectionData == Data([1, 2, 3]))
}

@Test func blockingStateStorePersistsThroughUserDefaults() throws {
    let suiteName = "BlockingStateStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let group = BlockGroup(
        id: "social",
        name: "Social",
        colorHex: "#E84855",
        selectionData: Data([4, 5, 6]),
        createdAt: now,
        updatedAt: now
    )
    let state = BlockingState(groups: [group], lastUpdated: now)
    let store = BlockingStateStore(defaults: defaults, key: "BlockingStateStoreTests")

    try store.save(state)

    #expect(store.load() == state)
}

@Test func shieldIndexPersistsActiveFriendRequestGroupWithoutSelectionDecode() throws {
    let suiteName = "BlockingShieldIndexStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let social = BlockGroup(
        id: "social",
        name: "Social",
        colorHex: "#E84855",
        selectionData: Data([1, 2, 3]),
        friendRequestConfig: BlockFriendRequestConfig(isEnabled: true),
        createdAt: now,
        updatedAt: now
    )
    let games = BlockGroup(
        id: "games",
        name: "Games",
        colorHex: "#1B998B",
        selectionData: Data([4, 5, 6]),
        createdAt: now,
        updatedAt: now
    )
    let disabled = BlockGroup(
        id: "disabled",
        name: "Disabled",
        colorHex: "#6A4C93",
        selectionData: Data([7, 8, 9]),
        isEnabled: false,
        friendRequestConfig: BlockFriendRequestConfig(isEnabled: true),
        createdAt: now,
        updatedAt: now
    )
    let state = BlockingState(groups: [games, social, disabled], lastUpdated: now)
    let index = BlockingShieldIndex(state: state, activeGroupIDs: ["social", "disabled"], now: now)
    let store = BlockingShieldIndexStore(defaults: defaults, key: "BlockingShieldIndexStoreTests")

    store.save(index)
    let loaded = store.load()

    #expect(loaded.activeGroupIDs == ["social"])
    #expect(loaded.activeGroups.map(\.id) == ["social"])
    #expect(loaded.friendRequestGroupID == "social")
    #expect(loaded.groups.first { $0.id == "social" }?.isFriendRequestEnabled == true)
    #expect(defaults.string(forKey: BlockingStoreCodec.shieldFriendRequestGroupIDKey) == "social")
    #expect(defaults.bool(forKey: BlockingStoreCodec.shieldFriendRequestEnabledKey))
    #expect(defaults.object(forKey: BlockingStoreCodec.shieldRuntimeUpdatedAtKey) != nil)
}

@Test func shieldIndexClearsFriendRequestRuntimeWhenNoActiveFriendRequestGroup() throws {
    let suiteName = "BlockingShieldRuntimeClearTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let social = BlockGroup(
        id: "social",
        name: "Social",
        colorHex: "#E84855",
        selectionData: Data([1, 2, 3]),
        friendRequestConfig: BlockFriendRequestConfig(isEnabled: true),
        createdAt: now,
        updatedAt: now
    )
    let games = BlockGroup(
        id: "games",
        name: "Games",
        colorHex: "#1B998B",
        selectionData: Data([4, 5, 6]),
        createdAt: now,
        updatedAt: now
    )
    let store = BlockingShieldIndexStore(defaults: defaults, key: "BlockingShieldIndexRuntimeClearTests")

    store.save(BlockingShieldIndex(state: BlockingState(groups: [social], lastUpdated: now), activeGroupIDs: ["social"], now: now))
    #expect(defaults.string(forKey: BlockingStoreCodec.shieldFriendRequestGroupIDKey) == "social")
    #expect(defaults.bool(forKey: BlockingStoreCodec.shieldFriendRequestEnabledKey))

    store.save(BlockingShieldIndex(state: BlockingState(groups: [games], lastUpdated: now), activeGroupIDs: ["games"], now: now))

    #expect(defaults.string(forKey: BlockingStoreCodec.shieldFriendRequestGroupIDKey) == nil)
    #expect(defaults.bool(forKey: BlockingStoreCodec.shieldFriendRequestEnabledKey) == false)
}

@Test func scheduledRuleNormalizesDaysAndValidatesMinuteBounds() throws {
    let kind = BlockRuleKind.scheduledWindow(
        days: [.wednesday, .monday, .wednesday],
        startMinute: 9 * 60,
        endMinute: 17 * 60
    )
    let data = try JSONEncoder().encode(kind)
    let decoded = try JSONDecoder().decode(BlockRuleKind.self, from: data)

    guard case .scheduledWindow(let days, let startMinute, let endMinute) = decoded else {
        Issue.record("Expected scheduled window")
        return
    }

    #expect(days == [.monday, .wednesday])
    #expect(startMinute == 9 * 60)
    #expect(endMinute == 17 * 60)
    #expect(decoded.isValid)
    #expect(!BlockRuleKind.scheduledWindow(days: [], startMinute: 0, endMinute: 1).isValid)
    #expect(!BlockRuleKind.scheduledWindow(days: [.monday], startMinute: -1, endMinute: 1).isValid)
    #expect(!BlockRuleKind.scheduledWindow(days: [.monday], startMinute: 60, endMinute: 60).isValid)
}

@Test func resolverOnlyReturnsRulesForEnabledGroupsAndValidKinds() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let enabledGroup = BlockGroup(
        id: "enabled",
        name: "Enabled",
        colorHex: "#1B998B",
        selectionData: Data(),
        createdAt: now,
        updatedAt: now
    )
    let disabledGroup = BlockGroup(
        id: "disabled",
        name: "Disabled",
        colorHex: "#6A4C93",
        selectionData: Data(),
        isEnabled: false,
        createdAt: now,
        updatedAt: now
    )
    let valid = BlockRule(
        id: "valid",
        groupID: "enabled",
        kind: .dailyAllowance(seconds: 30 * 60),
        createdAt: now,
        updatedAt: now
    )
    let invalid = BlockRule(
        id: "invalid",
        groupID: "enabled",
        kind: .dailyAllowance(seconds: 0),
        createdAt: now,
        updatedAt: now
    )
    let disabledByGroup = BlockRule(
        id: "disabled-by-group",
        groupID: "disabled",
        kind: .dailyAllowance(seconds: 30 * 60),
        createdAt: now,
        updatedAt: now
    )
    let disabledRule = BlockRule(
        id: "disabled-rule",
        groupID: "enabled",
        isEnabled: false,
        kind: .dailyAllowance(seconds: 30 * 60),
        createdAt: now,
        updatedAt: now
    )
    let state = BlockingState(
        groups: [enabledGroup, disabledGroup],
        rules: [valid, invalid, disabledByGroup, disabledRule],
        lastUpdated: now
    )

    let enabledRules = BlockingStateResolver.enabledRules(in: state)

    #expect(enabledRules.map(\.id) == ["valid"])
    #expect(BlockingStateResolver.activeGroupIDs(in: state) == Set(["enabled"]))
    #expect(BlockingStateResolver.dailyAllowanceSeconds(for: "enabled", in: state) == TimeInterval(30 * 60))
}

@Test func blockRequestResolutionSetsStatusAndDate() {
    let createdAt = Date(timeIntervalSince1970: 100)
    let resolvedAt = Date(timeIntervalSince1970: 200)
    let request = BlockRequest(
        id: "request-1",
        groupID: "social",
        requestedSeconds: 5 * 60,
        status: .pending,
        createdAt: createdAt
    )

    let resolved = request.resolving(as: .approved, at: resolvedAt)

    #expect(resolved.status == .approved)
    #expect(resolved.resolvedAt == resolvedAt)
    #expect(resolved.createdAt == createdAt)
}

@Test func groupModeRoundTripsAndValidatesTimeLimitRange() throws {
    let mode = BlockGroupMode.timeLimit(limitSeconds: 55 * 60, days: [.friday, .monday, .friday])
    let data = try JSONEncoder().encode(mode)
    let decoded = try JSONDecoder().decode(BlockGroupMode.self, from: data)

    guard case .timeLimit(let seconds, let days) = decoded else {
        Issue.record("Expected time limit mode")
        return
    }

    #expect(seconds == 55 * 60)
    #expect(days == [.monday, .friday])
    #expect(decoded.isValid)
    #expect(BlockGroupMode.timeLimit(limitSeconds: 5 * 60, days: [.monday]).isValid)
    #expect(!BlockGroupMode.timeLimit(limitSeconds: 4 * 60, days: [.monday]).isValid)
    #expect(!BlockGroupMode.timeLimit(limitSeconds: 7 * 60, days: [.monday]).isValid)
    #expect(!BlockGroupMode.timeLimit(limitSeconds: 30 * 60, days: []).isValid)
}

@Test func blockingFullDurationLabelsUseWords() {
    #expect(BlockingDisplayFormatter.fullDurationLabel(5 * 60) == "5 minutes")
    #expect(BlockingDisplayFormatter.fullDurationLabel(60 * 60) == "1 hour")
    #expect(BlockingDisplayFormatter.fullDurationLabel(3 * 3_600 + 25 * 60) == "3 hours 25 minutes")
}

@Test func unblockDurationOptionsAllowOneMinute() {
    let config = BlockUnblockConfig(isEnabled: true, unblocksPerDay: 1, maxDurationSeconds: 60)

    #expect(config.maxDurationSeconds == 60)
    #expect(BlockingUnblockDurationOptions.minutes == [1, 5, 10, 15, 30, 60])
}

@Test func legacyRulesMigrateIntoGroupOwnedMode() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let group = BlockGroup(
        id: "social",
        name: "Social",
        colorHex: "#E84855",
        selectionData: Data([1]),
        createdAt: now,
        updatedAt: now
    )
    let legacyRule = BlockRule(
        id: "bedtime",
        groupID: "social",
        kind: .scheduledWindow(days: [.monday, .wednesday], startMinute: 22 * 60, endMinute: 7 * 60),
        createdAt: now,
        updatedAt: now
    )
    let migrated = BlockingStateMigrator.migrated(
        BlockingState(groups: [group], rules: [legacyRule], lastUpdated: now),
        now: now
    )

    guard case .scheduled(let startMinute, let endMinute, let days) = migrated.groups.first?.mode else {
        Issue.record("Expected scheduled mode")
        return
    }

    #expect(startMinute == 22 * 60)
    #expect(endMinute == 7 * 60)
    #expect(days == [.monday, .wednesday])
}

@Test func passwordHashVerifiesAndResetWaitsForRecoveryDelay() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let password = BlockingPasswordHasher.makePassword("focus", now: now, salt: "salt")
    let reset = BlockPasswordResetState(requestedAt: now)

    #expect(BlockingPasswordHasher.verify("focus", against: password))
    #expect(!BlockingPasswordHasher.verify("wrong", against: password))
    #expect(!reset.isAvailable(now: now.addingTimeInterval(BlockPasswordResetState.recoveryDelay - 1)))
    #expect(reset.isAvailable(now: now.addingTimeInterval(BlockPasswordResetState.recoveryDelay)))
}

@Test func unblockQuotaAndSuppressionUseTodaysSessions() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let group = BlockGroup(
        id: "social",
        name: "Social",
        colorHex: "#E84855",
        selectionData: Data([1]),
        unblockConfig: BlockUnblockConfig(isEnabled: true, unblocksPerDay: 2, maxDurationSeconds: 15 * 60),
        createdAt: now,
        updatedAt: now
    )
    let active = BlockUnblockSession(
        id: "active",
        groupID: "social",
        durationSeconds: 10 * 60,
        startedAt: now.addingTimeInterval(-60),
        expiresAt: now.addingTimeInterval(9 * 60)
    )
    let expiredToday = BlockUnblockSession(
        id: "expired",
        groupID: "social",
        durationSeconds: 5 * 60,
        startedAt: now.addingTimeInterval(-20 * 60),
        expiresAt: now.addingTimeInterval(-15 * 60)
    )
    let state = BlockingState(groups: [group], unblockSessions: [active, expiredToday], lastUpdated: now)

    #expect(BlockingStateResolver.remainingUnblocks(for: "social", in: state, now: now) == 0)
    #expect(BlockingStateResolver.suppressedGroupIDs(in: state, now: now) == Set(["social"]))
    #expect(BlockingStateResolver.activeUnblockSessions(in: state, now: now.addingTimeInterval(20 * 60)).isEmpty)
}

@Test func localFriendRequestPayloadRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let photoReference = BlockFriendRequestPhotoReference(localIdentifier: "photo-123")
    let request = BlockFriendRequest(
        id: "friend-request",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam", "maya"],
        message: "Need to check a message",
        createdAt: now,
        photoReference: photoReference
    )
    let state = BlockingState(friendRequests: [request], lastUpdated: now)

    let data = try BlockingStoreCodec.encode(state)
    let decoded = try BlockingStoreCodec.decode(data)

    #expect(decoded.friendRequests == [request])
    #expect(decoded.friendRequests.first?.photoReference == photoReference)
    #expect(BlockingStateResolver.pendingFriendRequests(in: decoded).map(\.id) == ["friend-request"])
}

@Test func legacyFriendRequestWithoutPhotoStillDecodes() throws {
    let json = """
    {
      "id": "legacy-request",
      "groupID": "social",
      "requestedSeconds": 900,
      "selectedFriendIDs": ["sam"],
      "message": "Need a minute",
      "status": "pending",
      "createdAt": 0
    }
    """

    let request = try JSONDecoder().decode(BlockFriendRequest.self, from: Data(json.utf8))

    #expect(request.id == "legacy-request")
    #expect(request.photoReference == nil)
}

@Test func pendingReceivedFriendRequestsOnlyIncludeActionableIncomingRequests() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let olderIncoming = BlockFriendRequest(
        id: "older-incoming",
        groupID: "social",
        requestedSeconds: 10 * 60,
        selectedFriendIDs: ["me"],
        message: "",
        requesterID: "sam",
        createdAt: now.addingTimeInterval(-60)
    )
    let newerIncoming = BlockFriendRequest(
        id: "newer-incoming",
        groupID: "social",
        requestedSeconds: 20 * 60,
        selectedFriendIDs: ["me"],
        message: "",
        requesterID: "maya",
        createdAt: now
    )
    let approvedIncoming = BlockFriendRequest(
        id: "approved-incoming",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["me"],
        message: "",
        requesterID: "riley",
        status: .approved,
        createdAt: now.addingTimeInterval(-30)
    )
    let sent = BlockFriendRequest(
        id: "sent",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        createdAt: now.addingTimeInterval(-10)
    )
    let state = BlockingState(friendRequests: [olderIncoming, newerIncoming, approvedIncoming, sent], lastUpdated: now)

    let ids = BlockingStateResolver.pendingReceivedFriendRequests(for: "me", in: state).map(\.id)

    #expect(ids == ["newer-incoming", "older-incoming"])
}

@Test func pendingReceivedFriendRequestsMatchLegacyProfileAliases() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let incoming = BlockFriendRequest(
        id: "incoming",
        groupID: "social",
        requestedSeconds: 10 * 60,
        selectedFriendIDs: ["profile-me"],
        message: "",
        requesterID: "sam",
        createdAt: now
    )
    let sent = BlockFriendRequest(
        id: "sent",
        groupID: "social",
        requestedSeconds: 10 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "profile-me",
        createdAt: now
    )
    let state = BlockingState(friendRequests: [incoming, sent], lastUpdated: now)
    let currentIDs: Set<String> = ["me", "profile-me"]

    #expect(incoming.isReceived(byAny: currentIDs))
    #expect(sent.isSent(byAny: currentIDs))
    #expect(BlockingStateResolver.pendingReceivedFriendRequests(forAny: currentIDs, in: state).map(\.id) == ["incoming"])
}

@Test func pendingSentFriendRequestsAreGroupScopedAndPendingOnly() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let sentPendingSocial = BlockFriendRequest(
        id: "sent-pending-social",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        createdAt: now
    )
    let sentPendingGames = BlockFriendRequest(
        id: "sent-pending-games",
        groupID: "games",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        createdAt: now.addingTimeInterval(-10)
    )
    let sentApprovedSocial = BlockFriendRequest(
        id: "sent-approved-social",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "",
        requesterID: "me",
        status: .approved,
        createdAt: now.addingTimeInterval(-20)
    )
    let receivedPendingSocial = BlockFriendRequest(
        id: "received-pending-social",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["me"],
        message: "",
        requesterID: "sam",
        createdAt: now.addingTimeInterval(-5)
    )
    let state = BlockingState(
        friendRequests: [sentPendingSocial, sentPendingGames, sentApprovedSocial, receivedPendingSocial],
        lastUpdated: now
    )
    let currentIDs: Set<String> = ["me", "profile-me"]

    let ids = BlockingStateResolver.pendingSentFriendRequests(
        forAny: currentIDs,
        inGroup: "social",
        in: state
    ).map(\.id)

    #expect(ids == ["sent-pending-social"])
}

@Test func friendRequestsExpireAndCollectAfterApproval() {
    let now = Date(timeIntervalSince1970: 1_779_236_400)
    let request = BlockFriendRequest(
        id: "friend-request",
        groupID: "social",
        requestedSeconds: 15 * 60,
        selectedFriendIDs: ["sam"],
        message: "Need a minute",
        requesterID: "me",
        createdAt: now
    )

    let pendingExpired = request.expiringIfNeeded(
        now: now.addingTimeInterval(BlockFriendRequestLifecycle.pendingExpirationSeconds + 1)
    )
    #expect(pendingExpired.status == .expired)
    #expect(pendingExpired.resolvedAt == request.pendingExpiresAt)

    let approvedAt = now.addingTimeInterval(60)
    let approved = request.resolving(as: .approved, at: approvedAt, approvedByFriendID: "sam")
    #expect(approved.status == .approved)
    #expect(approved.resolvedAt == approvedAt)
    #expect(approved.approvedByFriendID == "sam")
    #expect(approved.collectionExpiresAt == approvedAt.addingTimeInterval(24 * 3_600))

    let collected = approved.collecting(at: approvedAt.addingTimeInterval(5 * 60))
    #expect(collected.status == .collected)
    #expect(collected.collectedAt == approvedAt.addingTimeInterval(5 * 60))

    let approvalExpired = approved.expiringIfNeeded(
        now: approvedAt.addingTimeInterval(BlockFriendRequestLifecycle.approvedCollectionExpirationSeconds + 1)
    )
    #expect(approvalExpired.status == .expired)
    #expect(approvalExpired.approvedByFriendID == "sam")
    #expect(approvalExpired.resolvedAt == approvedAt)
}

@Test func unblockSessionSelectionDataRoundTripsAndLegacyDecodes() throws {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let session = BlockUnblockSession(
        id: "unblock",
        groupID: "social",
        selectionData: Data([1, 2, 3]),
        durationSeconds: 15 * 60,
        startedAt: now,
        expiresAt: now.addingTimeInterval(15 * 60)
    )

    let decoded = try JSONDecoder().decode(
        BlockUnblockSession.self,
        from: JSONEncoder().encode(session)
    )

    #expect(decoded.selectionData == Data([1, 2, 3]))

    let legacyData = """
    {
      "id": "legacy",
      "groupID": "social",
      "durationSeconds": 300,
      "startedAt": 1000,
      "expiresAt": 1300
    }
    """.data(using: .utf8)!

    let legacy = try JSONDecoder().decode(BlockUnblockSession.self, from: legacyData)
    #expect(legacy.selectionData == nil)
    #expect(legacy.groupID == "social")
}

@Test func monitorNamesAreDeterministicAndParseable() {
    #expect(BlockingMonitorNameBuilder.dailyAllowanceActivityName(ruleID: "daily.social") == "screenlog.block.allowance.daily-social")
    #expect(BlockingMonitorNameBuilder.dailyAllowanceEventName(ruleID: "daily.social") == "screenlog.block.threshold.daily-social")
    #expect(
        BlockingMonitorNameBuilder.scheduledActivityName(ruleID: "bed time", weekday: .monday)
            == "screenlog.block.schedule.bed-time.2"
    )
    #expect(BlockingMonitorNameBuilder.timeLimitActivityName(groupID: "social", weekday: .monday) == "screenlog.block.limit.social.2")
    #expect(BlockingMonitorNameBuilder.scheduledActivityName(groupID: "social", weekday: .monday) == "screenlog.block.group.schedule.social.2")
    #expect(BlockingMonitorNameBuilder.parseGroupID(from: "screenlog.block.limit.social.2") == "social")
    #expect(BlockingMonitorNameBuilder.parseGroupID(from: "screenlog.block.group.schedule.social.2") == "social")
    #expect(BlockingMonitorNameBuilder.parseRuleID(from: "screenlog.block.allowance.daily-social") == "daily-social")
    #expect(BlockingMonitorNameBuilder.parseRuleID(from: "other.block.allowance.daily") == nil)
}
