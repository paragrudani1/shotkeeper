# 02: The Trash choke point and the written exception (`FileOrganizer.trash`, lint `trash`, AGENTS.md, CODING_STANDARDS #1)

**What to build:** the one place in the repository that can put a user file in the Trash, and the written rule that
allows it. After this ticket `FileOrganizer.trash(_:)` exists, moves a file to the Trash and returns where it went, or
throws and leaves the file where it was; it never deletes. The AGENTS.md rule and CODING_STANDARDS #1 carry Parag's
exception in its final wording, and `scripts/lint.sh` fails any other file that names the system Trash call. No
user-facing path calls `trash` yet (07 does).

**Blocked by:** None (can start immediately). Core, lint and docs.

**Status:** ready-for-agent

**Owns the exception.** This ticket, and only this one, changes the AGENTS.md "Rules" first bullet, CODING_STANDARDS
#1 and the lint `trash` rule. They land **in the same PR as the first code that can call `trashItem`** (this
ticket's primitive), and the old wording is left nowhere. **Nothing else may call `trashItem` or `recycle`**: no
later ticket adds a second caller, a `lint-allow` marker or a CLI path (spec "Out of Scope": no clean-up from the CLI).

**Sources:** spec "Moving to the Trash: the one choke point", "The written exception (lands in the same PR as
`FileOrganizer.trash`)", `scripts/lint.sh` bullets; research §1 "Answer to spec question 1", §1 "Other facts", "What
this changes in the spec" (first bullet). The research wins over the spec here (README, "Where the research wins").

**Test seam:** `FileOrganizerTests` (existing; the fake primitive) and seam 3, `scripts/lint.sh --self-test`.

**Likely touches:** core `Files/FileOrganizer.swift` (`trash`, the injected primitive, the error type),
`Files/UndoLog.swift` and `Files/NoReplaceRename.swift` doc comments only, `FileOrganizerTests`, `scripts/lint.sh`,
`AGENTS.md`, `CODING_STANDARDS.md`, `docs/core-api.md`, `docs/wiki/workflow.md`, `docs/wiki/clean-up.md`.

- [ ] `FileOrganizer.trash(_ url:) throws -> URL` returns the item's URL in the Trash. The primitive is injected like
      `renameNoReplace`. The default is `FileManager.trashItem(at:resultingItemURL:)` **inside `#if
      canImport(Darwin)`** (Linux Foundation has no `trashItem`, research [O2]); on Linux the default throws "no Trash
      on this system" and is never called in tests. `trashItem` is not wrapped in an `NSFileCoordinator` block
      (research §1 "Other facts"). A comment next to the call cites `docs/research/trash-and-last-used.md`.
- [ ] Never falls back to deleting: a volume without a Trash, a permission error or any thrown error leaves the file
      at its path (`noTrashOnVolume`, permission, other). If the primitive reports success with no resulting URL,
      `trash` throws `.trashedWithoutLocation` (kept as a defensive check; research: Apple documents no such case).
- [ ] `FileOrganizerTests` with a fake primitive that does a no-replace move into a temp "Trash" folder and renames
      on a clash: a clash in the Trash renames and never replaces (both files keep their bytes); an error leaves the
      file in place; no-URL success throws `.trashedWithoutLocation`.
- [ ] `scripts/lint.sh`: new rule `trash`: `trashItem(` and `recycle(` allowed **only** in `FileOrganizer.swift`; no
      `lint-allow: trash` marker accepted anywhere. `file-op` drops `trashItem` and `recycle` from its pattern. The
      header and the `file-op` message read "never deleted; moved to the Trash only by FileOrganizer.trash after the
      user confirmed (CODING_STANDARDS #1)". Self-test cases: `trashItem` in `FileOrganizer` passes; in `UndoLog`
      fails; `recycle(` in an app file fails; a `// lint-allow: trash (x)` marker still fails; expected count updated.
- [ ] AGENTS.md "Rules" first bullet and CODING_STANDARDS #1 replaced with the spec's drafts ("The written
      exception"), adjusted only where the research wins: the exception names `FileOrganizer.trash` (core,
      `trashItem`), and says nothing that promises Finder's Put Back. No copy of the old wording remains
      (`git grep "No code path deletes a user file"` finds only the new text).
- [ ] Doc comments on `FileOrganizer` and `UndoLog`: "Never overwrites and never deletes a user file" gains "; moves
      to the Trash only from `trash(_:)`". `WorkspaceActions`'s comment changes only if it becomes untrue.
- [ ] A dated decision line in `docs/wiki/workflow.md` pointing at the new wording; `docs/wiki/clean-up.md` started
      or appended (README, "Wiki page"); `docs/core-api.md` entry.
- [ ] `SCRATCH=.build/linux-<you> scripts/test-linux.sh` and `scripts/lint.sh` (and `--self-test`) green.
- [ ] **Done only when `macos-app` CI is green** on the PR: the Darwin branch of the primitive compiles only there.
- CI snapshots: none.
- Real-Mac checks: none here (no app caller yet). Research checks 2, 3, 4, 5, 6 and 7 exercise this primitive through
  ticket 07's run.
