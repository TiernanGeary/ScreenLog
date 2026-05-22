import Foundation

final class LocalProfileStore {
    private let defaults: UserDefaults
    private let key = "LocalUserProfile.v1"
    private let randomFallbackColorKey = "LocalUserProfile.RandomFallbackColor.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UserProfile {
        if let data = defaults.data(forKey: key),
           var profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            if !defaults.bool(forKey: randomFallbackColorKey) {
                profile.avatarColorHex = AppConfiguration.randomAvatarColorHex()
                profile.updatedAt = Date()
                save(profile)
                defaults.set(true, forKey: randomFallbackColorKey)
            }
            return profile
        }

        let profile = UserProfile(
            id: UUID().uuidString,
            displayName: "Me",
            avatarColorHex: AppConfiguration.randomAvatarColorHex(),
            shareStatus: .notShared,
            updatedAt: Date()
        )
        save(profile)
        defaults.set(true, forKey: randomFallbackColorKey)
        return profile
    }

    func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
