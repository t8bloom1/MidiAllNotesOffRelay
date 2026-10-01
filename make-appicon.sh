#!/bin/bash
#
# make-appicon.sh — Regenerate the macOS AppIcon set from a source image.
#
# Usage:
#   ./make-appicon.sh [path-to-source-image]
#
# Defaults to ~/Downloads/Guitar-pick.jpg. Requires `sips` (ships with macOS).
#
# The icon PNGs are also pre-generated and committed in the asset catalog, so
# you only need this if you want to change the icon to a different image.
#
# A square source is recommended (the current source is 583x583). If the source
# is not square, it is center-padded on black to avoid distortion.

set -euo pipefail

SRC="${1:-$HOME/Downloads/Guitar-pick.jpg}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONSET_DIR="$SCRIPT_DIR/MidiAllNotesOffRelay/Assets.xcassets/AppIcon.appiconset"

[[ -f "$SRC" ]] || { echo "ERROR: source not found: $SRC" >&2; exit 1; }
[[ -d "$ICONSET_DIR" ]] || { echo "ERROR: iconset dir not found: $ICONSET_DIR" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

W=$(sips -g pixelWidth  "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
echo "Source: ${W}x${H}"

sips -s format png "$SRC" --out "$TMP/src.png" >/dev/null
if [[ "$W" != "$H" ]]; then
  if (( W >= H )); then SIDE=$W; else SIDE=$H; fi
  echo "Not square; padding to ${SIDE}x${SIDE}."
  sips -p "$SIDE" "$SIDE" "$TMP/src.png" --out "$TMP/master.png" >/dev/null
else
  cp "$TMP/src.png" "$TMP/master.png"
fi

r(){ sips -z "$1" "$1" "$TMP/master.png" --out "$ICONSET_DIR/$2" >/dev/null; }
rm -f "$ICONSET_DIR"/*.png
r 16 icon_16x16.png;    r 32 icon_16x16@2x.png
r 32 icon_32x32.png;    r 64 icon_32x32@2x.png
r 128 icon_128x128.png; r 256 icon_128x128@2x.png
r 256 icon_256x256.png; r 512 icon_256x256@2x.png
r 512 icon_512x512.png; r 1024 icon_512x512@2x.png

cat > "$ICONSET_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Icon set updated from $SRC"
