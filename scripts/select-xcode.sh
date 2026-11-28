#!/bin/bash
# Selects the newest stable Xcode on a GitHub macOS runner. CI's `macos-app` job and the release workflow both call
# this, so the two can't drift (auto-update spec, release flow job 1 step 1; ticket 06).
#   scripts/select-xcode.sh
# Picks the highest /Applications/Xcode_<version>.app whose name has no beta/RC marker, runs `sudo xcode-select -s`,
# and logs the chosen path and versions. When $GITHUB_OUTPUT is set it appends `version=<Xcode version>` (the cache key
# uses it). Takes no input. Runs under macOS's bash 3.2 and BSD tools; no `set -x`.
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "usage: scripts/select-xcode.sh (no arguments)" >&2
  exit 2
fi

# A glob loop, not `ls | grep`: with pipefail, a grep that matches nothing (or an ls that finds nothing) ended the
# script inside the command substitution, so the message below never printed.
stable=""
for app in /Applications/Xcode*.app; do
  [ -d "$app" ] || continue
  echo "$app"
  case "$app" in
    /Applications/Xcode_*.app) ;;
    *) continue ;;
  esac
  case "$(printf '%s' "$app" | tr '[:upper:]' '[:lower:]')" in
    *beta* | *_rc* | *release_candidate*) continue ;;
  esac
  stable="$stable$app
"
done
XCODE=""
if [ -n "$stable" ]; then
  XCODE="$(printf '%s' "$stable" | sort -V | tail -1)"
fi
if [ -z "$XCODE" ]; then
  echo "select-xcode: no stable /Applications/Xcode_*.app found" >&2
  exit 1
fi
sudo xcode-select -s "$XCODE/Contents/Developer"
echo "Selected Xcode: $XCODE"
echo "xcode-select -p: $(xcode-select -p)"
xcodebuild -version
swift --version
sw_vers
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$(xcodebuild -version | head -1 | awk '{print $2}')" >> "$GITHUB_OUTPUT"
fi
