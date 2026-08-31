import SwiftUI
import WidgetKit

enum Palette {
    /// Green with room to spare, amber when it is worth noticing, red near the cap.
    static func tint(for percent: Int) -> Color {
        switch percent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }
}

/// Font sizes per widget family. The previous layout tried to fit five numbers
/// into a medium widget and clipped; these are sized so nothing truncates.
struct Metrics {
    var label: CGFloat
    var percent: CGFloat
    var reset: CGFloat
    var bar: CGFloat
    var spacing: CGFloat

    static let small = Metrics(label: 9, percent: 30, reset: 10, bar: 7, spacing: 5)
    static let medium = Metrics(label: 11, percent: 42, reset: 12, bar: 9, spacing: 7)
    static let large = Metrics(label: 13, percent: 56, reset: 14, bar: 11, spacing: 10)
}

/// One limit: name, percentage, bar, reset time.
struct GaugeBlock: View {
    let gauge: LimitGauge
    let now: Date
    let metrics: Metrics
    var showCountdown = true

    private var tint: Color { Palette.tint(for: gauge.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.shortLabel.uppercased())
                    .font(.system(size: metrics.label, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(gauge.percent)%")
                    .font(.system(size: metrics.percent, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    // The 3pt floor keeps 1% visible; a true zero gets an empty
                    // track rather than a sliver that reads as "some".
                    if gauge.percent > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(geo.size.width * gauge.fraction, 3))
                    }
                }
            }
            .frame(height: metrics.bar)

            Text(gauge.resetLine(at: now, includeCountdown: showCountdown))
                .font(.system(size: metrics.reset))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var metrics: Metrics {
        switch family {
        case .systemSmall: return .small
        case .systemLarge: return .large
        default: return .medium
        }
    }

    private var gauges: [LimitGauge] {
        [entry.snapshot.session, entry.snapshot.week].compactMap { $0 }
    }

    /// The small widget has room for a countdown only when the reset needs no
    /// date alongside it — which in practice means the session, not the week.
    private func showsCountdown(for gauge: LimitGauge) -> Bool {
        family != .systemSmall || gauge.resetsToday(at: entry.date)
    }

    var body: some View {
        Group {
            if gauges.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 14 : 22) {
                    ForEach(gauges) { gauge in
                        GaugeBlock(
                            gauge: gauge,
                            now: entry.date,
                            metrics: metrics,
                            showCountdown: showsCountdown(for: gauge)
                        )
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .overlay(alignment: .topTrailing) { statusBadge }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No usage data")
                .font(.system(size: metrics.reset + 2, weight: .medium))
            Text(entry.snapshot.failure ?? "Open ClaudeUsage to fetch it.")
                .font(.system(size: metrics.reset))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Percentages that stopped updating are worse than no percentages, so say
    /// when the last fetch failed or the app went quiet.
    @ViewBuilder private var statusBadge: some View {
        if entry.snapshot.failure != nil, !gauges.isEmpty {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        } else if entry.date.timeIntervalSince(entry.snapshot.generatedAt) > 1_800 {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
