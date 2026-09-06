#!/bin/bash
# Follows both logs at once.
#
# The app is unsandboxed and writes to ~/Library/Logs; the widget extension is
# sandboxed and the same code lands inside its container. Two files that can
# never be one, so this tails both.
#
#   Tools/logs.sh            follow both, after the last 40 lines of each
#   Tools/logs.sh --paths    just print where they are
#   Tools/logs.sh --stream   follow unified logging instead, live, no files
set -euo pipefail

WIDGET_ID="${WIDGET_BUNDLE_ID:-com.claudeusage.ClaudeUsage.Widget}"
APP_LOG="$HOME/Library/Logs/ClaudeUsage/ClaudeUsage.log"
WIDGET_LOG="$HOME/Library/Containers/$WIDGET_ID/Data/Library/Logs/ClaudeUsage/ClaudeUsageWidget.log"

case "${1:-}" in
  --paths)
    echo "app:    $APP_LOG"
    echo "widget: $WIDGET_LOG"
    exit 0
    ;;
  --stream)
    exec log stream --predicate 'subsystem == "com.claudeusage.ClaudeUsage"' --level info
    ;;
esac

for path in "$APP_LOG" "$WIDGET_LOG"; do
  [ -f "$path" ] || echo "not there yet: $path" >&2
done

# -F keeps following across the rotation at 2 MB. With both files present tail
# prefixes each block with its name, which is how you tell the two apart.
exec tail -n 40 -F "$APP_LOG" "$WIDGET_LOG"
