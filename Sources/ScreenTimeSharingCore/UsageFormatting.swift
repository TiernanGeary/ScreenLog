import Foundation

public enum UsageFormatting {
    public static func duration(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "Unavailable"
        }

        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    public static func capabilityLabel(_ capability: ScreenTimeCapability) -> String {
        switch capability.status {
        case .fullAppDetail:
            return "App detail available"
        case .aggregateOnly:
            return "Selected-app total only"
        case .unavailable:
            return "Screen Time unavailable"
        }
    }

    public static func lastUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "Never updated"
        }

        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 60 {
            return "Updated just now"
        }

        let minutes = elapsed / 60
        if minutes < 60 {
            return "Updated \(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "Updated \(hours)h ago"
        }

        let days = hours / 24
        return "Updated \(days)d ago"
    }
}
