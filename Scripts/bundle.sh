#!/bin/bash
# Assembles Blockpad.app. SPM can't emit app bundles, and LSUIElement needs a
# real Info.plist, so the bundle is put together by hand.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/Blockpad.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Blockpad" "$APP/Contents/MacOS/Blockpad"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Blockpad.icns" "$APP/Contents/Resources/Blockpad.icns"

# Ad-hoc signature is enough to run locally. Note it changes on every rebuild,
# so once M1 needs Accessibility the permission will reset each build until the
# app is signed with a stable identity.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
