#!/usr/bin/env bash
# PostToolUse (Edit/Write): formats the file just touched, so I never leave
# formatting for the check to find. QML is not formatted (hand style).
export PATH="$HOME/.vite-plus/bin:$PATH"
set -euo pipefail
file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0
cd "$(dirname "$0")/../.."
case "$file" in
  "$PWD"/plugin/lib/*) exit 0 ;;
  "$PWD"/*.ts | "$PWD"/*.md | "$PWD"/*.json) vp fmt "$file" >/dev/null 2>&1 || true ;;
esac
exit 0
