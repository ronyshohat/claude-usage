# Claude Usage

A macOS Notification Center widget showing your **current session** and
**current week** limits — percentage used and reset time for each.

<img src="docs/menu-bar.png" width="420"
     alt="The menu bar item open, showing a session gauge at 28% and a week gauge at 7%, each with its reset time and time remaining">

The menu bar carries the same two numbers and is where the app is driven from:
refresh, settings, quit. On the desktop the widget shows them side by side:

```
SESSION                 53%          WEEK                    27%
██████████████░░░░░░░░░░             ██████░░░░░░░░░░░░░░░░░░
resets 9:19pm · 1h 24m left          resets Aug 29 at 4:59pm
```

## Where the numbers come from

From `claude -p "/usage"`, which is the same thing `/usage` shows inside a
session:

```
Current session: 48% used · resets Aug 28 at 9:20pm (Europe/London)
Current week (all models): 27% used · resets Aug 29 at 5pm (Europe/London)
```

Those percentages come from the server and exist nowhere on disk. They cost
**$0.0000 and 0 tokens** to fetch — it is a quota lookup, not an inference
request — and the call takes about two seconds.

> An earlier version of this computed everything from the transcripts in
> `~/.claude/projects` and reconstructed the 5-hour window locally. That is
> worth avoiding: the local files can only give you token counts, there is no
> published ceiling to turn those into a percentage, and the reconstructed reset
> time was consistently a few minutes off the real one.

## How it works

```
claude -p "/usage"   ← ~2s, 0 tokens, needs network
        │
        ▼
ClaudeUsage.app  (menu bar agent, NOT sandboxed — it spawns a process)
        │
        │  snapshot.json → widget's container
        ▼
ClaudeUsageWidget.appex  (sandboxed, as macOS requires)
```

A widget extension is sandboxed and cannot spawn processes, so the app does the
fetching on a timer, writes a small JSON snapshot, and calls
`WidgetCenter.reloadAllTimelines()`. **The widget only has data while the app is
running**, so turn on *Launch at login* in the menu.

The snapshot travels through the **widget's own sandbox container**, at
`~/Library/Containers/<widget-id>/Data/…`. A sandboxed extension may always read
its own container, and the unsandboxed app can write into it — no entitlement,
no certificate, no team. An App Group would be tidier and `SharedStore` prefers
one when configured, but it is off by default: `application-groups` is a
restricted entitlement that will not ad-hoc sign, and a free Apple ID cannot
provision it. See *Signing*.

### The probe cleans up after itself

Every `claude -p` invocation writes a session transcript. At the default
one-minute refresh that would be ~1,400 files a day, so the probe runs with its
working directory set to `~/Library/ClaudeUsageProbe` and deletes the
transcripts that land in the matching `~/.claude/projects` folder. It only ever touches the
folder its own scratch path maps to, so real project transcripts are never at
risk.

## What can go wrong

- **The output format is human-readable text, not an API.** Parsing it is the
  fragile part of this project, so `UsageOutputParser` is lenient, treats "no
  gauges found" as an error rather than zero, and is covered by tests against
  fixtures holding both reset shapes (`9:20pm` and the hour-only `5pm`).
- **A limit at zero comes back thin.** With nothing spent against it, `/usage`
  prints `Current session: 0% used` with no reset clause, and sometimes leaves
  the line out altogether. Both are read as a real zero: the gauge stays on the
  widget at 0% with "nothing used yet" where the reset would be. A limit is only
  filled in this way when the rest of the report parsed, so a login prompt or a
  changed format still surfaces as an error rather than a confident pair of
  zeroes.
- **No network** means the fetch fails. The widget keeps showing the last known
  values with a warning badge rather than presenting them as current, and shows
  a clock badge if the app has been quiet for over 30 minutes.
- **The CLI has to be findable.** A login item starts with almost no `PATH`, so
  the probe checks the usual install locations and falls back to asking a login
  shell. If yours lives somewhere unusual, set the path in Settings.
- **`/usage` percentages are account-wide**, but the contribution breakdown the
  CLI prints below them is local-only. This widget shows the percentages, which
  do include your other devices.

## Setup

Requires **Xcode** — widget extensions cannot be built with Command Line Tools
alone.

```bash
brew install xcodegen && ./Tools/generate-project.sh && open ClaudeUsage.xcodeproj
```

Select the **ClaudeUsage** scheme and Run. The menu bar item appears. Then
right-click the desktop → **Edit Widgets**, search "Claude Usage", and drag out
the size you want.

On a completely fresh install the widget may briefly show *No usage data*: its
container does not exist until the extension has run once, so the app cannot
write there until then. It clears on the next refresh.

### Signing

Configured for **"Sign to Run Locally"** (`CODE_SIGN_IDENTITY = "-"`, no team),
which builds with no developer account. Neither target requests a restricted
entitlement: the app is unsandboxed and carries no entitlements file at all, and
the widget's only entitlement is `com.apple.security.app-sandbox`.

With a **paid** team you can switch to the App Group transport: set `APP_GROUP`
in `project.yml` to `<TEAMID>.group.com.claudeusage.shared`, add
`com.apple.security.application-groups` to the widget's entitlements and a
matching entitlements file for the app, then set `CODE_SIGN_STYLE: Automatic`
and your `DEVELOPMENT_TEAM`. A free Apple ID will not work for this.

## The icon

Two nested gauge arcs on clay — the widget's own idea at app-icon scale. It is
drawn in CoreGraphics rather than checked in as an opaque binary, so it can be
edited:

```bash
./Tools/icon/build-icon.sh
```

That renders all ten `.iconset` sizes from `Tools/icon/makeicon.swift` and runs
`iconutil` to produce `Sources/ClaudeUsageApp/Resources/AppIcon.icns`. The
generated `.icns` is committed, so a normal build needs no extra step.

## Tests

`ClaudeUsageCore` has a test target that runs with the Command Line Tools — no
Xcode, no project generation:

```bash
swift test
```

`Package.swift` exists only for this. It compiles `Sources/ClaudeUsageCore`
where it already lives, so there is no second copy of the sources; the app and
the widget are still built from `ClaudeUsage.xcodeproj` (see `project.yml`), and
neither XcodeGen nor `xcodebuild` reads that file.

The tests in `Tests/CoreTests` cover parsing a report, both reset formats, a
limit at zero in both of the shapes it arrives in, the line the widget renders
under each gauge, and the encoding the app and widget agree on. They read the
same `Tools/fixtures/` transcripts the harness below parses, and they pin both
the clock and the timezone in-process, so they give the same result whatever
your machine is set to.

## Checking it without Xcode

`Tools/verify.sh` builds `ClaudeUsageCore` with the Command Line Tools and runs
the real probe:

```bash
./Tools/verify.sh
```

```
locating claude…
  /Users/you/.local/bin/claude
running claude -p "/usage"…
  ok in 2.0s

  Session  53   #############...........  resets Aug 28 at 9:19pm (1h 24m)
  Week     27   ######..................  resets Aug 29 at 4:59pm (21h 4m)

leftover probe transcripts: 0
```

To exercise the parser without calling the CLI:

```bash
./Tools/verify.sh --parse Tools/fixtures/usage-output.txt
```

`Tools/fixtures/` also holds the shapes a limit at zero arrives in:
`usage-output-zero.txt` (no reset clause) and `usage-output-missing-session.txt`
(no line at all).

A fixture carries dates but no year, so whether its reset reads as same-day or a
year out depends on the day you run it. Add `--now` to pin the clock, and set
`TZ` so the printed times are reproducible:

```bash
TZ=UTC ./Tools/verify.sh --parse Tools/fixtures/usage-output.txt \
  --now 2026-08-28T20:00:00Z
```

## Building in CI

`.github/workflows/build.yml` has two jobs:

- **core** — runs `swift test` (see [Tests](#tests)), then smoke-tests
  `Tools/verify.sh` itself: it must parse a fixture and must still reject output
  it cannot make sense of. Neither step can run the live probe — the runner has
  no `claude` and no credentials.
- **app** — `xcodegen` + `xcodebuild`, verifies the widget extension was
  actually embedded with the right extension point, and uploads `ClaudeUsage.zip`.

CI signs ad-hoc, the same as a local build.

**Every push to `main` publishes a release** with `ClaudeUsage.zip` attached, so
there is always a current build to download from the Releases page. Pull
requests build and upload an artifact but do not release. The tag is one patch
past the last release — `v1.0.4`, `v1.0.5`, `v1.0.6` — rather than the workflow
run number, which pull request runs also consume and would leave gaps in. The
build is stamped with the same version, and **Settings** in the menu shows it,
so an installed copy says which release it came from.

### Installing a release

```bash
./Tools/install.sh
```

`com.apple.quarantine` is set by whatever *downloads* a file, not by the app
being unsigned. `gh` and `curl` do not set it; browsers do. So installing from
the terminal sidesteps Gatekeeper entirely — the installer downloads with `gh`,
swaps the bundle in `/Applications`, re-registers it with Launch Services and
relaunches, and never needs `xattr`.

If you download the zip in a browser you will get *"Apple could not verify
ClaudeUsage is free of malware"* — choose **Done**, not *Move to Trash* — and
you will need either `xattr -dr com.apple.quarantine ClaudeUsage.app` or
**System Settings → Privacy & Security → Open Anyway**. Move it out of
`~/Downloads` before launching, too: a quarantined app run from there is
translocated to a random read-only path, which stops the widget registering.

The only way to make a browser download open with no friction at all is to
**notarize**, which needs a paid Apple Developer account and a Developer ID
certificate. Nothing short of that satisfies Gatekeeper for a browser download.

macOS runners bill at 10× minutes on private repos; free on public ones.

## Layout

| Path | |
|---|---|
| `Sources/ClaudeUsageCore/UsageProbe.swift` | Finds the CLI, runs it, prunes its transcripts. |
| `Sources/ClaudeUsageCore/UsageOutputParser.swift` | Turns the printed report into gauges. |
| `Sources/ClaudeUsageCore/SharedStore.swift` | Snapshot transport between app and widget. |
| `Sources/ClaudeUsageApp/` | Menu bar agent, refresh loop, settings. |
| `Sources/ClaudeUsageWidget/` | Timeline provider and the small/medium/large views. |
| `Tests/CoreTests/` | Parser, reset-line, formatting and snapshot tests. |
| `Package.swift` | Test-only package, so `swift test` works without Xcode. |
| `Tools/` | CLI harness, fixtures, installer, project generator. |
| `Tools/icon/` | The app icon, drawn in CoreGraphics. |
