#!/usr/bin/env bash
# Syntax-checks the Hyprland hook and runs its tests (plain Lua, fake `hl`).
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."
tests=(tests/*.test.lua)
luac -p plugin/hypr.lua tests/*.lua
for t in "${tests[@]}"; do lua "$t"; done
