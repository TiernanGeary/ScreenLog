import Foundation

/// Lightweight shared log so the app and the DeviceActivity extension can
/// record what actually happens with blocking monitors. Read back in the app's
/// diagnostics screen to see whether re-block monitors schedule and whether the
/// system ever delivers their callbacks. Temporary instrumentation.
public enum BlockingDiagnosticsLog {
    private static let key = "BlockingDiagnosticsLog.v1"
    private static let limit = 60

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: BlockingStoreCodec.suiteName)
    }

    public static func record(_ message: String, now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: now))] \(message)"

        let d = defaults
        var entries = d?.stringArray(forKey: key) ?? []
        entries.append(line)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        d?.set(entries, forKey: key)
    }

    public static func entries() -> [String] {
        defaults?.stringArray(forKey: key) ?? []
    }

    public static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
