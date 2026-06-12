import Foundation
import Supabase

/// Single shared Supabase client for the app target. Auth sessions persist in
/// the Keychain (supabase-swift's default storage on Apple platforms), so a
/// signed-in user survives relaunch and, on device, reinstall.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: URL(string: AppConfiguration.supabaseURL)!,
        supabaseKey: AppConfiguration.supabaseAnonKey
    )
}
