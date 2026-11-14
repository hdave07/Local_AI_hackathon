#!/usr/bin/env bash
# Builds Flow.app from the SwiftPM FlowApp target and optionally launches it.
# Usage: scripts/build_app.sh [--release] [--open]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=debug
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=release ;;
    --open) OPEN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

swift build -c "$CONFIG" --product FlowApp
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Flow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FlowApp" "$APP/Contents/MacOS/FlowApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null   # ad-hoc signature for local runs only
echo "Built $APP ($CONFIG)"

if [[ "$OPEN" == 1 ]]; then
  open "$APP"
fi
