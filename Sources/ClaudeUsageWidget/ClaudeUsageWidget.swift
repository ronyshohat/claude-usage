import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    /// True when the app has never written a snapshot, so the view can say so
    /// instead of quietly showing sample numbers.
    var isPlaceholder = false
}

struct UsageProvider: TimelineProvider {

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        Log.debug("widget", "snapshot requested for \(context.family)")
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // WidgetKit decides when to ask, and it rations reloads. A widget
        // showing older numbers than the menu is usually this: the app wrote a
        // fresh snapshot and was not asked to redraw for a while. The gap
        // between these lines is what shows it.
        Log.info("widget", "timeline requested for \(context.family)")

        // The companion app reloads us whenever it rescans. These extra entries
        // only keep the countdown honest if the app is asleep, so they reuse the
        // same snapshot with a moving clock.
        let entry = currentEntry()
        let steps = stride(from: 0, through: 55, by: 5).map { minutes in
            UsageEntry(
                date: entry.date.addingTimeInterval(TimeInterval(minutes) * 60),
                snapshot: entry.snapshot,
                isPlaceholder: entry.isPlaceholder
            )
        }
        completion(Timeline(entries: steps, policy: .atEnd))
    }

    private func currentEntry() -> UsageEntry {
        guard let snapshot = SharedStore.read() else {
            Log.warn("widget", "no snapshot to read. The app may not be running, or it cannot"
                + " write where this extension reads: \(SharedStore.sourceSummary())")
            return UsageEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
        }

        // The age is the number to compare against the menu's: the widget
        // drawing something older than the panel means the reload was rationed,
        // not that the probe failed.
        Log.info("widget", "read a snapshot generated \(Format.relative(snapshot.generatedAt)):"
            + " \(snapshot.logSummary)"
            + (snapshot.failure.map { ", carrying failure: \($0)" } ?? ""))
        return UsageEntry(date: Date(), snapshot: snapshot)
    }
}

struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Session and weekly limits, with the reset time for each.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}
