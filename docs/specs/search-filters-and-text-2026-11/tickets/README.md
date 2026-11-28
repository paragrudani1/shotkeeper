# Wave 1 tickets: search filters and Copy Text (2026-11-28)

Tickets for the [spec](../../search-filters-and-text-2026-11.md) and the approved
[design](../../../design/search-filters-and-text.md) (Parag, 2026-11-28). Made with the to-tickets skill, local layout:
one file per ticket, blocking edges as text. The spec's requirements are not edited here.

Builds on the merged index prefactor ([prefactor-index](../../../wiki/prefactor-index.md), PR #9) and the app
prefactor, PR #10 (`t3/prefactor-app`: `SearchKeyMap`, `SearchResultActions`, one snapshot file per screen,
`scripts/lint.sh`). Every ticket that touches the app starts after PR #10 merges.

Every ticket counts as done only when `macos-app` CI is green on its PR (AGENTS.md), along with the Linux tests and
`scripts/lint.sh`.

## Tickets

| # | Ticket | Blocked by | Area |
|---|---|---|---|
| 01 | [Index migration: recognized text in search, filter indexes](01-index-migration-recognized-text.md) | none | core |
| 02 | [Date filter, end to end](02-date-filter.md) | PR #10 | core + search panel |
| 03 | [Source filter, end to end](03-source-filter.md) | 02 | core + search panel |
| 04 | [Read the text in new screenshots (Vision, runner)](04-text-recognition-new-screenshots.md) | 01, PR #10; merge gate 05 | core + app wiring |
| 05 | [Measure the Vision settings on a real Mac](05-measure-vision-settings.md) | none (needs Parag's Mac) | script + research note |
| 06 | [Copy Text from a search result](06-copy-text.md) | 01, PR #10 | core + search panel |
| 07 | [Read one screenshot on demand](07-read-on-demand.md) | 04, 06 | core + search panel |
| 08 | [Read Text in Existing Screenshots](08-read-existing-screenshots.md) | 04, PR #10 | core + menu |

```
01 ──┬──> 04 ──┬──> 07
     │    ^    └──> 08
     │    05 (merge gate for 04)
     └──> 06 ─────> 07
PR #10 ──> 02 ──> 03
PR #10 ──> 04, 06, 08
```

## What can run in parallel

- **Now (before PR #10):** 01 (core only, no app files) and 05's script (Parag runs it).
- **Once PR #10 merges:** 02, plus 01 and 05 if still open.
- **Once 01 merges:** 04 and 06, alongside 02 or 03.
- **Once 04 merges:** 08; 07 also needs 06.
- At most four agents at once (workflow, 2026-11-28).

## Hotspots and how the slices avoid them

- **Index migration** (`ScreenshotIndex.swift`): only 01 adds a version (one migration with the OCR columns, the FTS
  rebuild and the filter indexes). 02, 03, 06–08 add none. This departs from the spec's "two migrations, whichever
  merges second renumbers"; 01 records it in the wiki.
- **Search panel** (`SearchWindowState`, `SearchKeyMap.bindings`, `SearchView`, `SearchSnapshots`): 02 → 03 are
  chained because they share the picker and the no-match builder. 06 runs beside them and touches the preview, not
  row 2. Expected conflicts are one-line additions (key bindings, snapshot names); the second PR to merge rebases.
  New views go in their own files so `SearchView.swift` doesn't become the conflict point.
- **`ScreenshotProcessor`**: only 04 edits it (one field set on save).
- **Menu** (`MenuContentView`, `MenuText`, `MenuSnapshots`): only 08.
- **Coordinator**: 04 wires the runner; 08 and 07 use it. They don't edit the same lines if 04 gives the runner its
  own coordinator part (as PR #10 did for `CaptureSources` and `FileActions`).

## Snapshot names (light and dark)

- 02: `search-date-custom`, `search-no-match-filters-only`, `search-no-match-filters`
- 03: `search-filters-on`, `search-source-picker`; `search-empty-index` updated
- 06: `search-text-copied`, `search-text-reading`, `search-text-failed`, `search-text-none`
- 08: `menu-reading-text`, `menu-read-text-done` (proposed; the design lists no menu snapshots)
