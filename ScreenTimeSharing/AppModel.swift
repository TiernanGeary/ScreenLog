import CloudKit
import FamilyControls
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile
    @Published var selection: FamilyActivitySelection
    @Published var localSnapshot: DailyUsageSnapshot?
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var cloudAvailability: CloudAvailability = .checking
    @Published var screenTimeAuthorization = "Not requested"
    @Published var message: String?
    @Published var isWorking = false
    @Published var hasCompletedOnboarding: Bool

    let snapshotStore: CloudKitUsageSnapshotStore

    private let profileStore: LocalProfileStore
    private let selectionStore: FamilyActivitySelectionStore
    private let screenTimeProvider: ScreenTimeProvider
    private let widgetCacheWriter: AppGroupWidgetCacheWriter
    private let onboardingKey = "HasCompletedOnboarding.v1"
    #if DEBUG
    private let demoFriendsKey = "UsesDemoFriends.v1"
    #endif

    init(
        profileStore: LocalProfileStore = LocalProfileStore(),
        selectionStore: FamilyActivitySelectionStore = FamilyActivitySelectionStore(),
        screenTimeProvider: ScreenTimeProvider = DeviceActivityScreenTimeProvider(),
        snapshotStore: CloudKitUsageSnapshotStore = CloudKitUsageSnapshotStore(),
        widgetCacheWriter: AppGroupWidgetCacheWriter = AppGroupWidgetCacheWriter()
    ) {
        self.profileStore = profileStore
        self.selectionStore = selectionStore
        self.screenTimeProvider = screenTimeProvider
        self.snapshotStore = snapshotStore
        self.widgetCacheWriter = widgetCacheWriter
        self.profile = profileStore.load()
        self.selection = selectionStore.load()
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        self.screenTimeAuthorization = screenTimeProvider.authorizationLabel()
    }

    var selectedActivityCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    func load() async {
        screenTimeAuthorization = screenTimeProvider.authorizationLabel()
        cloudAvailability = await snapshotStore.cloudAvailability()
        await reloadFriends()
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
            try widgetCacheWriter.write(friends)
        } catch {
            message = "Could not refresh friends: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    func seedDemoFriends() {
        let friends = makeDemoFriends(now: Date())
        friendSummaries = friends
        UserDefaults.standard.set(true, forKey: demoFriendsKey)

        do {
            try widgetCacheWriter.write(friends)
            message = "Demo friends added for simulator testing."
        } catch {
            message = "Could not write demo widget cache: \(error.localizedDescription)"
        }
    }

    func clearDemoFriends() {
        friendSummaries = []
        UserDefaults.standard.set(false, forKey: demoFriendsKey)

        do {
            try widgetCacheWriter.write([])
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
    #endif
}
