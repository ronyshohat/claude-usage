import Foundation
import Testing

@testable import ClaudeUsageCore

/// `claude -p "/usage"` prints human-readable text, not an API, so this is the
/// part most likely to break underneath us.
@Suite("Parsing the CLI's usage output")
struct ParserTests {

    @Test("A normal report yields both gauges, in order")
    func parsesAKnownReport() throws {
        let gauges = UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)

        #expect(gauges.count == 2)
        #expect(gauges.map(\.label) == ["session", "week (all models)"])
        #expect(gauges.map(\.shortLabel) == ["Session", "Week"])
        #expect(gauges.map(\.percent) == [48, 27])
    }

    @Test("The reset clause is kept verbatim, with the timezone trimmed off")
    func keepsResetTextWithoutTheTimezone() throws {
        let gauges = UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)

        // "Aug 28 at 9:20pm (Europe/London)" — the time is already local, so
        // the parenthesised zone is noise.
        #expect(gauges[0].resetsText == "Aug 28 at 9:20pm")
        // On the hour the CLI drops the minutes entirely.
        #expect(gauges[1].resetsText == "Aug 29 at 5pm")
    }

    @Test("Both reset forms parse to a real date, so the countdown works")
    func resolvesResetTimes() throws {
        let gauges = UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)

        #expect(gauges.allSatisfy { $0.resetsAt != nil })
        // 8:00pm to 9:20pm the same evening.
        let session = try #require(gauges[0].remaining(at: pinnedNow))
        #expect(session == 80 * 60)
        // ...and 5pm the next day.
        let week = try #require(gauges[1].remaining(at: pinnedNow))
        #expect(week == 21 * 3600)
    }

    @Test("A limit at zero is a real zero, not a missing gauge",
          arguments: zeroSessionFixtures)
    func fillsInALimitAtZero(_ name: String) throws {
        let gauges = UsageOutputParser.parse(try fixture(name), now: pinnedNow)

        #expect(gauges.count == 2)
        // Session stays above week even when it had to be filled in.
        #expect(gauges[0].shortLabel == "Session")
        #expect(gauges[0].percent == 0)
        // Nothing has been spent, so no window has opened to reset.
        #expect(gauges[0].hasReset == false)
        #expect(gauges[0].resetsAt == nil)

        #expect(gauges[1].label == "week (all models)")
        #expect(gauges[1].percent == 4)
    }

    @Test("Output with nothing recognisable in it parses to nothing")
    func rejectsUnrelatedText() {
        #expect(UsageOutputParser.parse("some unrelated text", now: pinnedNow).isEmpty)
        #expect(UsageOutputParser.parse("", now: pinnedNow).isEmpty)
    }

    /// The zero-filling must not turn unfamiliar output — a login prompt, an
    /// error, a changed format — into a confident pair of zeroes. An empty
    /// parse is what the probe reports as a failure.
    @Test("A login prompt does not become two zeroes")
    func doesNotInventGaugesFromNothing() {
        let prompt = """
            Please run /login to authenticate.
            Current plan: none
            """
        #expect(UsageOutputParser.parse(prompt, now: pinnedNow).isEmpty)
    }

    @Test("A reset just past still reads as upcoming, not a year away")
    func rollsAResetForwardRatherThanBack() throws {
        // Just after midnight the evening's reset can parse as already elapsed.
        let justAfterMidnight = ISO8601DateFormatter().date(from: "2026-08-29T00:10:00Z")!
        let gauges = UsageOutputParser.parse(
            "Current session: 12% used · resets Aug 29 at 1:00am (Europe/London)",
            now: justAfterMidnight
        )

        let remaining = try #require(gauges.first?.remaining(at: justAfterMidnight))
        #expect(remaining == 50 * 60)
    }
}
