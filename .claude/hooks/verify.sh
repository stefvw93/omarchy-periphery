#!/usr/bin/env bash
# Stop: runs `vp run verify` before I finish a turn and sends me back to work
# (exit 2) while it fails: validate → fix → validate. Skips when the tree is
# unchanged. A second identical failure in a row lets me stop, with the output,
# so an environment problem I can't fix doesn't loop forever.
export PATH="$HOME/.vite-plus/bin:$PATH"
set -uo pipefail
cd "$(dirname "$0")/../.."
input=$(cat)
[ -z "$(git status --porcelain)" ] && exit 0
out=$(vp run verify 2>&1)
status=$?
[ $status = 0 ] && { rm -f .cache/verify-failure; exit 0; }
mkdir -p .cache
hash=$(printf '%s' "$out" | sed -E 's/[0-9]+(\.[0-9]+)?/N/g' | sha1sum | cut -d' ' -f1)
if [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = true ] && [ "$(cat .cache/verify-failure 2>/dev/null)" = "$hash" ]; then
  echo "vp run verify still fails the same way; stopping. Tell the user." >&2
  exit 0
fi
echo "$hash" > .cache/verify-failure
{
  echo "vp run verify failed. Fix it before finishing:"
  printf '%s\n' "$out" | grep -v "cache disabled\|^$" | tail -60
} >&2
exit 2
