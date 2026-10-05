#!/usr/bin/env bash
# Copies the shipped plugin into Omarchy's plugin folder. The dev repo lives
# outside it: the shell reloads plugins on any write under that folder.
set -euo pipefail
cd "$(dirname "$0")/.."
dest="$HOME/.config/omarchy/plugins/stef.periphery"
if [ -d "$dest/.git" ]; then
  echo "$dest is still a git repo; move its .git away first." >&2
  exit 1
fi
mkdir -p "$dest"
rsync -a --delete plugin/ "$dest/"
echo "Deployed to $dest. Run \`omarchy restart shell\` to load it."
