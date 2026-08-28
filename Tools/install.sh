#!/bin/bash
# Installs the latest release into /Applications and relaunches it.
#
# Downloads with `gh`, which — unlike a browser — never sets
# com.apple.quarantine, so Gatekeeper has nothing to object to and there is no
# `xattr` step. Nothing here needs sudo.
set -euo pipefail

REPO="${CLAUDE_USAGE_REPO:-ronyshohat/claude-usage}"
APP="/Applications/ClaudeUsage.app"

command -v gh >/dev/null 2>&1 || {
  echo "gh is required: brew install gh" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

tag="$(gh release view -R "$REPO" --json tagName --jq .tagName)"
echo "installing $tag"
gh release download "$tag" -R "$REPO" --pattern 'ClaudeUsage.zip' --dir "$work"
ditto -xk "$work/ClaudeUsage.zip" "$work/unpacked"

# A downloaded-by-gh bundle carries no quarantine flag; say so if that ever
# changes rather than silently shipping something Gatekeeper will block.
if xattr "$work/unpacked/ClaudeUsage.app" 2>/dev/null | grep -q com.apple.quarantine; then
  echo "note: quarantine flag present, clearing it"
  xattr -dr com.apple.quarantine "$work/unpacked/ClaudeUsage.app"
fi

osascript -e 'tell application "ClaudeUsage" to quit' 2>/dev/null || true
sleep 2

rm -rf "$APP"
ditto "$work/unpacked/ClaudeUsage.app" "$APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
open "$APP"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "ClaudeUsage $version running from $APP"
