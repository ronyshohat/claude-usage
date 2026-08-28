import Foundation

/// Runs `claude -p "/usage"` and parses what comes back.
///
/// This is the authoritative source for the percentages: they come from the
/// server, and nothing on disk carries them. The call costs no tokens — it is a
/// quota lookup, not an inference request — and takes a second or two.
public enum UsageProbe {

    public enum ProbeError: Error, LocalizedError {
        case cliNotFound
        case timedOut
        case failed(status: Int32, message: String)
        case unrecognizedOutput(String)

        public var errorDescription: String? {
            switch self {
            case .cliNotFound:
                return "Could not find the claude CLI. Set its path in the menu."
            case .timedOut:
                return "claude -p \"/usage\" timed out."
            case let .failed(status, message):
                let detail = message.isEmpty ? "" : ": \(message)"
                return "claude exited with code \(status)\(detail)"
            case let .unrecognizedOutput(output):
                let head = output.split(separator: "\n").first.map(String.init) ?? "no output"
                return "Could not read the usage output (\(head))"
            }
        }
    }

    /// Set from the app when the user points at a non-standard install.
    public static var overridePath: String?

    // MARK: - Locating the CLI

    private static let candidates = [
        "~/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "~/.claude/local/claude",
        "/usr/bin/claude",
    ]

    public static func locateCLI() -> URL? {
        let fm = FileManager.default

        if let overridePath, !overridePath.isEmpty {
            let url = URL(fileURLWithPath: (overridePath as NSString).expandingTildeInPath)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }

        for candidate in candidates {
            let path = (candidate as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }

        // A GUI app inherits a bare PATH, so ask a login shell as a last resort.
        return askLoginShell()
    }

    private static func askLoginShell() -> URL? {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice

        guard (try? shell.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()

        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Scratch directory

    /// The probe runs in a directory of its own so the transcript it leaves
    /// behind is ours to delete, and never lands in a real project.
    ///
    /// No spaces, dots or underscores in the name: Claude Code derives the
    /// transcript folder from the path, and a plain name keeps that derivation
    /// predictable.
    static var scratchDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/ClaudeUsageProbe")
    }

    static var transcriptDirectory: URL {
        let encoded = scratchDirectory.path.replacingOccurrences(of: "/", with: "-")
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encoded)
    }

    /// Each probe writes a session transcript. Left alone that is ~300 files a
    /// day, so clear the ones we caused.
    static func pruneTranscripts() {
        let fm = FileManager.default
        let directory = transcriptDirectory

        // Only ever touch the folder our own scratch path maps to.
        let expected = scratchDirectory.path.replacingOccurrences(of: "/", with: "-")
        guard directory.lastPathComponent == expected,
              let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }

        for file in contents where file.pathExtension == "jsonl" {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Running

    public static func run(timeout: TimeInterval = 30) -> Result<[LimitGauge], ProbeError> {
        guard let cli = locateCLI() else { return .failure(.cliNotFound) }

        let fm = FileManager.default
        try? fm.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = cli
        process.arguments = ["-p", "/usage"]
        process.currentDirectoryURL = scratchDirectory

        // A login item starts with almost no PATH, and the CLI may need node.
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            cli.deletingLastPathComponent().path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        environment["HOME"] = NSHomeDirectory()
        process.environment = environment

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .failure(.failed(status: -1, message: error.localizedDescription))
        }

        // Set by the watchdog so a terminate() is distinguishable from the
        // process dying on its own.
        final class Flag: @unchecked Sendable { var tripped = false }
        let expired = Flag()

        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            expired.tripped = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Output is a couple of kilobytes, so draining both pipes before waiting
        // cannot deadlock.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let timedOut = expired.tripped

        defer { pruneTranscripts() }

        if timedOut { return .failure(.timedOut) }

        let output = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed(status: process.terminationStatus, message: message))
        }

        let gauges = UsageOutputParser.parse(output)
        guard !gauges.isEmpty else { return .failure(.unrecognizedOutput(output)) }
        return .success(gauges)
    }

    /// Convenience for the app: always returns a snapshot, carrying the error
    /// rather than throwing, so the widget can show why it is stale.
    public static func snapshot(timeout: TimeInterval = 30) -> UsageSnapshot {
        switch run(timeout: timeout) {
        case let .success(gauges):
            return UsageSnapshot(gauges: gauges)
        case let .failure(error):
            var snapshot = SharedStore.read() ?? UsageSnapshot()
            snapshot.failure = error.localizedDescription
            return snapshot
        }
    }
}
