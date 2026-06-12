import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct AppleCredential {
    let userID: String
    let fullName: PersonNameComponents?
    let email: String?
    /// Apple-issued identity token (JWT) exchanged with Supabase Auth.
    let identityToken: String
    /// The raw nonce whose SHA-256 was embedded in the token request; Supabase
    /// verifies it against the token's nonce claim.
    let rawNonce: String
}

@MainActor
final class AppleSignInService: NSObject {
    private var continuation: CheckedContinuation<AppleCredential, any Error>?
    private var pendingRawNonce: String?

    func signIn() async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256Hex(configureNonce())

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }

    /// Prepares a SwiftUI `SignInWithAppleButton` request so its credential can
    /// be exchanged with Supabase. Returns nothing; the raw nonce is kept
    /// internally and consumed by `credential(from:)`.
    func configure(request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256Hex(configureNonce())
    }

    /// Builds an `AppleCredential` from a SwiftUI `SignInWithAppleButton`
    /// completion, pairing it with the nonce minted in `configure(request:)`.
    func credential(from authorization: ASAuthorization) throws -> AppleCredential {
        guard let rawNonce = pendingRawNonce else {
            throw AppleSignInError.invalidCredential
        }
        pendingRawNonce = nil
        return try Self.makeCredential(from: authorization, rawNonce: rawNonce)
    }

    private func configureNonce() -> String {
        let nonce = Self.randomNonce()
        pendingRawNonce = nonce
        return nonce
    }

    private static func makeCredential(
        from authorization: ASAuthorization,
        rawNonce: String
    ) throws -> AppleCredential {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else {
            throw AppleSignInError.invalidCredential
        }

        KeychainAppleID.save(credential.user)

        return AppleCredential(
            userID: credential.user,
            fullName: credential.fullName,
            email: credential.email,
            identityToken: token,
            rawNonce: rawNonce
        )
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func checkExistingCredential() async -> String? {
        guard let storedUserID = KeychainAppleID.load() else {
            return nil
        }

        let state = await credentialState(for: storedUserID)
        guard state == .authorized else {
            return nil
        }

        return storedUserID
    }

    private func credentialState(for userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            guard let rawNonce = pendingRawNonce else {
                continuation?.resume(throwing: AppleSignInError.invalidCredential)
                continuation = nil
                return
            }
            pendingRawNonce = nil
            do {
                let result = try Self.makeCredential(from: authorization, rawNonce: rawNonce)
                continuation?.resume(returning: result)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

enum AppleSignInError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Could not read Apple ID credential."
        }
    }
}

enum KeychainAppleID {
    private static let service = "com.jdco.deny.apple-id"
    private static let account = "apple-user-id"

    @discardableResult
    static func save(_ userID: String) -> Bool {
        let data = Data(userID.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
