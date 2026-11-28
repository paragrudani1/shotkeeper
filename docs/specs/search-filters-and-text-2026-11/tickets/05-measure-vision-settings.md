# 05: Measure the Vision settings on a real Mac (needs Parag)

**What to build:** a dated note in `docs/research/` with measured Vision settings, so 04 ships constants chosen on real
screenshots rather than defaults that skip interface text.

**Blocked by:** None for the script. Parag's Mac is needed to run it. 04 cannot merge until this note exists.

**Status:** needs-human (Parag runs the measurement; an agent prepares the script and writes up the results)

**Sources:** spec "Vision settings to measure on a real Mac" (candidates, test set, measures, decision rule);
research §3 [V1] [V3] [V4] [WV19] [WV22].

**Test seam:** none (measurement). The script is a macOS-only tool, not core, and is not part of the app build.

**Likely touches:** a measurement script under `scripts/` (macOS only, runs one `VNRecognizeTextRequest` revision 3
configuration per pass over a folder) and `docs/research/vision-ocr-settings.md`.

- [ ] Script sweeps `minimumTextHeight` 1/32, 1/64, 1/96, 1/128 and a ~10 px floor (`10 / pixelHeight`), `.accurate` vs
      `.fast`, language correction on/off, automatic language detection on. It uses the same request setup that 04
      uses (same revision and flags), so the results apply.
- [ ] Parag's test set (~20 images): Retina full screen, non-Retina external display, a window, a small region, dark
      mode, code, a chat, a receipt, non-English text. Images stay on his Mac; nothing is committed or uploaded.
- [ ] Per combination: median and slowest time per image, peak memory, known small strings found (title-bar filename,
      chat timestamp), code verbatim. The note never quotes private screenshot text.
- [ ] Decision per the spec's rule, confirmed by Parag: lowest height with `.accurate` unless the slowest image takes
      more than ~2 s; then raise the height before switching to `.fast`. The chosen values go into 04's core constants.
- [ ] Dated wiki line pointing at the note.
- [ ] If the script lands in the repo: **done only when `macos-app` CI is green** on that PR.
