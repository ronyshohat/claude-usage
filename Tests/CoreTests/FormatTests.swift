import Foundation
import Testing

@testable import ClaudeUsageCore

@Suite("Formatting")
struct FormatTests {

    @Test("Durations shorten to the largest unit that applies")
    func durationPicksItsUnits() {
        #expect(Format.duration(12 * 60) == "12m")
        #expect(Format.duration(2 * 3600 + 12 * 60) == "2h 12m")
        #expect(Format.duration(28 * 3600 + 10 * 60) == "1d 4h 10m")
    }

    @Test("A reset already past reads as zero, not as a negative")
    func durationClampsAtZero() {
        #expect(Format.duration(-500) == "0m")
        #expect(Format.duration(0) == "0m")
    }

    @Test("Freshness is rounded off under a minute")
    func relativeSaysJustNow() {
        #expect(Format.relative(pinnedNow, to: pinnedNow) == "just now")
        #expect(Format.relative(pinnedNow.addingTimeInterval(-30), to: pinnedNow) == "just now")
        #expect(Format.relative(pinnedNow.addingTimeInterval(-300), to: pinnedNow) == "5m ago")
    }

    @Test("The bar never overfills, whatever the CLI reports")
    func fractionIsClamped() {
        #expect(LimitGauge(label: "session", percent: 48, resetsText: "").fraction == 0.48)
        #expect(LimitGauge(label: "session", percent: 0, resetsText: "").fraction == 0)
        #expect(LimitGauge(label: "session", percent: 140, resetsText: "").fraction == 1)
        #expect(LimitGauge(label: "session", percent: -5, resetsText: "").fraction == 0)
    }

    @Test("The short label is the first word, capitalised")
    func shortLabelTakesTheFirstWord() {
        #expect(LimitGauge(label: "week (all models)", percent: 0, resetsText: "").shortLabel == "Week")
        #expect(LimitGauge(label: "session", percent: 0, resetsText: "").shortLabel == "Session")
    }
}
