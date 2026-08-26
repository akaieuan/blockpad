#!/bin/bash
# Creates a stable self-signed identity and signs the app with it.
#
# Why: macOS keys the Accessibility permission on the signing identity. An
# ad-hoc signature's hash changes with every rebuild, so the grant you gave five
# minutes ago no longer matches and auto-paste silently stops working until you
# re-grant it. A self-signed certificate stays the same across rebuilds, so the
# grant sticks.
#
# One-time setup. Creating the certificate needs Keychain Access, because macOS
# has no scriptable way to make one — the steps are printed below.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${BLOCKPAD_SIGNING_IDENTITY:-Blockpad Local}"
APP="$ROOT/build/Blockpad.app"

if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    cat <<INSTRUCTIONS
No signing certificate named "$IDENTITY" was found.

Create one once, in Keychain Access:

  1. Keychain Access → Certificate Assistant → Create a Certificate…
  2. Name:              $IDENTITY
     Identity Type:     Self Signed Root
     Certificate Type:  Code Signing
  3. Create, then Done.

Then run this script again. Everything after that is automatic:
the Accessibility grant will survive rebuilds.

To use a different name, set BLOCKPAD_SIGNING_IDENTITY.
INSTRUCTIONS
    exit 1
fi

[ -d "$APP" ] || "$ROOT/Scripts/bundle.sh" release

codesign --force --deep --identifier studio.ubik.blockpad --sign "$IDENTITY" "$APP"
echo "signed with \"$IDENTITY\""
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority" | sed 's/^/  /'
echo
echo "Reinstall with ./Scripts/install.sh, then grant Accessibility once."
