#!/usr/bin/env bash
# Builds build/Flow.app from the SwiftPM FlowApp target, signs it, and optionally launches it.
#
# Usage: scripts/build_app.sh [--release] [--open] [--allow-adhoc]
#
# Signing and Accessibility permission
# ------------------------------------
# macOS keys an app's Accessibility (TCC) grant to its code-signing "designated requirement".
#   * Ad-hoc signing (`codesign -s -`) makes that requirement the binary's cdhash, so every
#     rebuild that changes the binary looks like a different app and the grant stops applying.
#   * Signing with a certificate gives `identifier "dev.flow.FlowApp" and certificate ...`,
#     which stays the same across rebuilds, so a grant made once keeps working.
#
# Identity selection (first match wins):
#   1. $FLOW_SIGN_IDENTITY (name or SHA-1 of a code-signing identity)
#   2. An "Apple Development" identity in the keychain
#   3. The local self-signed identity created by scripts/create_local_signing_identity.sh
# With none available the build fails, unless --allow-adhoc is passed (permission then resets per build).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="dev.flow.FlowApp"
LOCAL_IDENTITY_NAME="Flow Local Code Signing"
CONFIG=debug
OPEN=0
ALLOW_ADHOC=0
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=release ;;
    --open) OPEN=1 ;;
    --allow-adhoc) ALLOW_ADHOC=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Prints the SHA-1 of the first identity whose line matches $1 (includes untrusted self-signed ones).
find_identity() {
  security find-identity -p codesigning 2>/dev/null \
    | awk -v pat="$1" 'index($0, pat) && $2 ~ /^[0-9A-F]{40}$/ { print $2; exit }'
}

IDENTITY="${FLOW_SIGN_IDENTITY:-}"
[[ -z "$IDENTITY" ]] && IDENTITY="$(find_identity "Apple Development")"
[[ -z "$IDENTITY" ]] && IDENTITY="$(find_identity "\"$LOCAL_IDENTITY_NAME\"")"
if [[ -z "$IDENTITY" ]]; then
  if [[ "$ALLOW_ADHOC" == 1 ]]; then
    echo "warning: no signing identity; signing ad-hoc. Accessibility permission will reset on each rebuild." >&2
    IDENTITY="-"
  else
    echo "error: no stable code-signing identity found." >&2
    echo "  Run scripts/create_local_signing_identity.sh, add an Apple Development certificate in Xcode," >&2
    echo "  set FLOW_SIGN_IDENTITY, or pass --allow-adhoc (permission then resets every build)." >&2
    exit 1
  fi
fi

swift build -c "$CONFIG" --product FlowApp
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# Update the bundle in place so its path stays fixed.
APP="build/Flow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FlowApp" "$APP/Contents/MacOS/FlowApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
echo "Built $APP ($CONFIG)"
echo "Designated requirement: $REQUIREMENT"
if [[ "$REQUIREMENT" == cdhash* ]]; then
  echo "warning: requirement is hash-based; Accessibility permission will not survive the next rebuild." >&2
fi

if [[ "$OPEN" == 1 ]]; then
  open "$APP"
fi
