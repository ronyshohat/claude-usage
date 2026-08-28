import Foundation

/// Sanity-check harness.
///
///   Tools/verify.sh                 run the real probe
///   Tools/verify.sh --parse FILE    parse saved output, no CLI call
///
/// Not part of the app or widget target.
@main
struct CLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.first == "--parse", args.count > 1 {
            parseOnly(path: args[1])
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

    static func parseOnly(path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("could not read \(path)")
            exit(1)
        }
        let gauges = UsageOutputParser.parse(text)
        guard !gauges.isEmpty else {
            print("parsed nothing")
            exit(1)
        }
        show(gauges)
    }

    static func show(_ gauges: [LimitGauge]) {
        for gauge in gauges {
            let filled = Int((Double(gauge.percent) / 100 * 24).rounded())
            let bar = String(repeating: "#", count: filled)
                + String(repeating: ".", count: max(0, 24 - filled))
            let countdown = gauge.remaining().map { " (\(Format.duration($0)))" } ?? ""
            print("  \(gauge.shortLabel.padding(toLength: 8, withPad: " ", startingAt: 0))"
                + " \(String(gauge.percent).padding(toLength: 4, withPad: " ", startingAt: 0))"
                + " \(bar)  resets \(gauge.resetsText)\(countdown)")
            print("    label:  \"\(gauge.label)\"")
            // What the widget actually renders on its third line.
            print("    widget: \"\(gauge.resetLine())\"")
        }
    }
}
