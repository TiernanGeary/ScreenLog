import Foundation

enum AppConfiguration {
    static let appGroupIdentifier = ScreenTimeReportStorage.appGroupSuiteName

    /// Supabase backend (Postgres + Auth + Storage). The anon key is a
    /// publishable client key; row-level security enforces all access.
    static let supabaseURL = "https://obvndsxjmzrtnlatbwdx.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9idm5kc3hqbXpydG5sYXRid2R4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyODU3MjMsImV4cCI6MjA5Njg2MTcyM30.fhF-16otWbKQ1k-Zb3QQvjvETaCg_00TVOz9yZC8NE8"

    static var isSupabaseConfigured: Bool {
        !supabaseURL.contains("REPLACE_WITH") && !supabaseAnonKey.contains("REPLACE_WITH")
    }

    static let defaultAvatarColor = "#1B998B"
    static let avatarFallbackColors = ["#1B998B", "#2E86AB", "#E84855", "#6A4C93", "#F18F01", "#2F4858"]

    static let subscriptionProductIDs: Set<String> = [
        "com.jdco.deny.subscription.monthly",
        "com.jdco.deny.subscription.yearly"
    ]

    /// Push notification server (Cloudflare Worker). Set the URL after deploying.
    /// Until set, push registration/sends are skipped (CloudKit silent push still
    /// works as a fallback).
    static let pushServerBaseURL = "https://deny-push-server.tiernan-33a.workers.dev"
    /// Shared secret sent in the `x-deny-secret` header; must match the Worker's
    /// APP_SHARED_SECRET. Replaced at deploy time.
    static let pushServerSharedSecret = "97127fb9fd313f27fb3d5556706347e6cd735617f5826a8dfbf95c179548d840"

    static var isPushServerConfigured: Bool {
        !pushServerBaseURL.contains("REPLACE_WITH") && !pushServerSharedSecret.contains("REPLACE_WITH")
    }

    static func randomAvatarColorHex() -> String {
        avatarFallbackColors.randomElement() ?? defaultAvatarColor
    }
}
