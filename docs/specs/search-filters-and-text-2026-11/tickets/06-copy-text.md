# 06: Copy Text from a search result (⇧⌘C and the badge)

**What to build:** with a result selected, ⇧⌘C or the **Copy Text** badge on the preview image copies the
screenshot's full text as plain text and shows "✓ Text copied". A row with no text shows "No text found in this
screenshot."; a failed row shows "The text could not be read."; a row still being read shows "Reading text…" and
copies when ready, unless the user copied something else or moved on meanwhile. ⌘C still copies the image.

**Blocked by:** 01 (text columns and statuses). PR #10 merged (`SearchKeyMap`, `SearchResultActions`,
`SearchSnapshots`). Does **not** need 04: rows with text are made through the index in tests and snapshot fixtures;
in the real app text appears once 04 is merged.

**Interim behaviour until 07 merges:** a never-read row (status NULL) shows no badge and ⇧⌘C beeps; the core outcome
`readFirst` is defined here but the app performs it in 07. Say so in the wiki.

**Status:** ready-for-agent

**Sources:** spec "Which key copies the text", "Late copy rule", "Core outcome", stories 28–35, 37, 52; design §2
("The one bold choice"), §4 (Preview: the Copy Text badge), §5 (Copy Text table, tooltips), §6 (⇧⌘C), §8, §9.

**Test seams:** seam 2 (`SearchWindowState` copy outcome per status), seam 1 (`SearchResultItem` carries the text
and status), `SearchKeyMapTests` (⇧⌘C).

**Likely touches:** core `SearchResultItem` (`recognizedText`, text status), a copy-outcome enum on
`SearchWindowState`, `SearchKeyMap` (accept ⇧⌘ for `c` only); app `SearchResultActions` (pasteboard write, late-copy
rule), a badge view (own file) over the preview image above `FileDragArea`, `SearchSnapshots`.
Shared hotspots with 02/03: `SearchWindowState`, `SearchKeyMap.bindings`, `SearchView`, `SearchSnapshots`; the
second to merge rebases.

- [ ] Copy outcome for the selection: copy text (`done`) / read first (NULL) / no text (`none`) / failed (`failed`,
      with "file missing" told apart) / wait (`pending`) / not available (no selection). Tests per status.
- [ ] `SearchKeyMap`: ⇧⌘C → Copy Text, matched on the lowercased ASCII character, else key code 8; ⌘C unchanged
      (image, or the field's selected text); the collision test covers ⇧⌘C.
- [ ] Pasteboard: one item with only `.string`; the "✓ Text copied" pill uses the "✓ Copied" timing; VoiceOver
      announces "Text copied". `none` and `failed` show their pills for 3 s with the design's symbols and announce them.
- [ ] Waiting (`pending`): the badge shows a spinner and "Reading text…"; on the row's `.updated` change the copy
      happens only if the pasteboard `changeCount` is unchanged since the key press and the panel still shows that row;
      otherwise nothing is written and the badge returns to Copy Text. Only the last waiting request counts.
- [ ] Badge: bottom-right of the image frame, inset 10 pt, 26 pt capsule, black 72%, "⇧⌘C" keycap; hidden for `none`;
      "Read text again" look for `failed` (the retry action itself is 07; here the badge shows the failure pill);
      a click never starts a drag or counts as a double-click. Footer keeps its five hints.
- [ ] New CI snapshots, light and dark: `search-text-copied`, `search-text-reading`, `search-text-failed`,
      `search-text-none`.
- [ ] Real-Mac checks: ⇧⌘C on QWERTY, Dvorak and Russian; pastes plain text only into TextEdit (rich mode) and Slack;
      the late-copy `changeCount` check (copy something else while a row is pending); badge over light and dark
      screenshots, click doesn't drag; VoiceOver badge states; Quick Look Live Text partial selection (record the
      result in the wiki).
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki lines (badge departure, interim NULL behaviour).
- [ ] **Done only when `macos-app` CI is green** on the PR.
