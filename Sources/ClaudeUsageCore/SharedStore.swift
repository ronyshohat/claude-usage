import Foundation

/// Hands the snapshot from the (unsandboxed) app to the (sandboxed) widget.
///
/// A macOS widget extension always runs sandboxed, so it cannot read
/// `~/.claude` itself. The app scans and drops the result somewhere both sides
/// can reach.
///
/// Two transports, tried in order:
///
/// 1. An App Group container — the tidy way, but the entitlement is only
///    honoured when the bundle is signed with a real team ID.
/// 2. The widget extension's own sandbox container. The app is unsandboxed so
///    it can write there, and a sandboxed extension may always read its own
///    container. This needs no team and no entitlement, which makes it the
///    path that works with plain local signing.
public enum SharedStore {

    private static func infoString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// Nil unless you have a paid team and have opted in, because
    /// `com.apple.security.application-groups` is a restricted entitlement that
    /// will not ad-hoc sign. See README for turning it on.
    /// macOS wants the team prefix, e.g. `ABCDE12345.group.com.you.claudeusage`.
    public static var appGroupID: String? {
        guard let value = infoString("ClaudeUsageAppGroup"), !value.isEmpty else { return nil }
        return value
    }

    /// Set on the app so it knows where the widget's container lives.
    public static var widgetBundleID: String {
        infoString("ClaudeUsageWidgetBundleID") ?? "com.claudeusage.ClaudeUsage.Widget"
    }

    private static let folderName = "ClaudeUsage"

    public enum StoreError: Error, LocalizedError {
        case noWritableLocation

        public var errorDescription: String? {
            "Could not write the snapshot anywhere the widget can read it."
        }
    }

    // MARK: - Locations

    /// The App Group container, if one is configured and the entitlement is
    /// actually in force.
    private static func groupContainer() -> URL? {
        let fm = FileManager.default
        guard let identifier = appGroupID,
              let url = fm.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return fm.isWritableFile(atPath: url.path) ? url : nil
    }

    /// Application Support for whoever is asking. Inside the widget's sandbox
    /// this resolves to its own container, which is the point.
    private static func localSupport() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let url = base.appendingPathComponent(folderName)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return fm.isWritableFile(atPath: url.path) ? url : nil
    }

    /// The widget's sandbox container, addressed from outside the sandbox.
    private static func widgetContainer() -> URL? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(widgetBundleID)
            .appendingPathComponent("Data/Library/Application Support")
            .appendingPathComponent(folderName)
        // Only meaningful once the widget has run at least once and the system
        // has made its container.
        guard fm.fileExists(atPath: containerRoot(for: widgetBundleID).path) else { return nil }
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return fm.isWritableFile(atPath: url.path) ? url : nil
    }

    private static func containerRoot(for bundleID: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(bundleID)
    }

    /// Everywhere the app should write. Writing to all of them costs a few
    /// kilobytes and removes a whole class of "widget shows nothing" bugs.
    public static func writeDestinations() -> [URL] {
        [groupContainer(), widgetContainer(), localSupport()].compactMap { $0 }
    }

    /// Everywhere the widget should look, best first.
    public static func readSources() -> [URL] {
        [groupContainer(), localSupport()].compactMap { $0 }
    }

    // MARK: - Coding

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

    private static func writeAll(_ data: Data, named name: String) throws {
        let destinations = writeDestinations()
        guard !destinations.isEmpty else {
            let root = containerRoot(for: widgetBundleID)
            Log.error("store", "nowhere to write \(name). appGroup=\(appGroupID ?? "off"),"
                + " widget container \(root.path)"
                + " exists=\(FileManager.default.fileExists(atPath: root.path))."
                + " The widget will keep showing whatever it last read")
            throw StoreError.noWritableLocation
        }

        var wrote: [String] = []
        var failed: [String] = []
        for directory in destinations {
            let url = directory.appendingPathComponent(name)
            do {
                // Atomic so the widget never reads a half-written file.
                try data.write(to: url, options: .atomic)
                wrote.append(url.path)
            } catch {
                failed.append("\(url.path) (\(error.localizedDescription))")
            }
        }

        // A partial write is the shape of "the menu is right and the widget is
        // stale", so name the destination that refused rather than only the
        // ones that worked.
        if !failed.isEmpty {
            Log.error("store", "could not write \(name) to \(failed.joined(separator: "; "))")
        }
        guard !wrote.isEmpty else { throw StoreError.noWritableLocation }
        Log.info("store", "wrote \(data.count)B to \(wrote.count) location(s):"
            + " \(wrote.joined(separator: ", "))")
    }

    private static func readFirst<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        let sources = readSources()
        guard !sources.isEmpty else {
            Log.warn("store", "no readable location for \(name) at all")
            return nil
        }

        for directory in sources {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                Log.debug("store", "no \(name) at \(url.path)")
                continue
            }
            do {
                let value = try decoder.decode(type, from: data)
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                Log.debug("store", "read \(data.count)B from \(url.path),"
                    + " written \(modified.map { Format.relative($0) } ?? "at an unknown time")")
                return value
            } catch {
                // A file that will not decode is skipped in favour of the next
                // source, which is exactly how a stale copy outlives a fresh
                // one. Never silently.
                Log.error("store", "\(url.path) exists but will not decode:"
                    + " \(error.localizedDescription). Delete it if this persists")
            }
        }

        Log.debug("store", "nothing readable named \(name) in"
            + " \(sources.map(\.path).joined(separator: ", "))")
        return nil
    }

    // MARK: - API

    public static func write(_ snapshot: UsageSnapshot) throws {
        try writeAll(encoder.encode(snapshot), named: "snapshot.json")
    }

    public static func read() -> UsageSnapshot? {
        readFirst(UsageSnapshot.self, named: "snapshot.json")
    }

    /// Human-readable list for the app's diagnostics.
    public static func destinationSummary() -> String {
        let paths = writeDestinations().map { $0.path }
        return paths.isEmpty ? "none" : paths.joined(separator: "\n")
    }

    /// Where this process would read from, for the launch banner. The app and
    /// the widget resolve `localSupport()` to different directories, so a log
    /// that does not say which is missing the fact that matters most.
    public static func sourceSummary() -> String {
        let paths = readSources().map { $0.path }
        return paths.isEmpty ? "none" : paths.joined(separator: ", ")
    }
}
