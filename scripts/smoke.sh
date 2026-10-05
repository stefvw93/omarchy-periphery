#!/usr/bin/env bash
# Live checks against the running session, after `vp run deploy` and
# `omarchy restart shell`. Toggles the mode off and on, asserts what Hyprland
# sees each time, and leaves the mode as it found it. Not part of verify: it
# needs the desktop.
set -uo pipefail

fail=0
pass() { echo "ok    $1"; }
bad() { echo "FAIL  $1" >&2; fail=1; }

lua() { hyprctl eval "error($1)" 2>&1 | sed 's/.*:1: //'; }
reserved() { hyprctl monitors -j | jq -c '.[] | select(.focused) | .reserved'; }
toggle() {
  omarchy-shell shell toggle stef.periphery '{}' >/dev/null
  sleep 1.5
}
mode_on() { [ "$(lua 'tostring(periphery ~= nil)')" = true ]; }

[ "$(lua 'type(periphery_select)')" = function ] && pass "hook loaded (hypr.lua)" ||
  bad "hook not loaded: add it to ~/.config/hypr/hyprland.lua and run hyprctl reload"

was_on=false
mode_on && was_on=true
$was_on || toggle

if mode_on; then pass "mode on: hook state is a table"; else bad "mode on: hook state is nil (plugin failed to load? check qs log)"; fi
r=$(reserved)
if [ "$(jq '.[0] > 0 and .[2] > 0 and .[0] == .[2]' <<<"$r")" = true ]; then
  pass "mode on: bands reserved $r"
else
  bad "mode on: bands not reserved ($r)"
fi

toggle
if mode_on; then bad "mode off: hook state still set"; else pass "mode off: hook state is nil"; fi
r=$(reserved)
[ "$(jq '.[0] == 0 and .[2] == 0' <<<"$r")" = true ] && pass "mode off: bands released $r" ||
  bad "mode off: bands still reserved ($r)"
n=$(hyprctl binds -j | jq '[.[] | select(.description | startswith("Periphery:"))] | length')
[ "$n" = 0 ] && pass "mode off: no Periphery binds left" || bad "mode off: $n Periphery binds left"

$was_on && toggle
exit $fail
