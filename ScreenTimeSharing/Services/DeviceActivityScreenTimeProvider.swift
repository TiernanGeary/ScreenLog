import FamilyControls
import Foundation

@MainActor
final class DeviceActivityScreenTimeProvider: ScreenTimeProvider {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func authorizationLabel() -> String {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        case .approved:
            return "Approved"
        @unknown default:
            return "Unknown"
        }
    }

    func loadTodayUsage(selection: FamilyActivitySelection, profile: UserProfile) async -> DailyUsageSnapshot {
        let now = Date()
        let interval = UsageDateBoundary.dayInterval(containing: now, calendar: calendar)
        let snapshotID = UsageDateBoundary.snapshotID(profileID: profile.id, date: now, calendar: calendar)

        guard selection.hasSelectedActivities else {
            return unavailableSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now,
                reason: "Choose at least one app, category, or website before sharing."
            )
        }

        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined:
            return unavailableSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now,
                reason: "Screen Time authorization has not been requested."
            )
        case .denied:
            return unavailableSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now,
                reason: "Screen Time authorization was denied."
            )
        case .approved:
            return unavailableSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now,
                reason: "Screen Time usage export requires a Device Activity report extension on a real device. The app will not upload placeholder data."
            )
        @unknown default:
            return unavailableSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now,
                reason: "Screen Time authorization is in an unknown state."
            )
        }
    }

    private func unavailableSnapshot(
        id: String,
        profile: UserProfile,
        date: Date,
        now: Date,
        reason: String
    ) -> DailyUsageSnapshot {
        DailyUsageSnapshot(
            id: id,
            ownerProfileID: profile.id,
            date: date,
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            totalDuration: nil,
            selectedAppDuration: nil,
            appRows: [],
            lastUpdated: now,
            capability: .unavailable(reason: reason)
        )
    }
}

private extension FamilyActivitySelection {
    var hasSelectedActivities: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }
}
