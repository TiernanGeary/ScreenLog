import Foundation
import Security

enum GroupBlockPasswordStore {
    private static func key(_ groupID: String) -> String { "group-block.\(groupID)" }

    @discardableResult
    static func save(_ password: String, groupID: String) -> Bool {
        delete(groupID: groupID)
        guard let data = password.data(using: .utf8) else { return false }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(groupID),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status != errSecSuccess else { return true }

        delete(groupID: groupID)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func load(groupID: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(groupID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(groupID: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key(groupID)
        ]
        SecItemDelete(q as CFDictionary)
    }
}
