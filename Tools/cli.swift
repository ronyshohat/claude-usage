import Foundation

/// Sanity-check harness.
///
///   Tools/verify.sh                    run the real probe
///   Tools/verify.sh --parse FILE       parse saved output, no CLI call
///   Tools/verify.sh --parse FILE --now 2026-08-28T20:00:00Z
///                                      ...against a pinned clock
///
/// `--now` only applies to `--parse`. A fixture carries dates but no year, so
/// whether its reset reads as same-day or a year out depends on the day the
/// harness runs; pinning the clock is what keeps CI's assertions stable.
///
/// Not part of the app or widget target.
@main
struct CLI {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())

        var now = Date()
        if let flag = args.firstIndex(of: "--now") {
            guard flag + 1 < args.count,
                  let pinned = ISO8601DateFormatter().date(from: args[flag + 1])
            else {
                print("--now needs an ISO-8601 date, e.g. 2026-08-28T20:00:00Z")
                exit(1)
            }
            now = pinned
            args.removeSubrange(flag...(flag + 1))
        }

        if args.first == "--parse", args.count > 1 {
            parseOnly(path: args[1], now: now)
            return
        }

        print("locating claude…")
        guard let cli = UsageProbe.locateCLI() else {
            print("  not found")
            exit(1)
        }
        print("  \(cli.path)")

        print("running claude -p \"/usage\"…")
        let clock = Date()
        switch UsageProbe.run() {
        case let .success(gauges):
            print("  ok in \(String(format: "%.1f", Date().timeIntervalSince(clock)))s\n")
            show(gauges)

            let snapshot = UsageSnapshot(gauges: gauges)
            do {
                try SharedStore.write(snapshot)
                print("\nwrote to:\n\(SharedStore.destinationSummary())")
            } catch {
                print("\nwrite failed: \(error.localizedDescription)")
            }

            let leftovers = (try? FileManager.default.contentsOfDirectory(
                at: UsageProbe.transcriptDirectory, includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "jsonl" }) ?? []
            print("leftover probe transcripts: \(leftovers.count)")

        case let .failure(error):
            print("  failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func parseOnly(path: String, now: Date) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("could not read \(path)")
            exit(1)
        }
        let gauges = UsageOutputParser.parse(text, now: now)
        guard !gauges.isEmpty else {
            print("parsed nothing")
            exit(1)
        }
        show(gauges, now: now)
    }

    static func show(_ gauges: [LimitGauge], now: Date = Date()) {
        for gauge in gauges {
            let filled = Int((Double(gauge.percent) / 100 * 24).rounded())
            let bar = String(repeating: "#", count: filled)
                + String(repeating: ".", count: max(0, 24 - filled))
            let countdown = gauge.remaining(at: now).map { " (\(Format.duration($0)))" } ?? ""
            let reset = gauge.hasReset ? "resets \(gauge.resetsText)" : "no reset reported"
            print("  \(gauge.shortLabel.padding(toLength: 8, withPad: " ", startingAt: 0))"
                + " \(String(gauge.percent).padding(toLength: 4, withPad: " ", startingAt: 0))"
                + " \(bar)  \(reset)\(countdown)")
            print("    label:  \"\(gauge.label)\"")
            // What the widget actually renders on its third line.
            print("    widget: \"\(gauge.resetLine(at: now))\"")
        }
    }
}
