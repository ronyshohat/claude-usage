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

    /// The probe spawns the CLI and makes a network call, so this is minutes,
    /// not seconds. The percentages move slowly enough that it does not matter.
    @AppStorage("refreshSeconds") var refreshSeconds = 300 {
        didSet { restartTimer() }
    }

    /// For non-standard installs where the CLI is not on any usual path.
    @AppStorage("claudeCLIPath") var cliPath = "" {
        didSet {
            UsageProbe.overridePath = cliPath
            Task { await refresh() }
        }
    }

    private var timer: Timer?

    init() {
        snapshot = SharedStore.read()
        UsageProbe.overridePath = cliPath
        restartTimer()
        Task { await refresh() }
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(60, refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Spawning and waiting on the CLI must not block the menu.
        let fresh = await Task.detached(priority: .utility) {
            UsageProbe.snapshot()
        }.value

        snapshot = fresh
        try? SharedStore.write(fresh)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var resolvedCLIPath: String {
        UsageProbe.locateCLI()?.path ?? "not found"
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
