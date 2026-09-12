#!/usr/bin/env bash
# Capture Wikimedia recent-change SSE for offline relay replay.
set -euo pipefail

OUT="${1:-feed.sse}"
BYTES="${BYTES:-50000000}"
URL="${UPSTREAM:-https://stream.wikimedia.org/v2/stream/recentchange}"
UA="${USER_AGENT:-pl-vs-inspected-tgw/1.0 (lab; capture-feed)}"

echo "capturing up to ${BYTES} bytes from ${URL} → ${OUT}"
curl -sN -A "$UA" "$URL" | head -c "$BYTES" >"$OUT"
echo "wrote $(wc -c <"$OUT") bytes to ${OUT}"
