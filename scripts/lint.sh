#!/usr/bin/env bash
# Mechanical rules from AGENTS.md and CODING_STANDARDS.md. CI runs this in the linux-core job; run it locally too:
#   scripts/lint.sh               # check the repository; prints file:line per violation, exits 1 if any
#   scripts/lint.sh --self-test   # check that each rule catches a planted violation
#
# Rules (Swift sources only; tests are not checked; lines that are only a comment are ignored):
#   core-imports  Sources/ShotkeeperCore imports only Foundation, FoundationNetworking, Dispatch, Darwin, Glibc,
#                 SQLite3 and CSQLite: no AppKit, SwiftUI, ImageIO, Security, CoreServices (core builds on Linux).
#   file-op       FileManager removeItem/trashItem/moveItem/replaceItem, NSWorkspace recycle and POSIX
#                 unlink/unlinkat/rmdir/rename/renameat/renamex_np and module-qualified remove (`Darwin.remove(`)
#                 only in FileOrganizer, NoReplaceRename and UndoLog (CODING_STANDARDS #1). A line that deletes or
#                 moves the app's own files (logs, PID file, downloaded model) says so with
#                 `// lint-allow: file-op (<why>)`.
#   analyze       `.analyze(` (sending an image to a model) only in ScreenshotProcessor, after UploadConsent.decide
#                 (CODING_STANDARDS #2). Other callers that never send a user file mark the line with
#                 `// lint-allow: analyze (<why>)`.
#
# Allow markers must be the trailing comment of the line and give a non-empty reason in parentheses:
#   `// lint-allow: <rule> (<why>)`. A marker inside a string literal or without a reason does not count.
#
# Known blind spots (grep, not a parser): a line that starts with a comment is skipped entirely, so code after a
# closing `*/` on a `/* ... */ code` line is not checked; method references without a call
# (`let op = FileManager.default.trashItem`) are not caught; a call split so the name and `(` are on different
# lines is not caught.
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
internal import Dispatch
func run() async throws { _ = try await analyzer.analyze(payload, context: context) }
EOF
  cat > "$tmp/App/Shotkeeper/Allowed.swift" <<'EOF'
public import AppKit
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
public import AppKit
package import SwiftUI
internal import CoreGraphics
import Foundation; import Security
func trash() { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
func send() async throws { _ = try await analyzer.analyze(p, context: c) }
EOF
  cat > "$tmp/App/Shotkeeper/Bad.swift" <<'EOF'
func delete() { try? fm.removeItem(at: url) }
func gone() { _ = unlink(path) }
func recycle() { NSWorkspace.shared.recycle([url]) { _, _ in } }
func gone2() { _ = unlinkat(fd, path, 0) }
func gone3() { _ = rmdir(path) }
func gone4() { _ = Darwin.remove(path) }
func gone5() { _ = Glibc.remove(path) }
func gone6() { _ = Foundation.remove(path) }
func spaced() { try? fm.removeItem (at: url) }
func noReason() { try? fm.removeItem(at: url) } // lint-allow: file-op
func emptyReason() { try? fm.removeItem(at: url) } // lint-allow: file-op ()
func inString() { log("// lint-allow: file-op (x)"); try? fm.removeItem(at: url) }
func notTrailing() { try? fm.removeItem(at: url) /* lint-allow: file-op (x) */ ; f() }
func ask() async throws { _ = try await analyzer.analyze(p, context: c) } // lint-allow: analyze
EOF
  cat > "$tmp/App/Shotkeeper/NotFileOps.swift" <<'EOF'
func fine() { items.remove(at: 0); _ = list.removeAll(); set.remove(x) }
EOF
  output="$(LINT_ROOT="$tmp" "$0" 2>&1 || true)"
  # core: 7 imports (AppKit, Security, SwiftUI.Color, public AppKit, package SwiftUI, internal CoreGraphics,
  # `; import Security`) + trashItem + analyze = 9; app: removeItem + unlink + recycle + unlinkat + rmdir +
  # 3 qualified remove + spaced removeItem + 4 bad file-op markers + 1 bad analyze marker = 14
  expected=23
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

# Extended regex for a valid allow marker: the line's trailing `//` comment, with a non-empty reason in parentheses.
allow_marker() {
  printf '%s' "//[[:space:]]*lint-allow:[[:space:]]*$1[[:space:]]+\\([[:space:]]*[^)[:space:]][^)]*\\)[[:space:]]*\$"
}

report() {
  local rule="$1" message="$2" hits="$3"
  [ -z "$hits" ] && return 0
  echo "lint [$rule] $message"
  printf '%s\n' "$hits" | sed 's/^/  /'
  failures=$((failures + $(printf '%s\n' "$hits" | wc -l)))
}

# core-imports
# Optional attributes and Swift 6 access level before `import`, at the start of the line or after a `;`.
import_regex='(^|;)[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+'
allowed_imports=" Foundation FoundationNetworking Dispatch Darwin Glibc SQLite3 CSQLite "
bad_imports=""
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  code="${hit#*:*:}"
  # Every `;`-separated statement on the line that is an import (trailing `//` comment dropped first).
  modules="$(printf '%s\n' "${code%%//*}" | tr ';' '\n' | grep -E "$import_regex" \
    | sed -E "s/$import_regex"'((struct|class|enum|protocol|typealias|func|var|let)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\8/' || true)"
  for module in $modules; do
    case "$allowed_imports" in
      *" $module "*) ;;
      *) bad_imports+="$hit"$'\n'; break ;;
    esac
  done
done < <(code_matches "$import_regex" Sources/ShotkeeperCore)
report core-imports "ShotkeeperCore must build on Linux: Foundation-only imports (AGENTS.md)" "${bad_imports%$'\n'}"

# file-op
file_op_homes='^Sources/ShotkeeperCore/Files/(FileOrganizer|NoReplaceRename|UndoLog)\.swift:'
hits="$(code_matches '(^|[^A-Za-z0-9_])((removeItem|trashItem|moveItem|replaceItem(At)?|recycle|unlink|unlinkat|rmdir|renamex_np|renameat2?)|(Darwin|Glibc|Foundation)\.(rename|remove))[[:space:]]*\(' \
  Sources App/Shotkeeper \
  | grep -vE "$file_op_homes" | grep -vE "$(allow_marker file-op)" || true)"
report file-op "user files move only through FileOrganizer/UndoLog and are never deleted (CODING_STANDARDS #1)" "$hits"

# analyze
hits="$(code_matches '\.analyze\(' Sources App/Shotkeeper \
  | grep -vE '^Sources/ShotkeeperCore/Pipeline/ScreenshotProcessor\.swift:' | grep -vE "$(allow_marker analyze)" || true)"
report analyze "images go to a model only from ScreenshotProcessor, after UploadConsent.decide (CODING_STANDARDS #2)" "$hits"

if [ "$failures" -gt 0 ]; then
  echo "lint: $failures violation(s). Rules and allow markers: scripts/lint.sh header."
  exit 1
fi
echo "lint: ok"
