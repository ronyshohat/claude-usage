import Foundation
import OSLog

/// A written record of every refresh: what ran, what came back, and whether it
/// differed from last time.
///
/// The panel cannot answer the question people actually ask about this app.
/// "The numbers are stale but it says it updated seconds ago" has at least five
/// causes that look identical from the outside — the timer never fired, the CLI
/// was not found, the probe failed and the last good snapshot was kept, the
/// snapshot could not be written where the widget reads, or `/usage` genuinely
/// returned the same report again — and by the time anyone notices, the moment
/// that would have told them apart is long gone. So the log is kept always,
/// not switched on after the fact.
///
/// Two destinations, because they answer different questions:
///
/// - A **file**, which survives the app quitting and can be attached to a bug.
/// - **Unified logging**, for watching a refresh happen live with `log stream`.
///
/// The app is unsandboxed and its file lands in `~/Library/Logs/ClaudeUsage`.
/// A widget extension is always sandboxed, so the very same code resolves to
/// its own container instead. Hence one file per process, named for it, and
/// `Tools/logs.sh` to follow both at once.
public enum Log {

    public static let subsystem = "com.claudeusage.ClaudeUsage"

    public enum Level: Int, Sendable, Comparable {
        case debug = 0, info, warn, error

        /// Padded so the columns line up in a file nobody is going to open in
        /// anything cleverer than `less`.
        fileprivate var tag: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO "
            case .warn: return "WARN "
            case .error: return "ERROR"
            }
        }

        fileprivate var osType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            // .default is the level that survives in the unified log store
            // long enough to be worth looking for.
            case .warn: return .default
            case .error: return .error
            }
        }

        public init?(name: String) {
            switch name.lowercased() {
            case "debug", "verbose", "all": self = .debug
            case "info": self = .info
            case "warn", "warning": self = .warn
            case "error": self = .error
            default: return nil
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Level

    /// Lines below this are dropped. Debug carries the raw CLI output, which is
    /// nearly all of the volume and only interesting when the parse itself is
    /// in question, so it is off unless asked for.
    public static var minimumLevel: Level = {
        if let name = ProcessInfo.processInfo.environment["CLAUDE_USAGE_LOG_LEVEL"],
           let level = Level(name: name) {
            return level
        }
        return UserDefaults.standard.bool(forKey: verboseKey) ? .debug : .info
    }()

    /// The app's *Verbose logging* checkbox. The widget reads a different
    /// defaults domain — it is sandboxed — so the checkbox does not reach it;
    /// `CLAUDE_USAGE_LOG_LEVEL=debug` is the way in there.
    public static let verboseKey = "verboseLogging"

    /// Ignored when `CLAUDE_USAGE_LOG_LEVEL` is set, so an explicit override is
    /// not quietly undone by whatever the checkbox was last left on.
    public static func setVerbose(_ on: Bool) {
        guard ProcessInfo.processInfo.environment["CLAUDE_USAGE_LOG_LEVEL"] == nil else { return }
        minimumLevel = on ? .debug : .info
    }

    // MARK: - Destination

    /// `Logs` inside whatever Library this process can see: the real one for
    /// the unsandboxed app, the container's for the widget extension.
    public static var directory: URL {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/ClaudeUsage")
    }

    /// One file per process. The app and the widget can never share a
    /// directory, and naming each file after its writer keeps a pair of logs
    /// read side by side from being mistaken for one another.
    public static var fileURL: URL {
        directory.appendingPathComponent("\(processName).log")
    }

    /// The previous file. One rotation is kept, which at the default refresh
    /// covers a couple of days — long enough to still hold the refresh that
    /// went wrong when someone gets round to looking.
    public static var rotatedFileURL: URL {
        directory.appendingPathComponent("\(processName).log.1")
    }

    private static let maxBytes = 2 * 1024 * 1024

    /// "ClaudeUsage", "ClaudeUsageWidget", "claude-usage-cli".
    public static let processName: String = {
        let name = ProcessInfo.processInfo.processName
        return name.isEmpty ? "ClaudeUsage" : name
    }()

    /// The column in the file, so a log pasted into an issue says which side
    /// of the app it came from without needing its filename.
    private static let processColumn: String = {
        let short = processName.hasSuffix("Widget") ? "widget" : "app"
        return processName.hasPrefix("ClaudeUsage") ? short : processName
    }()

    /// Off inside a test run, which has no business leaving files in
    /// `~/Library`, and off entirely for `CLAUDE_USAGE_LOG=0`.
    ///
    /// Both checks are needed: XCTest announces itself in the environment,
    /// while swift-testing runs the suite under `swiftpm-testing-helper` and
    /// sets none of those variables — so the process name is the only tell.
    private static let fileLoggingEnabled: Bool = {
        let environment = ProcessInfo.processInfo.environment
        let testVariables = [
            "XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier",
        ]
        if testVariables.contains(where: { environment[$0] != nil }) { return false }
        if processName.contains("xctest") || processName.contains("testing-helper") {
            return false
        }
        if let flag = environment["CLAUDE_USAGE_LOG"]?.lowercased(),
           flag == "0" || flag == "off" || flag == "no" {
            return false
        }
        return true
    }()

    // MARK: - Writing

    public static func debug(_ category: String, _ message: @autoclosure () -> String) {
        emit(.debug, category, message)
    }

    public static func info(_ category: String, _ message: @autoclosure () -> String) {
        emit(.info, category, message)
    }

    public static func warn(_ category: String, _ message: @autoclosure () -> String) {
        emit(.warn, category, message)
    }

    public static func error(_ category: String, _ message: @autoclosure () -> String) {
        emit(.error, category, message)
    }

    /// The message is built lazily: a filtered debug line that would have
    /// interpolated a few kilobytes of CLI output costs nothing.
    private static func emit(_ level: Level, _ category: String, _ message: () -> String) {
        guard level >= minimumLevel else { return }
        let text = message()

        // .public because none of this is private data — percentages, paths and
        // exit codes — and redacted placeholders would make the stream useless.
        logger(for: category).log(level: level.osType, "\(text, privacy: .public)")

        guard fileLoggingEnabled else { return }
        append(
            "\(timestamp.string(from: Date()))  "
                + "\(processColumn.padded(to: 6))  \(level.tag)  "
                + "\(category.padded(to: 6))  \(text)\n"
        )
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let lock = NSLock()
    private static var handle: FileHandle?
    private static var loggers: [String: Logger] = [:]

    private static func logger(for category: String) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[category] { return existing }
        let made = Logger(subsystem: subsystem, category: category)
        loggers[category] = made
        return made
    }

    /// Appends under a lock, and holds the handle open: at a line a second this
    /// is on the refresh path, and reopening the file each time would be the
    /// most expensive thing the probe does apart from the probe.
    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }

        rotateIfNeeded()
        if handle == nil { handle = openFile() }
        guard let handle else { return }
        try? handle.write(contentsOf: data)
    }

    private static func openFile() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }

    private static func rotateIfNeeded() {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maxBytes
        else { return }

        try? handle?.close()
        handle = nil

        let fm = FileManager.default
        try? fm.removeItem(at: rotatedFileURL)
        try? fm.moveItem(at: fileURL, to: rotatedFileURL)
    }

    // MARK: - Helpers

    /// A short, stable fingerprint of the CLI's output (FNV-1a).
    ///
    /// `/usage` prints live request counts below the gauges, so two honest
    /// probes a minute apart practically never match. That is what makes an
    /// *unchanged* digest worth logging: it means the CLI handed back a
    /// byte-identical report, which is a cached answer rather than a fresh one.
    /// A changed digest says nothing about whether the percentages moved — the
    /// `gauges unchanged`/`gauges changed` line is what answers that.
    public static func digest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    /// Where this process is logging, for the banner and the Settings pane.
    public static var locationSummary: String {
        fileLoggingEnabled ? fileURL.path : "disabled"
    }
}

private extension String {
    /// Pads short, never truncates: a category longer than the column is worth
    /// more than the alignment is.
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
