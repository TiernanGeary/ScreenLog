import FamilyControls
import Foundation

@MainActor
final class DeviceActivityScreenTimeProvider: ScreenTimeProvider {
    private let calendar: Calendar
    private let reportDefaults: UserDefaults?

    init(
        calendar: Calendar = .current,
        reportDefaults: UserDefaults? = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier)
    ) {
        self.calendar = calendar
        self.reportDefaults = reportDefaults
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func authorizationLabel() -> String {
        let status = AuthorizationCenter.shared.authorizationStatus
        if isApprovedStatus(status) {
            return status.rawValue == 3 ? "Approved with data access" : "Approved"
        }

        switch status {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        case .approved:
            return "Approved"
        @unknown default:
            return unknownAuthorizationLabel(status)
        }
    }

    func loadTodayUsage(selection: FamilyActivitySelection, profile: UserProfile) async -> DailyUsageSnapshot {
        let now = Date()
        let interval = UsageDateBoundary.dayInterval(containing: now, calendar: calendar)
        let snapshotID = UsageDateBoundary.snapshotID(profileID: profile.id, date: now, calendar: calendar)

        let status = AuthorizationCenter.shared.authorizationStatus
        if isApprovedStatus(status) {
            return reportBackedSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now
            )
        }

        switch status {
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
            return reportBackedSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now
            )
        @unknown default:
            return unavailableSnapshot(
                id: snapshotID,
                profile: profile,
                date: interval.start,
                now: now,
                reason: "Screen Time authorization is \(unknownAuthorizationLabel(status))."
            )
        }
    }

    private func isApprovedStatus(_ status: AuthorizationStatus) -> Bool {
        status == .approved || status.rawValue == 3
    }

    private func reportBackedSnapshot(
        id: String,
        profile: UserProfile,
        date: Date,
        now: Date
    ) -> DailyUsageSnapshot {
        if let snapshot = ScreenTimeReportStorage.latestSnapshot(
            for: profile.id,
            on: now,
            defaults: reportDefaults,
            calendar: calendar
        ) {
            return snapshot
        }

        return unavailableSnapshot(
            id: id,
            profile: profile,
            date: date,
            now: now,
            reason: "Live Screen Time reports are shown on Home and Stats."
        )
    }

    private func unknownAuthorizationLabel(_ status: AuthorizationStatus) -> String {
        "Unknown (raw \(status.rawValue), \(status.description))"
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
