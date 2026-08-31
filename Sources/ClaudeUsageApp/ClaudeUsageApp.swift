import ServiceManagement
import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .frame(width: 290)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: gaugeSymbol)
                Text(model.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var gaugeSymbol: String {
        switch model.worstPercent {
        case ..<34: return "gauge.with.dots.needle.0percent"
        case ..<67: return "gauge.with.dots.needle.50percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: UsageModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = model.snapshot, !snapshot.gauges.isEmpty {
                ForEach(snapshot.gauges) { gauge in
                    GaugeRow(gauge: gauge)
                }
            } else {
                Text("No data yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let failure = model.snapshot?.failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            controls

            if showingSettings {
                Divider()
                settings
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            Text("Claude Usage").font(.headline)
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let generated = model.snapshot?.generatedAt {
                Text(Format.relative(generated))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button("Refresh") { Task { await model.refresh() } }
            Button(showingSettings ? "Done" : "Settings") { showingSettings.toggle() }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.caption)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        enabled
                            ? try SMAppService.mainApp.register()
                            : try SMAppService.mainApp.unregister()
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            HStack {
                Text("Refresh every").font(.caption)
                Picker("", selection: $model.refreshSeconds) {
                    Text("1 min").tag(60)
                    Text("5 min").tag(300)
                    Text("15 min").tag(900)
                    Text("30 min").tag(1800)
                }
                .labelsHidden()
                .frame(width: 90)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("claude CLI").font(.caption)
                TextField("auto-detect", text: $model.cliPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                Text(model.resolvedCLIPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            // Releases are tagged v1.0.<patch> and the bundle carries the
            // same string, so this says which release the copy came from.
            Text("Version \(bundleVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        return Format.version(
            short: info?["CFBundleShortVersionString"] as? String ?? "",
            build: info?["CFBundleVersion"] as? String ?? ""
        )
    }
}

/// Same information as the widget, laid out for the menu.
struct GaugeRow: View {
    let gauge: LimitGauge

    private var tint: Color {
        switch gauge.percent {
        case ..<60: return .green
        case ..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.label.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(gauge.percent)%")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
            }

            ProgressView(value: gauge.fraction).tint(tint)

            Text(gauge.resetLine())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
