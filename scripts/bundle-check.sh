#!/usr/bin/env bash
# Loads every plugin/lib/*.mjs in Quickshell's own QML engine (a headless
# `qs -p` shell, no windows) and fails if one doesn't parse there. Vitest runs
# the TypeScript in Node, which accepts syntax the QML engine doesn't.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r plugin/lib "$tmp/lib"
{
  echo "import Quickshell"
  echo "import QtQuick"
  for f in plugin/lib/*.mjs; do
    name=$(basename "$f" .mjs)
    echo "import \"lib/$name.mjs\" as M_$name"
  done
  echo "ShellRoot {"
  echo "  Component.onCompleted: {"
  for f in plugin/lib/*.mjs; do
    name=$(basename "$f" .mjs)
    echo "    console.log(\"BUNDLE-OK $name\", Object.keys(M_$name).length)"
  done
  echo "  }"
  echo "}"
} > "$tmp/shell.qml"
out=$(QT_QPA_PLATFORM=offscreen timeout 10 qs -p "$tmp/shell.qml" 2>&1 & pid=$!; sleep 3; kill $pid 2>/dev/null; wait $pid 2>/dev/null) || true
out=$(cat <<<"$out")
fail=0
for f in plugin/lib/*.mjs; do
  name=$(basename "$f" .mjs)
  if ! grep -q "BUNDLE-OK $name" <<<"$out"; then
    echo "plugin/lib/$name.mjs does not load in Quickshell's QML engine:" >&2
    fail=1
  fi
done
if [ "$fail" = 1 ]; then
  grep -a -E "unavailable|Unexpected|Expected|Error" <<<"$out" >&2 || true
  exit 1
fi
