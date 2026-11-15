#!/usr/bin/env bash
# Builds and runs the T-024 live EventKit check as a signed app bundle.
# macOS only grants calendar access to app bundles with NSCalendarsFullAccessUsageDescription,
# so this cannot run inside `swift test`. Read-only; reads only the "FlowTest" calendar.
# The first run shows macOS's calendar consent prompt for "Flow Calendar Live Check".
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${FLOW_SIGN_IDENTITY:-$(security find-identity -p codesigning 2>/dev/null | awk '/Apple Development/ && $2 ~ /^[0-9A-F]{40}$/ { print $2; exit }')}"
[[ -z "$IDENTITY" ]] && { echo "error: no Apple Development signing identity (set FLOW_SIGN_IDENTITY)" >&2; exit 1; }

swift build --product flow-calendar-livecheck >/dev/null
BIN="$(swift build --show-bin-path)/flow-calendar-livecheck"
APP="build/FlowCalendarLiveCheck.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/flow-calendar-livecheck"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Flow Calendar Live Check</string>
  <key>CFBundleIdentifier</key><string>dev.flow.CalendarLiveCheck</string>
  <key>CFBundleExecutable</key><string>flow-calendar-livecheck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Flow's test tool reads ONLY the synthetic FlowTest calendar to verify calendar answers. It never changes events.</string>
  <key>NSCalendarsUsageDescription</key><string>Flow's test tool reads ONLY the synthetic FlowTest calendar to verify calendar answers. It never changes events.</string>
</dict></plist>
PLIST
codesign --force --sign "$IDENTITY" --identifier dev.flow.CalendarLiveCheck "$APP" >/dev/null 2>&1
OUT="$(mktemp)"
open -W -n --stdout "$OUT" --stderr "$OUT" "$APP"
cat "$OUT"
grep -q "^RESULT .* passed" "$OUT" && ! grep -q "^FAIL" "$OUT"; STATUS=$?
rm -f "$OUT"
exit $STATUS
