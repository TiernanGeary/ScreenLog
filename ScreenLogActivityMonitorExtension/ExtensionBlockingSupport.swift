import FamilyControls
import Foundation
import ManagedSettings

enum ExtensionBlockingSupport {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: BlockingStoreCodec.suiteName)
    }

    private static var managedStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("screenlog.blocking"))
    }

    static func state() -> BlockingState {
        BlockingStateStore(defaults: defaults).load()
    }

    static func groupID(forRuleNamed rawName: String, state: BlockingState) -> String? {
        if let groupID = BlockingMonitorNameBuilder.parseGroupID(from: rawName),
           state.groups.contains(where: { $0.id == groupID }) {
            return groupID
        }

        guard let ruleID = BlockingMonitorNameBuilder.parseRuleID(from: rawName) else {
            return nil
        }

        return state.rules.first { $0.id == ruleID }?.groupID
    }

    static func setShieldActive(_ isActive: Bool, groupID: String, state: BlockingState) {
        var activeGroupIDs = activeShieldedGroupIDs()
        if isActive {
            activeGroupIDs.insert(groupID)
        } else {
            activeGroupIDs.remove(groupID)
        }

        defaults?.set(Array(activeGroupIDs), forKey: BlockingStoreCodec.activeShieldedGroupIDsKey)
        saveShieldIndex(activeGroupIDs: activeGroupIDs, state: state)
        applyShields(for: activeGroupIDs, state: state)
    }

    static func refreshActiveShields(state: BlockingState) {
        let enabledGroupIDs = Set(BlockingStateResolver.enabledGroups(in: state).map(\.id))
        let activeGroupIDs = activeShieldedGroupIDs().intersection(enabledGroupIDs)
        defaults?.set(Array(activeGroupIDs), forKey: BlockingStoreCodec.activeShieldedGroupIDsKey)
        saveShieldIndex(activeGroupIDs: activeGroupIDs, state: state)
        applyShields(for: activeGroupIDs, state: state)
    }

    /// Re-applies shields as an unblock ends. The warning callback fires up to a
    /// minute before the session's stored expiry, so the session would still
    /// count as active; exclude it explicitly so the shield actually returns.
    static func reapplyShieldsEndingUnblock(sessionID: String, state: BlockingState) {
        let enabledGroupIDs = Set(BlockingStateResolver.enabledGroups(in: state).map(\.id))
        let activeGroupIDs = activeShieldedGroupIDs().intersection(enabledGroupIDs)
        defaults?.set(Array(activeGroupIDs), forKey: BlockingStoreCodec.activeShieldedGroupIDsKey)
        saveShieldIndex(activeGroupIDs: activeGroupIDs, state: state)
        applyShields(for: activeGroupIDs, state: state, excludingUnblockSessionID: sessionID)
    }

    @discardableResult
    static func queueFriendRequestDraft(matching _: ApplicationToken? = nil) -> Bool {
        queueFriendRequestDraft(groupID: shieldIndex().friendRequestGroupID)
    }

    @discardableResult
    static func queueFriendRequestDraft(matching _: ActivityCategoryToken? = nil) -> Bool {
        queueFriendRequestDraft(groupID: shieldIndex().friendRequestGroupID)
    }

    @discardableResult
    static func queueFriendRequestDraft(matching _: WebDomainToken? = nil) -> Bool {
        queueFriendRequestDraft(groupID: shieldIndex().friendRequestGroupID)
    }

    static func shieldCopy(matching _: ApplicationToken? = nil, itemName: String? = nil) -> ShieldCopy {
        shieldCopy(index: shieldIndex(), itemName: itemName)
    }

    static func shieldCopy(matching _: ActivityCategoryToken? = nil, itemName: String? = nil) -> ShieldCopy {
        shieldCopy(index: shieldIndex(), itemName: itemName)
    }

    static func shieldCopy(matching _: WebDomainToken? = nil, itemName: String? = nil) -> ShieldCopy {
        shieldCopy(index: shieldIndex(), itemName: itemName)
    }

    private static func queueFriendRequestDraft(groupID: String?) -> Bool {
        guard let groupID = groupID else {
            return false
        }

        defaults?.set(groupID, forKey: BlockingFriendRequestIntentStore.groupIDKey)
        defaults?.set(Date(), forKey: BlockingFriendRequestIntentStore.createdAtKey)
        defaults?.synchronize()
        return true
    }

    private static func shieldIndex() -> BlockingShieldIndex {
        let index = BlockingShieldIndexStore(defaults: defaults).load()
        if !index.groups.isEmpty {
            return index
        }

        return BlockingShieldIndex(state: state(), activeGroupIDs: activeShieldedGroupIDs())
    }

    private static func saveShieldIndex(activeGroupIDs: Set<String>, state: BlockingState) {
        BlockingShieldIndexStore(defaults: defaults).save(
            BlockingShieldIndex(state: state, activeGroupIDs: activeGroupIDs)
        )
    }

    private static func shieldCopy(index: BlockingShieldIndex, itemName: String?) -> ShieldCopy {
        let groups = index.activeGroups
        let restrictedItemName = normalizedItemName(itemName)
        guard !groups.isEmpty else {
            return ShieldCopy(
                title: "Restricted",
                subtitle: "You cannot use \(restrictedItemName) because it is restricted.",
                primaryButton: "OK",
                secondaryButton: "Friend request disabled",
                isFriendRequestEnabled: false
            )
        }

        let hasFriendRequest = groups.contains(where: \.isFriendRequestEnabled)
        let hasQueuedFriendRequest = groups.contains { $0.id == pendingFriendRequestDraftGroupID() }

        if hasQueuedFriendRequest {
            return ShieldCopy(
                title: "Request ready",
                subtitle: "Tap the deny notification to take your photo request for \(restrictedItemName).",
                primaryButton: "OK",
                secondaryButton: "Send notification again",
                isFriendRequestEnabled: true
            )
        }

        return ShieldCopy(
            title: "Restricted",
            subtitle: "You cannot use \(restrictedItemName) because it is restricted.",
            primaryButton: "OK",
            secondaryButton: hasFriendRequest ? "Request time from friends" : "Friend request disabled",
            isFriendRequestEnabled: hasFriendRequest
        )
    }

    private static func pendingFriendRequestDraftGroupID(now: Date = Date()) -> String? {
        guard let groupID = defaults?.string(forKey: BlockingFriendRequestIntentStore.groupIDKey) else {
            return nil
        }

        let createdAt = defaults?.object(forKey: BlockingFriendRequestIntentStore.createdAtKey) as? Date
        if let createdAt,
           now.timeIntervalSince(createdAt) <= BlockingFriendRequestIntentStore.expirationSeconds {
            return groupID
        }

        return nil
    }

    private static func normalizedItemName(_ itemName: String?) -> String {
        let trimmed = itemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "this app" : trimmed
    }

    private static func activeShieldedGroupIDs() -> Set<String> {
        Set(defaults?.stringArray(forKey: BlockingStoreCodec.activeShieldedGroupIDsKey) ?? [])
    }

    private static func applyShields(
        for groupIDs: Set<String>,
        state: BlockingState,
        excludingUnblockSessionID excludedID: String? = nil
    ) {
        let now = Date()
        let forcedGroupIDs = forcedPoolExhaustionGroupIDs(in: state, now: now)
        // A group with an active unblock session is suppressed (not shielded).
        // When ending a specific unblock, that session must also be dropped from
        // suppression — otherwise the group stays suppressed because the warning
        // fires just before the session's stored expiry, and nothing re-shields.
        let suppressedGroupIDs = Set(
            BlockingStateResolver.activeUnblockSessions(in: state, now: now)
                .filter { $0.id != excludedID }
                .map(\.groupID)
        ).subtracting(forcedGroupIDs)
        let shieldedGroupIDs = groupIDs.union(forcedGroupIDs)
        let selections = state.groups
            .filter { shieldedGroupIDs.contains($0.id) && $0.isEnabled && !suppressedGroupIDs.contains($0.id) }
            .compactMap { decodeSelection($0.selectionData) }
        let forcedSelections = state.groups
            .filter { forcedGroupIDs.contains($0.id) && $0.isEnabled }
            .compactMap { decodeSelection($0.selectionData) }

        let exemptSelections = activeUnblockSelections(in: state, now: now, excluding: excludedID)
        var exemptApplications = exemptSelections.reduce(into: Set<ApplicationToken>()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }
        var exemptCategories = exemptSelections.reduce(into: Set<ActivityCategoryToken>()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }
        var exemptWebDomains = exemptSelections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }
        let forcedApplications = forcedSelections.reduce(into: Set<ApplicationToken>()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }
        let forcedCategories = forcedSelections.reduce(into: Set<ActivityCategoryToken>()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }
        let forcedWebDomains = forcedSelections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }
        exemptApplications.subtract(forcedApplications)
        exemptCategories.subtract(forcedCategories)
        exemptWebDomains.subtract(forcedWebDomains)

        let applications = selections.reduce(into: Set<ApplicationToken>()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }.subtracting(exemptApplications)
        let categories = selections.reduce(into: Set<ActivityCategoryToken>()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }.subtracting(exemptCategories)
        let webDomains = selections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }.subtracting(exemptWebDomains)

        managedStore.shield.applications = applications.isEmpty ? nil : applications
        // ManagedSettings exposes ONE opaque applicationCategories policy and no API to map an
        // ApplicationToken to its category, so we cannot express "force-shield category X with
        // no exceptions but keep category Y's per-app exemptions" in a single policy. When any
        // pool is exhausted (forcedCategories non-empty) we therefore fail CLOSED and drop the
        // `except:` for the whole policy. KNOWN/ACCEPTED collateral: an unrelated, non-forced
        // group's earned per-app unblock that happens to fall under some shielded category is
        // also re-shielded until the override clears. We accept that over the alternative
        // (keeping `except:`), which would punch a hole in the exhausted pool's guardrail — the
        // opposite and, for an accountability app, worse failure. Deliberate; do not flip
        // without an OS API for per-category exemptions. (Mirror of BlockingEnforcementService.)
        managedStore.shield.applicationCategories = categories.isEmpty ? nil : forcedCategories.isEmpty ? .specific(categories, except: exemptApplications) : .specific(categories)
        managedStore.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        managedStore.shield.webDomainCategories = categories.isEmpty ? nil : forcedCategories.isEmpty ? .specific(categories, except: exemptWebDomains) : .specific(categories)
    }

    private static func forcedPoolExhaustionGroupIDs(in state: BlockingState, now: Date = Date()) -> Set<String> {
        let groupIDs = Set(state.groups.map(\.id))
        return Set(
            state.poolExhaustionOverrides
                .filter { $0.isActive(now: now) && groupIDs.contains($0.groupID) }
                .map(\.groupID)
        )
    }

    private static func activeUnblockSelections(
        in state: BlockingState,
        now: Date = Date(),
        excluding excludedID: String? = nil
    ) -> [FamilyActivitySelection] {
        BlockingStateResolver.activeUnblockSessions(in: state, now: now)
            .filter { $0.id != excludedID }
            .compactMap { session in
            if let selectionData = session.selectionData,
               let selection = decodeSelection(selectionData) {
                return selection
            }

            guard let group = BlockingStateResolver.group(for: session.groupID, in: state) else {
                return nil
            }

            return decodeSelection(group.selectionData)
        }
    }

    private static func requestGroupID(matching token: ApplicationToken?, in state: BlockingState) -> String? {
        requestGroupID(from: groupIDs(matching: token, in: state), state: state)
    }

    private static func requestGroupID(matching token: ActivityCategoryToken?, in state: BlockingState) -> String? {
        requestGroupID(from: groupIDs(matching: token, in: state), state: state)
    }

    private static func requestGroupID(matching token: WebDomainToken?, in state: BlockingState) -> String? {
        requestGroupID(from: groupIDs(matching: token, in: state), state: state)
    }

    private static func requestGroupID(from matchingGroupIDs: Set<String>, state: BlockingState) -> String? {
        let candidateIDs = matchingGroupIDs.isEmpty ? effectiveActiveGroupIDs(in: state) : matchingGroupIDs.intersection(effectiveActiveGroupIDs(in: state))
        return state.groups.first { group in
            candidateIDs.contains(group.id)
                && group.isEnabled
                && group.friendRequestConfig.isEnabled
        }?.id
    }

    private static func effectiveActiveGroupIDs(in state: BlockingState) -> Set<String> {
        activeShieldedGroupIDs().subtracting(BlockingStateResolver.suppressedGroupIDs(in: state))
    }

    private static func groupIDs(matching token: ApplicationToken?, in state: BlockingState) -> Set<String> {
        guard let token else {
            return []
        }

        return Set(state.groups.compactMap { group in
            decodeSelection(group.selectionData)?.applicationTokens.contains(token) == true ? group.id : nil
        })
    }

    private static func groupIDs(matching token: ActivityCategoryToken?, in state: BlockingState) -> Set<String> {
        guard let token else {
            return []
        }

        return Set(state.groups.compactMap { group in
            decodeSelection(group.selectionData)?.categoryTokens.contains(token) == true ? group.id : nil
        })
    }

    private static func groupIDs(matching token: WebDomainToken?, in state: BlockingState) -> Set<String> {
        guard let token else {
            return []
        }

        return Set(state.groups.compactMap { group in
            decodeSelection(group.selectionData)?.webDomainTokens.contains(token) == true ? group.id : nil
        })
    }

    private static func decodeSelection(_ data: Data) -> FamilyActivitySelection? {
        try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}

struct ShieldCopy {
    let title: String
    let subtitle: String
    let primaryButton: String
    let secondaryButton: String
    let isFriendRequestEnabled: Bool
}
