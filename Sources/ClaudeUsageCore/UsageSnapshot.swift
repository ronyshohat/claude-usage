import Foundation

/// One rate limit as Claude Code reports it: a percentage and a reset time.
public struct LimitGauge: Codable, Sendable, Equatable, Identifiable {
    /// As printed, e.g. "session" or "week (all models)".
    public var label: String
    public var percent: Int
    /// Verbatim from the CLI, e.g. "Aug 28 at 9:20pm". Already in local time.
    public var resetsText: String
    /// Best-effort parse of `resetsText`, for the countdown. Nil is fine — the
    /// text is what gets displayed either way.
    public var resetsAt: Date?

    public var id: String { label }

    public init(label: String, percent: Int, resetsText: String, resetsAt: Date? = nil) {
        self.label = label
        self.percent = percent
        self.resetsText = resetsText
        self.resetsAt = resetsAt
    }

    /// "session" -> "Session", "week (all models)" -> "Week".
    public var shortLabel: String {
        let first = label.split(separator: " ").first.map(String.init) ?? label
        return first.prefix(1).uppercased() + first.dropFirst()
    }

    public var fraction: Double { min(1, max(0, Double(percent) / 100)) }

    public func remaining(at now: Date = Date()) -> TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSince(now))
    }

    /// The reset time, trimmed to fit a widget.
    ///
    /// The CLI always prints the date ("Aug 28 at 9:19pm"), but for a session
    /// resetting in an hour that date is noise, and it is the difference between
    /// the line fitting and being scaled down to nothing. Falls back to the raw
    /// text when the date could not be parsed.
    public func resetDisplay(at now: Date = Date()) -> String {
        guard let resetsAt else { return resetsText }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = Calendar.current.isDate(resetsAt, inSameDayAs: now)
            ? "h:mma"
            : "MMM d, h:mma"
        return formatter.string(from: resetsAt)
    }

    /// True when the reset falls on today, so the date can be dropped.
    public func resetsToday(at now: Date = Date()) -> Bool {
        guard let resetsAt else { return false }
        return Calendar.current.isDate(resetsAt, inSameDayAs: now)
    }

    /// "resets 9:19pm · 1h 24m left"
    ///
    /// The countdown is optional because on a small widget a dated reset plus a
    /// countdown is more text than the width allows, and scaling it down to fit
    /// just makes it unreadable.
    public func resetLine(at now: Date = Date(), includeCountdown: Bool = true) -> String {
        let base = "resets \(resetDisplay(at: now))"
        guard includeCountdown, let remaining = remaining(at: now) else { return base }
        return "\(base) · \(Format.duration(remaining)) left"
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var gauges: [LimitGauge]
    /// Set when the last probe failed, so the widget can say so instead of
    /// presenting stale percentages as current.
    public var failure: String?

    public init(generatedAt: Date = Date(), gauges: [LimitGauge] = [], failure: String? = nil) {
        self.generatedAt = generatedAt
        self.gauges = gauges
        self.failure = failure
    }

    public var session: LimitGauge? {
        gauges.first { $0.label.hasPrefix("session") }
    }

    public var week: LimitGauge? {
        gauges.first { $0.label.hasPrefix("week") }
    }

    public static let placeholder = UsageSnapshot(
        gauges: [
            LimitGauge(
                label: "session",
                percent: 48,
                resetsText: "Aug 28 at 9:20pm",
                resetsAt: Date().addingTimeInterval(4_400)
            ),
            LimitGauge(
                label: "week (all models)",
                percent: 27,
                resetsText: "Aug 29 at 4:59pm",
                resetsAt: Date().addingTimeInterval(76_000)
            ),
        ]
    )
}
