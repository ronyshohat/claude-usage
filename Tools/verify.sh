#!/bin/bash
# Compiles ClaudeUsageCore together with the CLI harness and runs it.
# Uses only the Command Line Tools, so this works without Xcode installed.
# Pass a directory to scan somewhere other than ~/.claude/projects.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/claude-usage-cli"
xcrun swiftc -parse-as-library -O \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Sources/ClaudeUsageCore/*.swift Tools/cli.swift \
  -o "$OUT"
exec "$OUT" "$@"
