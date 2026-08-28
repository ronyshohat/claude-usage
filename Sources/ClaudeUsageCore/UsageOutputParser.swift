import Foundation

/// Pulls the gauges out of `claude -p "/usage"`.
///
/// The lines look like:
///
///     Current session: 48% used · resets Aug 28 at 9:20pm (Europe/London)
///     Current week (all models): 27% used · resets Aug 29 at 4:59pm (Europe/London)
///
/// This is human-readable output, not an API, so treat it as liable to change:
/// parse leniently and let a missing line surface as an error rather than a
/// silently wrong number.
public enum UsageOutputParser {

    /// Separator is U+00B7 MIDDLE DOT, verified against real output.
    private static let pattern = #"^Current\s+(.+?):\s*(\d+)%\s*used\s*[·|-]\s*resets\s+(.+?)\s*$"#

    private static let regex = try! NSRegularExpression(
        pattern: pattern,
        options: [.anchorsMatchLines, .caseInsensitive]
    )

    public static func parse(_ output: String, now: Date = Date()) -> [LimitGauge] {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return regex.matches(in: output, range: range).compactMap { match in
            guard let label = capture(1, match, output),
                  let percentText = capture(2, match, output),
                  let percent = Int(percentText),
                  var resets = capture(3, match, output)
            else { return nil }

            // Drop the trailing "(Europe/London)" — the time is already local.
            if let paren = resets.range(of: " (", options: .backwards) {
                resets = String(resets[resets.startIndex..<paren.lowerBound])
            }

            return LimitGauge(
                label: label.lowercased(),
                percent: percent,
                resetsText: resets,
                resetsAt: parseReset(resets, now: now)
            )
        }
    }

    private static func capture(_ index: Int, _ match: NSTextCheckingResult, _ string: String)
        -> String?
    {
        guard let range = Range(match.range(at: index), in: string) else { return nil }
        return String(string[range]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Reset time

    /// Dated formats roll forward by a year when they land in the past; time-only
    /// formats roll forward by a day. Getting that backwards puts a reset that is
    /// twenty minutes away twelve months away instead.
    private static let formats: [(format: String, rollover: Calendar.Component)] = [
        ("MMM d 'at' h:mma", .year),
        ("MMM d 'at' h:mm a", .year),
        // On the hour the CLI drops the minutes: "resets Aug 29 at 5pm".
        ("MMM d 'at' ha", .year),
        ("MMM d 'at' h a", .year),
        ("h:mma", .day),
        ("h:mm a", .day),
        ("ha", .day),
        ("h a", .day),
    ]

    /// Best effort. Only drives the countdown; the raw text is always shown.
    static func parseReset(_ text: String, now: Date) -> Date? {
        let calendar = Calendar.current

        for (format, rollover) in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.defaultDate = calendar.startOfDay(for: now)

            guard var date = formatter.date(from: text) else { continue }

            // The output carries no year, so a reset just after midnight can
            // parse as already past. Allow a little slack for a reset that has
            // genuinely just elapsed.
            if date < now.addingTimeInterval(-2 * 3600) {
                date = calendar.date(byAdding: rollover, value: 1, to: date) ?? date
            }
            return date
        }
        return nil
    }
}
