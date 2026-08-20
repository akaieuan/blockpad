#!/bin/bash
# Regenerates Blockpad.icns from IconRender. The icon is drawn in code rather
# than kept as a binary asset so it stays in step with the palette.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build
ICONSET="$ROOT/build/Blockpad.iconset"
rm -rf "$ICONSET"
"$(swift build --show-bin-path)/Blockpad" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Blockpad.icns"
echo "wrote $ROOT/Resources/Blockpad.icns"
