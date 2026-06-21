import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

struct BlockingEnforcementService {
    static var storeName: ManagedSettingsStore.Name {
        ManagedSettingsStore.Name("screenlog.blocking")
    }

    private let center: DeviceActivityCenter
    private let store: ManagedSettingsStore
    private let defaults: UserDefaults?

    init(
        center: DeviceActivityCenter = DeviceActivityCenter(),
        store: ManagedSettingsStore = ManagedSettingsStore(named: Self.storeName),
        defaults: UserDefaults? = UserDefaults(suiteName: BlockingStoreCodec.suiteName)
    ) {
        self.center = center
        self.store = store
        self.defaults = defaults
    }

    private static let unblockSignatureKey = "BlockingEnforcementUnblockSignature.v1"

    func syncMonitoring(for state: BlockingState) throws {
        let now = Date()
        let blockSig = blockSignature(for: state)
        let unblockSig = unblockSignature(for: state, now: now)
        let blockChanged = defaults?.string(forKey: BlockingStoreCodec.blockingEnforcementSignatureKey) != blockSig
        let unblockChanged = defaults?.string(forKey: Self.unblockSignatureKey) != unblockSig

        if !blockChanged && !unblockChanged {
            saveShieldIndex(activeGroupIDs: currentActiveGroupIDs(for: state, now: now), state: state)
            return
        }

        if blockChanged {
            // Block configuration changed: re-register every block monitor. This
            // is the churny path, now gated so it does NOT run when only an
            // unblock session was added/expired — which was thrashing the
            // scheduled-block monitors and toggling their shields off.
            center.stopMonitoring()
            reconcileActiveShields(for: state, now: now)

            for group in BlockingStateResolver.enabledGroups(in: state) {
                guard let selection = try? BlockingSelectionCodec.decode(group.selectionData),
                      !selection.isEmpty else {
                    continue
                }

                switch group.mode {
                case .timeLimit(let seconds, let days):
                    try startTimeLimit(group: group, selection: selection, seconds: seconds, days: days)
                case .scheduled(let startMinute, let endMinute, let days):
                    try startScheduledWindows(group: group, days: days, startMinute: startMinute, endMinute: endMinute)
                }
            }
            defaults?.set(blockSig, forKey: BlockingStoreCodec.blockingEnforcementSignatureKey)
        } else {
            // Only unblock state changed: leave the block monitors untouched and
            // just re-apply shields to reflect current exemptions.
            applyShields(for: currentActiveGroupIDs(for: state, now: now), in: state)
        }

        // (Re)register monitors for active unblock sessions either way.
        for session in BlockingStateResolver.activeUnblockSessions(in: state, now: now) {
            try? startUnblockExpirationMonitor(for: session, now: now)
        }

        defaults?.set(unblockSig, forKey: Self.unblockSignatureKey)
        defaults?.synchronize()
    }

    func applyShields(for groupIDs: Set<String>, in state: BlockingState) {
        let now = Date()
        let forcedGroupIDs = forcedPoolExhaustionGroupIDs(in: state, now: now)
        let suppressedGroupIDs = BlockingStateResolver.suppressedGroupIDs(in: state, now: now)
            .subtracting(forcedGroupIDs)
        let shieldedGroupIDs = groupIDs.union(forcedGroupIDs)
        let selections = state.groups
            .filter { shieldedGroupIDs.contains($0.id) && $0.isEnabled && !suppressedGroupIDs.contains($0.id) }
            .compactMap { try? BlockingSelectionCodec.decode($0.selectionData) }
        let forcedSelections = state.groups
            .filter { forcedGroupIDs.contains($0.id) && $0.isEnabled }
            .compactMap { try? BlockingSelectionCodec.decode($0.selectionData) }

        applyShields(
            for: selections,
            exempting: activeUnblockSelections(in: state, excluding: forcedGroupIDs, now: now),
            forcing: forcedSelections
        )
    }

    private func reconcileActiveShields(for state: BlockingState, now: Date = Date()) {
        let enabledGroupIDs = Set(BlockingStateResolver.enabledGroups(in: state).map(\.id))
        let activeGroupIDs = Set(defaults?.stringArray(forKey: BlockingStoreCodec.activeShieldedGroupIDsKey) ?? [])
        let validActiveGroupIDs = activeGroupIDs.intersection(enabledGroupIDs)

        defaults?.set(Array(validActiveGroupIDs), forKey: BlockingStoreCodec.activeShieldedGroupIDsKey)
        saveShieldIndex(activeGroupIDs: validActiveGroupIDs, state: state)
        applyShields(for: validActiveGroupIDs, in: state)
    }

    func clearShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        defaults?.removeObject(forKey: BlockingStoreCodec.blockingEnforcementSignatureKey)
    }

    private func startTimeLimit(
        group: BlockGroup,
        selection: FamilyActivitySelection,
        seconds: TimeInterval,
        days: [BlockWeekday]
    ) throws {
        let eventName = DeviceActivityEvent.Name(
            BlockingMonitorNameBuilder.timeLimitEventName(groupID: group.id)
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: thresholdComponents(seconds: seconds)
        )

        for day in BlockRuleKind.normalizedDays(days) {
            let activityName = DeviceActivityName(
                BlockingMonitorNameBuilder.timeLimitActivityName(groupID: group.id, weekday: day)
            )
            let schedule = DeviceActivitySchedule(
                intervalStart: dateComponents(for: day, minuteOfDay: 0),
                intervalEnd: dateComponents(for: day, minuteOfDay: 23 * 60 + 59),
                repeats: true
            )

            try center.startMonitoring(activityName, during: schedule, events: [eventName: event])
        }
    }

    private func startScheduledWindows(
        group: BlockGroup,
        days: [BlockWeekday],
        startMinute: Int,
        endMinute: Int
    ) throws {
        for day in BlockRuleKind.normalizedDays(days) {
            let activityName = DeviceActivityName(
                BlockingMonitorNameBuilder.scheduledActivityName(groupID: group.id, weekday: day)
            )
            let schedule = DeviceActivitySchedule(
                intervalStart: dateComponents(for: day, minuteOfDay: startMinute),
                intervalEnd: dateComponents(
                    for: endDay(for: day, startMinute: startMinute, endMinute: endMinute),
                    minuteOfDay: endMinute
                ),
                repeats: true
            )

            try center.startMonitoring(activityName, during: schedule)
        }
    }

    private func startUnblockExpirationMonitor(
        for session: BlockUnblockSession,
        now: Date
    ) throws {
        guard session.expiresAt > now else {
            return
        }

        let activityName = DeviceActivityName(
            BlockingMonitorNameBuilder.unblockActivityName(sessionID: session.id)
        )
        // DeviceActivity enforces a 15-minute minimum interval (intervalTooShort)
        // and its intervalDidStart/intervalDidEnd callbacks are unreliable for
        // short non-repeating windows. The supported way to get a sub-15-minute
        // callback is warningTime + intervalWillEndWarning: schedule an interval
        // that ends a fixed 15 minutes AFTER the unblock expiry, with a flat
        // 15-minute warning, so intervalWillEndWarning lands exactly at expiry.
        //
        // Precision lives in intervalEnd's seconds (not in warningTime): pinning
        // intervalEnd to expiresAt + 15m and warningTime to a round 15m makes the
        // warning fire at the true expiry instant instead of snapping to the next
        // clock minute, so the re-block matches the visible countdown.
        let warningInterval: TimeInterval = 15 * 60
        let intervalEnd = session.expiresAt.addingTimeInterval(warningInterval)

        let schedule = DeviceActivitySchedule(
            intervalStart: secondAlignedComponents(for: now),
            intervalEnd: secondAlignedComponents(for: intervalEnd),
            repeats: false,
            warningTime: DateComponents(minute: 15)
        )

        try center.startMonitoring(activityName, during: schedule)
    }

    private func applyShields(
        for selections: [FamilyActivitySelection],
        exempting exemptSelections: [FamilyActivitySelection],
        forcing forcedSelections: [FamilyActivitySelection] = []
    ) {
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
        let nonForcedCategories = categories.subtracting(forcedCategories)
        let webDomains = selections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }.subtracting(exemptWebDomains)

        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty ? nil : nonForcedCategories.isEmpty ? .specific(categories) : .specific(categories, except: exemptApplications)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty ? nil : nonForcedCategories.isEmpty ? .specific(categories) : .specific(categories, except: exemptWebDomains)
    }

    private func activeUnblockSelections(
        in state: BlockingState,
        excluding excludedGroupIDs: Set<String> = [],
        now: Date = Date()
    ) -> [FamilyActivitySelection] {
        BlockingStateResolver.activeUnblockSessions(in: state, now: now).compactMap { session in
            guard !excludedGroupIDs.contains(session.groupID) else {
                return nil
            }

            if let selectionData = session.selectionData,
               let selection = try? BlockingSelectionCodec.decode(selectionData) {
                return selection
            }

            guard let group = BlockingStateResolver.group(for: session.groupID, in: state) else {
                return nil
            }

            return try? BlockingSelectionCodec.decode(group.selectionData)
        }
    }

    private func saveShieldIndex(activeGroupIDs: Set<String>, state: BlockingState) {
        BlockingShieldIndexStore(defaults: defaults).save(
            BlockingShieldIndex(state: state, activeGroupIDs: activeGroupIDs)
        )
    }

    private func currentActiveGroupIDs(for state: BlockingState, now: Date) -> Set<String> {
        let enabledGroupIDs = Set(BlockingStateResolver.enabledGroups(in: state).map(\.id))
        let activeGroupIDs = Set(defaults?.stringArray(forKey: BlockingStoreCodec.activeShieldedGroupIDsKey) ?? [])
        let forcedGroupIDs = forcedPoolExhaustionGroupIDs(in: state, now: now)
        let suppressedGroupIDs = BlockingStateResolver.suppressedGroupIDs(in: state, now: now)
            .subtracting(forcedGroupIDs)
        return activeGroupIDs
            .union(forcedGroupIDs)
            .intersection(enabledGroupIDs)
            .subtracting(suppressedGroupIDs)
    }

    private func forcedPoolExhaustionGroupIDs(in state: BlockingState, now: Date = Date()) -> Set<String> {
        let groupIDs = Set(state.groups.map(\.id))
        return Set(
            state.poolExhaustionOverrides
                .filter { $0.isActive(now: now) && groupIDs.contains($0.groupID) }
                .map(\.groupID)
        )
    }

    private func blockSignature(for state: BlockingState) -> String {
        state.groups
            .sorted { $0.id < $1.id }
            .map { group in
                [
                    group.id,
                    group.isEnabled ? "1" : "0",
                    modeSignature(group.mode),
                    group.selectionData.base64EncodedString()
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private func unblockSignature(for state: BlockingState, now: Date) -> String {
        let sessionSignature = state.unblockSessions
            .filter { $0.isActive(now: now) }
            .sorted { $0.id < $1.id }
            .map { session in
                [
                    session.id,
                    session.groupID,
                    String(Int(session.durationSeconds.rounded())),
                    String(format: "%.3f", session.startedAt.timeIntervalSinceReferenceDate),
                    String(format: "%.3f", session.expiresAt.timeIntervalSinceReferenceDate)
                ].joined(separator: ":")
            }
            .joined(separator: "|")
        let overrideSignature = state.poolExhaustionOverrides
            .filter { $0.isActive(now: now) }
            .sorted { $0.groupID < $1.groupID }
            .map { override in
                [
                    override.groupID,
                    String(format: "%.3f", override.exhaustedAt.timeIntervalSinceReferenceDate),
                    String(format: "%.3f", override.resetsAt.timeIntervalSinceReferenceDate)
                ].joined(separator: ":")
            }
            .joined(separator: "|")

        return [sessionSignature, overrideSignature].joined(separator: "#")
    }

    private func modeSignature(_ mode: BlockGroupMode) -> String {
        switch mode {
        case .timeLimit(let seconds, let days):
            return "timeLimit:\(Int(seconds.rounded())):\(daySignature(days))"
        case .scheduled(let startMinute, let endMinute, let days):
            return "scheduled:\(startMinute):\(endMinute):\(daySignature(days))"
        }
    }

    private func daySignature(_ days: [BlockWeekday]) -> String {
        BlockRuleKind.normalizedDays(days)
            .map { String($0.rawValue) }
            .joined(separator: ",")
    }

    private func thresholdComponents(seconds: TimeInterval) -> DateComponents {
        let wholeSeconds = max(60, Int(seconds.rounded(.up)))
        return DateComponents(
            hour: wholeSeconds / 3_600,
            minute: (wholeSeconds % 3_600) / 60,
            second: wholeSeconds % 60
        )
    }

    private func dateComponents(for weekday: BlockWeekday, minuteOfDay: Int) -> DateComponents {
        DateComponents(
            hour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            weekday: weekday.rawValue
        )
    }

    private func secondAlignedComponents(for date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }

    private func endDay(
        for startDay: BlockWeekday,
        startMinute: Int,
        endMinute: Int
    ) -> BlockWeekday {
        guard endMinute <= startMinute else {
            return startDay
        }

        let allDays = BlockWeekday.allCases.sorted()
        guard let index = allDays.firstIndex(of: startDay) else {
            return startDay
        }

        return allDays[(index + 1) % allDays.count]
    }
}

extension FamilyActivitySelection {
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
