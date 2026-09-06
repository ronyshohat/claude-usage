import Foundation
import SwiftUI
import WidgetKit

/// Owns the refresh loop.
///
/// The widget extension is sandboxed and cannot spawn processes, so this app
/// runs `claude -p "/usage"`, writes the result to the shared container, and
/// nudges WidgetKit to redraw.
@MainActor
final class UsageModel: ObservableObject {

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false

    /// Each refresh spawns the CLI and makes a network call, so a minute is the
    /// floor `restartTimer` enforces. It costs no tokens, but it is a process
    /// launch and a round trip every time — raise it if that bothers you.
    @AppStorage("refreshSeconds") var refreshSeconds = 60 {
        didSet { restartTimer() }
    }

    /// For non-standard installs where the CLI is not on any usual path.
    @AppStorage("claudeCLIPath") var cliPath = "" {
        didSet {
            Log.info("app", "cli path set to \(cliPath.isEmpty ? "auto-detect" : cliPath)")
            UsageProbe.overridePath = cliPath
            Task { await refresh(trigger: "cli path changed") }
        }
    }

    /// Adds the raw CLI output and the per-path store decisions to the log.
    /// Off by default because the raw output is most of the volume.
    @AppStorage(Log.verboseKey) var verboseLogging = false {
        didSet {
            Log.setVerbose(verboseLogging)
            Log.info("app", "verbose logging \(verboseLogging ? "on" : "off")")
        }
    }

    private var timer: Timer?
    private var lastTimerFire: Date?
    /// How many refreshes in a row came back with the same gauges. Counted so
    /// the log distinguishes a probe that is not running from one that is
    /// running and getting the same answer.
    private var unchangedRefreshes = 0

    init() {
        Log.setVerbose(verboseLogging)
        Log.info("app", "launched, version \(Self.bundleVersion),"
            + " pid \(ProcessInfo.processInfo.processIdentifier)")
        Log.info("app", "logging to \(Log.locationSummary)")

        snapshot = SharedStore.read()
        Log.info("app", "snapshot at launch: "
            + (snapshot.map { "\(Format.relative($0.generatedAt)), \($0.logSummary)" } ?? "none"))
        Log.info("app", "snapshot goes to \(SharedStore.writeDestinations().count) location(s):"
            + " \(SharedStore.destinationSummary().replacingOccurrences(of: "\n", with: ", "))")
        Log.info("app", "and is read back from \(SharedStore.sourceSummary())")

        UsageProbe.overridePath = cliPath
        Log.info("app", "claude CLI resolves to \(UsageProbe.locateCLI()?.path ?? "nothing")")

        restartTimer()
        Task { await refresh(trigger: "launch") }
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(60, refreshSeconds))
        Log.info("timer", "refreshing every \(Int(interval))s")
        lastTimerFire = Date()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.noteTimerFire(expected: interval)
                await self?.refresh(trigger: "timer")
            }
        }
    }

    /// A timer that fires late is the quietest way for this app to look broken.
    /// macOS throttles a background agent's run loop, and the machine sleeps;
    /// either way the panel goes on showing the last good numbers with the last
    /// good timestamp, and nothing on screen says a refresh was skipped. The
    /// gap between fires is the only evidence, so record it.
    private func noteTimerFire(expected: TimeInterval) {
        let now = Date()
        defer { lastTimerFire = now }
        guard let last = lastTimerFire else { return }

        let actual = now.timeIntervalSince(last)
        if actual > expected * 1.5 {
            Log.warn("timer", "fired \(Int(actual))s after the previous one, expected"
                + " \(Int(expected))s — the run loop was throttled or the machine slept")
        } else {
            Log.debug("timer", "fired after \(Int(actual))s")
        }
    }

    func refresh(trigger: String = "manual") async {
        guard !isRefreshing else {
            // Not harmless: at a 60s interval with a 30s probe timeout, a run
            // that hangs eats the next tick, and the panel simply keeps its
            // old numbers.
            Log.warn("app", "refresh (\(trigger)) skipped, the previous one is still running")
            return
        }
        isRefreshing = true
        let started = Date()
        defer { isRefreshing = false }

        Log.info("app", "refresh start (\(trigger))")

        // Spawning and waiting on the CLI must not block the menu.
        let fresh = await Task.detached(priority: .utility) {
            UsageProbe.snapshot()
        }.value

        let previous = snapshot
        snapshot = fresh
        logOutcome(previous: previous, fresh: fresh)

        do {
            try SharedStore.write(fresh)
        } catch {
            Log.error("app", "the snapshot could not be published:"
                + " \(error.localizedDescription). The menu is current; the widget is not")
        }
        WidgetCenter.shared.reloadAllTimelines()

        Log.info("app", "refresh done (\(trigger)) in"
            + " \(Format.elapsed(Date().timeIntervalSince(started))), widget timelines reloaded")
    }

    /// The heart of the log: whether this refresh actually changed anything.
    ///
    /// A successful probe always stamps a fresh `generatedAt`, so the panel says
    /// "2s ago" whether the numbers moved or not. Only the log can say which.
    private func logOutcome(previous: UsageSnapshot?, fresh: UsageSnapshot) {
        if let failure = fresh.failure {
            Log.warn("app", "the snapshot carries a failure: \(failure)")
        }

        guard let previous else {
            Log.info("app", "first snapshot: \(fresh.logSummary)")
            return
        }

        if previous.gauges == fresh.gauges {
            unchangedRefreshes += 1
            Log.info("app", "gauges unchanged for \(unchangedRefreshes) refresh(es) running:"
                + " \(fresh.logSummary)")
        } else {
            Log.info("app", "gauges changed after \(unchangedRefreshes) unchanged refresh(es):"
                + " \(fresh.changes(since: previous))")
            unchangedRefreshes = 0
        }

        // Only reachable through the failure path, which keeps the stored
        // snapshot and its original timestamp. Worth naming, because it is the
        // one case where the panel's age keeps growing while refreshes succeed.
        if fresh.generatedAt <= previous.generatedAt {
            Log.warn("app", "the snapshot timestamp did not advance"
                + " (still \(Format.relative(fresh.generatedAt))), so the panel will go on"
                + " ageing the numbers it already had")
        }
    }

    var resolvedCLIPath: String {
        UsageProbe.locateCLI()?.path ?? "not found"
    }

    /// Releases are tagged v1.0.<patch> and the bundle carries the same string,
    /// so this says which release a copy came from — in the log as well as in
    /// Settings, since a log without it cannot be matched to a build.
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        return Format.version(
            short: info?["CFBundleShortVersionString"] as? String ?? "",
            build: info?["CFBundleVersion"] as? String ?? ""
        )
    }

    // MARK: - Menu bar summary

    var menuBarText: String {
        guard let snapshot, !snapshot.gauges.isEmpty else { return "—" }
        return [snapshot.session, snapshot.week]
            .compactMap { $0.map { "\($0.percent)%" } }
            .joined(separator: " · ")
    }

    var worstPercent: Int {
        snapshot?.gauges.map(\.percent).max() ?? 0
    }
}
