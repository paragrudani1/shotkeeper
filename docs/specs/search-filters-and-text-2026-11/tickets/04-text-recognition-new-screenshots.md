# 04: Read the text in new screenshots (Vision, runner)

**What to build:** each new screenshot that the model analyses successfully is marked `pending`; right after, on the
Mac, Shotkeeper reads all its text with Apple Vision and stores it, so a search finds words that appear only in the
image. The rename toast is not delayed. Reading resumes after quit and relaunch. The text never leaves the Mac.

**Blocked by:** 01 (columns, conditional write, newest-pending query). PR #10 merged (the runner is started from the
coordinator, whose parts it split). **Merge gate:** the Vision constants are set from 05's measurement note before
this PR merges (spec "Vision settings to measure"); the PR can be built and reviewed before that.

**Status:** ready-for-agent

**Sources:** spec "Text recognition: where it runs", "when it runs", "Privacy", stories 24–27, 43–51; research
`docs/research/spotlight-shortcuts-ocr.md` §3 ([V1]–[V4], [WV19], [WV22], [WV24]) cited next to the Vision code.

**Test seams:** seam 3 (new): `TextRecognitionRunner` with a stub `TextRecognizer` over a real in-memory index
(prior art `StubAnalyzer`, `TempDir` in `ScreenshotProcessorTests`); plus one assertion in the existing processor seam.

**Likely touches:** core `TextRecognizer` port (new, Foundation only), pure line ordering/joining/cap and the pixel
floor function, `TextRecognitionRunner` (new), `ScreenshotProcessor` (set `pending` on a successful `done` save);
app `VisionTextRecognizer` (new file, `VNRecognizeTextRequest` revision 3), coordinator startup/quit wiring.
Hotspot: `ScreenshotProcessor.swift` (wave 2 also edits it; wave 1 only adds one field here).
Does not touch the search panel, so it runs in parallel with 02, 03 and 06.

- [ ] `TextRecognizer`: file URL → lines (text, confidence, normalized box). Core imports nothing from Vision; Linux
      and the CLI have no recognizer and rows stay `pending`.
- [ ] Pure rules, tested through the text a row ends up with: top-to-bottom then left-to-right with a same-baseline
      tolerance; joined with "\n"; whitespace-only lines dropped; empty → `none`; cap at 100,000 characters cut at a
      line boundary and marked truncated.
- [ ] Runner: subscribes to `changes()`, wakes at launch, reads one row at a time newest `pending` first at utility
      priority, reads the original file at the row's current path (not the `ImagePreparer` payload), writes through
      01's conditional write, stops on quit. Tests: `pending` → `done` / `none` / `failed`; missing file → `failed`
      "file missing"; content changed during the read → late result dropped and the row read again (story 45);
      newest first; the row's analysis and `done` status untouched.
- [ ] `ScreenshotProcessor`: a successful analysis saves the row with `text_status = pending`; test asserts that and
      that the analyzer request carries no recognized text (`AnalysisContext` unchanged), for both backends.
- [ ] `text_recognized_by` records the recognizer id and settings (e.g. `vision-r3-accurate-h1/96-lc0`) from core
      constants.
- [ ] Privacy: recognized text never in `AnalysisContext`, prompts, `FinderMetadata` (tags/comment), the undo log,
      `note`, `text_error`, `lastError`, os_log or CLI output. Dated wiki line stating the rule (spec "Privacy").
- [ ] Pause doesn't stop reading (spec decision 8); restored-by-undo rows are read like any `done` row.
- [ ] CI snapshots: none new (no UI). Existing snapshots unchanged.
- [ ] Real-Mac checks: a new screenshot's words become searchable within seconds; the rename toast timing is unchanged;
      Vision runs on macOS 14; memory stays bounded while reading.
- [ ] Linux tests and `scripts/lint.sh` green; `docs/core-api.md` updated.
- [ ] **Done only when `macos-app` CI is green** on the PR.
