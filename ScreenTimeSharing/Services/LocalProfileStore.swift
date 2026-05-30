import Foundation
import Security

final class LocalProfileStore {
    private let defaults: UserDefaults
    private let key = "LocalUserProfile.v1"
    private let randomFallbackColorKey = "LocalUserProfile.RandomFallbackColor.v1"
    private static let mappingKeychainService = "com.jdco.deny.apple-profile-mapping"

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

    func load(appleUserID: String) -> UserProfile {
        if let existingProfileID = profileID(forAppleUserID: appleUserID),
           let data = defaults.data(forKey: key),
           var profile = try? JSONDecoder().decode(UserProfile.self, from: data),
           profile.id == existingProfileID {
            return stampingAppleUserID(appleUserID, on: &profile)
        }

        if let data = defaults.data(forKey: key),
           var profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            linkAppleUserID(appleUserID, toProfileID: profile.id)
            return stampingAppleUserID(appleUserID, on: &profile)
        }

        var profile = UserProfile(
            id: UUID().uuidString,
            displayName: "Me",
            avatarColorHex: AppConfiguration.randomAvatarColorHex(),
            shareStatus: .notShared,
            updatedAt: Date(),
            appleUserID: appleUserID
        )
        save(profile)
        linkAppleUserID(appleUserID, toProfileID: profile.id)
        defaults.set(true, forKey: randomFallbackColorKey)
        return profile
    }

    func restoreProfile(_ profile: UserProfile, appleUserID: String) {
        var restored = profile
        restored.appleUserID = appleUserID
        save(restored)
        linkAppleUserID(appleUserID, toProfileID: restored.id)
        defaults.set(true, forKey: randomFallbackColorKey)
    }

    /// Ensures the locally stored profile carries the Apple identifier so it is
    /// published to CloudKit and can be recovered on reinstall. Persists only
    /// when the value was missing or changed.
    private func stampingAppleUserID(_ appleUserID: String, on profile: inout UserProfile) -> UserProfile {
        guard profile.appleUserID != appleUserID else {
            return profile
        }

        profile.appleUserID = appleUserID
        profile.updatedAt = Date()
        save(profile)
        return profile
    }

    func profileID(forAppleUserID appleUserID: String) -> String? {
        loadMapping()[appleUserID]
    }

    func linkedAppleUserID() -> String? {
        guard let data = defaults.data(forKey: key),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }

        return loadMapping().first { $0.value == profile.id }?.key
    }

    func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func linkAppleUserID(_ appleUserID: String, toProfileID profileID: String) {
        var mapping = loadMapping()
        mapping[appleUserID] = profileID
        saveMapping(mapping)
    }

    private func loadMapping() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.mappingKeychainService,
            kSecAttrAccount as String: "mapping",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return mapping
    }

    private func saveMapping(_ mapping: [String: String]) {
        guard let data = try? JSONEncoder().encode(mapping) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.mappingKeychainService,
            kSecAttrAccount as String: "mapping"
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
