import FamilyControls
import Foundation
import ManagedSettings

enum ExtensionBlockingSupport {
    private static let activeGroupIDsKey = "ActiveShieldedBlockGroupIDs.v1"
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

        defaults?.set(Array(activeGroupIDs), forKey: activeGroupIDsKey)
        applyShields(for: activeGroupIDs, state: state)
    }

    @discardableResult
    static func logExtraTimeRequest(seconds: TimeInterval, matching token: ApplicationToken? = nil) -> Bool {
        let state = state()
        return logExtraTimeRequest(seconds: seconds, groupID: requestGroupID(matching: token, in: state), state: state)
    }

    @discardableResult
    static func logExtraTimeRequest(seconds: TimeInterval, matching token: ActivityCategoryToken? = nil) -> Bool {
        let state = state()
        return logExtraTimeRequest(seconds: seconds, groupID: requestGroupID(matching: token, in: state), state: state)
    }

    @discardableResult
    static func logExtraTimeRequest(seconds: TimeInterval, matching token: WebDomainToken? = nil) -> Bool {
        let state = state()
        return logExtraTimeRequest(seconds: seconds, groupID: requestGroupID(matching: token, in: state), state: state)
    }

    static func shieldCopy(matching token: ApplicationToken? = nil) -> ShieldCopy {
        let state = state()
        let groupIDs = groupIDs(matching: token, in: state)
        return shieldCopy(groupIDs: groupIDs.isEmpty ? effectiveActiveGroupIDs(in: state) : groupIDs, state: state)
    }

    static func shieldCopy(matching token: ActivityCategoryToken? = nil) -> ShieldCopy {
        let state = state()
        let groupIDs = groupIDs(matching: token, in: state)
        return shieldCopy(groupIDs: groupIDs.isEmpty ? effectiveActiveGroupIDs(in: state) : groupIDs, state: state)
    }

    static func shieldCopy(matching token: WebDomainToken? = nil) -> ShieldCopy {
        let state = state()
        let groupIDs = groupIDs(matching: token, in: state)
        return shieldCopy(groupIDs: groupIDs.isEmpty ? effectiveActiveGroupIDs(in: state) : groupIDs, state: state)
    }

    private static func logExtraTimeRequest(seconds: TimeInterval, groupID: String?, state initialState: BlockingState) -> Bool {
        var state = initialState
        guard let groupID = groupID else {
            return false
        }

        let group = state.groups.first { $0.id == groupID }
        guard group?.friendRequestConfig.isEnabled == true else {
            return false
        }

        state.friendRequests.insert(
            BlockFriendRequest(
                id: UUID().uuidString,
                groupID: groupID,
                requestedSeconds: seconds,
                selectedFriendIDs: [],
                message: "Requested from shield",
                createdAt: Date()
            ),
            at: 0
        )
        state.lastUpdated = Date()
        try? BlockingStateStore(defaults: defaults).save(state)
        return true
    }

    private static func shieldCopy(groupIDs: Set<String>, state: BlockingState) -> ShieldCopy {
        let groups = state.groups.filter { groupIDs.contains($0.id) && $0.isEnabled }
        guard !groups.isEmpty else {
            return ShieldCopy(
                title: "Blocked by ScreenLog",
                subtitle: "Open ScreenLog to manage this block.",
                primaryButton: "Request 15m",
                secondaryButton: "Open ScreenLog"
            )
        }

        let hasLocalUnblock = groups.contains { $0.unblockConfig.isEnabled }
        let hasFriendRequest = groups.contains { $0.friendRequestConfig.isEnabled }
        let subtitle: String
        switch (hasLocalUnblock, hasFriendRequest) {
        case (true, true):
            subtitle = "Open ScreenLog for a limited unblock or to request friend approval."
        case (true, false):
            subtitle = "Open ScreenLog for a limited unblock."
        case (false, true):
            subtitle = "Open ScreenLog to request friend approval."
        case (false, false):
            subtitle = "This group is blocked by your current ScreenLog settings."
        }

        return ShieldCopy(
            title: groups.count == 1 ? "\(groups[0].name) is blocked" : "App is blocked",
            subtitle: subtitle,
            primaryButton: hasFriendRequest ? "Request 15m" : "Open ScreenLog",
            secondaryButton: "Open ScreenLog"
        )
    }

    private static func activeShieldedGroupIDs() -> Set<String> {
        Set(defaults?.stringArray(forKey: activeGroupIDsKey) ?? [])
    }

    private static func applyShields(for groupIDs: Set<String>, state: BlockingState) {
        let suppressedGroupIDs = BlockingStateResolver.suppressedGroupIDs(in: state)
        let selections = state.groups
            .filter { groupIDs.contains($0.id) && $0.isEnabled && !suppressedGroupIDs.contains($0.id) }
            .compactMap { decodeSelection($0.selectionData) }

        let applications = selections.reduce(into: Set<ApplicationToken>()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }
        let categories = selections.reduce(into: Set<ActivityCategoryToken>()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }
        let webDomains = selections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }

        managedStore.shield.applications = applications.isEmpty ? nil : applications
        managedStore.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        managedStore.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        managedStore.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
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
}
