import Foundation

public enum UsageDateBoundary {
    public static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    public static func snapshotID(profileID: String, date: Date, calendar: Calendar = .current) -> String {
        let interval = dayInterval(containing: date, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(profileID)-\(formatter.string(from: interval.start))"
    }
}
