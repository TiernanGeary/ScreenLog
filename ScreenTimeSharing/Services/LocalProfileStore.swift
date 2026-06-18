import Foundation
import Security

/// Local cache of the user's profile. The canonical identity is the Supabase
/// auth user UUID (derived from Sign in with Apple), so this store no longer
/// manages identity recovery — it only persists the last known profile for
/// instant launch and offline display.
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

    /// Debug-only: wipes all local identity state for a clean slate — the stored
    /// profile and the Apple sign-in credential, so onboarding restarts.
    func clearAll() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: randomFallbackColorKey)
        KeychainAppleID.delete()
    }
}
