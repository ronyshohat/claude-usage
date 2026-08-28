#!/bin/bash
# Turns project.yml into ClaudeUsage.xcodeproj.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found."
  echo "Install it with:  brew install xcodegen"
  echo "(Or build the targets by hand in Xcode — see README.md.)"
  exit 1
fi

if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  echo "warning: xcode-select points at the Command Line Tools, not Xcode."
  echo "         Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app"
fi

xcodegen generate
echo "Generated ClaudeUsage.xcodeproj — open it and hit Run."
