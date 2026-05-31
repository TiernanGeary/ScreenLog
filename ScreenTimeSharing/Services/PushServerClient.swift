import Foundation

/// Talks to the deny push server (Cloudflare Worker) so friend-request events
/// reach the recipient as real APNs alert pushes — delivered even when the app
/// is force-quit, which silent CloudKit pushes cannot guarantee.
struct PushServerClient {
    enum PushEnvironment: String {
        case production
        case sandbox
    }

    /// The APNs environment the running build uses: TestFlight/App Store builds
    /// are production; debug builds attach to the sandbox gateway.
    static var currentEnvironment: PushEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }

    /// Registers this device's APNs token against the user's profile ID so the
    /// server can target pushes to them.
    func register(profileID: String, deviceToken: String) async {
        guard AppConfiguration.isPushServerConfigured else {
            return
        }

        await post(
            path: "/register",
            payload: [
                "profileID": profileID,
                "token": deviceToken,
                "environment": Self.currentEnvironment.rawValue
            ]
        )
    }

    /// Asks the server to send an alert push to another user.
    func notify(toProfileID: String, title: String, body: String, requestID: String? = nil) async {
        guard AppConfiguration.isPushServerConfigured,
              !toProfileID.isEmpty else {
            return
        }

        var payload: [String: String] = [
            "toProfileID": toProfileID,
            "title": title,
            "body": body
        ]
        if let requestID {
            payload["requestID"] = requestID
        }
        await post(path: "/notify", payload: payload)
    }

    private func post(path: String, payload: [String: String]) async {
        guard let url = URL(string: AppConfiguration.pushServerBaseURL + path) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.pushServerSharedSecret, forHTTPHeaderField: "x-deny-secret")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // Best-effort: a push failure must never block the in-app flow.
        _ = try? await URLSession.shared.data(for: request)
    }
}
