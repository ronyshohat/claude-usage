import Foundation
import Testing

@testable import ClaudeUsageCore

/// The app writes a snapshot, the widget reads it back. SharedStore's own
/// write path targets real container directories, so what is worth pinning
/// here is the encoding contract between the two sides — not the file I/O.
@Suite("The snapshot the app hands the widget")
struct SnapshotTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("A snapshot survives the round trip unchanged")
    func roundTripsThroughJSON() throws {
        let original = UsageSnapshot(
            generatedAt: pinnedNow,
            gauges: UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)
        )

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(UsageSnapshot.self, from: data)

        #expect(decoded == original)
    }

    /// The widget may still have a snapshot on disk from an older build. It
    /// should read, rather than leave the widget blank after an update.
    @Test("A snapshot written before `failure` existed still decodes")
    func decodesASnapshotWithoutTheFailureKey() throws {
        let json = """
            {
              "generatedAt": "2026-08-28T20:00:00Z",
              "gauges": [
                {
                  "label": "session",
                  "percent": 48,
                  "resetsText": "Aug 28 at 9:20pm",
                  "resetsAt": "2026-08-28T21:20:00Z"
                }
              ]
            }
            """

        let decoded = try Self.decoder.decode(UsageSnapshot.self, from: Data(json.utf8))

        #expect(decoded.failure == nil)
        #expect(decoded.session?.percent == 48)
        let remaining = try #require(decoded.session?.remaining(at: pinnedNow))
        #expect(remaining == 80 * 60)
    }

    @Test("Gauges are found by prefix, so the week's model suffix doesn't matter")
    func looksUpGaugesByPrefix() throws {
        let snapshot = UsageSnapshot(
            gauges: UsageOutputParser.parse(try fixture("usage-output"), now: pinnedNow)
        )

        #expect(snapshot.session?.percent == 48)
        #expect(snapshot.week?.percent == 27)
    }

    @Test("A failed probe is carried, so the widget can say so")
    func carriesAFailure() {
        let snapshot = UsageSnapshot(failure: "claude not found")

        #expect(snapshot.gauges.isEmpty)
        #expect(snapshot.failure == "claude not found")
    }
}
