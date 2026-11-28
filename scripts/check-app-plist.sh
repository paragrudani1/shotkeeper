#!/bin/bash
# Checks the update keys in a built Shotkeeper.app's Info.plist. CI's `macos-app` job runs it after signing on every
# push; the release workflow's build job runs it with the planned versions (auto-update spec, release flow job 1
# step 4, and "The existing CI job uses the same signing script"; ticket 07).
#
#   scripts/check-app-plist.sh [--version <short version>] [--build <build number>] [--require-public-key] <App.app>
#   scripts/check-app-plist.sh --self-test     # fake plutil everywhere; on macOS also the real plutil
#
# Checks (Sparkle "Customizing Sparkle", https://sparkle-project.org/documentation/customization/ ):
#   SUEnableAutomaticChecks  a boolean, false: no automatic checks, and no "check automatically?" question (Sparkle
#                            asks it on the second launch only while the key is unset).
#   SUFeedURL                present and a non-empty string.
#   --version / --build      CFBundleShortVersionString / CFBundleVersion equal the given values.
#   --require-public-key     SUPublicEDKey present and a non-empty string (ticket 08 turns this on).
# Every failing check prints one line; the script exits 1 if any failed, 2 on a usage error. Nothing here is secret
# (the public key is public). Runs under macOS's bash 3.2 and BSD tools.
set -euo pipefail

usage() {
  echo "usage: scripts/check-app-plist.sh [--version <v>] [--build <n>] [--require-public-key] <path/to/App.app>" >&2
  echo "       scripts/check-app-plist.sh --self-test" >&2
  exit 2
}

self_test() {
  local self tmp mode out status
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # A fake `plutil -extract <key> raw|xml1 -o - <file>` for test plists written as one `<key>` line followed by
  # one value line (how make_app writes them). Exits 1 like plutil when the key is missing.
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/plutil" <<'EOF'
#!/bin/sh
[ "$1" = "-extract" ] && [ "$4" = "-o" ] && [ "$5" = "-" ] || { echo "fake plutil: unexpected call: $*" >&2; exit 64; }
value="$(awk -v k="<key>$2</key>" 'found { print; exit } index($0, k) { found = 1 }' "$6" | sed 's/^[[:space:]]*//')"
[ -n "$value" ] || { echo "No value at that key path or invalid key path: $2" >&2; exit 1; }
case "$3" in
  xml1) printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n%s\n</plist>\n' "$value" ;;
  raw)
    case "$value" in
      "<true/>") echo true ;;
      "<false/>") echo false ;;
      "<string/>") echo ;;
      "<string>"*) printf '%s\n' "$value" | sed 's#^<string>##; s#</string>$##' ;;
      *) echo "fake plutil: unknown value $value" >&2; exit 64 ;;
    esac ;;
  *) echo "fake plutil: unknown format $3" >&2; exit 64 ;;
esac
EOF
  chmod +x "$tmp/bin/plutil"

  # make_app <name> <key>=<plist value line>...; `<key>=-` leaves the key out. Starts from a good app.
  make_app() {
    local app="$tmp/$1.app" pair key value
    shift
    mkdir -p "$app/Contents"
    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
      echo '<plist version="1.0">'
      echo '<dict>'
      for pair in "CFBundleShortVersionString=<string>0.1.0</string>" "CFBundleVersion=<string>1</string>" \
                  "SUEnableAutomaticChecks=<false/>" \
                  "SUFeedURL=<string>https://example.com/releases/latest/download/appcast.xml</string>" "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        # A later pair for the same key replaces the default one.
        if grep -q "<key>$key</key>" "$app/Contents/Info.plist.tmp" 2>/dev/null; then
          awk -v k="<key>$key</key>" 'skip { skip = 0; next } index($0, k) { skip = 1; next } { print }' \
            "$app/Contents/Info.plist.tmp" > "$app/Contents/Info.plist.tmp2"
          mv "$app/Contents/Info.plist.tmp2" "$app/Contents/Info.plist.tmp"
        fi
        [ "$value" = "-" ] && continue
        printf '\t<key>%s</key>\n\t%s\n' "$key" "$value" >> "$app/Contents/Info.plist.tmp"
      done
      cat "$app/Contents/Info.plist.tmp"
      echo '</dict>'
      echo '</plist>'
    } > "$app/Contents/Info.plist.body"
    rm "$app/Contents/Info.plist.tmp"
    mv "$app/Contents/Info.plist.body" "$app/Contents/Info.plist"
  }

  make_app good
  make_app checks-on "SUEnableAutomaticChecks=<true/>"
  make_app checks-unset "SUEnableAutomaticChecks=-"
  make_app checks-string "SUEnableAutomaticChecks=<string>false</string>"
  make_app no-feed "SUFeedURL=-"
  make_app empty-feed "SUFeedURL=<string></string>"
  make_app with-key "SUPublicEDKey=<string>pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=</string>"
  make_app empty-key "SUPublicEDKey=<string></string>"
  make_app no-version "CFBundleShortVersionString=-"

  fail() {
    echo "check-app-plist self-test ($mode plutil): $1"
    printf '%s\n' "$out"
    exit 1
  }
  # expect <status> <text the output must contain, or ""> <args...>
  expect() {
    local want="$1" text="$2"
    shift 2
    status=0
    if [ "$mode" = fake ]; then
      out="$(PATH="$tmp/bin:$PATH" "$BASH" "$self" "$@" 2>&1)" || status=$?
    else
      out="$("$BASH" "$self" "$@" 2>&1)" || status=$?
    fi
    [ "$status" = "$want" ] || fail "expected exit $want, got $status for: $*"
    if [ -n "$text" ]; then
      case "$out" in *"$text"*) ;; *) fail "expected \"$text\" for: $*" ;; esac
    fi
  }

  for mode in fake real; do
    if [ "$mode" = real ] && [ "$(uname -s)" != Darwin ]; then
      echo "check-app-plist self-test: not macOS, real plutil part skipped"
      continue
    fi
    [ "$mode" = real ] && for f in "$tmp"/*.app/Contents/Info.plist; do plutil -lint "$f" >/dev/null; done

    expect 0 "SUEnableAutomaticChecks: false" "$tmp/good.app"
    case "$out" in *"SUFeedURL: https://example.com/releases/latest/download/appcast.xml"*) ;;
      *) fail "the feed URL goes to the log" ;; esac
    expect 0 "CFBundleVersion: 1" --version 0.1.0 --build 1 "$tmp/good.app"
    expect 0 "CFBundleShortVersionString: 0.1.0" --version 0.1.0 --build 1 "$tmp/good.app"
    expect 1 "SUEnableAutomaticChecks must be false" "$tmp/checks-on.app"
    expect 1 "SUEnableAutomaticChecks is missing" "$tmp/checks-unset.app"
    expect 1 "SUEnableAutomaticChecks must be a boolean" "$tmp/checks-string.app"
    expect 1 "SUFeedURL is missing or empty" "$tmp/no-feed.app"
    expect 1 "SUFeedURL is missing or empty" "$tmp/empty-feed.app"
    expect 1 "CFBundleShortVersionString is 0.1.0, expected 0.2.0" --version 0.2.0 "$tmp/good.app"
    expect 1 "CFBundleVersion is 1, expected 20000" --build 20000 "$tmp/good.app"
    expect 1 "CFBundleShortVersionString is missing, expected 0.1.0" --version 0.1.0 "$tmp/no-version.app"
    # Every failing check is reported, not only the first.
    expect 1 "SUFeedURL is missing or empty" --build 2 "$tmp/no-feed.app"
    case "$out" in *"CFBundleVersion is 1, expected 2"*) ;; *) fail "all failures are listed" ;; esac
    # SUPublicEDKey: not checked by default (until ticket 08), required with --require-public-key.
    expect 0 "" "$tmp/good.app"
    case "$out" in *SUPublicEDKey*) fail "the public key is not checked without --require-public-key" ;; esac
    expect 1 "SUPublicEDKey is missing or empty" --require-public-key "$tmp/good.app"
    expect 1 "SUPublicEDKey is missing or empty" --require-public-key "$tmp/empty-key.app"
    expect 0 "SUPublicEDKey: pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=" --require-public-key "$tmp/with-key.app"
    # Usage and missing files.
    expect 2 "usage:"
    expect 2 "usage:" --version
    expect 2 "usage:" --bogus "$tmp/good.app"
    expect 2 "usage:" "$tmp/good.app" "$tmp/good.app"
    expect 1 "no Info.plist" "$tmp/missing.app"
    echo "check-app-plist self-test ($mode plutil): ok"
  done
  exit 0
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
fi

WANT_VERSION=""
WANT_BUILD=""
REQUIRE_KEY=0
APP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || usage; WANT_VERSION="$2"; shift 2 ;;
    --build) [ $# -ge 2 ] || usage; WANT_BUILD="$2"; shift 2 ;;
    --require-public-key) REQUIRE_KEY=1; shift ;;
    -*) usage ;;
    *) [ -z "$APP" ] || usage; APP="$1"; shift ;;
  esac
done
[ -n "$APP" ] || usage
PLIST="$APP/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "check-app-plist: no Info.plist at $PLIST" >&2
  exit 1
fi

failures=0
problem() {
  echo "check-app-plist: $1" >&2
  failures=$((failures + 1))
}
# The key's value as text (booleans as true/false); empty and exit 1 when the key is missing.
raw() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null; }

# SUEnableAutomaticChecks must be the boolean false: the xml1 form tells a boolean from the string "false".
if ! xml="$(plutil -extract SUEnableAutomaticChecks xml1 -o - "$PLIST" 2>/dev/null)"; then
  problem "SUEnableAutomaticChecks is missing (Sparkle would ask to check automatically on the second launch)"
elif printf '%s\n' "$xml" | grep -q '<false/>'; then
  echo "SUEnableAutomaticChecks: false"
elif printf '%s\n' "$xml" | grep -q '<true/>'; then
  problem "SUEnableAutomaticChecks must be false (update checks are manual only)"
else
  problem "SUEnableAutomaticChecks must be a boolean false"
fi

# Present and non-empty strings.
require_string() {
  local value
  value="$(raw "$1" || true)"
  if [ -z "$value" ]; then problem "$1 is missing or empty"; else echo "$1: $value"; fi
}
require_string SUFeedURL
[ "$REQUIRE_KEY" = 1 ] && require_string SUPublicEDKey

# Expected versions.
require_equal() {
  local key="$1" want="$2" have
  [ -n "$want" ] || return 0
  have="$(raw "$key" || true)"
  if [ "$have" = "$want" ]; then echo "$key: $have"; else problem "$key is ${have:-missing}, expected $want"; fi
}
require_equal CFBundleShortVersionString "$WANT_VERSION"
require_equal CFBundleVersion "$WANT_BUILD"

if [ "$failures" -gt 0 ]; then
  echo "check-app-plist: $failures problem(s)" >&2
  exit 1
fi
echo "check-app-plist: ok"
