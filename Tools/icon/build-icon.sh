#!/bin/bash
# Regenerates Sources/ClaudeUsageApp/Resources/AppIcon.icns, docs/icon.png and
# docs/social-preview.png from makeicon.swift.
set -euo pipefail
cd "$(dirname "$0")/../.."

work="${TMPDIR:-/tmp}/claude-usage-icon"
rm -rf "$work"
mkdir -p "$work"

xcrun swiftc -parse-as-library -O \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Tools/icon/makeicon.swift -o "$work/makeicon"

mkdir -p docs
"$work/makeicon" "$work/AppIcon.iconset" docs/social-preview.png

mkdir -p Sources/ClaudeUsageApp/Resources
iconutil -c icns "$work/AppIcon.iconset" -o Sources/ClaudeUsageApp/Resources/AppIcon.icns
echo "wrote Sources/ClaudeUsageApp/Resources/AppIcon.icns"

cp "$work/AppIcon.iconset/icon_512x512.png" docs/icon.png
echo "wrote docs/icon.png"
