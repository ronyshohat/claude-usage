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
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
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
            return UsageEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
        }
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
