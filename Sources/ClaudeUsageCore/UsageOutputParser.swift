import Foundation

/// Pulls the gauges out of `claude -p "/usage"`.
///
/// The lines look like:
///
///     Current session: 48% used · resets Aug 28 at 9:20pm (Europe/London)
///     Current week (all models): 27% used · resets Aug 29 at 4:59pm (Europe/London)
///
/// A limit nothing has been spent against yet has no window to reset, so the
/// CLI prints the percentage on its own — and sometimes leaves the line out
/// altogether:
///
///     Current session: 0% used
///
/// This is human-readable output, not an API, so treat it as liable to change:
/// parse leniently and let output with nothing recognisable in it surface as an
/// error rather than a silently wrong number.
public enum UsageOutputParser {

    /// The reset clause is optional: at 0% the CLI prints the percentage alone.
    /// Separator is U+00B7 MIDDLE DOT, verified against real output.
    private static let pattern =
        #"^Current\s+(.+?):\s*(\d+)%\s*used\s*(?:[·|-]\s*resets\s+(.+?))?\s*$"#

    private static let regex = try! NSRegularExpression(
        pattern: pattern,
        options: [.anchorsMatchLines, .caseInsensitive]
    )

    public static func parse(_ output: String, now: Date = Date()) -> [LimitGauge] {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let parsed = regex.matches(in: output, range: range).compactMap { match -> LimitGauge? in
            guard let label = capture(1, match, output),
                  let percentText = capture(2, match, output),
                  let percent = Int(percentText)
            else { return nil }

            // Absent for a limit that reported no reset.
            var resets = capture(3, match, output) ?? ""

            // Drop the trailing "(Europe/London)" — the time is already local.
            if let paren = resets.range(of: " (", options: .backwards) {
                resets = String(resets[resets.startIndex..<paren.lowerBound])
            }

            return LimitGauge(
                label: label.lowercased(),
                percent: percent,
                resetsText: resets,
                resetsAt: resets.isEmpty ? nil : parseReset(resets, now: now)
            )
        }
        return addingImplicitZeros(parsed)
    }

    // MARK: - Missing limits

    /// The limits the CLI reports, in the order it prints them.
    private static let expected = ["session", "week"]

    /// A limit the output leaves out is a limit at zero, not missing data, so
    /// fill it in rather than dropping a gauge off the widget.
    ///
    /// Guarded on something having parsed: if the output is wholly unfamiliar —
    /// a login prompt, an error, a changed format — nothing here should turn
    /// that into a confident pair of zeroes. The probe reports an empty parse as
    /// a failure, and that is the right outcome for it.
    private static func addingImplicitZeros(_ gauges: [LimitGauge]) -> [LimitGauge] {
        guard !gauges.isEmpty else { return [] }

        var result = gauges
        for (rank, prefix) in expected.enumerated()
        where !result.contains(where: { $0.label.hasPrefix(prefix) }) {
            // Insert ahead of the first limit it outranks, so session stays
            // above week however few of them came back.
            let index = result.firstIndex { self.rank(of: $0.label) > rank } ?? result.count
            result.insert(
                LimitGauge(
                    label: prefix == "week" ? "week (all models)" : prefix,
                    percent: 0,
                    resetsText: ""
                ),
                at: index
            )
        }
        return result
    }

    private static func rank(of label: String) -> Int {
        expected.firstIndex { label.hasPrefix($0) } ?? expected.count
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
