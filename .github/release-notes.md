A menu bar app plus a Notification Center widget showing your Claude **session**
and **week** limits — percentage used and reset time for each.

### Install

The download is quarantined, and a quarantined app run from `~/Downloads` gets
translocated to a random read-only path, which stops the widget registering. So
unzip, clear the quarantine flag, and move it before launching:

```bash
unzip ClaudeUsage.zip
xattr -dr com.apple.quarantine ClaudeUsage.app
mv ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

Then right-click the desktop → **Edit Widgets**, search "Claude Usage", and drag
out the size you want.

### Notes

- Signed ad-hoc, so macOS will not recognise a developer. The `xattr` step above
  is what gets it past Gatekeeper.
- The widget only has data while the app is running — turn on **Launch at login**
  in the menu.
- Numbers come from `claude -p "/usage"`, so the `claude` CLI must be installed
  and logged in. The call costs no tokens.
- On a fresh install the widget may briefly show *No usage data*: its container
  does not exist until the extension has run once. It clears on the next refresh.
