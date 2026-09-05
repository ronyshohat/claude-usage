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

    /// "47s ago" under a minute, then the same units as `duration`.
    ///
    /// Seconds, not a "just now" band: the refresh interval goes as low as a
    /// minute, so anything that rounded the first minute off would spend most
    /// of its life unable to say anything else.
    public static func relative(_ date: Date, to now: Date = Date()) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 60 { return "\(Int(delta))s ago" }
        return duration(delta) + " ago"
    }

    /// "1.0.42" from a release build, "1.0 (1)" from a local one.
    ///
    /// CI stamps the marketing version as `1.0.<patch>` and the build as the
    /// patch on its own, so spelling the build out again there would only
    /// repeat the tail. A local build leaves the two unrelated, and then
    /// the build number is the half worth seeing.
    public static func version(short: String, build: String) -> String {
        if short.isEmpty { return build.isEmpty ? "unknown" : build }
        if build.isEmpty || short == build || short.hasSuffix(".\(build)") { return short }
        return "\(short) (\(build))"
    }
}
