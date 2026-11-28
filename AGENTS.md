# Shotkeeper: agent guide

macOS menu-bar app that renames, tags and indexes new screenshots using a model backend (Cloudflare Clairic, or local Inkling 2 Mini).

## Layout
- `Sources/ShotkeeperCore` — Foundation-only core. MUST build on Linux: no AppKit, SwiftUI, ImageIO, Security, CoreServices imports.
  Use `#if canImport(FoundationNetworking)` for URLSession on Linux; SQLite via `#if canImport(SQLite3) import SQLite3 #else import CSQLite`.
- `Tests/ShotkeeperCoreTests` — XCTest; fixtures in `Tests/ShotkeeperCoreTests/Fixtures` (load with `Bundle.module`).
- `Sources/shotkeeper-cli` — CLI for live analyzer calls and release tooling.
- `App/` — macOS app (XcodeGen `App/project.yml`), built only in CI. Its one third-party dependency is Sparkle, pinned `exactVersion: 2.10.1`, app target only, imported only in `App/Shotkeeper/Coordinator/UpdateChecks.swift` (approved by Parag 2026-11-28; upgrades are their own PR with the real-Mac checks).
- `design/icon/` — app icon and menu bar glyph SVGs, generated from core `IconGeometry` with the AppIcon asset catalog and `App/Shotkeeper/AppIcon.icon` by `scripts/make-icons.sh` (never hand-edit).
- `docs/wiki/` — dated decision log (read `docs/wiki/index.md` first). `docs/research/` — API facts with sources.
- `docs/specs/` — approved product specs (verbatim from Parag; never edit the requirements).

## Commands (Linux box)
- Test core: `scripts/test-linux.sh` (Docker, no network). Build only: `scripts/test-linux.sh build`.
- Concurrent callers: set `SCRATCH=.build/linux-<you>`.
- GitHub: the repo is public since 2026-11-22, so plain `gh` and the T3 PR tools can read it. Push, merge and run commands use `/root/local-dev/shotkeeper-llm/bin/gh-shotkeeper`, which since 2026-11-28 is plain `gh` (the machine's login) with `GH_REPO` set; `git push` uses the global `gh auth git-credential` helper (no repo-local helper).
- macOS app code compiles only in CI (`.github/workflows/ci.yml`); read failures with `gh-shotkeeper run view <id> --log-failed`.
- A green Linux run does not prove core builds on macOS: Linux has no availability checks (e.g. `AsyncSequence.Failure` is macOS 15+, the package targets 14). Core-only changes still need the `macos-app` CI job green before you report done.
- `gh-shotkeeper run watch` ends with a 403 "annotations" warning that hides the result: read it with `gh-shotkeeper run view <id> --json conclusion,jobs`.
- Never install a host Swift toolchain; never use `docker system/image/volume prune`. Keep ≥15 GB disk free.

## Rules
- Never delete or overwrite a user file. Moves/renames must fail rather than replace.
- No guessing external API schemas: cite `docs/research/` or the live docs in a comment next to request/response code.
- Never print or commit secrets (`.env*` is gitignored). Cloudflare token lives in Keychain in the app.
- Every behaviour in core gets a unit test; tests must not need network.
- No workarounds for a temporary state of `main` or the environment (missing permission, missing tests, flaky runner): report it instead.
- Reviewers: check changes against `CODING_STANDARDS.md`.
