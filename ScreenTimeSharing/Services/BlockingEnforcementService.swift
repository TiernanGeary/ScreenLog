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

    func syncMonitoring(for state: BlockingState) throws {
        let now = Date()
        let signature = enforcementSignature(for: state, now: now)

        if defaults?.string(forKey: BlockingStoreCodec.blockingEnforcementSignatureKey) == signature {
            saveShieldIndex(activeGroupIDs: currentActiveGroupIDs(for: state, now: now), state: state)
            return
        }

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

        for session in BlockingStateResolver.activeUnblockSessions(in: state, now: now) {
            try startUnblockExpirationMonitor(for: session, now: now)
        }

        defaults?.set(signature, forKey: BlockingStoreCodec.blockingEnforcementSignatureKey)
        defaults?.synchronize()
    }

    func applyShields(for groupIDs: Set<String>, in state: BlockingState) {
        let suppressedGroupIDs = BlockingStateResolver.suppressedGroupIDs(in: state)
        let selections = state.groups
            .filter { groupIDs.contains($0.id) && $0.isEnabled && !suppressedGroupIDs.contains($0.id) }
            .compactMap { try? BlockingSelectionCodec.decode($0.selectionData) }

        applyShields(
            for: selections,
            exempting: activeUnblockSelections(in: state)
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
        // DeviceActivity schedules operate at MINUTE resolution. Including the
        // seconds component produced a malformed interval whose intervalDidEnd
        // never fired, so timed unblocks never re-blocked. Build the interval at
        // minute granularity, starting a minute in the past so the system treats
        // it as already-running and only needs to deliver the end callback.
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: -1, to: now) ?? now
        let schedule = DeviceActivitySchedule(
            intervalStart: minuteAlignedComponents(for: start),
            intervalEnd: minuteAlignedComponents(for: session.expiresAt),
            repeats: false
        )

        try center.startMonitoring(activityName, during: schedule)
    }

    private func applyShields(
        for selections: [FamilyActivitySelection],
        exempting exemptSelections: [FamilyActivitySelection]
    ) {
        let exemptApplications = exemptSelections.reduce(into: Set<ApplicationToken>()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }
        let exemptCategories = exemptSelections.reduce(into: Set<ActivityCategoryToken>()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }
        let exemptWebDomains = exemptSelections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }
        let applications = selections.reduce(into: Set<ApplicationToken>()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }.subtracting(exemptApplications)
        let categories = selections.reduce(into: Set<ActivityCategoryToken>()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }.subtracting(exemptCategories)
        let webDomains = selections.reduce(into: Set<WebDomainToken>()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }.subtracting(exemptWebDomains)

        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories, except: exemptApplications)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories, except: exemptWebDomains)
    }

    private func activeUnblockSelections(
        in state: BlockingState,
        now: Date = Date()
    ) -> [FamilyActivitySelection] {
        BlockingStateResolver.activeUnblockSessions(in: state, now: now).compactMap { session in
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
        let suppressedGroupIDs = BlockingStateResolver.suppressedGroupIDs(in: state, now: now)
        return activeGroupIDs.intersection(enabledGroupIDs).subtracting(suppressedGroupIDs)
    }

    private func enforcementSignature(for state: BlockingState, now: Date) -> String {
        let groupSignature = state.groups
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

        let activeUnblockSignature = state.unblockSessions
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

        return [groupSignature, activeUnblockSignature].joined(separator: "||")
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

    private func minuteAlignedComponents(for date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
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
