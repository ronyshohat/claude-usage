import Foundation

public enum Format {

    /// "2h 12m", or "12m" under an hour.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func relative(_ date: Date, to now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        return duration(delta) + " ago"
    }
}
