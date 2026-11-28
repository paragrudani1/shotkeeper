#!/bin/bash
# Signs Shotkeeper.app inside-out, then verifies it. CI's `macos-app` job runs it on every push with the ad-hoc
# identity; the release workflow runs the same script with the self-signed identity (auto-update spec, "The existing
# CI job uses the same signing script" and release flow job 2 steps 2-3; ticket 06).
#
#   scripts/sign-app.sh - path/to/Shotkeeper.app
#   scripts/sign-app.sh [--keychain <file>] "Shotkeeper Release" path/to/Shotkeeper.app
#   scripts/sign-app.sh --self-test     # fake codesign everywhere; on macOS also a real throwaway bundle
#
# Identity: only `-` (ad-hoc) or `Shotkeeper Release` (Parag's certificate, checklist P1.4) is accepted.
# `--keychain` (real identity only): codesign looks for the identity only in that keychain file (codesign(1),
# "--keychain filename"). The release job creates and unlocks that keychain before calling this script; this script
# never sees a password.
#
# Order (inside-out, never `--deep` for signing), each item only if it is in the bundle:
#   1. Sparkle.framework/Versions/B/XPCServices/Installer.xpc and Downloader.xpc (optional: Sparkle allows removing
#      them, and a non-sandboxed app doesn't use them)
#   2. Sparkle.framework/Versions/B/Autoupdate     (required once Sparkle.framework is present)
#   3. Sparkle.framework/Versions/B/Updater.app    (required once Sparkle.framework is present)
#   4. Sparkle.framework
#   5. the app itself
# Sources:
#   [S5] Sparkle, "Sandboxing" > "Code Signing", https://sparkle-project.org/documentation/sandboxing/ : the per-item
#        flags below are copied from its example ("For Sparkle versions >= 2.6" for Downloader.xpc), and "please do
#        not add --deep ... when signing your application".
#   Apple, "Creating distribution-signed code for macOS",
#        https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac : "Sign code
#        from the inside out" and "Don't pass the --deep option to codesign when you sign code" (it helps "in
#        verifying a code signature").
#   Hardened Runtime: Sparkle's helpers ship with it on ([S5]) and keep it (`-o runtime`). The app keeps it off: with
#        Library Validation on, a non-Team-ID signature may stop Sparkle from loading ([S1]
#        https://sparkle-project.org/documentation/ ; App/project.yml has ENABLE_HARDENED_RUNTIME: NO).
#
# Verification: `codesign --verify --deep --strict --verbose=2` (--deep is fine for verifying), a Hardened Runtime
# check per signed item, then `codesign --display -r -` to the log. The DR-shape check (`certificate leaf`, no
# `cdhash`; auto-update research [A8]) runs only for the real identity: an ad-hoc DR is a cdhash by nature.
#
# Logs: no `set -x`; the identity, the keychain path and the app path are never echoed by this script. Runs under
# macOS's bash 3.2 and BSD tools.
set -euo pipefail

REAL_IDENTITY="Shotkeeper Release"
SPARKLE="Contents/Frameworks/Sparkle.framework"
SPARKLE_B="$SPARKLE/Versions/B"

usage() {
  echo "usage: scripts/sign-app.sh [--keychain <file>] <- | Shotkeeper Release> <path/to/App.app>" >&2
  echo "       scripts/sign-app.sh --self-test" >&2
  exit 2
}

# codesign's signing call; `-f -s <identity>` as in [S5], with `--keychain` after it when given.
# codesign's own errors (e.g. no identity found) may name the identity in the log. That is fine: "Shotkeeper Release"
# is public (it is in this script); the certificate and the keychain password are the secrets.
sign() {
  if [ -n "$KEYCHAIN" ]; then
    codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" "$@"
  else
    codesign -f -s "$IDENTITY" "$@"
  fi
}

# CodeDirectory flags of a signed item, e.g. "adhoc,runtime" (from `codesign --display --verbose=1`, on stderr).
cd_flags() {
  codesign --display --verbose=1 "$1" 2>&1 | sed -n 's/^CodeDirectory .*flags=0x[0-9a-fA-F]*(\([^)]*\)).*/\1/p'
}

# Fails unless the item's Hardened Runtime flag is as expected ("on" or "off").
check_runtime() {
  local rel="$1" want="$2" flags have path="$APP" name="the app"
  if [ -n "$rel" ]; then path="$APP/$rel"; name="${rel#Contents/Frameworks/}"; fi
  flags="$(cd_flags "$path")"
  case ",$flags," in
    *,runtime,*) have=on ;;
    *) have=off ;;
  esac
  if [ "$have" != "$want" ]; then
    echo "sign-app: ${name}: Hardened Runtime is $have, expected $want (flags: ${flags:-none})" >&2
    exit 1
  fi
  echo "runtime: ${name}: Hardened Runtime $have (flags: $flags)"
}

run_self_test() {
  local tmp self out status expected
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  self="$0"
  mkdir -p "$tmp/bin"
  # Fake codesign: logs every call; signing records whether `-o runtime` was passed, so `--display --verbose=1`
  # reports the flags this script asked for. FAKE_DR, FAKE_VERIFY_EXIT, FAKE_DROP_RUNTIME, FAKE_APP_RUNTIME steer it.
  cat > "$tmp/bin/codesign" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
last=""; for a in "$@"; do last="$a"; done
case " $* " in
  *" -s "*)
    case " $* " in *" -o runtime "*) echo "runtime $last" >> "$FAKE_STATE" ;; *) echo "plain $last" >> "$FAKE_STATE" ;; esac ;;
  *" --verify "*) echo "$last: valid on disk" >&2; exit "${FAKE_VERIFY_EXIT:-0}" ;;
  *" -r - "*) printf '%s\n' "${FAKE_DR:-# designated => cdhash H\"00\"}" ;;
  *" --verbose=1 "*)
    kind="$(grep -Fx -e "runtime $last" -e "plain $last" "$FAKE_STATE" | tail -1 | cut -d' ' -f1)"
    if [ "$kind" = runtime ] && [ -z "${FAKE_DROP_RUNTIME:-}" ]; then flags="0x10002(adhoc,runtime)"
    elif [ "$kind" = plain ] && [ -n "${FAKE_APP_RUNTIME:-}" ]; then flags="0x10002(adhoc,runtime)"
    else flags="0x2(adhoc)"; fi
    echo "Executable=$last" >&2
    echo "CodeDirectory v=20500 size=1 flags=$flags hashes=1+0 location=embedded" >&2 ;;
esac
exit 0
EOF
  chmod +x "$tmp/bin/codesign"

  # A bundle shaped like the app with Sparkle 2 embedded (files only; the fake never reads them).
  make_fake_app() {
    local app="$1" parts="$2" fw="$1/$SPARKLE"
    mkdir -p "$app/Contents/MacOS"
    : > "$app/Contents/MacOS/App"
    case "$parts" in none) return 0 ;; esac
    if [ "$parts" = no-b ]; then mkdir -p "$fw/Versions/A"; return 0; fi
    mkdir -p "$fw/Versions/B"
    case "$parts" in *xpc*) mkdir -p "$fw/Versions/B/XPCServices/Installer.xpc" "$fw/Versions/B/XPCServices/Downloader.xpc" ;; esac
    case "$parts" in *autoupdate*) : > "$fw/Versions/B/Autoupdate" ;; esac
    case "$parts" in *updater*) mkdir -p "$fw/Versions/B/Updater.app" ;; esac
  }

  # Runs the script against the fake codesign; sets $out (stdout+stderr), $status and $tmp/calls (APP-relative).
  run_fake() {
    : > "$tmp/log"; : > "$tmp/state"
    status=0
    out="$(PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/log" FAKE_STATE="$tmp/state" "$BASH" "$self" "$@" 2>&1)" || status=$?
    sed "s|$tmp/[A-Za-z0-9_-]*\.app|APP|g; s|$tmp/|TMP/|g" "$tmp/log" > "$tmp/calls"
  }

  fail() {
    echo "sign-app self-test: $1"
    echo "--- output:"; printf '%s\n' "$out"
    echo "--- codesign calls:"; cat "$tmp/calls"
    exit 1
  }

  make_fake_app "$tmp/full.app" xpc,autoupdate,updater
  make_fake_app "$tmp/plain.app" none
  make_fake_app "$tmp/noxpc.app" autoupdate,updater
  make_fake_app "$tmp/noauto.app" xpc,updater
  make_fake_app "$tmp/noupdater.app" xpc,autoupdate
  make_fake_app "$tmp/nob.app" no-b
  : > "$tmp/release.keychain-db"

  # 1. Ad-hoc, full Sparkle: exact order and flags ([S5]), app without runtime, verify, runtime checks, DR.
  run_fake - "$tmp/full.app"
  [ "$status" = 0 ] || fail "ad-hoc full bundle failed (exit $status)"
  expected='-f -s - -o runtime APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc
-f -s - -o runtime --preserve-metadata=entitlements APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc
-f -s - -o runtime APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate
-f -s - -o runtime APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app
-f -s - -o runtime APP/Contents/Frameworks/Sparkle.framework
-f -s - APP
--verify --deep --strict --verbose=2 APP
--display --verbose=1 APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc
--display --verbose=1 APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc
--display --verbose=1 APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate
--display --verbose=1 APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app
--display --verbose=1 APP/Contents/Frameworks/Sparkle.framework
--display --verbose=1 APP
--display -r - APP'
  [ "$(cat "$tmp/calls")" = "$expected" ] || fail "ad-hoc full bundle: unexpected codesign calls; expected:
$expected"
  case "$out" in *"DR shape check skipped"*) ;; *) fail "ad-hoc run did not say the DR shape check was skipped" ;; esac
  case "$out" in *'designated => cdhash'*) ;; *) fail "the DR was not printed" ;; esac

  # 2. No `--deep` in any signing call (`-s`), across every run below too.
  check_no_deep() {
    if grep -e ' -s ' "$tmp/calls" | grep -q -e '--deep'; then fail "a signing call used deep signing"; fi
  }
  check_no_deep

  # 3. No Sparkle yet (before ticket 07): only the app is signed.
  run_fake - "$tmp/plain.app"
  [ "$status" = 0 ] || fail "bundle without Sparkle failed"
  [ "$(grep -c -e ' -s ' "$tmp/calls")" = 1 ] && grep -qx -e '-f -s - APP' "$tmp/calls" \
    || fail "bundle without Sparkle: expected one signing call for the app"
  case "$out" in *"Sparkle.framework is not in the bundle"*) ;; *) fail "missing Sparkle was not reported" ;; esac
  check_no_deep

  # 4. XPC services removed: skipped, the rest signed in order.
  run_fake - "$tmp/noxpc.app"
  [ "$status" = 0 ] || fail "bundle without XPC services failed"
  [ "$(grep -e ' -s ' "$tmp/calls" | sed 's|.*APP|APP|')" = "APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate
APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app
APP/Contents/Frameworks/Sparkle.framework
APP" ] || fail "bundle without XPC services: wrong signing order"
  case "$out" in *"skip: Sparkle.framework/Versions/B/XPCServices/Installer.xpc"*) ;; *) fail "skipped XPC not reported" ;; esac

  # 5. Sparkle present but incomplete or a different layout: fail before signing anything.
  for broken in noauto noupdater nob; do
    run_fake - "$tmp/$broken.app"
    [ "$status" = 1 ] || fail "$broken: expected exit 1, got $status"
    if grep -q -e ' -s ' "$tmp/calls"; then fail "$broken: signed something before failing"; fi
  done

  # 6. Real identity with a keychain: same order, `--keychain` after the identity, DR shape enforced, nothing echoed.
  run_fake --keychain "$tmp/release.keychain-db" "$REAL_IDENTITY" "$tmp/full.app"
  [ "$status" = 1 ] || fail "real identity with a cdhash DR: expected exit 1, got $status"
  FAKE_DR='# designated => identifier "dev.shotkeeper.Shotkeeper" and certificate leaf = H"ab12"' \
    run_fake --keychain "$tmp/release.keychain-db" "$REAL_IDENTITY" "$tmp/full.app"
  [ "$status" = 0 ] || fail "real identity with a certificate-leaf DR failed"
  [ "$(head -1 "$tmp/calls")" = "-f -s $REAL_IDENTITY --keychain TMP/release.keychain-db -o runtime APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" ] \
    || fail "real identity: --keychain not passed after the identity"
  [ "$(grep -c -e '--keychain' "$tmp/calls")" = 6 ] || fail "real identity: --keychain missing from a signing call"
  # (codesign itself prints the app path, which is not secret; the identity and keychain path must never appear.)
  case "$out" in *"$REAL_IDENTITY"*|*release.keychain-db*) fail "the identity or the keychain path was echoed" ;; esac
  case "$out" in *"DR shape: ok"*) ;; *) fail "real identity: DR shape check did not run" ;; esac
  check_no_deep
  FAKE_DR='# designated => identifier "x" and certificate leaf = H"ab" or cdhash H"00"' \
    run_fake "$REAL_IDENTITY" "$tmp/full.app"
  [ "$status" = 1 ] || fail "real identity with a DR naming a cdhash: expected exit 1"

  # 7. Hardened Runtime checks: a helper without it, or an app with it, fails.
  FAKE_DROP_RUNTIME=1 run_fake - "$tmp/full.app"
  [ "$status" = 1 ] || fail "helper without Hardened Runtime was accepted"
  FAKE_APP_RUNTIME=1 run_fake - "$tmp/full.app"
  [ "$status" = 1 ] || fail "app with Hardened Runtime was accepted"

  # 8. Verification failure fails the script.
  FAKE_VERIFY_EXIT=3 run_fake - "$tmp/full.app"
  [ "$status" != 0 ] || fail "a failed verification was accepted"

  # 9. Usage errors exit 2 without echoing the input.
  for args in "Somebody Else|$tmp/full.app" "|$tmp/full.app" "-" "--keychain|$tmp/release.keychain-db|-|$tmp/full.app" \
      "--keychain" "--unknown|-|$tmp/full.app" "-|$tmp/full.app|extra"; do
    set -f; old_ifs="$IFS"; IFS='|'
    # shellcheck disable=SC2086
    set -- $args
    IFS="$old_ifs"; set +f
    run_fake "$@"
    [ "$status" = 2 ] || fail "usage error ($*): expected exit 2, got $status"
    case "$out" in *"Somebody Else"*|*"$tmp"*) fail "a usage error echoed its input" ;; esac
  done
  # A missing app or keychain file fails (exit 1) without echoing the path.
  run_fake - "$tmp/missing.app"
  [ "$status" = 1 ] || fail "missing app: expected exit 1, got $status"
  run_fake --keychain "$tmp/missing.keychain-db" "$REAL_IDENTITY" "$tmp/full.app"
  [ "$status" = 1 ] || fail "missing keychain: expected exit 1, got $status"
  case "$out" in *"$tmp"*) fail "a missing path was echoed" ;; esac
  echo "sign-app self-test (fake codesign): ok"

  if [ "$(uname -s)" = Darwin ]; then
    real_self_test "$tmp/real"
    echo "sign-app self-test (real codesign, throwaway bundle): ok"
  else
    echo "sign-app self-test: not macOS, real codesign part skipped"
  fi
}

# On macOS: a throwaway app with a Sparkle-shaped framework of tiny real Mach-O files, signed ad-hoc by this script
# with the real codesign. Exercises the Sparkle order before Sparkle is linked (ticket 07).
real_self_test() {
  local root="$1" app fw b
  app="$root/Throwaway.app"; fw="$app/$SPARKLE"; b="$fw/Versions/B"
  mkdir -p "$root/src" "$app/Contents/MacOS" "$b/Resources" "$b/Updater.app/Contents/MacOS" \
    "$b/XPCServices/Installer.xpc/Contents/MacOS" "$b/XPCServices/Downloader.xpc/Contents/MacOS"
  printf 'int main(void) { return 0; }\n' > "$root/src/main.c"
  printf 'int sparkle_stub(void) { return 0; }\n' > "$root/src/lib.c"
  plist() { # <file> <executable> <identifier> <package type>
    cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$2</string>
<key>CFBundleIdentifier</key><string>$3</string>
<key>CFBundlePackageType</key><string>$4</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
EOF
  }
  cc -o "$app/Contents/MacOS/Throwaway" "$root/src/main.c"
  plist "$app/Contents/Info.plist" Throwaway dev.shotkeeper.selftest.app APPL
  cc -dynamiclib -install_name @rpath/Sparkle.framework/Versions/B/Sparkle -o "$b/Sparkle" "$root/src/lib.c"
  plist "$b/Resources/Info.plist" Sparkle dev.shotkeeper.selftest.sparkle FMWK
  cc -o "$b/Autoupdate" "$root/src/main.c"
  cc -o "$b/Updater.app/Contents/MacOS/Updater" "$root/src/main.c"
  plist "$b/Updater.app/Contents/Info.plist" Updater dev.shotkeeper.selftest.updater APPL
  cc -o "$b/XPCServices/Installer.xpc/Contents/MacOS/Installer" "$root/src/main.c"
  plist "$b/XPCServices/Installer.xpc/Contents/Info.plist" Installer dev.shotkeeper.selftest.installer XPC!
  cc -o "$b/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" "$root/src/main.c"
  plist "$b/XPCServices/Downloader.xpc/Contents/Info.plist" Downloader dev.shotkeeper.selftest.downloader XPC!
  ln -s B "$fw/Versions/Current"
  for link in Sparkle Resources Autoupdate Updater.app XPCServices; do ln -s "Versions/Current/$link" "$fw/$link"; done
  # Sparkle ships Downloader.xpc with entitlements; [S5]'s `--preserve-metadata=entitlements` must keep them.
  cat > "$root/src/downloader.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.network.client</key><true/></dict></plist>
EOF
  codesign -f -s - -o runtime --entitlements "$root/src/downloader.entitlements" "$b/XPCServices/Downloader.xpc"

  "$BASH" "$0" - "$app"

  if ! codesign --display --entitlements - --xml "$b/XPCServices/Downloader.xpc" 2>/dev/null \
      | grep -q com.apple.security.network.client; then
    echo "sign-app self-test: Downloader.xpc lost its entitlements"
    exit 1
  fi
  echo "self-test: Downloader.xpc kept its entitlements"
}

# --- main ---
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  run_self_test
  exit 0
fi

KEYCHAIN=""
if [ "${1:-}" = "--keychain" ]; then
  [ "$#" -ge 2 ] || usage
  KEYCHAIN="$2"
  shift 2
fi
[ "$#" -eq 2 ] || usage
IDENTITY="$1"
APP="$2"
case "$IDENTITY" in
  -|"$REAL_IDENTITY") ;;
  *) echo "sign-app: unknown identity (expected - or the release certificate's name)" >&2; exit 2 ;;
esac
if [ "$IDENTITY" = "-" ] && [ -n "$KEYCHAIN" ]; then
  echo "sign-app: --keychain applies only to the real identity, not ad-hoc" >&2
  exit 2
fi
if [ -n "$KEYCHAIN" ] && [ ! -f "$KEYCHAIN" ]; then
  echo "sign-app: the --keychain file does not exist" >&2
  exit 1
fi
if [ ! -d "$APP/Contents/MacOS" ]; then
  echo "sign-app: the app path is not an app bundle" >&2
  exit 1
fi
if [ "$IDENTITY" = "-" ]; then echo "identity: ad-hoc"; else echo "identity: release certificate"; fi

# Plan the Sparkle items first, so an unexpected layout fails before anything is signed.
signed_helpers=""
xpcs=""
if [ -d "$APP/$SPARKLE" ]; then
  if [ ! -d "$APP/$SPARKLE_B" ]; then
    echo "sign-app: Sparkle.framework has no Versions/B; update this script for the new layout ([S5])" >&2
    exit 1
  fi
  for required in Autoupdate Updater.app; do
    if [ ! -e "$APP/$SPARKLE_B/$required" ]; then
      echo "sign-app: Sparkle.framework is embedded but has no Versions/B/$required" >&2
      exit 1
    fi
  done
  for xpc in Installer.xpc Downloader.xpc; do
    if [ -d "$APP/$SPARKLE_B/XPCServices/$xpc" ]; then
      xpcs="$xpcs $xpc"
    else
      echo "skip: ${SPARKLE_B#Contents/Frameworks/}/XPCServices/$xpc is not in the bundle"
    fi
  done

  # Flags per item: [S5] "Code Signing" example (Sparkle >= 2.6 for Downloader.xpc). Never --deep.
  for xpc in $xpcs; do
    rel="$SPARKLE_B/XPCServices/$xpc"
    echo "sign: ${rel#Contents/Frameworks/} (Hardened Runtime)"
    if [ "$xpc" = Downloader.xpc ]; then
      sign -o runtime --preserve-metadata=entitlements "$APP/$rel"
    else
      sign -o runtime "$APP/$rel"
    fi
    signed_helpers="$signed_helpers $rel"
  done
  for rel in "$SPARKLE_B/Autoupdate" "$SPARKLE_B/Updater.app" "$SPARKLE"; do
    echo "sign: ${rel#Contents/Frameworks/} (Hardened Runtime)"
    sign -o runtime "$APP/$rel"
    signed_helpers="$signed_helpers $rel"
  done
else
  echo "skip: Sparkle.framework is not in the bundle (its items are skipped)"
fi

# The app: no `-o runtime` (Hardened Runtime stays off, [S1]; App/project.yml).
echo "sign: the app (no Hardened Runtime)"
sign "$APP"

echo "verify: codesign --verify --deep --strict --verbose=2"
codesign --verify --deep --strict --verbose=2 "$APP"

for rel in $signed_helpers; do check_runtime "$rel" on; done
check_runtime "" off

echo "designated requirement (codesign --display -r -):"
dr="$(codesign --display -r - "$APP")"
printf '%s\n' "$dr"
case "$dr" in
  *"designated =>"*) ;;
  *) echo "sign-app: codesign printed no designated requirement" >&2; exit 1 ;;
esac
if [ "$IDENTITY" = "-" ]; then
  echo "DR shape check skipped: an ad-hoc signature's DR is a cdhash by nature; it runs with the release identity"
else
  case "$dr" in
    *cdhash*) echo "sign-app: the DR names a cdhash; expected certificate leaf only ([A8])" >&2; exit 1 ;;
    *"certificate leaf"*) echo "DR shape: ok (certificate leaf, no cdhash)" ;;
    *) echo "sign-app: the DR has no certificate leaf ([A8])" >&2; exit 1 ;;
  esac
fi
echo "sign-app: signed and verified"
