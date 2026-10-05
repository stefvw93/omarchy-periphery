#!/usr/bin/env bash
# Fails when plugin/lib/ doesn't match a fresh `vp pack` of src/: the bundle
# QML imports must never lag behind the TypeScript it is built from.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
vp pack --out-dir "$tmp" --log-level error >/dev/null
if ! diff -r "$tmp" plugin/lib >/dev/null 2>&1; then
  echo "plugin/lib/ is stale: run \`vp pack\`." >&2
  diff -r "$tmp" plugin/lib >&2 || true
  exit 1
fi
