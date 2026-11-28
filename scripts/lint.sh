#!/usr/bin/env bash
# Mechanical rules from AGENTS.md and CODING_STANDARDS.md. CI runs this in the linux-core job; run it locally too:
#   scripts/lint.sh               # check the repository; prints file:line per violation, exits 1 if any
#   scripts/lint.sh --self-test   # check that each rule catches a planted violation
#
# Rules (Swift sources only; tests are not checked; lines that are only a comment are ignored):
#   core-imports  Sources/ShotkeeperCore imports only Foundation, FoundationNetworking, Dispatch, Darwin, Glibc,
#                 SQLite3 and CSQLite: no AppKit, SwiftUI, ImageIO, Security, CoreServices (core builds on Linux).
#   file-op       FileManager removeItem/trashItem/moveItem/replaceItem and POSIX unlink/rename only in
#                 FileOrganizer, NoReplaceRename and UndoLog (CODING_STANDARDS #1). A line that deletes or moves
#                 the app's own files (logs, PID file, downloaded model) says so with `// lint-allow: file-op (<why>)`.
#   analyze       `.analyze(` (sending an image to a model) only in ScreenshotProcessor, after UploadConsent.decide
#                 (CODING_STANDARDS #2). Other callers that never send a user file mark the line with
#                 `// lint-allow: analyze (<why>)`.
set -euo pipefail

ROOT="${LINT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/Sources/ShotkeeperCore/Files" "$tmp/Sources/ShotkeeperCore/Pipeline" "$tmp/App/Shotkeeper"
  cat > "$tmp/Sources/ShotkeeperCore/Files/FileOrganizer.swift" <<'EOF'
import Foundation
#if canImport(Glibc)
import Glibc
#endif
func move() { try? FileManager.default.moveItem(at: a, to: b) }
EOF
  cat > "$tmp/Sources/ShotkeeperCore/Pipeline/ScreenshotProcessor.swift" <<'EOF'
@preconcurrency import Foundation
func run() async throws { _ = try await analyzer.analyze(payload, context: context) }
EOF
  cat > "$tmp/App/Shotkeeper/Allowed.swift" <<'EOF'
import AppKit
func clean() { try? FileManager.default.removeItem(at: log) } // lint-allow: file-op (our own log)
// try FileManager.default.removeItem(at: userFile) is only a comment here
func test() async throws { _ = try await analyzer.analyze(image, context: c) } // lint-allow: analyze (generated image)
EOF
  if ! LINT_ROOT="$tmp" "$0" >/dev/null; then
    echo "self-test: a clean tree failed"; LINT_ROOT="$tmp" "$0" || true; exit 1
  fi
  cat > "$tmp/Sources/ShotkeeperCore/Bad.swift" <<'EOF'
import AppKit
@preconcurrency import Security
import struct SwiftUI.Color
func trash() { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
func send() async throws { _ = try await analyzer.analyze(p, context: c) }
EOF
  cat > "$tmp/App/Shotkeeper/Bad.swift" <<'EOF'
func delete() { try? fm.removeItem(at: url) }
func gone() { _ = unlink(path) }
EOF
  output="$(LINT_ROOT="$tmp" "$0" 2>&1 || true)"
  expected=7  # 3 imports + trashItem + removeItem + unlink + analyze
  found="$(printf '%s\n' "$output" | grep -c '^  ' || true)"
  if [ "$found" != "$expected" ]; then
    echo "self-test: expected $expected violations, got $found:"; printf '%s\n' "$output"; exit 1
  fi
  echo "lint self-test: ok"
  exit 0
fi

cd "$ROOT"
failures=0

# Lines of Swift code under the given paths matching the extended regex, as "file:line:text". Lines whose code
# starts with a comment are dropped.
code_matches() {
  local pattern="$1"; shift
  local existing=()
  for path in "$@"; do [ -e "$path" ] && existing+=("$path"); done
  [ ${#existing[@]} -eq 0 ] && return 0
  grep -rnE --include='*.swift' -- "$pattern" "${existing[@]}" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*)' || true
}

report() {
  local rule="$1" message="$2" hits="$3"
  [ -z "$hits" ] && return 0
  echo "lint [$rule] $message"
  printf '%s\n' "$hits" | sed 's/^/  /'
  failures=$((failures + $(printf '%s\n' "$hits" | wc -l)))
}

# core-imports
allowed_imports=" Foundation FoundationNetworking Dispatch Darwin Glibc SQLite3 CSQLite "
bad_imports=""
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  code="${hit#*:*:}"
  module="$(printf '%s\n' "$code" | sed -E 's/^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\4/')"
  case "$allowed_imports" in
    *" $module "*) ;;
    *) bad_imports+="$hit"$'\n' ;;
  esac
done < <(code_matches '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' Sources/ShotkeeperCore)
report core-imports "ShotkeeperCore must build on Linux: Foundation-only imports (AGENTS.md)" "${bad_imports%$'\n'}"

# file-op
file_op_homes='^Sources/ShotkeeperCore/Files/(FileOrganizer|NoReplaceRename|UndoLog)\.swift:'
hits="$(code_matches '(^|[^A-Za-z0-9_])((removeItem|trashItem|moveItem|replaceItem(At)?|unlink|renamex_np|renameat2?)|(Darwin|Glibc)\.rename)\(' \
  Sources App/Shotkeeper \
  | grep -vE "$file_op_homes" | grep -v 'lint-allow: file-op' || true)"
report file-op "user files move only through FileOrganizer/UndoLog and are never deleted (CODING_STANDARDS #1)" "$hits"

# analyze
hits="$(code_matches '\.analyze\(' Sources App/Shotkeeper \
  | grep -vE '^Sources/ShotkeeperCore/Pipeline/ScreenshotProcessor\.swift:' | grep -v 'lint-allow: analyze' || true)"
report analyze "images go to a model only from ScreenshotProcessor, after UploadConsent.decide (CODING_STANDARDS #2)" "$hits"

if [ "$failures" -gt 0 ]; then
  echo "lint: $failures violation(s). Rules and allow markers: scripts/lint.sh header."
  exit 1
fi
echo "lint: ok"
