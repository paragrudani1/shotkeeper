# Search filters and copy text spec (wave 1, 2026-11-28)

Parag's requirements are copied verbatim below. Do not edit them. Everything after them is synthesis by the design
sub-agent (2026-11-28) and must not contradict them. Add dated implementation notes and deviations to the wiki
(`docs/wiki/search-filters-and-text.md`, once it exists), not here.

## Requirements (Parag, 2026-11-28)

> 2026-11-28: "Search filters: narrow results by date, source app or site, or content type." (approved: "let's do all of it")

> 2026-11-28: "Copy the text in a screenshot, straight from a search result."

> 2026-11-28 (decision): full on-device OCR with Apple Vision, stored in the index, searchable and copyable, and added to existing screenshots when the user asks. The model's `key_text` is unchanged.

---

## Basis

- Code state: `295df83` (origin/main). Survey: `docs/wiki/roadmap-survey.md` (features 1 and 2, hotspots, prefactors).
- Vision facts: `docs/research/spotlight-shortcuts-ocr.md` §3. Claims from it are cited as [V1]–[V4], [WV19], [WV22], [WV24].
- Search panel: `docs/specs/ui-polish-2026-11.md` (PR 2, global style) and `docs/wiki/ui-polish.md` (PR 2 rules).
- **Depends on prefactor A, which is not merged yet.** Branch `t3/prefactor-index`. On 2026-11-28 its work was still
  uncommitted in its worktree, on top of `295df83`. It adds:
  - one column table (`ScreenshotIndex.columns`, one `IndexColumn` per column, with `addedIn`), from which the
    upsert, the bindings, the row read and the `ADD COLUMN` migrations are all built;
  - a test that migration versions are 1, 2, 3… with no gaps;
  - a change feed, `ScreenshotIndex.changes()` (an `AsyncStream<IndexChange>` of inserted, updated and removed rows);
  - an `IndexedScreenshot.testRow` builder for tests.

  This spec assumes that shape. If prefactor A merges with a different shape, follow the merged code, not this text.
- Also uses prefactor B where noted: the survey's prefactor 5, "Move the search key map into core with a collision test".
  It is not started. Without it, the new key is checked only on a real Mac.

## Problem Statement

Search finds a screenshot by words, and the type chips narrow it to one kind of content. But the user often remembers
something else: "it was last week", "it was in Slack", "a receipt from October". With hundreds of screenshots, a short
query returns too many results, and the user can't narrow them by when or where the screenshot was taken.

Once the user finds the screenshot, they often want its words, not its picture: a code snippet, an error message, an
address, an order number. Today they have to open the image and retype the text. The model's `key_text` doesn't help.
It holds at most 500 characters, the model chose which text to keep, and the search window doesn't offer it anyway.
Words that appear only in the image, beyond what the model wrote down, can't be found by search either.

## Solution

**Filters.** Search gets two more filters next to the type chips: **date** (when the screenshot was taken) and
**source** (the app or site the model named). Each filter narrows the results, and all of them combine with the typed
text and with each other. The footer counts what is left ("6 of 214 screenshots"). Esc and "Clear search" reset
everything at once. How the filters look and where they sit is left to the design pass.

**Text.** Shotkeeper reads all of the text in each new screenshot with Apple Vision, on the Mac, right after the model
has analysed it. It stores that text in the index, so a search also finds words that only appear in the image. From any
search result, one key (or a button) copies the screenshot's full text as plain text. Screenshots indexed before this
feature have no text yet. The user can ask Shotkeeper to read them all, or copying from one of them reads that one
on the spot. The text never leaves the Mac. The model's `key_text` stays as it is.

## User Stories

Filters
1. As a user, I want to show only screenshots taken today, so that I find the one I took an hour ago without typing.
2. As a user, I want to show only screenshots taken yesterday, in the last 7 days or in the last 30 days, so that I can match how I remember time.
3. As a user, I want to pick a custom range of days, so that I can find "the screenshots from my trip in October".
4. As a user, I want the date filter to use the day the screenshot was taken, the same date the result row shows, so that the filter and the list agree.
5. As a user, I want "Today" to mean today in my time zone and to roll over at midnight, so that a panel left open overnight doesn't show yesterday as today.
6. As a user, I want to pick a source (Slack, X, GitHub…) from a list of the sources in my index, so that I don't have to guess how the model spelled it.
7. As a user, I want each source in that list to show how many screenshots it has, so that I can see which sources are worth picking.
8. As a user, I want "X" and "x.com", or "GitHub" and "github.com", to be one source, so that one choice finds all of them.
9. As a user, I want the source list ordered by how many screenshots each source has, so that my usual apps come first.
10. As a user, I want the type chips to keep working as they do now (⌘1–⌘7), so that what I already know still works.
11. As a user, I want date, source, type and text to combine, so that "invoice" + Receipt + last 30 days + Stripe finds exactly one screenshot.
12. As a user, I want filters without any text to list matching screenshots newest first, so that "Slack, this week" works as a view.
13. As a user, I want the footer to say how many screenshots match, so that I know how much the filters narrowed the results.
14. As a user, I want to see at a glance which filters are on, so that I'm never confused by a short result list.
15. As a user, I want Esc to clear the text, the chip and the filters in one press, and to close the panel on the next press, so that Esc stays predictable.
16. As a user, I want "Clear search" in the no-match state to reset every filter as well, so that one click gets me back to all screenshots.
17. As a user, I want a no-match message that names the filters that caused it, so that I know which one to loosen.
18. As a user, I want my filters to stay set when I hide and reopen the panel, like the typed text does, so that I can come back to the same view.
19. As a user, I want a batch view ("View in Search" from the batch toast) to end when I change a filter, like it ends when I type, so that filters always search the whole index.
20. As a user, I want clicking a tag to search for that tag across all screenshots, so that the tag search isn't hidden by an old filter.
21. As a keyboard user, I want to reach and change every filter without leaving the search field, so that the panel works without the mouse.
22. As a VoiceOver user, I want each filter to announce its name and current value, so that I know what is applied.
23. As a user with thousands of screenshots, I want filtered searches to stay instant, so that filters don't make search slower.

Text in screenshots
24. As a user, I want Shotkeeper to read the text in every new screenshot automatically, so that the text is ready when I need it.
25. As a user, I want reading the text not to delay the rename toast, so that the rename still feels instant.
26. As a user, I want a search to find words that appear only in the image, so that I can find a screenshot by an error message, an order number or a line of code.
27. As a user, I want a screenshot whose title matches my words to rank above one that only has those words somewhere in its text, so that the results stay relevant.
28. As a user, I want to copy all of a screenshot's text from the selected search result with one key, so that I can paste it into an editor.
29. As a user, I want ⌘C to keep copying the image, so that what I already know still works.
30. As a user, I want a "Copy Text" button in the preview, so that I can copy the text without knowing the key.
31. As a user, I want a short confirmation after copying the text, like the "✓ Copied" pill for the image, so that I know it worked.
32. As a user, I want the copied text to keep its line breaks in reading order, so that code and addresses paste correctly.
33. As a user, I want the copied text as plain text only, so that it pastes cleanly everywhere.
34. As a user, I want a clear message when a screenshot has no text, so that I don't wonder whether copy failed.
35. As a user, I want a clear message when the text is still being read, so that I know to try again in a moment.
36. As a user, I want to copy text from an older screenshot that hasn't been read yet, and have Shotkeeper read it right then, so that I'm never sent to Settings first.
37. As a user, I want my clipboard left alone if I copy something else while a slow read is still running, so that a late result never overwrites what I copied since.
38. As a user, I want one command that reads the text in all my existing screenshots, so that old screenshots become searchable by their text too.
39. As a user, I want that command to tell me how many screenshots it will read before it starts, so that I know what I'm starting.
40. As a user, I want to see progress while existing screenshots are read, and be able to stop it, so that a large index doesn't run with no end in sight.
41. As a user, I want reading to continue after I quit and reopen Shotkeeper, so that a long backfill isn't lost.
42. As a user, I want newest screenshots read first during a backfill, so that the ones I'm most likely to search become searchable first.
43. As a user, I want a screenshot whose text could not be read to be marked as failed and retried by the next "read existing" command, so that one bad file doesn't block the rest.
44. As a user, I want a file I moved or deleted after indexing to be marked rather than to stop reading, so that the backfill finishes.
45. As a user, I want the text of a screenshot whose content changed to be read again, so that I never copy text from an older version of the image.
46. As a user, I want the text and the model's `key_text` kept separately, so that nothing the model wrote is overwritten.
47. As a privacy-conscious user, I want the text in my screenshots read only on my Mac and never sent to any model, server or log, so that private text stays private.
48. As a privacy-conscious user, I want the text not written into the file's Finder comment or tags, so that it doesn't travel with the file when I share it.
49. As a user of either backend (Clairic or Inkling 2 Mini), I want text reading to work the same way, so that my choice of model doesn't change it.
50. As a user on macOS 14, I want text reading to work, so that I don't need a newer macOS for it.
51. As a user who restored a file's name with Undo, I want its text still readable and copyable, so that undoing a rename doesn't lose the feature (reading the text never renames or uploads anything).
52. As a VoiceOver user, I want "Copy Text" and its result to be announced, so that I know the text is on the clipboard.

## Implementation Decisions

### Filter model (core, Linux-tested)

- `ScreenshotQuery` gains two fields next to `text`, `contentType` and `paths`:
  - `date: DateFilter?` (nil = any time).
  - `source: SourceKey?` (nil = every source).
  All fields combine with AND, as today.
- **`DateFilter`** is an `Equatable` value: `.today`, `.yesterday`, `.last7Days`, `.last30Days`, or
  `.days(from:through:)`. The custom range holds two calendar days (year, month, day), not instants.
  - A pure function resolves it to a half-open interval `[start, end)` of whole local days for a given `now` and `Calendar`.
  - `.last7Days` is today plus the 6 days before it. `.last30Days` works the same way with 29 days.
  - A custom range whose end comes before its start is swapped.
  - Because the query holds the filter and not the instants, `SearchWindowState.query` stays stable while time
    passes. The stale-answer check (`query == self.query`) keeps working. "Today" is resolved again when each search
    runs.
- **Which date:** `COALESCE(captured_at, processed_at)`, the same date the result row and the preview's "Taken" show
  (`SearchResultItem.date`).
- **`ScreenshotIndex.search(_:limit:)`** gains `now` and `calendar` parameters, defaulting to the current clock and
  calendar. The parameters let tests pin the clock. It resolves the date filter and adds the range condition.
- **Sources** come from the stored `source_app_or_site`, which is free model text. A pure core function turns a raw
  value into a `SourceKey`:
  - Trim it, fold case and diacritics, and drop a leading `www.`.
  - If what is left is a single name plus one top-level domain (`x.com`, `github.com`, `nytimes.com`), drop the
    domain, so it matches the app name ("X", "GitHub").
  - Leave anything with more labels (`bbc.co.uk`, `docs.google.com`) as it is.
  - There is no alias table (Twitter is not mapped to X). See "Decisions Parag might disagree with".
- **`ScreenshotIndex.sources()`** returns the source list: `[SourceFacet]` with `key`, `displayName` and `count`.
  - It groups `done` rows by raw value in SQL, then merges the groups by `SourceKey` in Swift.
  - `displayName` is the most common raw spelling; ties go to the first alphabetically.
  - The list is sorted by count (highest first), then by name. Rows without a source are left out.
  - Counts cover the whole index, not the current query. See "Decisions".
- **Filtering by source:** the index resolves the chosen key to its raw spellings, using the same grouping, and
  filters with `source_app_or_site IN (SELECT value FROM json_each(?))`. That is the pattern the batch paths already
  use. No new column and no backfill are needed for sources.
- **Content type** stays the existing chip row: single choice, ⌘1–⌘7, All…Design. `.other` keeps no chip, as the
  approved ui-polish spec says. The query field was already `ContentType?`, so the model can hold `.other` if a later
  spec adds it.
- **`SearchWindowState`** gains the matching changes, each returning true when a search must run:
  - `setDateFilter(_:)`, `setSource(_:)` and `clearFilters()`.
  - Every change of a filter ends a batch view, as typing does today.
  - `escape()` and `clearSearch()` reset text, chip, date and source together. Esc closes only when all four are
    empty.
  - `clickTag(_:)` also resets date and source, not only the chip (story 20).
  - `windowHidden()` keeps the filters, as it keeps the text today.
  - `hasFilter` counts date and source, so the footer says "N of M screenshots".
  - `noMatchMessage` names the active filters when there is no text, for example "No Slack screenshots from the last
    7 days" with "Clear filters to see every screenshot.". Core owns this wording, like the existing messages. The
    design pass supplies the final copy.
  - The state holds the source list (`[SourceFacet]`) that the app loads, so the panel can render it and tests can
    check it.

### How filters show in the panel (behaviour and states only; layout is the design pass's)

- **Default:** no date filter, no source filter, chip All. The panel looks and behaves exactly as today.
- **Active:** each active filter is visible in the panel with its value ("Last 7 days", "Slack") and can be cleared
  on its own. The footer switches to "N of M screenshots".
- **Source list states:**
  - Empty index, or no row has a source: the source filter is disabled, with a tooltip saying why.
  - Many sources: the user can narrow the list by typing. The list loads again each time the panel opens.
- **A chosen source that no longer exists** (its rows were renamed away or undone) stays selected, and the
  no-match state says which filters caused it.
- **Keyboard:** the focus stays in the search field (ui-polish PR 2 rule). So every filter control needs a key
  equivalent, or a recorded deviation (`appkit-gotchas`, "every control works with the keyboard").
  - The design pass picks the keys.
  - They go through `performKeyEquivalent` and must not collide with ⌘C, ⌘R, ⌘Y, ⌘1–⌘7, ⇧⌘C (below), or the IME
    guard.
  - Pop-up lists in a non-activating panel must not take key status from the field. Check on a real Mac.
- **Accessibility:** each filter has a VoiceOver name and value ("Date, last 7 days"). Clearing a filter is announced.

### Text recognition: where it runs

- **A new core port**, `TextRecognizer`, in the same spirit as `ImagePreparer`. It takes a file URL and returns
  recognized lines, each with its text, a confidence and a normalized bounding box.
  - The macOS app implements it with Vision: `VNRecognizeTextRequest`, revision 3, the Live Text recognizer
    [V1] [WV22].
  - One code path for every supported macOS. The macOS 15 `RecognizeTextRequest` is not used, so results don't
    differ by OS [V2] [WV24].
  - Core imports nothing from Vision. Linux and the CLI have no recognizer; rows there stay `pending`.
- The recognizer reads the **original file at the row's current path, at full resolution**. It does not use the
  `ImagePreparer` payload: that is downscaled to `maxImageLongSide` (1280 px) for upload, which would shrink small
  text below what Vision reads.
- **Ordering and joining are pure core rules:**
  - Lines are sorted top to bottom, then left to right, using a tolerance for lines on the same baseline.
  - They are joined with "\n". Whitespace-only lines are dropped.
  - Text whose trimmed result is empty counts as "no text".
  - A safety cap of 100,000 characters keeps one row from bloating the index. Longer text is cut at a line
    boundary and marked truncated.

### Text recognition: when it runs

- **At indexing.** When `ScreenshotProcessor` saves a row as `done` after a successful analysis, it sets
  `text_status = pending`. It does not run OCR itself, so the rename toast is not delayed (story 25).
- **A core `TextRecognitionRunner`** does the work. It subscribes to the index change feed (prefactor A) and also
  wakes at launch and on requests.
  - It reads one row at a time, newest `pending` row first, at utility priority. One at a time keeps Vision's
    memory use bounded.
  - It stops on quit. `pending` rows survive in the index and resume at the next launch.
- **Existing rows on request.** Rows indexed before this feature get `text_status = NULL` from the migration, so they
  are not read automatically, as Parag decided. Two requests queue them:
  - "Read text in existing screenshots": counts `done` rows whose status is NULL or `failed`, shows the count, then
    marks them `pending`. It can be stopped; stopping sets the rows that are still `pending` back to their previous
    state. Where the command lives (menu or Settings) is left to the design pass.
  - Copy Text on one such row reads that row at once, ahead of the queue (story 36).
- **Writes are conditional:** "set the text for row *id* if its `content_hash` still equals the one read and its
  status is still `pending`".
  - If the file's content changed during the read, the processor has saved the row again as `pending`, so the late
    result is dropped and the row is read again (story 45).
  - The write publishes an `.updated` change, so an open search refreshes.
- **Failure and no text:**
  - Vision error: `failed`, with a short reason in `text_error`. The reason never contains recognized text.
  - File missing at its indexed path: `failed`, reason "file missing".
  - No text found: `none`, with `recognized_text` NULL.
  - Nothing retries automatically. The next "read existing" request re-queues `failed` rows. The row's analysis
    and `done` status are never touched.
- **Restored-by-undo rows** are read like any other `done` row. Reading is local and renames nothing (story 51).
- **Pause** doesn't stop reading. It controls what is analysed and uploaded, and rows only become `pending` after an
  analysis. If Parag wants Pause to hold OCR too, it's one check in the runner.

### Index schema change (on top of prefactor A)

- One migration. Its number is claimed at merge, under prefactor A's rule that the second PR to merge renumbers. It
  adds four entries to the column table:
  - `recognized_text TEXT`: the joined lines.
  - `text_status TEXT`: NULL = not requested, `pending`, `done`, `none` or `failed`.
  - `text_recognized_by TEXT`: the recognizer id plus its settings (for example `vision-r3-accurate-h1/96-lc0`),
    so a later settings change can find rows to re-read.
  - `text_error TEXT`.
- `IndexedScreenshot` gains the matching fields. The upsert writes them like every other column, so a fresh
  processor entry sets `pending` and clears old text.
- **The same migration rebuilds FTS.**
  - An FTS5 table cannot gain a column, so the migration drops the three triggers and `screenshots_fts`, and
    recreates them with `recognized_text` as a sixth column.
  - The `AFTER UPDATE OF` trigger list must include `recognized_text`.
  - It then runs the FTS5 `'rebuild'` command for the external-content table (https://www.sqlite.org/fts5.html,
    "The 'rebuild' Command").
  - The FTS column list and `bm25Weights` stay outside prefactor A's column table. Put the FTS column list in one
    constant that the triggers and the weights both use, so they can't drift apart.
- **SQL indexes** for filters (in the filters PR's own migration):
  - `screenshots(COALESCE(captured_at, processed_at))`: an expression index matching the date condition exactly.
  - `screenshots(source_app_or_site)`.
- **SQL index** for OCR (in the OCR migration): a partial index on `text_status` where it is `'pending'`.
- Wave 1 runs filters and OCR in parallel, so the two features have two migrations. Whichever merges second
  renumbers.

### FTS match and ranking

- Recognized text **is part of the text match**. A term may match in any column, and every term must match
  somewhere (AND), as today.
- **Weights** (FTS column order: title, tags, description, key_text, source, recognized_text) become
  `10, 6, 3, 1, 2, 0.5`.
  - A title hit counts 20× a hit in recognized text, and bm25 also discounts long columns. A screenshot that
    matches only in its OCR text ranks below one that matches in its title, tags or description (story 27).
  - Tests pin the order, not the numbers.
- UI words ("File", "Edit", "Cancel") will make some broad one-word queries noisier. The weighting keeps those
  results low. If real use shows too much noise, the next lever is to drop low-confidence lines at write time. That
  needs no new UI.
- `SearchResultItem` carries `recognizedText` and the text status. Showing a match snippet from the text is optional
  and left to the design pass (FTS5 `snippet()`).

### Which key copies the text

- **⇧⌘C, "Copy Text".**
  - ⌘C stays Copy Image, and still copies the field's own text when it has a selection.
  - ⇧⌘C is free in the panel. As of `295df83`, `SearchKey.command` accepts only exactly ⌘ and maps c, r, y and 1–7.
  - It reads as "Copy, variant". Fallbacks if the design pass objects: ⌥⌘C (Finder uses it for "Copy as Pathname").
- **Matching:** extend `SearchKey.command` to accept ⇧⌘ for `c` only. Use the same rule: the ASCII character, else
  the physical key (`appkit-gotchas`). With Shift held, compare the lowercased character, and check on a Russian
  layout.
- **Collision test:** if prefactor B (survey prefactor 5) has moved the key map into core, the ⌘ collision test
  covers ⇧⌘C. Otherwise it is on the real-Mac checklist.
- **Footer:** keeps the approved spec's exact five hints. Copy Text is found through its preview button, whose
  tooltip shows "⇧⌘C".
- **What copy does, by text status:**
  - `done`: writes **one** pasteboard item with only `.string` (plain text, story 33), shows a pill on the image
    ("✓ Text copied", same timing as "✓ Copied") and posts a VoiceOver announcement.
  - `none`: message "No text found in this screenshot."
  - `failed`: message "The text could not be read." plus a retry, which re-queues the row.
  - `pending`: "Reading text…"; then copies when ready, under the rule below.
  - NULL (never requested): reads the row now, then copies, under the rule below.
- **Late copy rule (story 37):** a copy that has to wait writes to the pasteboard only if both still hold:
  - the pasteboard `changeCount` is unchanged since the key press;
  - the panel is still showing that row.
  Otherwise the text is saved but not copied.
- **Core outcome:** `SearchWindowState` exposes the copy outcome for the selection as a core enum (copy text / read
  first / no text / failed / not available). The app only performs it.
- Partial selection of the text is out of scope. Quick Look (Space) shows the image, and macOS Live Text there may
  let the user select part of it. That is inferred, not checked: verify on a real Mac and mention it in the design
  note if it works.

### Privacy: the text never leaves the Mac

- Vision runs on the device [V3] [WV19].
- The recognized text is never sent anywhere:
  - It is not added to `AnalysisContext` or to any prompt, so neither backend receives it. That includes wave 2's
    re-analyse.
  - It is not written to Finder tags or the Finder comment (`FinderMetadata`), so it doesn't travel inside the file's
    xattrs.
  - It never appears in the undo log, `note`, `text_error`, `lastError`, os_log or the CLI output.
- It lives only in the index on the Mac. It reaches the pasteboard only through the user's explicit Copy Text.
  Universal Clipboard may then sync that copy to the user's own devices, the same as any copy they make.
- Whether Core Spotlight (wave 3) may index it is a wave 3 decision. It is not decided here.
- Add a dated wiki line stating the rule. Reviewers check it under CODING_STANDARDS #2: "Secrets never reach
  logs…" applies in spirit, and no new send path may carry the text.

### Vision settings to measure on a real Mac

These are starting values, held as core constants, so `text_recognized_by` records them. Parag measures on his Mac;
the results go into a dated note in `docs/research/` and set the constants before the OCR PR merges.

- **Minimum text height** (`minimumTextHeight`, a fraction of the image height; the default is 1/32 [V1]).
  - A full-screen Retina screenshot is about 1,800–2,900 px tall. 1/32 of that is 56–90 px, while UI text there is
    roughly 20–30 px tall. So the default would probably skip most interface text (inferred from [V1]).
  - Candidates: 1/32 (default), 1/64, 1/96, 1/128, and a pixel floor of about 10 px converted per image
    (`10 / pixelHeight`). The pixel floor is a pure core function.
- **Recognition level:** `.accurate` (the default, the Live Text recognizer, better on small and stylized text) vs
  `.fast` [V3] [V4] [WV19]. Starting value: `.accurate`.
- Also record:
  - `usesLanguageCorrection` on vs off. Correction may "fix" code identifiers, and turning it off is faster [V1].
  - `automaticallyDetectsLanguage` on (accurate only, macOS 13+ [V1] [WV22]).
- **Test set:** about 20 real screenshots:
  - full-screen on a Retina display and on a non-Retina external display;
  - a window;
  - a small region;
  - dark mode;
  - code;
  - a chat;
  - a receipt;
  - non-English text.
- **Measure per combination:**
  - time per image (median and slowest);
  - peak memory;
  - whether known small strings were found (a filename in a title bar, a timestamp in a chat);
  - whether code survives verbatim.
- **Decision rule to confirm with Parag:** pick the lowest height and `.accurate`, unless the slowest image takes
  more than about 2 s on his Mac. In that case raise the height before switching to `.fast`.

## Testing Decisions

- **Good tests** drive public behaviour through the highest seam and check what a user would see:
  - the rows and their order;
  - the counts;
  - the window's state and wording;
  - what text a row ends up with.
  They don't check SQL strings, private helpers or call counts. Fixtures are built with prefactor A's
  `IndexedScreenshot.testRow`. No test needs the network, Vision or a Mac.
- **Seam 1: `ScreenshotIndex` public API, in-memory** (existing; prior art `ScreenshotIndexTests`). It covers:
  - date filters, with a fixed `now` and calendar: day edges, midnight rollover, time zones and DST, swapped custom
    ranges, and rows with only `processed_at`;
  - source normalization and merging, through `sources()`, plus the source filter;
  - combining text, type, date, source and batch;
  - `matchCount` and `totalCount`;
  - recognized text in the match;
  - ranking: a title hit beats a hit only in the OCR text;
  - the migration: the FTS rebuild finds existing rows afterwards, and pre-existing rows get `text_status` NULL;
  - the conditional text write: a stale hash or a non-pending status is refused.
- **Seam 2: `SearchWindowState`** (existing; prior art `SearchWindowTests`). Filter changes produce `query`. It also
  covers:
  - Esc and Clear reset everything;
  - a tag click resets the filters;
  - the hide and reopen rules;
  - leaving a batch;
  - `hasFilter` and the footer;
  - no-match wording for each filter combination;
  - the copy outcome for each text status.
- **Seam 3: `TextRecognitionRunner` with a stub `TextRecognizer`** (new; the one new port; prior art `StubAnalyzer`
  and `TempDir` in `ScreenshotProcessorTests`). It drives a real in-memory index. It covers:
  - `pending` → `done`, `none` or `failed`;
  - a missing file;
  - content changed during the read;
  - newest first;
  - "read existing" counts and re-queues NULL and `failed` rows;
  - stopping restores states;
  - reading one row ahead of the queue;
  - line ordering, joining and the cap, checked through the text the row ends up with.
- **Existing processor seam:** one more assertion in `ScreenshotProcessorTests`. A successful analysis saves the row
  with `text_status = pending`, and the analyzer's request carries no recognized text.
- **Key map:** if prefactor B lands first, ⇧⌘C goes in its core collision test. If not, it is a real-Mac check.
- **App side, checked only in CI snapshots and on a real Mac:**
  - the Vision recognizer;
  - the pasteboard write (one item, `.string` only);
  - the late-copy `changeCount` check;
  - filter controls in the non-activating panel;
  - the backfill command and its progress.
  New snapshot states: filters active, filtered no-match, the text-status pills, and the source list with many
  entries.

## Out of Scope

- Spotlight and Shortcuts (wave 3), including whether Core Spotlight may index the recognized text.
- Re-analyse, fixing a title, and editing names in the search window (wave 2).
- Clean-up of duplicates and old screenshots (wave 4).
- Selecting or copying part of the text inside the panel, translating it, or showing a full-text viewer.
- More than one source at a time, an "Other" chip, and filters by tag, folder or `date_mentioned`.
- Changing what the model returns: `key_text` stays as it is.
- Reading text from screen recordings or clipboard captures: Parag dropped feature 7 on 2026-11-28 (`58e5542`).
- A Settings switch to turn text reading off.

## Decisions Parag might disagree with

1. **No setting to turn OCR off.** New screenshots are always read; existing ones only when asked.
2. **Copying from a never-read screenshot reads it right away.** This counts as "when the user asks", for that one
   screenshot.
3. **⇧⌘C** is the Copy Text key, and the footer keeps its five approved hints, so ⇧⌘C appears only in the button's
   tooltip.
4. **Recognized text is in the search match by default,** at the lowest weight. It may make broad one-word queries
   noisier.
5. **Source filter:**
   - one source at a time;
   - counts cover the whole index;
   - the normalization only drops `www.` and a lone top-level domain. "Twitter" and "X" stay separate.
6. **Content type** stays the existing seven chips. Screenshots of type "Other" can still not be filtered on their
   own.
7. **A tag click now also clears the date and source filters.** The approved spec only says it resets the chip.
8. **Pause doesn't stop reading text.**
9. **One Vision API** (`VNRecognizeTextRequest`, revision 3) on every macOS, not the newer Swift API on macOS 15+.
10. **Safety cap of 100,000 characters** on the stored text.
