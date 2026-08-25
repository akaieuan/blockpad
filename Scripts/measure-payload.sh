#!/bin/bash
# Measures what the README claims, so the claim is reproducible rather than
# asserted. Prints the token cost of the sample payload in each mode.
#
# Text is counted by Anthropic's count_tokens endpoint — the only accurate
# source for Claude. Character-based estimates and OpenAI tokenizers both get
# this wrong, badly so for symbol-dense text like a scene tree.
#
# Raw curl rather than an SDK: this repo is Swift, there is no Swift SDK, and
# Scripts/ is shell. Needs ANTHROPIC_API_KEY in the environment.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="$ROOT/docs/payload.tree.txt"
IMAGE="$ROOT/docs/payload.png"
MODEL="${MODEL:-claude-opus-5}"

[ -f "$TREE" ] || { echo "missing $TREE — run --render-sample first"; exit 1; }
[ -f "$IMAGE" ] || { echo "missing $IMAGE — run --render-sample first"; exit 1; }

# --- image: arithmetic, no API call needed ---------------------------------
# Anthropic resizes any image whose long edge exceeds 1568px, then charges
# (width x height) / 750 tokens on the *resized* dimensions.
read -r W H < <(sips -g pixelWidth -g pixelHeight "$IMAGE" \
    | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
IMAGE_TOKENS=$(python3 -c "
w, h = $W, $H
scale = min(1.0, 1568 / max(w, h))
print(round(round(w * scale) * round(h * scale) / 750))
")
RESIZED=$(python3 -c "
w, h = $W, $H
scale = min(1.0, 1568 / max(w, h))
print(f'{round(w * scale)}x{round(h * scale)}')
")

# --- text: measured, not estimated -----------------------------------------
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "ANTHROPIC_API_KEY is not set."
    echo
    echo "The image side needs no key — it is arithmetic:"
    echo "  image  $W x $H, resized to $RESIZED  ->  $IMAGE_TOKENS tokens"
    echo
    echo "The tree side must be measured. Set ANTHROPIC_API_KEY and re-run;"
    echo "do not substitute a character count or tiktoken — both are wrong for"
    echo "Claude, and structured text is where they are most wrong."
    exit 2
fi

BODY=$(python3 -c "
import json, sys
text = open('$TREE').read()
print(json.dumps({'model': '$MODEL',
                  'messages': [{'role': 'user', 'content': text}]}))
")

TREE_TOKENS=$(curl -sS https://api.anthropic.com/v1/messages/count_tokens \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$BODY" | python3 -c "
import json, sys
r = json.load(sys.stdin)
if 'input_tokens' not in r:
    sys.exit(f\"count_tokens failed: {r}\")
print(r['input_tokens'])
")

BOTH=$((TREE_TOKENS + IMAGE_TOKENS))
RATIO=$(python3 -c "print(f'{$IMAGE_TOKENS / $TREE_TOKENS:.1f}')")

cat <<TABLE

model: $MODEL
image: $W x $H, resized to $RESIZED

| Mode         | Tokens |
|--------------|--------|
| Tree only    | $TREE_TOKENS |
| Image only   | $IMAGE_TOKENS |
| Tree + image | $BOTH |

Tree is ${RATIO}x cheaper than the image.
TABLE
