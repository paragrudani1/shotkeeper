# 06: Shared Xcode and signing scripts, run ad-hoc in `macos-app` on every push

**What to build:** the release's signing path exists and runs on every CI push before any secret or certificate
exists. `macos-app` stops calling `codesign --force --deep --sign -` and instead calls one signing script with the
ad-hoc identity `-`. The script signs inside-out and never with `--deep`: Sparkle's XPC services (if present),
`Autoupdate`, `Updater.app`, `Sparkle.framework`, then `Shotkeeper.app`. Items that aren't in the bundle yet (no
Sparkle until 07) are skipped. Then it verifies. The "Select newest stable Xcode" step moves into a shared script
that the release workflow (09) will call too. The CI artifact stays `Shotkeeper-unsigned`, ad-hoc, build 1.

**Blocked by:** None for the work. It edits `.github/workflows/ci.yml`, which PR #10 also changes (it adds the lint
steps). Start on `main` now and rebase after PR #10 merges, or start once it merges. Expect a small conflict only.

**Status:** ready-for-agent

**Sources:** spec "The existing CI job uses the same signing script", release flow job 1 step 1 and job 2 steps 2–3,
stories 32, 35; Testing Decisions, seam 3.

**Test seam:** seam 3, the CI workflow itself. The script also gets a `--self-test` (or equivalent) that runs on a
throwaway bundle so the Sparkle order is exercised before Sparkle is linked. Prior art: `scripts/lint.sh --self-test`
from PR #10.

- [ ] Signing script takes the identity (`-` or `Shotkeeper Release`) and an optional `--keychain`; per-item flags
      copied from Sparkle's documented example ([S5]), cited in a comment next to them. Sparkle's helpers keep
      Hardened Runtime; the app does not ([S1], [R2]).
- [ ] Verification: `codesign --verify --deep --strict --verbose=2` (`--deep` is allowed for verifying only), then
      `codesign --display -r -` printed to the log. The DR-shape check (`certificate leaf`, no `cdhash`) is enabled
      only for a real identity; with `-` the DR is a cdhash by nature, so the script skips that check and says so.
- [ ] A grep-style guard (in `scripts/lint.sh` from PR #10, or in the script's self-test) fails if `--deep` appears in
      a signing call.
- [ ] Shared Xcode-selection script used by `macos-app`; same Xcode chosen as today (compare the logged path).
- [ ] Scripts run under macOS's bash 3.2 and BSD tools (as `lint.sh` does), with no `set -x` and no `echo` of
      inputs.
- [ ] Dated wiki lines in `docs/wiki/macos-ci.md` (and `auto-update.md`, created by whichever of 01/06 merges first).
- [ ] **Done only when `macos-app` CI is green** on the PR, and the downloaded artifact still verifies with
      `codesign --verify --deep --strict`.

**Real-Mac checks:** the CI artifact from this PR opens on a Mac exactly as before (README "Install the CI build"
steps). Anyone with a Mac can do it; list it in the PR.
