# Vision text recognition settings: measurement (ticket 05, prepared 2026-11-28, results 2026-11-28)

Chooses the Vision constants for ticket 04 (`VisionTextRecognizer`) from measurements on Parag's Mac, following the
spec `docs/specs/search-filters-and-text-2026-11.md`, "Vision settings to measure on a real Mac". Background and
sources: `docs/research/spotlight-shortcuts-ocr.md` §3 ([V1] [V3] [V4] [WV19] [WV22]).

Tool: `scripts/measure-vision.swift`. macOS only; not part of the Swift package or the app. The `macos-app` CI job
type-checks it and runs it on two generated sample images.

## What the tool measures

One `VNRecognizeTextRequest` per image, revision 3, read from the original file with `VNImageRequestHandler(url:)`.
This is the setup ticket 04 must use, so the numbers apply to it. It tries 20 settings:

| Setting | Values |
|---|---|
| Recognition level | `.accurate`, `.fast` |
| Minimum text height (`minimumTextHeight`) | 1/32 (Apple's default), 1/64, 1/96, 1/128, and a 10 px floor (`10 / image pixel height`) |
| Language correction (`usesLanguageCorrection`) | on, off |
| Automatic language detection (`automaticallyDetectsLanguage`) | on with `.accurate`; `.fast` does not support it [V1] [WV22] |

For each setting it reports the median and slowest time per image, peak memory, how many of your known strings it
found, and which ones it missed (by line number in your strings file). Each setting's id has the same shape as 04's
`text_recognized_by`, for example `vision-r3-accurate-h1/96-lc0`.

Privacy: the recognised text stays in memory. The tool never prints or saves it, nor your expected strings; the table
lists only line numbers, counts, times and memory, plus the image file names. Nothing is uploaded.

## How to run (Parag)

You need a Mac with Xcode or the Command Line Tools installed (`xcode-select --install` if `xcrun` is missing). It
takes about 15–20 minutes, most of it collecting screenshots. The sweep itself takes a few minutes.

### 1. Collect about 20 screenshots

Use your own real screenshots, in their original files (not resized or re-saved). Aim for roughly:

| How many | What |
|---|---|
| 3 | Full screen on the Retina (built-in) display |
| 2 | Full screen on a non-Retina external display (skip if you have none, and say so when you paste back) |
| 3 | One window (Shift-Command-4, then Space) |
| 2 | A small region |
| 2 | Dark mode |
| 3 | Code (an editor or terminal) |
| 2 | A chat with timestamps |
| 1 | A receipt or invoice |
| 2 | Non-English text |

Several of these can overlap (a dark-mode code window counts for both).

### 2. Put them in one folder

Make a new folder outside the repo, for example `~/vision-test`, and copy the screenshots into it. Give them
short names without a colon, for example `01-retina-full.png`, `02-chat.png`. The images stay on your Mac; do not add
them to the repo or send them anywhere.

### 3. Write `strings.txt` in the same folder

List small pieces of text you can see in each screenshot, so the tool can check whether Vision found them. One per
line: the image file name, a colon, then the text. Pick the hard ones:

- the file name in a window's title bar;
- a timestamp in a chat;
- small menu-bar or sidebar labels;
- for code, a whole line copied exactly, starting with `exact:` (checked character for character, case included);
- a word or two of the non-English text.

```
# Lines starting with # are ignored.
01-retina-full.png: Downloads
02-chat.png: 10:42
05-code.png: exact: let total = items.count + 1
08-receipt.png: Subtotal
```

Plain strings ignore upper and lower case. Two to four strings per image is plenty. The strings are only checked on
your Mac; the results table refers to them by line number, so they are never pasted back.

### 4. Run the tool

In Terminal, from the Shotkeeper repo folder:

```
xcrun swift scripts/measure-vision.swift ~/vision-test
```

It shows progress (`[3/20] vision-r3-accurate-h1/96-lc1: 21.4 s`), then prints a table. It also saves the table in
the folder as `vision-results-<date>.md`. Close other heavy apps first so the times are fair, and keep the Mac plugged
in.

To try the tool before collecting screenshots:

```
xcrun swift scripts/measure-vision.swift --make-sample ~/vision-sample
xcrun swift scripts/measure-vision.swift ~/vision-sample
```

If the summary says that no setting found every string, open the table: the "missed" column shows which lines of
`strings.txt` were never found by any setting. Usually that's a typo; fix the line and run again.

### 5. Paste back

Paste the whole `vision-results-<date>.md` file into the chat or the PR. It contains your Mac model, macOS version,
image names and sizes, and the numbers, but none of the screenshot text. Rename an image first if its file name
itself is private. Also say:

- which images (if any) were from a non-Retina display, or that you had none;
- whether the times felt representative (on battery or busy?).

An agent then writes the Results below and proposes the settings with the decision rule; you confirm them.

## Decision rule (spec)

Pick the lowest minimum height with `.accurate`, unless the slowest image takes more than about 2 s on Parag's Mac. In
that case, raise the height before switching to `.fast`.

Not in the spec (a proposal for Parag to confirm): language correction off if turning it on loses `exact:` code
strings and turning it off loses no other found strings.

## Results (measured 2026-11-28)

### Environment
Parag's MacBook Air (M4), macOS 27.0.1, Command Line Tools with Swift 6.4.2, `scripts/measure-vision.swift`.

### Method, and why the accuracy set is synthetic
- **20 synthetic screenshots**, not Parag's own: Retina (2×) and 1× images of UI, dark mode, code, chat, a receipt,
  Japanese, German and Arabic text. Parag's real screenshots were never opened by the tool or an agent, so that
  they stay on the Mac. That means no `strings.txt` could be written for them, so the accuracy numbers below come from
  the synthetic set only.
- Known strings: **48 plain strings** (case ignored) and **7 exact code lines** (`exact:`, character for character).
- The planned speed run on real screenshots was **skipped**, because the tool needs a `strings.txt` for every folder it
  reads. The times below are on the synthetic images.

### Summary by setting

| Setting | Plain strings (of 48) | Exact code lines (of 7) | Time per image |
|---|---|---|---|
| `.accurate`, any minimum height | 47–48 | see language correction | median about 0.08–0.10 s, slowest about 0.14 s |
| `.accurate`, minimum height 1/32 | 48 (all) | | |
| `.accurate`, 1/64, 1/96, 1/128, 10 px floor | 47: each misses one spreadsheet number | | |
| `.fast`, any height | 32 at best; no Japanese or Arabic text | 0 | |
| Language correction on (`.accurate`) | | 4–5: it inserts a space before `(` (`URL (string:`) | |
| Language correction off (`.accurate`) | no plain string lost compared with on | 6 | |
| Automatic language detection off (`.accurate`) | Japanese comes out as gibberish | | |
| Automatic language detection on (`.accurate`) | Japanese, German and Arabic read | | |

### Decision (Parag, 2026-11-28)
`VisionTextSettings.current` = `.accurate`, minimum text height **1/32**, language correction **off**, automatic
language detection **on**. `text_recognized_by` = `vision-r3-accurate-h1/32-lc0`.

- **1/32 deviates from the spec's rule.** The rule says to pick the lowest height with `.accurate` unless the slowest
  image takes more than about 2 s. The slowest took about 0.14 s, so the rule would pick 1/128. Parag chose 1/32
  (Apple's default) because it was the only height that found all 48 strings: every lower height missed one
  spreadsheet number.
- Language correction off meets the proposed rule above: on, it loses exact code lines; off, it loses no other string.
- `.fast` is out: it found no code line and no Japanese or Arabic text.

### Outlier: the first recognition
Once, the first recognition took **28.9 s**. It did not happen again, so it was probably the first load of the model.
Recognition must therefore run off the main thread with no short timeout. `VisionTextRecognizer` runs Vision on a
utility-priority dispatch queue, and neither it nor `TextRecognitionRunner` has a timeout
(`testASlowFirstReadIsWaitedForWithoutATimeout`).

### Known recognition errors (with the chosen settings)
- Junk characters after numbers in table cells (`52,407.9ął`).
- SF Mono's slashed zero read as `ø`.
- `[]` read as `[1)`.

These end up in `recognized_text` as read. Search still finds the rest of the line.
