#!/usr/bin/env bash
# Lints the plugin's QML with Qt 6's qmllint (/usr/bin/qmllint is Qt 5's
# syntax checker). `qs.*` imports resolve through a link to the Omarchy shell.
# Warnings only for now: Quickshell's dynamic types still produce noise.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache/qml
ln -sfn "${OMARCHY_PATH:-/usr/share/omarchy}/shell" .cache/qml/qs
/usr/lib/qt6/bin/qmllint -I .cache/qml plugin/*.qml 2>&1 | grep -E "^(Warning|Error):" | sed -E "s/:[0-9]+:[0-9]+:/:/" | sort | uniq -c | sort -rn | sed 's/^/qmllint: /' || true
