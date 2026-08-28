# Claude Usage

A macOS Notification Center widget showing your **current session** and
**current week** limits — percentage used and reset time for each.

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
  gauges found" as an error rather than zero, and is covered by CI against a
  fixture holding both reset shapes (`9:20pm` and the hour-only `5pm`).
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

## Building in CI

`.github/workflows/build.yml` has two jobs:

- **core** — compiles the parser with the Command Line Tools and runs it against
  the fixture, asserting both percentages, the label, both reset formats, and
  that each reset parsed to a real date. It also checks that unparseable input
  is rejected rather than silently yielding nothing. It cannot run the live
  probe: the runner has no `claude` and no credentials.
- **app** — `xcodegen` + `xcodebuild`, verifies the widget extension was
  actually embedded with the right extension point, and uploads `ClaudeUsage.zip`.

CI signs ad-hoc, the same as a local build.

**Every push to `main` publishes a release** tagged `v1.0.<run number>` with
`ClaudeUsage.zip` attached, so there is always a current build to download from
the Releases page. Pull requests build and upload an artifact but do not
release. The build is stamped with the same version, so an installed copy
reports which run produced it.

### Installing a CI build

A downloaded app is quarantined, and a quarantined app run from `~/Downloads`
gets translocated to a random read-only path, which stops the widget
registering:

```bash
unzip ClaudeUsage.zip && xattr -dr com.apple.quarantine ClaudeUsage.app && mv ClaudeUsage.app /Applications/
```

macOS runners bill at 10× minutes on private repos; free on public ones.

## Layout

| Path | |
|---|---|
| `Sources/ClaudeUsageCore/UsageProbe.swift` | Finds the CLI, runs it, prunes its transcripts. |
| `Sources/ClaudeUsageCore/UsageOutputParser.swift` | Turns the printed report into gauges. |
| `Sources/ClaudeUsageCore/SharedStore.swift` | Snapshot transport between app and widget. |
| `Sources/ClaudeUsageApp/` | Menu bar agent, refresh loop, settings. |
| `Sources/ClaudeUsageWidget/` | Timeline provider and the small/medium/large views. |
| `Tools/` | CLI harness, fixture, project generator. |
| `Tools/icon/` | The app icon, drawn in CoreGraphics. |
