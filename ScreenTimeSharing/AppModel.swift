import CloudKit
import FamilyControls
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var profile: UserProfile
    @Published var selection: FamilyActivitySelection
    @Published var localSnapshot: DailyUsageSnapshot?
    @Published var friendSummaries: [FriendUsageSummary] = []
    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var leaderboardWindow: LeaderboardWindow = .week
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
            leaderboardEntries = []
            try widgetCacheWriter.write(friends: friends, leaderboardEntries: leaderboardEntries)
        } catch {
            message = "Could not refresh friends: \(error.localizedDescription)"
        }
    }

    func setLeaderboardWindow(_ window: LeaderboardWindow) {
        leaderboardWindow = window

        #if DEBUG
        if UserDefaults.standard.bool(forKey: demoFriendsKey) {
            seedDemoFriends()
        }
        #endif
    }

    #if DEBUG
    func seedDemoFriends() {
        let now = Date()
        let friends = makeDemoFriends(now: now)
        let demo = makeDemoLeaderboard(now: now)
        friendSummaries = friends
        leaderboardEntries = demo.entries
        UserDefaults.standard.set(true, forKey: demoFriendsKey)

        do {
            try widgetCacheWriter.write(friends: friends, leaderboardEntries: leaderboardEntries)
            message = "Demo friends added for simulator testing."
        } catch {
            message = "Could not write demo widget cache: \(error.localizedDescription)"
        }
    }

    func clearDemoFriends() {
        friendSummaries = []
        leaderboardEntries = []
        UserDefaults.standard.set(false, forKey: demoFriendsKey)

        do {
            try widgetCacheWriter.write(friends: [], leaderboardEntries: [])
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

    private func makeDemoLeaderboard(now: Date) -> (participants: [AccountabilityParticipant], events: [AccountabilityEvent], entries: [LeaderboardEntry]) {
        let me = AccountabilityParticipant(
            id: profile.id,
            displayName: profile.displayName == "Me" ? "You" : profile.displayName,
            avatarColorHex: profile.avatarColorHex
        )
        let participants = [
            AccountabilityParticipant(id: "demo-maya", displayName: "Maya Chen", avatarColorHex: "#E84855"),
            AccountabilityParticipant(id: "demo-sam", displayName: "Sam Lee", avatarColorHex: "#1B998B"),
            me,
            AccountabilityParticipant(id: "demo-riley", displayName: "Riley Park", avatarColorHex: "#F18F01")
        ]
        let events = demoAccountabilityEvents(now: now, meID: profile.id)
        let entries = LeaderboardBuilder.entries(
            participants: participants,
            events: events,
            window: leaderboardWindow,
            now: now
        )
        return (participants, events, entries)
    }

    private func demoAccountabilityEvents(now: Date, meID: String) -> [AccountabilityEvent] {
        var events: [AccountabilityEvent] = [
            AccountabilityEvent(
                id: "sam-request-1",
                userID: "demo-sam",
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-45 * 60),
                seconds: 10 * 60,
                requestID: "sam-req-1"
            ),
            AccountabilityEvent(
                id: "sam-approved-1",
                userID: "demo-sam",
                kind: .extraTimeApproved,
                occurredAt: now.addingTimeInterval(-40 * 60),
                seconds: 10 * 60,
                requestID: "sam-req-1",
                actorUserID: "demo-maya"
            ),
            AccountabilityEvent(
                id: "me-request-1",
                userID: meID,
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-80 * 60),
                seconds: 15 * 60,
                requestID: "me-req-1"
            ),
            AccountabilityEvent(
                id: "me-request-2",
                userID: meID,
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-20 * 60),
                seconds: 30 * 60,
                requestID: "me-req-2"
            ),
            AccountabilityEvent(
                id: "me-approved-1",
                userID: meID,
                kind: .extraTimeApproved,
                occurredAt: now.addingTimeInterval(-74 * 60),
                seconds: 15 * 60,
                requestID: "me-req-1",
                actorUserID: "demo-sam"
            ),
            AccountabilityEvent(
                id: "me-denied-2",
                userID: meID,
                kind: .extraTimeDenied,
                occurredAt: now.addingTimeInterval(-16 * 60),
                requestID: "me-req-2",
                actorUserID: "demo-maya"
            ),
            AccountabilityEvent(
                id: "riley-request-1",
                userID: "demo-riley",
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-130 * 60),
                seconds: 45 * 60,
                requestID: "riley-req-1"
            ),
            AccountabilityEvent(
                id: "riley-request-2",
                userID: "demo-riley",
                kind: .extraTimeRequested,
                occurredAt: now.addingTimeInterval(-2 * 3_600),
                seconds: 35 * 60,
                requestID: "riley-req-2"
            ),
            AccountabilityEvent(
                id: "riley-emergency-1",
                userID: "demo-riley",
                kind: .emergencyUnlockUsed,
                occurredAt: now.addingTimeInterval(-90 * 60)
            )
        ]

        let streaks: [(String, Int)] = [
            ("demo-maya", 5),
            ("demo-sam", 3),
            (meID, 1)
        ]

        for (userID, dayCount) in streaks {
            for offset in 0..<dayCount {
                if let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) {
                    events.append(
                        AccountabilityEvent(
                            id: "\(userID)-streak-\(offset)",
                            userID: userID,
                            kind: .underLimitDayCompleted,
                            occurredAt: date
                        )
                    )
                }
            }
        }

        return events
    }
    #endif
}
