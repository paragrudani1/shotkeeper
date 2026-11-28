# Shortcuts and Spotlight spec (wave 3, 2026-11-28)

Parag's requirement is copied verbatim below. Do not edit it. Everything after it is synthesis by the design
sub-agent (2026-11-28) and must not contradict it. Add dated implementation notes and deviations to the wiki
(`docs/wiki/shortcuts-spotlight.md`, once it exists), not here.

## Requirements (Parag, 2026-11-28)

> 2026-11-28: "Shortcuts and Spotlight: \"Find screenshot of…\" as a Shortcuts action, and indexed screenshots in system search." (approved: "let's do all of it")

---

## Open decisions for Parag (answer before tickets are cut)

The research ([../research/spotlight-shortcuts-ocr.md](../research/spotlight-shortcuts-ocr.md), "Gaps") left four
questions that only Parag can answer. Each one is below with its options and a recommendation. The rest of the spec
is written to hold under any answer. Where a part applies to one answer only, it says so in its heading
("**if D2 = A**"). The real-Mac probe (ticket 01, see "Gate") runs whatever the answers are. Its results can send a
decision back to Parag.

### D1. Minimum macOS version
`IndexedEntity`, `FileEntity` and Transferable entities need macOS 15 [AI9] [AI12] [W24a]. The app targets 14.0
(`App/project.yml`).

| Option | What it means |
|---|---|
| **A. Keep macOS 14 (recommended)** | Everything in this spec uses APIs from macOS 13/14: `AppIntent`, `String` parameters, `ReturnsValue<[IntentFile]>`, `AppShortcutsProvider`, classic `CSSearchableItem`, and `NSUserActivity` for opening a result [AI1] [AI11] [AI20] [CS3] [CS10]. One code path on every macOS version. |
| B. Raise the minimum to 15 | The action can return `FileEntity` values. Their ID is bookmark data, so a shortcut keeps pointing at a screenshot after Shotkeeper renames or moves it [W24a]. One `IndexedEntity` can serve both Shortcuts and Spotlight, with no double entry [CS12]. Users on macOS 14 stop getting updates; Sparkle's minimum system version has to be raised in the same release. |
| C. Keep 14, add macOS 15 extras behind `if #available` | Both of the above, with two code paths. That doubles the real-Mac checks, and only one Mac is available. |

Why A: the action returns files that the next shortcut step uses right away, so bookmark-stable IDs add little.
The entity features matter most for a Spotlight section, and D2 recommends not adding one. The core seams below are
the same under A, B or C. Only the app adapters change.

### D2. Should Shotkeeper add its own items to system Spotlight?
Plain Spotlight already finds Shotkeeper's screenshots in several ways:
- by file name, which is the model's title when renaming is on;
- by the Finder tags and the comment (the description, up to 240 characters), when "Write Finder tags and comment"
  is on (README; Apple doesn't document how Spotlight imports the xattr [MD1] [MD2]);
- by the words in the image, through Live Text [SUP1].

Core Spotlight items would add a second result for the same screenshot. Apple doesn't say whether a `contentURL`
item and its file show up as one result or two [CS5]. It also doesn't say whether an ad-hoc or self-signed build may
write to a named index [CS2].

| Option | What it means |
|---|---|
| **A. Rely on macOS (recommended)** | No Core Spotlight code. "Indexed screenshots in system search" is met by the metadata Shotkeeper already writes. The probe confirms that it works. On macOS 26, the "Search in Shotkeeper" action (below) also appears in Spotlight as an action [W25b]. That gives Shotkeeper a place in system search without listing every screenshot twice. D3 and D4 then don't apply. |
| B. Add a Shotkeeper section (own items, on by default) | One `CSSearchableItem` per screenshot the search window can show, in a named index, kept in sync through the index change feed. Each item shows the description and opens into Shotkeeper. It may make every screenshot appear twice. |
| C. Like B, but off by default | Same code as B. Only people who switch it on see the duplicates. |

Why A: the Shotkeeper item would match mostly the same words as the file result: the title (the file name), the tags
and the description (the comment). Pressing ⌥⌘S already opens the same search with better ranking and filters.
Option B adds sync code, a launch rebuild, an unknown signing risk and probably duplicate results to every system
search. **A is re-asked if the probe shows either of these:**
- plain Spotlight does not find a screenshot by its tag or comment (so A doesn't really cover them);
- a `contentURL` item and its file merge into one result (so B costs no duplicates).

### D3. What does opening a Shotkeeper Spotlight result do? (only if D2 = B or C)
| Option | What it means |
|---|---|
| **A. Open the search panel on that screenshot (recommended)** | The panel opens as a batch of one (the existing `showBatch`), selected. ⇧⌘C copies its text, ⌘R reveals it, Space opens Quick Look, and Return opens the file. Typing leaves the batch, as today. |
| B. Open the file in its default app | The same as clicking the file's own Spotlight result. The item would then be a pure duplicate. |
| C. Quick Look it | No Shotkeeper context, and Quick Look from a non-activating panel already needs care (`appkit-gotchas`). |

Why A: opening into Shotkeeper is the only thing the item can do that the file result can't.

### D4. If Core Spotlight refuses this build's signature (only if D2 = B or C)
"Refuses" here means an index call that **returns an error** on a user's Mac. A silent refusal (no error, but items
never appear) can't be detected at runtime. The probe handles that case: if items don't appear for the signing that
ships, the Spotlight half doesn't ship, and the question goes back to Parag.

| Option | What it means |
|---|---|
| **A. Show a disabled state with the reason (recommended)** | The Settings row stays. The switch is off and disabled, with one line: what happened, and that Spotlight still finds screenshots by name, tags and the text in the image. Shotkeeper tries again at each launch. |
| B. Hide the feature | The Settings row disappears and a note goes to the log. Nothing is explained. |

Why A: the user turned the feature on, or saw it on. A switch that silently vanishes looks like a bug. A future
signing change (a self-signed release, then maybe Developer ID) can fix it, and the retry at launch picks that up.

---

## Basis

- Code state: origin/main `f19156b`. It includes PR #9 (prefactor A: `ScreenshotIndex.columns`, `changes()` feed,
  `IndexedScreenshot.testRow`, settings round-trip test) and PR #10 (prefactor B: `FileActions`,
  `SearchResultActions`, `WorkspaceActions`, `SearchKeyMap` in core, `scripts/lint.sh`). Follow the merged code if it
  differs from this text.
- **Needs wave 1** ([search-filters-and-text-2026-11.md](search-filters-and-text-2026-11.md), on
  `t3/wave1-search`): `DateFilter`, `SourceKey`/`SourceFacet`, `ScreenshotQuery.date`/`.source`, the `recognized_text`
  FTS column and its ranking, and `search(_:limit:now:calendar:)`. The action reuses that query, so wave 3 starts
  from wave 1's tip, as wave 2 does.
- Wave 2 ([subfolders-and-retitle-2026-11.md](subfolders-and-retitle-2026-11.md)) and wave 4
  ([clean-up-2026-11.md](clean-up-2026-11.md)) change rows through the same feed: Sort Existing (`updatePath`),
  Edit name, Analyze Again, Undo (`markRestoredByUndo`), and clean-up's `trashed` status and `remove(id:)`. Clean-up
  states the rule this spec follows: "Wave 3's Spotlight sync treats a non-`done` row as absent."
- Research: [../research/spotlight-shortcuts-ocr.md](../research/spotlight-shortcuts-ocr.md) §1–2, cited as
  [AI…], [CS…], [MD…], [SUP…], [W…].
- Signing: the CI artifact is ad-hoc signed (`ci.yml`, "Ad-hoc sign and zip the app"). Releases will be signed with
  Parag's self-signed "Shotkeeper Release" certificate
  ([auto-update-2026-11.md](auto-update-2026-11.md), P1). That spec says wave 3 should test against the release
  signing, not only the CI artifact. The probe tests both.
- Index feed: [../wiki/prefactor-index.md](../wiki/prefactor-index.md). `IndexChange` = kind
  (inserted/updated/removed), a row `id` that stays the same across path changes, and `path`. Changes are published
  after the commit, in commit order, with an unbounded buffer.
- App structure: [../wiki/prefactor-app.md](../wiki/prefactor-app.md). The Spotlight sync "should follow the index
  change feed, not `handle(_:)`".

## Problem Statement

Shotkeeper only helps when its own window is open. Shortcuts is how people on a Mac tie apps together, but there is
no Shortcuts step that says "get me the screenshot of the Stripe invoice". So a shortcut that mails the latest
receipt screenshot, or drops the screenshot of an error message into a bug report, has to go through Finder, which
knows nothing about the titles, types or sources Shotkeeper worked out.

Many people search their Mac with ⌘Space out of habit, not with ⌥⌘S. They should find their screenshots there too,
by the words they remember, without learning a second search.

## Solution

**A Shortcuts action, "Find Screenshots".** It takes some text, plus optional type, date and source filters, runs
the same search as the Shotkeeper search window (title, tags, description, source and the text in the image, ranked
the same way), and returns the matching screenshot files, best match first. The next step in the shortcut can mail,
copy, move or open them. A second action, **"Search in Shotkeeper"**, opens the search window, optionally with text
already typed in. A Siri phrase can run it too. Both work on macOS 14.

**System search.** Under the recommended D2 = A, Shotkeeper keeps doing what makes screenshots findable in Spotlight:
- a descriptive file name;
- Finder tags;
- the description as the Finder comment.

macOS adds the words in the image itself. The probe on a real Mac confirms that this works and says what it misses.
On macOS 26, "Search in Shotkeeper" also shows up as an action in Spotlight.

If Parag picks D2 = B or C instead, Shotkeeper also puts one item per screenshot into Spotlight, under Shotkeeper,
showing the description. Opening the item does what D3 says. A Settings switch turns this off and removes the items.

## User Stories

Shortcuts action
1. As a Shortcuts user, I want a "Find Screenshots" action from Shotkeeper, so that a shortcut can get a screenshot by what is in it.
2. As a Shortcuts user, I want to give the action text, so that "stripe invoice" finds the screenshot of my Stripe invoice.
3. As a Shortcuts user, I want the action to search the same things as the search window (title, tags, description, source and the text in the image), so that a screenshot I can find with ⌥⌘S I can also find in a shortcut.
4. As a Shortcuts user, I want results in the same order as the search window, so that "the first result" means the same thing in both places.
5. As a Shortcuts user, I want the best match only by default, so that "Find screenshot of…" followed by "Send" sends one file.
6. As a Shortcuts user, I want to raise the limit, so that a shortcut can collect, say, every receipt from this month.
7. As a Shortcuts user, I want to filter by type (Receipt, Code, Chat…), so that the action returns the same kinds as the search window's chips.
8. As a Shortcuts user, I want to filter by when the screenshot was taken (today, yesterday, last 7 days, last 30 days), so that "today's screenshots" works as a step.
9. As a Shortcuts user, I want to filter by source and have "x.com" and "X" count as the same source, so that I don't have to guess how the model spelled it.
10. As a Shortcuts user, I want to leave the text empty and get the newest screenshots that pass the filters, so that "latest screenshot" or "latest receipt" works without a search word.
11. As a Shortcuts user, I want the result to be the real files, so that Quick Look, Mail, Messages, Save File and "Reveal in Finder" all work with them.
12. As a Shortcuts user, I want an empty result rather than an error when nothing matches, so that an "If" step can handle it.
13. As a Shortcuts user, I want a clear error when the index can't be read, so that I know the shortcut failed and why.
14. As a Shortcuts user, I want screenshots whose file I moved or deleted outside Shotkeeper left out, so that the next step never gets a missing file.
15. As a Shortcuts user, I want missing files left out without cutting the result short, so that a limit of 3 still returns 3 if 3 exist.
16. As a Shortcuts user, I want the action to work when Shotkeeper isn't running, so that a scheduled shortcut doesn't depend on me having opened the app.
17. As a Shortcuts user, I want the action to run without bringing up any Shotkeeper window, so that it works in the background and in automations.
18. As a Shortcuts user, I want screenshots that are still waiting for analysis left out, so that I only get screenshots with a title and type.
19. As a Shortcuts user, I want screenshots I put in the Trash with Clean Up left out, so that a shortcut never picks up a binned file.
20. As a Shortcuts user, I want a screenshot whose rename I undid to still be found, so that undoing a name doesn't hide it.
21. As a Shortcuts user, I want my saved shortcuts to keep working after Shotkeeper updates, so that I build them once.
22. As a user on macOS 14, I want the action to work, so that I don't need a newer macOS for it.
23. As a user of either backend (Clairic or Inkling 2 Mini), I want the action to work the same way, so that my choice of model doesn't change it.

Opening the search window
24. As a Shortcuts user, I want a "Search in Shotkeeper" action that opens the search window, so that a shortcut or keyboard trigger can start a search.
25. As a Shortcuts user, I want to pass text to "Search in Shotkeeper", so that a shortcut can search for what's on the clipboard.
26. As a Siri user, I want to say "Search screenshots in Shotkeeper" to open the search window, so that I can start a search hands-free.
27. As a user on macOS 26, I want "Search in Shotkeeper" offered in Spotlight, so that I can jump from ⌘Space into Shotkeeper's search.
28. As a user, I want the search window opened by an action to behave exactly like the one opened with ⌥⌘S, so that the keys I know still work.

System search
29. As a user, I want ⌘Space to find my screenshots by the title Shotkeeper gave them, so that I can find them without opening Shotkeeper.
30. As a user, I want ⌘Space to find screenshots by their Shotkeeper tags and description, so that a word I remember from the summary works.
31. As a user, I want ⌘Space to find screenshots by the words in the image, so that an error message or order number works.
32. As a user, I want each screenshot to appear once in Spotlight, not twice, so that results stay readable. (This is why D2 = A is recommended.)
33. As a user (if D2 = B or C), I want a Shotkeeper result to show the screenshot's description and when it was taken, so that I can tell similar screenshots apart.
34. As a user (if D2 = B or C), I want opening a Shotkeeper result to do what D3 decides, so that I land where I can act on it.
35. As a user (if D2 = B or C), I want a Spotlight result to follow the file when Shotkeeper renames or moves it, sorts it into a subfolder, or I undo a rename, so that it never opens a stale path.
36. As a user (if D2 = B or C), I want a screenshot to leave Spotlight when Clean Up moves it to the Trash, and come back if I undo that, so that Spotlight matches what I have.
37. As a user (if D2 = B or C), I want a Shotkeeper result for a file that has gone missing to open Shotkeeper with a clear message, so that a click never does nothing.
38. As a user (if D2 = B or C), I want Shotkeeper's Spotlight items to match what the search window can show, no more and no less, so that the two never disagree.
39. As a user (if D2 = B or C), I want the items to stay correct after Shotkeeper quits or crashes, so that a missed update doesn't leave a wrong result forever.

Privacy and control
40. As a privacy-conscious user, I want to know exactly what Shotkeeper puts into the system index, so that I can decide whether to allow it.
41. As a privacy-conscious user (if D2 = B or C), I want one switch that turns Shotkeeper's Spotlight items off and removes the ones already there, so that I can take it back.
42. As a privacy-conscious user, I want the full text read from my screenshots kept out of Shotkeeper's Spotlight items, so that passwords or messages in a screenshot aren't copied into one more index.
43. As a privacy-conscious user, I want the Shortcuts action to send nothing anywhere, so that searching from a shortcut is as private as the search window.
44. As a user who turned off "Write Finder tags and comment", I want that choice to stay respected, so that turning on another feature doesn't quietly add the description to Spotlight through a different route. (If D2 = B or C, the Settings text says that the Spotlight switch puts the description in the system index.)
45. As a user (if D2 = B or C), when macOS refuses Shotkeeper's items, I want to see why and what still works (D4), so that a missing feature doesn't look like a bug.

## Implementation Decisions

### Gate: a real-Mac probe before any UI (ticket 01)

Apple's documentation is silent on whether this kind of build works with these system features at all. The probe
answers that in about 15 minutes on Parag's Mac, before anyone builds UI. It is throwaway code. Its results go into a
dated note, `docs/research/shortcuts-spotlight-probe-<date>.md`.

- **What it is:** a separate tiny app target, `ShotkeeperProbe`, bundle id `dev.shotkeeper.Probe`. It is built with
  the app's settings, so the signing question is the same: `LSUIElement`, no sandbox, Hardened Runtime off, macOS
  14.0 target, Swift 6. A separate bundle id keeps the probe out of the real app's Spotlight index and saved
  shortcuts.
  - CI builds and ad-hoc signs it the way it signs the app, as its own artifact.
  - Parag re-signs a copy with the "Shotkeeper Release" identity (one `codesign` command in the instructions, after
    the auto-update P1 certificate exists). That tests the signing releases will use.
  - The target is deleted once the results are recorded.
- **What it contains:**
  1. An intent "Probe Find" (`String` in, `[IntentFile]` out). It returns a PNG the probe made in its own
     Application Support folder (never a user file), with `removedOnCompletion` set to false explicitly [AI11].
  2. An intent "Probe Open" (`openAppWhenRun`) that shows a small non-activating panel, like the search panel.
  3. One App Shortcut with a phrase.
  4. At launch, the probe writes that PNG:
     - with the word `qzprobe2` drawn large in the image;
     - with Finder comment `qzprobe4 qzprobe6` and Finder tag `qzprobe5`, using the app's own xattr writer.
  5. It indexes two `CSSearchableItem`s in a named index:
     - one with title `qzprobe1`, keyword `qzprobe6`, and `contentURL` set to the PNG;
     - one with title `qzprobe3` and no URL.
     It logs each completion handler's error to a log file.
  6. It logs `application(_:continue:restorationHandler:)`, showing the activity type and the item identifier in an
     alert [CS10] [CS11].
- **What Parag does and records**, for each signing (ad-hoc, then self-signed), with the app in `/Applications`.
  Also record the macOS version.

  | # | Check | Decides |
  |---|---|---|
  | 1 | In Shortcuts → Apps, is ShotkeeperProbe listed with both actions? | The whole Shortcuts half |
  | 2 | Run Probe Find in a new shortcut, then Quick Look: does the image show? After the run, is the PNG still in place and unchanged? | Returning files in place (`IntentFile`) |
  | 3 | Run Probe Open while the probe is in the background: does the panel come to the front? | "Search in Shotkeeper" |
  | 4 | In ⌘Space, search `qzprobe1` and `qzprobe3`: do the items show? Clicking one shows the alert? Any error in the log? | D2 = B/C is possible; D3; D4 |
  | 5 | In ⌘Space, search `qzprobe2`, `qzprobe4` and `qzprobe5`: is the PNG found by the image word, the comment and the tag? | Whether D2 = A covers enough |
  | 6 | In ⌘Space, search `qzprobe6`: does the PNG show once or twice? | The duplicate question in D2 |
  | 7 | On macOS 26 only: type "Probe Open" in ⌘Space. Is it offered as an action? | Story 27 |

- **Gate rules:**
  - Ticket 03 (app intents) starts only after checks 1–3 pass for the signing that ships, which is self-signed.
    If check 1 fails for both signings, the Shortcuts half is blocked and goes back to Parag. There is no
    workaround (AGENTS.md: report it instead).
  - If check 2 shows the file was copied, moved or removed, the action returns copies in a temporary folder instead.
    That is a recorded deviation.
  - Under D2 = A, check 5 must pass. If the comment or tag isn't found, D2 goes back to Parag.
  - Under D2 = B/C, the Spotlight tickets start only after check 4 passes for the signing that ships. If check 6
    shows no duplicate, or check 5 fails, D2 goes back to Parag with the results.

### Shortcuts action: "Find Screenshots" (macOS 14)

- **An `AppIntent` in the app target**, not in core and not in a package. Discovery reads the build-time metadata
  of the app bundle [AI1] [W22a] [W25a] [AI15]. Its title and description are constants [W25a].
  - Parameter summary: "Find screenshots of *Text*", with the filters below it.
  - It runs in the background: no `openAppWhenRun`, and no window shows [AI15].
- **Parameters** (all optional, so a blank action means "newest screenshot"):

  | Parameter | Type | Default | Maps to |
  |---|---|---|---|
  | Text | `String` | empty | `ScreenshotQuery.text` (the same FTS match and weights as the search window, including `recognized_text`, wave 1) |
  | Type | an `AppEnum`: Any, then the seven chip types in chip order | Any | `ScreenshotQuery.contentType` |
  | Taken | an `AppEnum`: Any time, Today, Yesterday, Last 7 days, Last 30 days | Any time | `ScreenshotQuery.date` (`DateFilter`, wave 1) |
  | Source | `String` | empty | `SourceKey(raw:)` → `ScreenshotQuery.source`, so "x.com" = "X" |
  | Limit | `Int`, 1…50 | 1 | `limit` |

  - There is no custom date range in v1. The presets cover "today" and "this week" shortcuts. A range needs two date
    parameters shown only for "Custom", which is more surface than v1 needs.
  - The enum cases' identifiers are fixed strings, not `ContentType` raw values. Saved shortcuts store them [AI4],
    so renaming a `ContentType` case must not break a saved shortcut. The same goes for parameter names and the
    intent type name: **never rename them after the first release.**
- **Output:** `ReturnsValue<[IntentFile]>`, best match first [AI11] [AI13] [AI20].
  - Each `IntentFile` points at the screenshot **in place** (its current path), with its file name and UTType.
    `removedOnCompletion` is false, set explicitly. Probe check 2 confirms Shortcuts leaves the file alone. A
    shortcut the user builds may then move or delete the file. That is the user's own action, as in Finder.
  - Only files that exist at their indexed path are returned. The action asks the index for more than `limit` rows
    (`limit + 20`), drops rows whose file is missing, and returns the first `limit`.
  - No match: an empty list, not an error (story 12).
  - Index can't be opened or read: the action throws an error whose message is
    `UserFacingError.problem(for:)`'s short text. It never shows a raw error, a path or recognized text.
- **Which rows:** exactly the rows `ScreenshotIndex.search` returns today: `done` rows only. That includes
  restored-by-undo rows, and excludes pending, failed, skipped and (wave 4) trashed rows. Empty text with filters:
  newest first, as in the search window. The batch `paths` field is not exposed.
- **Core logic:** a new core value, `FindScreenshotsRequest`. It holds text, type, date, source and limit, clamps
  the limit, and builds the `ScreenshotQuery`. Its `run(in:fileExists:now:calendar:) -> [URL]` calls
  `index.search`, applies the missing-file rule, and returns paths in ranked order. The intent's `perform()` is a
  thin adapter: parameters → request → `IntentFile`s.
- **Getting the index:** the app registers its `ScreenshotIndex` (through the coordinator) with
  `AppDependencyManager` at launch, before an intent can run [AI14]. When Shotkeeper isn't running, the system
  launches it to run the intent. `AppDelegate`'s normal launch builds the coordinator and starts its services. The
  search panel stays hidden.
  - The setup window must not pop up because an intent launched the app. If setup isn't finished, the index is
    empty and the action returns an empty list. Check on a real Mac whether an intent launch goes through
    `applicationDidFinishLaunching` (where setup is shown) and suppress the setup window for that launch if needed.
- **Not "opened":** returning a file to a shortcut doesn't count as opening it for clean-up's "never opened" rule
  (wave 4). Shotkeeper can't see what the shortcut does with the file.
- **Pause** doesn't affect the action. It only reads the index.

### Shortcuts action: "Search in Shotkeeper", and the App Shortcut

- An `AppIntent` with one optional `String` parameter, Text, and `openAppWhenRun = true` [AI16].
  - It calls the same `SearchPanelController.show()` that ⌥⌘S calls. With text, it first sets the field through
    `SearchWindowState.setText`, so filters, Esc and the rest behave as usual (story 28).
  - `openAppWhenRun` is deprecated in macOS 26 in favor of `supportedModes` [AI16]. On a 14.0 target it is the
    available API. If the CI SDK warns, wrap the deprecation, don't raise the target.
- **One `AppShortcutsProvider` entry** for it, phrases "Search screenshots in `\(.applicationName)`" and
  "Find a screenshot in `\(.applicationName)`". Phrases can't carry free text [W22b], so the phrase opens the window
  and the user types. Find Screenshots is not an App Shortcut: Siri would have to ask for the text and then hand
  files back to Siri, which is little use. Apple recommends 2–5 App Shortcuts [AI19]. One is enough here.
- On macOS 26, Spotlight lists an app's actions whose parameter summary covers every required parameter [W25b].
  Both actions have only optional parameters, so both may appear there. That is a bonus, checked in probe check 7,
  not a requirement.

### System search: if D2 = A (rely on macOS)

- No Core Spotlight code, no new setting and no new data leaving Shotkeeper.
- Deliverables:
  - the probe's check 5 recorded in the research note;
  - a README paragraph saying how screenshots show up in Spotlight (file name, tags, comment, image text) and that
    "Write Finder tags and comment" controls the middle two;
  - a dated wiki line.
- If check 5 shows a gap, D2 goes back to Parag. This spec does not add a workaround (for example, appending the
  source to the Finder comment).

### System search: if D2 = B or C (Shotkeeper items in Spotlight)

**The item.** A pure core mapping, `SpotlightItem.make(from: IndexedScreenshot) -> SpotlightItem?`, gives `nil` for
any row the search window wouldn't show (not `done`). The app turns a `SpotlightItem` into a `CSSearchableItem`.

| `CSSearchableItem` / attribute | Value | Source |
|---|---|---|
| `uniqueIdentifier` | the row `id` (stays the same across renames and moves, so they are updates) | [CS6] [CS7], prefactor A |
| `domainIdentifier` | `screenshots` | [CS7] |
| `title`, `displayName` | the file's current stem: the same as `SearchResultItem.title`, so after Undo it is the restored name | [CS3] |
| `contentDescription` | the model's description | [CS4] |
| `keywords` | the tags, the source's display name, the type's chip name, and the model title if it differs from the stem | [CS5] |
| `contentType` | the file's UTType, from its extension (app side) | [CS3] [CS5] |
| `contentURL`, `thumbnailURL` | the file URL | [CS5] |
| `contentCreationDate` | `captured_at`, else `processed_at` (the date the search window shows) | [CS5] |
| `expirationDate` | launch time + 1 year; the launch rebuild renews it | [CS6] |

- **Never in the item:** `recognized_text`, `key_text`, `note`, `text_error`, `title_source`, consent or backend
  details, or any error text. A core test asserts the exact field set (story 42). Leaving out the OCR text also
  keeps the item from matching the same image words as the file's own Live Text result.
- **Index:** one named index, `CSSearchableIndex(name: "dev.shotkeeper.screenshots")`. Never `default()`, which is
  "only for prototyping or testing" [CS4] [CS8]. All calls go through one app actor, because the index and attribute
  sets are not thread-safe [CS2] [CS5].

**Sync (core `SpotlightSync`, behind the port `SystemSearchIndex`).**
- The port has three calls: `upsert([SpotlightItem])`, `delete(ids:)` and `deleteAll()`. The app implements it with
  the named index. Tests use an in-memory fake that holds the resulting id → item map.
- **Level-triggered, not event-replaying:** for each change, the sync re-reads the row by `id` *now*, maps it, and
  upserts, or deletes when the row is gone or not `done`. So coalescing is safe and the event kind doesn't matter.
  - Changes are coalesced per `id` over 2 s and sent in batches.
  - An in-memory digest per `id` skips upserts whose item didn't change. Wave 1's OCR backfill and wave 4's "opened"
    stamps update rows without changing the item.

  | Change in Shotkeeper | Feed event (prefactor A and later waves) | Spotlight result |
  |---|---|---|
  | New screenshot analyzed | `inserted`/`updated`, row `done` | item added |
  | Still pending, failed, skipped, excluded | `inserted`/`updated`, row not `done` | no item (deleted if there was one) |
  | Edit name, Analyze Again, Sort Existing, sorting new screenshots | `updated` (same `id`, new path or title) | item updated in place |
  | Undo (move back + `markRestoredByUndo`) | `updated` | item updated: restored name and path |
  | Stale row replaced by `updatePath` | `removed` (old `id`) | old item deleted |
  | Clean Up moves to Trash (`trashed`) | `updated`, row not `done` | item deleted |
  | Undo of Clean Up / Put Back | `updated`, row `done` again | item added back |
  | Row removed (Trash emptied, wave 4 `remove(id:)`) | `removed` | item deleted |
  | Text read, opened stamp | `updated`, item unchanged | nothing sent |

- **Launch rebuild:** at each launch, when the switch is on, the sync replaces the whole domain:
  - `deleteAll()`, then upsert every `done` row whose file exists, in batches, at background priority;
  - then it follows the feed.
  - Subscribe to the feed *before* reading the rows, so no change falls between the two.
  - This repairs anything missed while Shotkeeper wasn't running or crashed (story 39), and renews the expiry.
  - Its time for a large index is measured on the real Mac. If it's slow, the next step is a client-state version
    check [CS4]. Not in v1.
- **System-requested reindex:** a `CSSearchableIndexDelegate` in the running app answers "reindex all" with the
  launch rebuild, and "reindex these ids" by re-reading those rows [CS9]. There is no extension target: an extension
  adds a bundle with its own signing questions, and the launch rebuild covers the app-not-running case.
- **Lookup:** `ScreenshotIndex` gains `lookup(id:)`. The feed gives an `id`, and opening a result gives the item
  identifier, which is that `id`.

**The switch.**
- Settings → General: "Show screenshots in Spotlight" (`AppSettings.spotlightEnabled`). On by default for D2 = B,
  off for D2 = C. The round-trip test covers it.
- The row's help text lists what goes in: name, description, tags, source, type, date and file location, but not
  the text read from the image.
- Turning it off stops the sync and calls `deleteAll()`. Turning it on runs the launch rebuild.
- **Independent of "Write Finder tags and comment":** turning that off does not change what the Spotlight items
  carry. The help text says so (story 44).

**Opening a result (D3).**
- AppKit delivers `NSUserActivity` type `CSSearchableItemActionType` to `application(_:continue:restorationHandler:)`,
  with the identifier in `userInfo[CSSearchableItemActivityIdentifier]` [CS10] [CS11]. How an `LSUIElement` app gets
  it is silent in Apple's docs: probe check 4.
- A core function `SpotlightSync.target(forIdentifier:) -> SpotlightTarget` decides
  `.screenshot(path)` or `.missing`:
  - unknown id, row not `done`, or file missing → `.missing`, and that id is deleted from Spotlight;
  - otherwise `.screenshot(path)`.
- D3 = A: `.screenshot(path)` → `searchPanel.showBatch([path])`. `.missing` → the panel opens with the existing
  missing-file pill wording ("That screenshot is no longer where Shotkeeper put it"; the final copy comes from the
  design pass).
- D3 = B: `.screenshot(path)` → `NSWorkspace.open`. `.missing` → same as above.

**Refusal (D4).**
- An error from any index call puts the sync into `.refused(reason)`. The sync stops and makes no further calls this
  session, and the next launch tries again. The reason is a short fixed string chosen by error domain/code. It never
  contains a path or row data.
- D4 = A: the Settings row shows the switch disabled, with "macOS didn't accept Shotkeeper's Spotlight items
  (*reason*). Spotlight still finds your screenshots by name, tags and the text in the image." (the design pass
  owns the final copy).
- D4 = B: the row is hidden while refused.

### Privacy: what leaves Shotkeeper

- **The actions:** everything runs on the Mac. The action reads the index and returns file references to the
  shortcut the user built. Nothing is uploaded, and `UploadConsent` is not involved: no image goes to a model.
  Logs record only counts and timings, never the query text, titles or paths.
- **System search, D2 = A:** nothing new. The existing Finder tags and comment, under the existing switch.
- **System search, D2 = B/C:** the fields in the item table, into an index that "remain[s] on device … Devices don't
  share indexed data with Apple, or synchronize that data" [CS1]. The full image text and the model's `key_text`
  are never included. The switch removes everything. Whether removing the app removes its named index is silent;
  the README says to turn the switch off first.
- **If D1 = B (macOS 15 entities) is chosen later:** entity properties become visible to system intelligence
  features [W24a] [W25c]. That would need its own privacy review. It is not part of this spec.
- A dated wiki line states these rules. Reviewers check new item fields against them, as with CODING_STANDARDS #2.

### Where code lives

- **Core** (Foundation only, Linux-tested): `FindScreenshotsRequest`, plus, only if D2 = B/C, `SpotlightItem`,
  `SpotlightSync`, `SystemSearchIndex` and `ScreenshotIndex.lookup(id:)`.
- **App:** `Intents/` (the two intents, the two `AppEnum`s, the `AppShortcutsProvider`, dependency registration).
  If D2 = B/C, also `Platform/CoreSpotlightIndex.swift` (the port, an actor), the `continue` handler in
  `AppDelegate`, and the sync started from `startServices()`, following the feed as prefactor B's note asks.
- **Lint** (`scripts/lint.sh`): add `AppIntents` and `CoreSpotlight` to the imports forbidden in core.
- **CI:** after building, `macos-app` checks that `Shotkeeper.app` contains the generated `Metadata.appintents`
  [W23] and that it names both intents. This catches the intents silently dropping out of discovery. The exact file
  inside is read from the first CI build and then pinned in the check.

### Build order (tickets follow the spec's approval)

1. **01 Probe** (gate). It doesn't depend on D1–D4 or wave 1, so it can start as soon as the auto-update P1
   certificate exists. The ad-hoc half can start before that.
2. **02 `FindScreenshotsRequest`** in core. It needs wave 1's query fields, so it is based on `t3/wave1-search` or
   its successor. It can run alongside 01.
3. **03 Intents + App Shortcut + lint + CI metadata check.** After 01's checks 1–3 and 02.
4. If D2 = A: **04 README + wiki** only.
   If D2 = B/C:
   - **04** `SpotlightItem` + `SpotlightSync` + `lookup(id:)` + setting (core);
   - **05** the Core Spotlight adapter + launch rebuild + delegate;
   - **06** opening a result (D3);
   - **07** the Settings row and the refused state (D4; needs a design pass);
   - all after check 4.
5. **Last: integration and the real-Mac pass**, on a self-signed build.

A design pass (`docs/wiki/workflow.md`, "UI design step") covers only copy:
- the two actions' titles, descriptions, parameter names and the App Shortcut phrases;
- if D2 = B/C, the Settings row and its disabled state.
There are no new windows.

## Testing Decisions

- **Good tests** drive the highest seam and check what a user would get:
  - which files the action returns, and in what order;
  - what Spotlight ends up holding (the fake's final id → item map);
  - where opening a result lands.
  They don't check SQL, call counts or the order of port calls. Fixtures use `IndexedScreenshot.testRow`. No test
  needs the network, a Mac, Shortcuts or Spotlight.
- **Seam 1: `ScreenshotIndex` public API, in-memory** (existing; prior art `ScreenshotIndexTests`). Only new API:
  `lookup(id:)` (D2 = B/C).
- **Seam 2: `FindScreenshotsRequest.run(in:fileExists:now:calendar:)`** (new, always; real in-memory index,
  injected `fileExists`, fixed clock; prior art: wave 1's date and source tests). It covers:
  - for any input, the order is the same as `index.search` for the same query;
  - text matching the title, tags, description and recognized text;
  - each type, each date preset at day edges, source normalization ("x.com" finds "X");
  - empty text gives newest first;
  - the limit is clamped to 1…50, and the default is 1;
  - missing files are skipped and the result is filled up to the limit;
  - only `done` rows are returned, restored-by-undo rows are included, trashed rows (once wave 4 lands) are not;
  - an empty index gives an empty result.
- **Seam 3: `SpotlightSync` with a fake `SystemSearchIndex`** (new, only if D2 = B/C; driven by a real in-memory
  index and its `changes()` feed; prior art: prefactor A's feed tests with `awaitResult`). It covers:
  - every row in the sync table above, checked on the fake's final map;
  - the exact item field set: no recognized text, `key_text` or note;
  - title = the current stem after a rename and after Undo;
  - coalescing (ten updates to one row → one final item);
  - the unchanged-item skip;
  - the launch rebuild (stale fake contents are replaced; missing files are skipped; a change made during the
    rebuild still lands);
  - the switch: off empties the fake, on rebuilds it;
  - `target(forIdentifier:)` for a live, missing, unknown and not-`done` row;
  - `.refused` after a fake error: no further calls, and the reason has no row data.
- **Settings:** `spotlightEnabled` goes through the existing `testEveryPropertyRoundTrips`.
- **App side** (CI compile, CI metadata check, snapshots, real Mac):
  - the intents' parameter mapping is a thin adapter, with no unit test beyond compiling;
  - if D2 = B/C, snapshots of the Settings row: on, off, refused.

### Real-Mac checks (integration ticket, on a self-signed build)
1. Both actions are listed in Shortcuts. A saved shortcut still works after an update N → N+1. This joins auto-update
   P5, which checks a new signature anyway.
2. Find Screenshots with each parameter. An image word from the OCR text finds the screenshot. The returned file
   opens in Quick Look, attaches in Mail, and is unchanged afterwards.
3. Find Screenshots while Shotkeeper is quit: it launches with no window and no setup window, and returns results.
4. Find Screenshots on a screenshot on the Desktop: note any privacy prompt from Shortcuts.
5. Search in Shotkeeper with and without text, with Shotkeeper in the background: the panel comes to the front,
   focused, as with ⌥⌘S (`appkit-gotchas`).
6. The Siri phrase opens the panel.
7. If D2 = A: probe check 5 repeated with a real Shotkeeper screenshot (renamed, tagged, commented).
8. If D2 = B/C:
   - an item appears within a few seconds of a new screenshot;
   - it follows Edit name, Sort Existing and Undo;
   - it leaves on Move to Trash and comes back on Undo;
   - the switch off empties Spotlight;
   - opening a result does what D3 says, including for a missing file;
   - the launch rebuild time is measured with the real index size.
9. These checks go into the consolidated per-release Mac checklist planned in `docs/wiki/workflow.md`
   (2026-11-28, trash research).

## Out of Scope

- `IndexedEntity`, `FileEntity`, Transferable entities and `IndexedEntityQuery` (macOS 15+/27+), unless D1 changes.
- A Core Spotlight delegate app extension [CS9].
- A custom date range parameter. Presets only in v1.
- An action that returns a screenshot's recognized text. Shortcuts' own text extraction from an image probably
  covers it; check that in the real-Mac pass and, if it doesn't, propose it as a follow-up.
- Find Screenshots as a Siri phrase with spoken search text: phrases can't carry free text [W22b].
- Interactive snippets or a results UI inside Shortcuts.
- Putting the recognized text, `key_text` or the source into the Finder comment, or anything else that changes
  `FinderMetadata`.
- Any change to what is analyzed, uploaded or renamed.

## Further Notes

- The action and the search window share one query type. A later search change (a new filter, a weight change)
  reaches Shortcuts for free, and seam 2's "same order as `index.search`" test keeps them from drifting apart.
- Intent, parameter and enum case identifiers are persisted in users' shortcuts [AI4]. Treat them like a public API.
- The probe is the cheapest way to settle four "silent" items from the research at once: ad-hoc and self-signed
  Core Spotlight, `LSUIElement` discovery, `continue` delivery, and file-result duplicates.
- If the self-signed release identity is ever replaced (auto-update says it must not be), probe checks 1 and 4 have
  to be repeated.

## Decisions Parag might disagree with

Beyond D1–D4 above, these calls were made without asking:

1. **Default limit 1** (best match only), maximum 50.
2. **Files returned in place**, not as copies (unless probe check 2 fails).
3. **No custom date range** in the action; the four presets only.
4. **Rows waiting for analysis are never returned**, matching the search window.
5. **Running the action doesn't count as "opening"** a screenshot for clean-up.
6. **Only "Search in Shotkeeper" gets a Siri phrase;** Find Screenshots is a Shortcuts action only.
7. If D2 = B/C: **recognized text and `key_text` are kept out of Spotlight items**, and **title = the current file
   name** (as in the search window), not the model's title.
8. If D2 = B/C: **a full rebuild at every launch** instead of tracking what was sent.
9. If D2 = B/C: **the Spotlight switch is independent of "Write Finder tags and comment".**
