import Foundation

public enum Format {

    /// "1d 4h 10m" past a day, "2h 12m" past an hour, "12m" under one.
    ///
    /// The week runs to well over a hundred hours, which is a number nobody
    /// reads as a length of time.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func relative(_ date: Date, to now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        return duration(delta) + " ago"
    }
}
