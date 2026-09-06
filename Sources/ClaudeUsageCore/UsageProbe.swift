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
        // Debug, not info: the settings pane re-resolves this on every
        // keystroke, and `run` logs the path it settled on once per cycle.
        let fm = FileManager.default

        if let overridePath, !overridePath.isEmpty {
            let url = URL(fileURLWithPath: (overridePath as NSString).expandingTildeInPath)
            if fm.isExecutableFile(atPath: url.path) {
                Log.debug("probe", "cli from the configured override: \(url.path)")
                return url
            }
            Log.debug("probe", "override \(url.path) is not executable, falling through")
        }

        for candidate in candidates {
            let path = (candidate as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: path) {
                Log.debug("probe", "cli found at \(path)")
                return URL(fileURLWithPath: path)
            }
        }

        // A GUI app inherits a bare PATH, so ask a login shell as a last resort.
        Log.debug("probe", "no candidate path matched, asking a login shell")
        let found = askLoginShell()
        Log.debug("probe", "login shell returned \(found?.path ?? "nothing")")
        return found
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

    /// Each probe writes a session transcript. At the default one-minute
    /// interval that is ~1,400 files a day, so clear the ones we caused.
    static func pruneTranscripts() {
        let fm = FileManager.default
        let directory = transcriptDirectory

        // Only ever touch the folder our own scratch path maps to.
        let expected = scratchDirectory.path.replacingOccurrences(of: "/", with: "-")
        guard directory.lastPathComponent == expected else {
            Log.warn("probe", "not pruning \(directory.path): it is not the folder our scratch"
                + " path maps to (expected \(expected))")
            return
        }
        guard let contents = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else {
            Log.debug("probe", "no transcript folder at \(directory.path) yet")
            return
        }

        var removed = 0
        var failed = 0
        for file in contents where file.pathExtension == "jsonl" {
            if (try? fm.removeItem(at: file)) != nil { removed += 1 } else { failed += 1 }
        }
        // A folder that keeps growing means the probe is leaving a transcript a
        // day per minute of uptime behind it, which is worth seeing.
        if removed > 0 || failed > 0 {
            Log.debug("probe", "pruned \(removed) probe transcript(s), \(failed) would not delete")
        }
    }

    // MARK: - Running

    public static func run(timeout: TimeInterval = 30) -> Result<[LimitGauge], ProbeError> {
        guard let cli = locateCLI() else {
            Log.error("probe", "claude CLI not found. override=\(overridePath ?? "none");"
                + " tried \(candidates.joined(separator: ", ")) and a login shell")
            return .failure(.cliNotFound)
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        let started = Date()
        Log.info("probe", "running \(cli.path) -p \"/usage\" in \(scratchDirectory.path),"
            + " timeout \(Int(timeout))s")

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
            Log.error("probe", "could not launch \(cli.path): \(error.localizedDescription)")
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
        let took = Format.elapsed(Date().timeIntervalSince(started))

        defer { pruneTranscripts() }

        if timedOut {
            Log.error("probe", "timed out after \(Int(timeout))s and was terminated."
                + " The panel will keep the last good numbers")
            return .failure(.timedOut)
        }

        let output = String(decoding: outData, as: UTF8.self)
        let errorText = String(decoding: errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // The report carries live request counts, so the digest changes on
        // nearly every honest call. It earns its place by the case where it
        // does not: identical bytes mean a cached answer.
        Log.info("probe", "exit \(process.terminationStatus) in \(took),"
            + " stdout \(outData.count)B digest \(Log.digest(output)),"
            + " stderr \(errData.count)B")
        Log.debug("probe", "stdout:\n\(output)")
        if !errorText.isEmpty { Log.debug("probe", "stderr:\n\(errorText)") }

        guard process.terminationStatus == 0 else {
            Log.error("probe", "claude exited \(process.terminationStatus):"
                + " \(errorText.isEmpty ? "(nothing on stderr)" : errorText)")
            return .failure(.failed(status: process.terminationStatus, message: errorText))
        }

        let gauges = UsageOutputParser.parse(output)
        guard !gauges.isEmpty else {
            // Logged in full regardless of level: this is the format having
            // changed, or a login prompt, and the output is the whole evidence.
            Log.error("probe", "nothing recognisable in \(outData.count)B of output"
                + " — the report format may have changed. Raw output:\n\(output)")
            return .failure(.unrecognizedOutput(output))
        }

        Log.info("probe", "parsed \(gauges.count) gauge(s) in \(took): \(gauges.logSummary)")
        return .success(gauges)
    }

    /// Convenience for the app: always returns a snapshot, carrying the error
    /// rather than throwing, so the widget can show why it is stale.
    public static func snapshot(timeout: TimeInterval = 30) -> UsageSnapshot {
        switch run(timeout: timeout) {
        case let .success(gauges):
            return UsageSnapshot(gauges: gauges)
        case let .failure(error):
            let stored = SharedStore.read()
            var snapshot = stored ?? UsageSnapshot()
            snapshot.failure = error.localizedDescription
            if let stored {
                // The one case where a fresh-looking panel is showing old
                // numbers on purpose — say how old, in the log as well as
                // in the warning badge.
                Log.warn("probe", "probe failed (\(error.localizedDescription)); keeping the"
                    + " snapshot stored \(Format.relative(stored.generatedAt)):"
                    + " \(stored.logSummary)")
            } else {
                Log.warn("probe", "probe failed (\(error.localizedDescription)) with no stored"
                    + " snapshot to fall back on")
            }
            return snapshot
        }
    }
}
