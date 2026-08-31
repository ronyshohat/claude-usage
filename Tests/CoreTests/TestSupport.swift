import Foundation

/// The clock every test runs against.
///
/// The fixtures carry dates but no year, so whether "Aug 28" reads as same-day
/// or a year out depends on the day the tests run. Pinning the clock is what
/// keeps the assertions stable — the same reason Tools/verify.sh takes `--now`.
let pinnedNow = ISO8601DateFormatter().date(from: "2026-08-28T20:00:00Z")!

/// The parser and the display helpers go through `Calendar.current` and
/// unzoned `DateFormatter`s, so the machine's timezone changes what they
/// produce. Pin it to UTC for the same reason as the clock above: otherwise
/// these tests pass in London and fail in Jerusalem.
///
/// A global `let` is initialised once, on first use, and every helper below
/// touches it before formatting anything.
private let utcTimeZone: Void = {
    setenv("TZ", "UTC", 1)
    NSTimeZone.resetSystemTimeZone()
}()

/// The repo root, found by walking up from this file — Tests/CoreTests/x.swift.
private func repoRoot(_ file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()  // CoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
}

/// Reads one of the saved CLI transcripts in Tools/fixtures.
///
/// Read from their real location rather than copied into the test bundle:
/// Tools/verify.sh parses the same files, and two copies would drift.
func fixture(_ name: String) throws -> String {
    _ = utcTimeZone
    let url = repoRoot().appending(path: "Tools/fixtures/\(name).txt")
    return try String(contentsOf: url, encoding: .utf8)
}

/// Both fixtures where the session limit is at zero: once printed as "0% used"
/// with no reset clause, once left out of the output altogether. Both are a
/// real zero rather than a missing gauge — the case that regressed once.
let zeroSessionFixtures = ["usage-output-zero", "usage-output-missing-session"]
