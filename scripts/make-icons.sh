#!/usr/bin/env bash
# Regenerate the icon files from core `IconGeometry` (the only source of the shape):
#   1. design/icon/AppIcon.svg and design/icon/MenuBarGlyph.svg   (shotkeeper-cli icon-svg, in the Swift image)
#   2. App/Shotkeeper/AppIcon.icon/ (icon.json + Assets/*.svg)      (shotkeeper-cli icon-composer; macOS 26 layered icon)
#   3. App/Shotkeeper/Assets.xcassets/AppIcon.appiconset/*.png    (rsvg-convert in a throwaway Alpine container)
# Run after changing IconGeometry/IconSVG, then commit the results. The core test
# `IconSVGTests.testCommittedSVGsMatchTheGeometry` and `IconComposerBundleTests` fail while the SVGs / .icon are stale.
# Nothing is installed on the host. The Alpine image is removed again if this script pulled it.
# Usage: scripts/make-icons.sh   (SCRATCH=.build/linux-<you> for a separate Swift scratch dir)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export SCRATCH="${SCRATCH:-.build/linux-icons}"
SVG_DIR="design/icon"
SET_DIR="App/Shotkeeper/Assets.xcassets/AppIcon.appiconset"
RASTER_IMAGE="alpine:3.20"

mkdir -p "$SVG_DIR" "$SET_DIR"
scripts/test-linux.sh build --product shotkeeper-cli
for kind in app glyph; do
  case "$kind" in app) out="$SVG_DIR/AppIcon.svg" ;; glyph) out="$SVG_DIR/MenuBarGlyph.svg" ;; esac
  scripts/test-linux.sh run --skip-build -q shotkeeper-cli icon-svg "$kind" > "$out.tmp"
  grep -q '^<svg ' "$out.tmp" || { echo "icon-svg $kind did not print an SVG" >&2; rm -f "$out.tmp"; exit 1; }
  mv "$out.tmp" "$out"
done

# The Icon Composer package: rebuilt from scratch, so a file the generator dropped does not linger.
ICON_DIR="App/Shotkeeper/AppIcon.icon"
NEW_ICON="$(mktemp -d "$ROOT/.build/icon-XXXXXX")"
for file in $(scripts/test-linux.sh run --skip-build -q shotkeeper-cli icon-composer --list); do
  mkdir -p "$NEW_ICON/$(dirname "$file")"
  scripts/test-linux.sh run --skip-build -q shotkeeper-cli icon-composer "$file" > "$NEW_ICON/$file"
  [ -s "$NEW_ICON/$file" ] || { echo "icon-composer $file printed nothing" >&2; exit 1; }
done
# Only generated files live in AppIcon.icon (see IconComposerBundle); replacing the folder is safe.
rm -rf "$ICON_DIR"
mv "$NEW_ICON" "$ICON_DIR"

pulled=0
docker image inspect "$RASTER_IMAGE" >/dev/null 2>&1 || pulled=1
# The network is only for `apk add`; the container sees the SVG read-only and the icon set folder.
docker run --rm --network bridge \
  -v "$ROOT/$SVG_DIR":/in:ro -v "$ROOT/$SET_DIR":/out \
  -e OWNER="$(id -u):$(id -g)" "$RASTER_IMAGE" sh -euc '
    apk add --no-cache -q rsvg-convert
    rsvg-convert --version
    # macOS app icon sizes: <point size>@1x and @2x (Contents.json lists the same files).
    for pt in 16 32 128 256 512; do
      rsvg-convert -w "$pt" -h "$pt" /in/AppIcon.svg -o "/out/icon_${pt}x${pt}.png"
      rsvg-convert -w "$((pt * 2))" -h "$((pt * 2))" /in/AppIcon.svg -o "/out/icon_${pt}x${pt}@2x.png"
    done
    chown "$OWNER" /out/*.png
  '
if [ "$pulled" = 1 ]; then docker rmi "$RASTER_IMAGE" >/dev/null; fi
ls -lR "$SVG_DIR" "$ICON_DIR" "$SET_DIR"
