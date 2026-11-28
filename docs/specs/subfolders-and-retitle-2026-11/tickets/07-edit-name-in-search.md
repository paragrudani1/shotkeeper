# 07: Edit name from the search window (⌘E)

**What to build:** in the search panel, the selected screenshot's title gets two quiet icon buttons (✎ Edit name and
✦ Analyze Again; ✦ stays disabled with its tooltip until 08). ⌘E or ✎ turns the title into a field with the name
selected; ↩ saves, Esc cancels. Saving renames the file with the toast's rules, marks the title as the user's, shows
"✓ Renamed", keeps the row selected and is undoable from the menu. The preview's Folder line shows the subfolder path.
This ticket also builds the status line under the title that 08 fills.

**Blocked by:** 02 (`rename` sets `title_source`), and **wave 1's panel work merged** (wave 1 tickets 02, 03, 06,
07: they change `SearchWindowState`, `SearchKeyMap` including the ⇧⌘ trigger, `SearchView` and `SearchSnapshots`
first, and their Esc order and focus order are what this extends). Start on the wave 2 integration branch, cut from
main after wave 1 merges.

**Status:** ready-for-agent

**Sources:** spec "Rename by hand from the search window" (all, including keys), stories 30–41, 29 (Folder line),
UI surfaces 4, 7 (renaming indicator), 8, 11; design §2 "Where the two new actions go" and "Where results go", §3,
§5.1, §5.2, §5.4 (renaming), §9 (keys, Esc order, focus, VoiceOver for the editor), §10, §12 (polish 1–4, 8, 10;
wave 1 1–3).

**Test seam:** seam 3, `SearchWindowState` + `SearchKeyMap` (prior art `SearchWindowTests`, `SearchKeyMapTests`);
seam 1 for the rename itself (already covered by `rename(_:to:)` tests; add the subfolder case: a sorted file stays in
its subfolder).

**Likely touches:** core `Search/SearchWindowState.swift` (`beginEditing()`, `commitEdit()`, `cancelEdit()`,
`editingText`, Esc order, cancel on hide / search / chip / filter / selection, selection kept by row id),
`Search/SearchKeyMap.swift` (`SearchKey.editName` ⌘E and `SearchKey.analyzeAgain` ⇧⌘E bound now, so the collision
tests cover both), `Feedback/UserFacingError.swift` if the messages need a home; app new view files for the title row,
the editor and the status line (keep `SearchView.swift` from becoming the conflict point), `Platform/SearchPanel.swift`
(key routing while editing), `Platform/SearchResultActions.swift` (rename through `FileActions`),
`Coordinator/FileActions+Retitle.swift` (new: rename from the panel), `SearchSnapshots`.

- [ ] Keys: ⌘E (`e`, key code 14) → edit name; ⇧⌘E → analyze again (bound, handler beeps until 08). Matched on the
      lowercased ASCII character, else the physical key, with the IME guard. Collision tests pass, including non-Latin
      layouts. The footer keeps its five hints; tooltips show the keys ("Edit name (⌘E)").
- [ ] Editing state: begin selects the stem without extension; while editing every panel binding is ignored except
      ↩ (save) and Esc (cancel), and ⌘A/C/V/X/Z edit the field's text. Esc order: (consent card, added in 09) → name
      editor → wave 1 picker → clear → close. Hide, a search, a chip, a filter or a selection change cancels.
- [ ] Results (design §5.2): success closes the editor, shows the "✓ Renamed" pill for 1.4 s, keeps the selection by
      row id after the change-feed refresh; a row that no longer matches moves the selection to the nearest row with
      the status line "Renamed. It no longer matches your search, so the next screenshot is selected." (announced);
      clash → pill plus status line "Renamed to “X 2”: “X” is already in this folder."; unusable name → editor stays
      open, error line "Choose a name with letters or numbers."; file missing → editor closes, the existing missing
      pill; other error → editor stays, "Could not rename: <readable message>." (no `String(describing:)`).
- [ ] Title row: 22×22 icon buttons `pencil` and `sparkles`, quiet until hover, hidden while editing; ✦ disabled with
      tooltip "Analyze this screenshot again (⇧⌘E)" until 08. Editor: 18 pt rounded-border field, hint row "↩ Save
      esc Cancel" with Cancel and Save buttons; spinner only if saving takes over 0.3 s.
- [ ] Status line component (12 pt, symbol, coloured first phrase, optional trailing button, max 2 lines, tooltip
      with full text) that belongs to the row and clears when the panel hides. 08 adds its states.
- [ ] Folder line: inside the organized folder shows "Screenshots › Receipts" (middle truncation, full path tooltip,
      VoiceOver "Folder: Screenshots, Receipts"); elsewhere as today.
- [ ] Result row indicator: a 12 pt spinner while renaming; VoiceOver appends ", renaming".
- [ ] Focus: the field takes focus while editing and gives it back to the search field; the panel stays key and never
      activates Shotkeeper. Full Keyboard Access order inserts Edit name and Analyze Again after the Copy Text badge.
- [ ] VoiceOver: "Renamed to …", the unusable-name message.
- [ ] Menu: "Undo: <new title>" undoes the hand rename (existing rename record).
- [ ] New CI snapshots, light and dark: `search-edit-name`, `search-edit-name-error`, `search-edit-name-clash`, and the
      default preview with the two icon buttons (update the existing search preview snapshots; list them in the PR).
- [ ] Real-Mac checks: ⌘E not taken by the field ("Use Selection for Find") or SwiftUI default menus; the editor in the
      non-activating panel takes focus and gives it back; Japanese IME (↩ in the candidate list doesn't save); ⌘E and
      ⇧⌘E on QWERTY, Dvorak and Russian; Esc order; VoiceOver announcements; Full Keyboard Access order.
- [ ] Linux tests and `scripts/lint.sh` green; dated wiki lines (including the recorded keyboard deviation for
      "Use This Name" / "Fix Settings…" if 08 hasn't recorded it).
- [ ] **Done only when `macos-app` CI is green** on the PR.
