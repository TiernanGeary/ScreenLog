import FamilyControls
import Foundation

@MainActor
protocol ScreenTimeProvider {
    func requestAuthorization() async throws
    func authorizationLabel() -> String
    func loadTodayUsage(selection: FamilyActivitySelection, profile: UserProfile) async -> DailyUsageSnapshot
}
