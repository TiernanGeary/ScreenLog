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

    init(
        center: DeviceActivityCenter = DeviceActivityCenter(),
        store: ManagedSettingsStore = ManagedSettingsStore(named: Self.storeName)
    ) {
        self.center = center
        self.store = store
    }

    func syncMonitoring(for state: BlockingState) throws {
        center.stopMonitoring()

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
    }

    func applyShields(for groupIDs: Set<String>, in state: BlockingState) {
        let suppressedGroupIDs = BlockingStateResolver.suppressedGroupIDs(in: state)
        let selections = state.groups
            .filter { groupIDs.contains($0.id) && $0.isEnabled && !suppressedGroupIDs.contains($0.id) }
            .compactMap { try? BlockingSelectionCodec.decode($0.selectionData) }

        applyShields(for: selections)
    }

    func clearShields() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
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

    private func applyShields(for selections: [FamilyActivitySelection]) {
        let applications = selections.reduce(into: Set()) { partial, selection in
            partial.formUnion(selection.applicationTokens)
        }
        let categories = selections.reduce(into: Set()) { partial, selection in
            partial.formUnion(selection.categoryTokens)
        }
        let webDomains = selections.reduce(into: Set()) { partial, selection in
            partial.formUnion(selection.webDomainTokens)
        }

        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
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
