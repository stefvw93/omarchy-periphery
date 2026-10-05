#!/usr/bin/env bash
# Lints the plugin's QML with Qt 6's qmllint (/usr/bin/qmllint is Qt 5's
# syntax checker). `qs.*` imports resolve through a link to the Omarchy shell.
# Any warning fails. Lines qmllint can't type (theme singletons, lib/*.mjs,
# Quickshell's PanelWindow) carry a same-line `// qmllint disable <category>`.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache/qml
ln -sfn "${OMARCHY_PATH:-/usr/share/omarchy}/shell" .cache/qml/qs
/usr/lib/qt6/bin/qmllint -I .cache/qml --max-warnings 0 plugin/*.qml
