A menu bar app plus a Notification Center widget showing your Claude **session**
and **week** limits — percentage used and reset time for each.

### Install

From a clone of the repo:

```bash
./Tools/install.sh
```

Or directly:

```bash
gh release download --repo ronyshohat/claude-usage --pattern 'ClaudeUsage.zip'
ditto -xk ClaudeUsage.zip . && mv ClaudeUsage.app /Applications/ && open /Applications/ClaudeUsage.app
```

Downloading with `gh` (or `curl`) does **not** set `com.apple.quarantine`, so
Gatekeeper has nothing to object to and there is no `xattr` step.

<details>
<summary>If you downloaded the zip in a browser instead</summary>

Browsers do set the quarantine flag, and because this app is signed ad-hoc
rather than notarized, macOS will refuse to open it — *"Apple could not verify
ClaudeUsage is free of malware"*. Choose **Done**, never *Move to Trash*. Then
either:

```bash
xattr -dr com.apple.quarantine ~/Downloads/ClaudeUsage.app
mv ~/Downloads/ClaudeUsage.app /Applications/
```

or, without the terminal, open **System Settings → Privacy & Security** and
click **Open Anyway**.

Also move it out of `~/Downloads` before launching: a quarantined app run from
there gets translocated to a random read-only path, which stops the widget
registering.
</details>

### Notes

- The widget only has data while the app is running — turn on **Launch at login**
  in the menu.
- Numbers come from `claude -p "/usage"`, so the `claude` CLI must be installed
  and logged in. The call costs no tokens.
- Refreshes every minute by default; change it in Settings.
- On a fresh install the widget may briefly show *No usage data*: its container
  does not exist until the extension has run once. It clears on the next refresh.
