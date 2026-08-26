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
# Sweep any "Blockpad 2.app" siblings. macOS's conflict-rename can leave these
# behind, and each one registers itself as another copy of the same app.
find "$ROOT/build" -maxdepth 1 -name "Blockpad *.app" -type d -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Blockpad" "$APP/Contents/MacOS/Blockpad"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Blockpad.icns" "$APP/Contents/Resources/Blockpad.icns"

# Ad-hoc signature is enough to run locally, but the identifier has to be set
# explicitly: codesign otherwise names the signature after the binary
# ("Blockpad") while the bundle declares studio.ubik.blockpad, and TCC keys
# Accessibility on the signing identity.
#
# The ad-hoc hash still changes on every rebuild, so the Accessibility grant
# resets each time until this is signed with a stable identity. Scripts/sign.sh
# sets one up.
#
# Extended attributes have to go first, or codesign refuses the bundle as
# carrying "resource fork, Finder information, or similar detritus". That
# failure used to be swallowed by redirecting to /dev/null, so the identifier
# silently stayed wrong while the script claimed success.
#
# com.apple.provenance survives this on macOS 14+ — the system re-adds it and it
# cannot be stripped. It makes `codesign --verify --strict` complain and affects
# nothing else, so plain --verify is what to check.
xattr -cr "$APP" 2>/dev/null || true

if ! codesign --force --identifier studio.ubik.blockpad --sign "${BLOCKPAD_SIGNING_IDENTITY:--}" "$APP" 2>/tmp/blockpad-codesign.log; then
    echo "warning: codesign failed —"
    sed 's/^/  /' /tmp/blockpad-codesign.log
fi

echo "built $APP"
