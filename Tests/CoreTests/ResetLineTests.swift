import Foundation
import Testing

@testable import ClaudeUsageCore

/// The third line of each widget gauge. Short enough to fit is the whole point:
/// a line that has to be scaled down to fit is unreadable.
@Suite("The reset line the widget renders")
struct ResetLineTests {

    @Test("A reset later today drops the date")
    func sameDayResetDropsTheDate() throws {
        let session = UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)[0]

        #expect(session.resetsToday(at: pinnedNow))
        #expect(session.resetDisplay(at: pinnedNow) == "9:20pm")
        #expect(session.resetLine(at: pinnedNow) == "resets 9:20pm · 1h 20m left")
    }

    @Test("A reset on another day keeps the date")
    func datedResetKeepsTheDate() throws {
        let week = UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)[1]

        #expect(week.resetsToday(at: pinnedNow) == false)
        #expect(week.resetDisplay(at: pinnedNow) == "Aug 29, 5:00pm")
        #expect(week.resetLine(at: pinnedNow) == "resets Aug 29, 5:00pm · 21h 0m left")
    }

    @Test("The countdown can be left off when the width is tight")
    func countdownIsOptional() throws {
        let week = UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)[1]

        #expect(week.resetLine(at: pinnedNow, includeCountdown: false) == "resets Aug 29, 5:00pm")
    }

    @Test("A limit at zero says so instead of inventing a time",
          arguments: zeroSessionFixtures)
    func zeroGaugeHasNoResetLine(_ name: String) throws {
        let gauges = UsageOutputParser.parse(try fixture(name), now: pinnedNow)

        #expect(gauges[0].resetLine(at: pinnedNow) == "nothing used yet")
    }

    /// A percentage above zero with no reset clause would be the CLI changing
    /// shape, so it must not read as "nothing used yet".
    @Test("A missing reset above zero is reported, not glossed over")
    func missingResetAboveZeroIsFlagged() {
        let gauge = LimitGauge(label: "session", percent: 30, resetsText: "")

        #expect(gauge.resetLine(at: pinnedNow) == "reset time unavailable")
    }

    @Test("Past a day the countdown carries days", arguments: zeroSessionFixtures)
    func countdownOverADayCarriesDays(_ name: String) throws {
        let week = UsageOutputParser.parse(try fixture(name), now: pinnedNow)[1]

        // Otherwise the week reports a three-figure hour count.
        #expect(week.resetLine(at: pinnedNow) == "resets Sep 5, 4:59pm · 7d 20h 59m left")
    }

    @Test("An unparseable reset still shows the text the CLI printed")
    func fallsBackToTheRawText() {
        let gauge = LimitGauge(label: "session", percent: 30, resetsText: "sometime on Thursday")

        #expect(gauge.resetDisplay(at: pinnedNow) == "sometime on Thursday")
        #expect(gauge.resetLine(at: pinnedNow) == "resets sometime on Thursday")
    }
}
