#!/bin/bash
# Regenerates Sources/ClaudeUsageApp/Resources/AppIcon.icns and docs/icon.png
# from makeicon.swift.
set -euo pipefail
cd "$(dirname "$0")/../.."

work="${TMPDIR:-/tmp}/claude-usage-icon"
rm -rf "$work"
mkdir -p "$work"

xcrun swiftc -parse-as-library -O \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Tools/icon/makeicon.swift -o "$work/makeicon"

"$work/makeicon" "$work/AppIcon.iconset"

mkdir -p Sources/ClaudeUsageApp/Resources
iconutil -c icns "$work/AppIcon.iconset" -o Sources/ClaudeUsageApp/Resources/AppIcon.icns
echo "wrote Sources/ClaudeUsageApp/Resources/AppIcon.icns"

mkdir -p docs
cp "$work/AppIcon.iconset/icon_512x512.png" docs/icon.png
echo "wrote docs/icon.png"
