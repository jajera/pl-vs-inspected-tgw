#!/usr/bin/env bash
# Rasterise the brand assets from their SVG sources.
#
#   docs/assets/images/icon.svg      -> favicon-{16,32,48}.png, favicon.ico,
#                                       apple-touch-icon.png, icon-512.png
#   docs/assets/images/og-image.svg  -> og-image.png (1200x630)
#
# Requires ImageMagick 7 built with the rsvg/cairo delegate (magick -version).
set -euo pipefail

cd "$(dirname "$0")/.."
IMG="docs/assets/images"

if ! command -v magick &>/dev/null; then
  echo "Error: ImageMagick 7 (magick) not found on PATH." >&2
  exit 1
fi

render() { # svg width height out
  magick -background none -density 384 "$1" -resize "${2}x${3}" \
    -strip -depth 8 -define png:compression-level=9 "$4"
}

render "${IMG}/icon.svg" 512 512 "${IMG}/icon-512.png"
render "${IMG}/icon.svg" 180 180 "${IMG}/apple-touch-icon.png"
render "${IMG}/icon.svg" 48 48 "${IMG}/favicon-48.png"
render "${IMG}/icon.svg" 32 32 "${IMG}/favicon-32.png"
render "${IMG}/icon.svg" 16 16 "${IMG}/favicon-16.png"

magick "${IMG}/favicon-16.png" "${IMG}/favicon-32.png" "${IMG}/favicon-48.png" \
  -strip "${IMG}/favicon.ico"

render "${IMG}/og-image.svg" 1200 630 "${IMG}/og-image.png"

echo "Built:"
ls -1sh "${IMG}"/*.png "${IMG}"/*.ico
