import Foundation

final class LocalProfileStore {
    private let defaults: UserDefaults
    private let key = "LocalUserProfile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserProfile {
        if let data = defaults.data(forKey: key),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            return profile
        }

        let profile = UserProfile(
            id: UUID().uuidString,
            displayName: "Me",
            avatarColorHex: AppConfiguration.defaultAvatarColor,
            shareStatus: .notShared,
            updatedAt: Date()
        )
        save(profile)
        return profile
    }

    func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
