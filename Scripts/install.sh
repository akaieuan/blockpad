#!/bin/bash
# Builds and installs Blockpad into ~/Applications, leaving exactly one copy
# registered with LaunchServices.
#
# Why this exists rather than a cp: two bundles sharing one bundle identifier
# means macOS can resolve the hotkey, `open -a`, and the menu bar item to either
# of them, and which one you get is not something you control. The build
# directory always contains a bundle, so unregistering it after every install is
# the only way to keep that from happening.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
DEST="$HOME/Applications/Blockpad.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

"$ROOT/Scripts/bundle.sh" "$CONFIG"

# Quit any running copy, wherever it was launched from, or the replace races it.
pkill -f "Blockpad.app/Contents/MacOS/Blockpad" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$ROOT/build/Blockpad.app" "$DEST"

# Point LaunchServices at the installed copy and forget the build one.
"$LSREG" -u "$ROOT/build/Blockpad.app" >/dev/null 2>&1 || true
"$LSREG" -f "$DEST" >/dev/null 2>&1 || true

REGISTERED=$("$LSREG" -dump 2>/dev/null \
    | grep -io "/[^ ]*Blockpad\.app" | sort -u | wc -l | tr -d ' ')
echo "installed $DEST"
echo "registered copies: $REGISTERED"
if [ "$REGISTERED" != "1" ]; then
    echo "warning: more than one Blockpad.app is registered —"
    "$LSREG" -dump 2>/dev/null | grep -io "/[^ ]*Blockpad\.app" | sort -u | sed 's/^/  /'
fi
