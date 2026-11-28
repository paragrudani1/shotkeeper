# Trash, Put Back and the last-used date: research notes (gathered 2026-11-28)

Context: `docs/specs/clean-up-2026-11.md` needs three answers before any code. (1) Which Trash call to use, and how it
behaves: Put Back, the resulting URL, other volumes, name clashes, overwrites. (2) What `kMDItemLastUsedDate` records,
and how to read it. (3) How an in-app Undo gets a file back from the Trash. It also asks about TCC. Target: macOS 14
and later.

Every source was read on 2026-11-28. Labels: facts are quoted or paraphrased from the source. **Source code** means
read in Apple's open-source Foundation (commits below). **DTS** means a reply by Apple Developer Technical Support on
the Developer Forums; it carries Apple's voice but isn't API documentation. **Forum (non-Apple)** means a forum post
with no Apple badge; it's used only as a lead, never as the basis for a decision. **Inferred** means a conclusion drawn
from the sources that none of them states. **Silent** means no Apple source covers it. **Must test** means only a real
Mac can answer it.

## Sources

Apple API documentation (read through the DocC JSON behind each page, `https://developer.apple.com/tutorials/data/documentation/<path>.json`):
- [D1] `FileManager.trashItem(at:resultingItemURL:)`: https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- [D2] `NSWorkspace.recycle(_:completionHandler:)`: https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)
- [D3] `FileManager.moveItem(at:to:)`: https://developer.apple.com/documentation/foundation/filemanager/moveitem(at:to:)
- [D4] `FileManager.SearchPathDirectory.trashDirectory`: https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/trashdirectory
- [D5] `kMDItemLastUsedDate`: https://developer.apple.com/documentation/coreservices/kmditemlastuseddate
- [D6] `MDItemCopyAttribute(_:_:)`: https://developer.apple.com/documentation/coreservices/1427080-mditemcopyattribute
- [D7] `MDItemCreate(_:_:)`: https://developer.apple.com/documentation/coreservices/1426917-mditemcreate
- [D8] `NSMetadataItem`, `init(url:)` and `NSMetadataItemLastUsedDateKey`:
  https://developer.apple.com/documentation/foundation/nsmetadataitem,
  https://developer.apple.com/documentation/foundation/nsmetadataitem/init(url:)-9xxs3,
  https://developer.apple.com/documentation/foundation/nsmetadataitemlastuseddatekey
- [D9] `URLResourceKey` (the full key list) and `contentAccessDateKey`:
  https://developer.apple.com/documentation/foundation/urlresourcekey,
  https://developer.apple.com/documentation/foundation/urlresourcekey/contentaccessdatekey
- [D10] `NSWorkspace.open(_:)`, `open(_:configuration:completionHandler:)`, `OpenConfiguration.addsToRecentItems`:
  https://developer.apple.com/documentation/appkit/nsworkspace/open(_:),
  https://developer.apple.com/documentation/appkit/nsworkspace/open(_:configuration:completionhandler:),
  https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/addstorecentitems
- [D11] Privacy Preferences Policy Control payload, `Services`: https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol/services-data.dictionary

Apple documentation archive:
- [A1] File Metadata Attributes Reference, "Spotlight Metadata Attributes" (updated 2014-07-15): https://developer.apple.com/library/archive/documentation/CoreServices/Reference/MetadataAttributesRef/Reference/CommonAttrs.html
- [A2] File System Programming Guide, "Managing Files and Directories" (updated 2018-04-09): https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/ManagingFIlesandDirectories/ManagingFIlesandDirectories.html
- [A3] Launch Services Programming Guide, "Launch Services Concepts" (updated 2013-12-16): https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html
- [A4] Spotlight Importer Programming Guide, "Troubleshooting Spotlight Importers" (updated 2013-08-08): https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/MDImporters/Concepts/Troubleshooting.html

Apple Support (pages served for macOS 27 on 2026-11-28):
- [S1] Mac User Guide, "Delete files and folders on Mac": https://support.apple.com/guide/mac-help/delete-files-and-folders-on-mac-mchlp1093/mac
- [S2] Mac User Guide, "Control access to files and folders on Mac": https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac
- [S3] Mac User Guide, "Change Privacy & Security settings on Mac": https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac
- [S4] "Manage your iCloud storage on your Apple device": https://support.apple.com/en-us/108922
- [S5] Mac User Guide, "Store files in iCloud Drive on Mac": https://support.apple.com/guide/mac-help/store-desktop-documents-files-icloud-drive-mchle5a61431/mac

Apple Developer Forums:
- [F1] DTS: "trashItem, recycle, but no put back option...it depends" (Feb 2025, reply by Quinn "The Eskimo!", DTS, accepted answer): https://developer.apple.com/forums/thread/773997
- [F2] DTS: "On File System Permissions" (Quinn, first posted 2021-04-26, last edited 2026-09-18): https://developer.apple.com/forums/thread/678819
- [F3] DTS: "Data to different types ?" (May 2019, reply by Quinn about `com.apple.lastuseddate#PS`): https://developer.apple.com/forums/thread/116739
- [F4] Forum (non-Apple): "Permissions on .Trash folder" (Sep 2019, macOS 10.15 beta): https://developer.apple.com/forums/thread/122716
- [F5] Forum (non-Apple): "'Last Used' metadata (kMDItemLastUsedDate) is not update on some files when opened in Finder" (Sep 2015): https://developer.apple.com/forums/thread/20639
- [F6] Forum (non-Apple): "Changes to NSMetadataQueryDidUpdate functionality in ios 11" (Feb 2018 reply about `com.apple.lastuseddate#PS`): https://developer.apple.com/forums/thread/91159

Apple open source:
- [O1] `swiftlang/swift-foundation` at `72996dbdde1147dd142f5b2ce4c7998c689ba9bb`:
  `Sources/FoundationEssentials/FileManager/FileManager+Directories.swift` (lines 118-132),
  `Sources/FoundationEssentials/FileManager/SearchPaths/FileManager+DarwinSearchPaths.swift` (lines 58-62, 112-135).
- [O2] `swiftlang/swift-corelibs-foundation` at `0c2951a362addd219d6496517fe366feb79d0bda`: `Sources/Foundation/FileManager.swift`.

Repo facts (origin/main `0e755e8`):
- [R1] `Sources/ShotkeeperCore/Files/FileOrganizer.swift:29-32`: the injected `renameNoReplace` primitive, and
  `Sources/ShotkeeperCore/Files/NoReplaceRename.swift:21`: Darwin `renamex_np(RENAME_EXCL)`.
- [R2] `scripts/lint.sh:9` (`file-op` covers `trashItem` and `recycle`).
- [R3] `App/project.yml` is ad-hoc signed, no sandbox, no hardened runtime (see `docs/research/auto-update.md` [R2]).

---

## 1. `FileManager.trashItem` vs `NSWorkspace.recycle`

### What Apple documents

| | `trashItem(at:resultingItemURL:)` [D1] | `recycle(_:completionHandler:)` [D2] |
|---|---|---|
| Availability | macOS 10.8+ (also iOS 11+). Foundation. | macOS 10.6+. **AppKit only.** |
| Shape | Synchronous, one URL, `throws`. | Asynchronous, many URLs. Swift also has `async throws -> [URL: URL]`. With a handler, it must be called "from a block running on an active dispatch queue"; the handler then runs on that queue. |
| Where it went | `resultingItemURL` "is set to the item's location in the trash. **The actual name of the item may be changed when moving it to the trash, so use this URL to access it.**" | `newURLs` "maps the file's original location to its location in the trash … **If this method could not move a file to the trash, the corresponding URL is not included in the dictionary.**" |
| Errors | Throws. | One `error` "describing the overall result of the operation in a manner suitable for presentation to the user"; `nil` only if every file succeeded. |
| UI | None documented. | "Moves the specified URLs to the trash **in the same manner as the Finder**." "This method may cause a progress indicator, or other user interface element, to be shown by the Finder." |

- Neither page mentions Put Back, other volumes, network volumes, iCloud Drive, or a name clash in the Trash.
  **Silent.**
- On Linux, **`trashItem` doesn't exist.** swift-corelibs-foundation's `FileManager` has no `trashItem` [O2] (a grep
  of `Sources` finds only a comment about `getRelationship` and `.trashDirectory`). swift-foundation has none either
  [O1]. So core code that names `trashItem` must sit inside `#if canImport(Darwin)` (or `#if os(macOS)`), or the
  Linux build breaks. **Source code.**

### Put Back: which one records it?

**Neither does it reliably, and Apple says the two behave the same.** In [F1] a developer reports that with several
files trashed in a row, by `trashItem` or by `recycle`, only the first gets Put Back. A two-second gap between calls
fixes it. Quinn (DTS) answered (accepted answer, Feb 2025, macOS 15.2):

- the bug is known and open: "That link includes a bug number (r. 23153124)";
- two `trashItem` calls in a row on his Mac **both** got Put Back ("File > Put Away enabled") at first, then the
  failure reproduced, and "In the second test the Finder had its trash window open. Once I closed that window things
  started working again.";
- "I suspect that Finder and File Manager are bumping into each other when it comes to managing the `.DS_Store` file
  … which is why things work when you add a delay. However, I don't know this code well enough to say anything
  definitive.";
- "Unfortunately I don't see a good workaround for this."
- The poster adds that `recycle` "has the same problem"; its only advantage is that it takes an array.

Conclusions:
- `trashItem` **does** record Put Back in the normal case; it is not "never works" (DTS's test). **DTS.**
- `recycle` gives no Put Back advantage that any Apple source records. "In the same manner as the Finder" [D2] is
  the only hint, and [F1] contradicts it in practice. **DTS + Silent.**
- A batch (Clean Up's normal case) can lose Put Back on all items after the first, at least while a Finder Trash
  window is open. **DTS.** Whether it also happens with that window closed on macOS 14, 15 and 26 is **Must test**.
- So Put Back is best-effort. **Undo is the only way back that Shotkeeper controls**, and the confirmation wording
  should not promise Put Back for every file.

### Is `resultingItemURL` always filled in?

- The docs say it "is set to the item's location in the trash" and say nothing about success without a URL [D1].
  **Silent** on the edge case. Apple documents no case where the call succeeds and leaves it `nil`.
- Keep the spec's `.trashedWithoutLocation` branch as a defensive check: it costs one `if`, and **Must test** can't
  prove a negative.
- For `recycle`, a missing entry means the file wasn't moved [D2]. So "moved but no URL" cannot be told apart from
  "failed" there without checking the disk; one more reason not to use it.

### Which Trash, and can it be on another volume?

- swift-foundation (the code Apple ships as Foundation on macOS 14+) answers
  `url(for: .trashDirectory, in:, appropriateFor: url, create:)` through a private
  `_URLForTrashingItem(at: url, create:)` when a URL is given (`FileManager+Directories.swift:126-130`, guarded by
  `FOUNDATION_FRAMEWORK` and `os(macOS) || os(iOS)`). So the Trash depends on the item, not only on the user.
  For the user domain without a URL, it asks `__user_relative_dirname(…, DIRHELPER_RELATIVE_TRASH, home)`, and for the
  local domain the same relative to `/` (`FileManager+DarwinSearchPaths.swift:112-135`). **Source code.** The private
  function body isn't open source, so Apple doesn't show per-volume `.Trashes`. **Silent.**
- **Inferred:** the item goes to a Trash on its own volume: `~/.Trash` for the boot volume (this includes iCloud Drive
  Desktop and Documents, which live under the home folder), and the volume's own Trash on an external disk. The
  resulting URL is therefore on the same volume as the original, so moving it back is a same-volume rename.
  **Must test** on an external APFS and an exFAT disk: log the resulting URL, and check that it is on the same volume
  (`volumeIdentifierKey` equal).

### External, network and iCloud Drive volumes

- **External disks:** Apple is **Silent** on API behaviour. **Must test**: APFS, HFS+, exFAT and FAT32 external disks
  (FAT and exFAT have no `.Trashes` until something creates it).
- **Network volumes (SMB, AFP, NFS):** Apple is **Silent** on both APIs. [S1] doesn't mention network volumes. **Must
  test**: does `trashItem` throw on an SMB share, or delete, or create a `.Trashes` on the server? The spec's "no
  Trash → error, never delete" rule holds only if `trashItem` throws there; this is the most important test in this
  note. A thrown error must leave the file in place (check that the file is still at the original path after the
  error).
- **iCloud Drive** (including Desktop and Documents synced to iCloud): [S1] "Items that you move to the Trash from
  iCloud Drive are automatically emptied from the Trash after 30 days" "regardless of Finder settings". [S4] "If you
  move it to the Trash, you can find it in Trash for 30 days." So a screenshot binned from an iCloud-synced Desktop
  **can vanish from the Trash after 30 days even if the user never turned on "Remove items from the Trash after 30
  days"**. `reconcileTrash` and the "Trash emptied" Undo message cover it; the Clean Up confirmation could say so
  for such files. [S5] doesn't say how "Optimize Mac Storage" (files not downloaded) behaves when trashed. **Silent**
  → **Must test**: trash a not-downloaded (evicted) file in iCloud Desktop, then check the resulting URL, that the file
  is in `~/.Trash`, and that Undo brings it back and it syncs again.
- Finder's own 30-day option: [S1] Finder > Settings > Advanced > "Remove items from the Trash after 30 days";
  auto-removed items "are permanently deleted".

### Name already in the Trash

- `trashItem`: "The actual name of the item may be changed when moving it to the trash" [D1]. So a clash gets a new
  name in the Trash, and the resulting URL is the only way to find the file. **Fact** (the rename); the naming scheme
  (Finder uses `name 12-34-56.png` style) is **Silent**, and code must not guess it.
- `recycle`: **Silent** on clashes.

### Can either overwrite anything?

- Apple documents no case in which either replaces an item already in the Trash or anywhere else. `trashItem`'s
  "name may be changed" [D1] is the documented answer to a clash. **Fact + Silent** (no explicit "never replaces").
  **Must test**: trash `a.png`, create a new `a.png` in the same folder, trash it, and check both are in the Trash with
  their bytes.
- Neither API deletes. [A2] contrasts the remove methods ("you are permanently removing the files … these methods do
  not move the file to the Trash") with the Trash; it doesn't cover `trashItem`.

### Other facts worth knowing

- `trashItem` inside an outer `NSFileCoordinator` write block can deadlock (forum thread 128381, non-Apple, macOS
  10.15: https://developer.apple.com/forums/thread/128381). Shotkeeper doesn't coordinate today; don't wrap the call.
  **Forum (non-Apple).**
- `contentAccessDateKey` and other `URLResourceKey`s have no Trash link: there is no "original location" key [D9].
  Finder's Put Back data is private (`.DS_Store`, per DTS [F1]); Shotkeeper must not read or write it.

### Answer to spec question 1

**Use `FileManager.trashItem(at:resultingItemURL:)`.** Apple's only statement on Put Back [F1] treats `trashItem` and
`recycle` as having the same Put Back behaviour and the same open bug, so `recycle` doesn't serve "get them back from
the Trash" better. `trashItem` is also synchronous, reports one file at a time, documents its resulting URL and the
rename on a clash, and needs no AppKit. Put Back for a batch is best-effort (DTS: a Finder Trash window open during the
batch breaks it), so Undo is the guaranteed way back. Network volumes, exFAT/FAT disks and evicted iCloud files:
**needs a real-Mac test.**

---

## 2. `kMDItemLastUsedDate`

### What Apple documents

- [D5], [A1]: "The date and time that the file was last used. This value is updated automatically by LaunchServices
  everytime a file is opened by double clicking, or by asking LaunchServices to open a file. A CFDate." macOS 10.4+.
- [A1] lists it under **"Common Spotlight Metadata Attribute Keys"**, not under "File System Metadata Attribute
  Keys", which alone carry "These attributes are available for files on any mounted volume." So Apple does **not**
  promise it on every volume. **Fact** (the placement); what that means for an unindexed volume is **Silent**.
- [A4] shows it in `mdls` output, "the metadata attributes and values in the system store for a file".

### What updates it

| Action | Apple's answer |
|---|---|
| Double-click in Finder (opens in Preview) | Updated. **Fact** [D5]. |
| `open` command / another app calling Launch Services (`LSOpenCFURLRef` etc.) | Updated ("asking LaunchServices to open a file"). **Fact** [D5]; [A3] names the LS open functions. |
| Another app's `NSWorkspace.open` | **Inferred** updated: [D10] doesn't say NSWorkspace goes through Launch Services, but its `addsToRecentItems` ("add the items to the Recent Items menu", default `true`) matches [A3]'s "Launch Services adds both the application and the document (or URL) to the Recent Items submenus". **Must test.** |
| Shotkeeper's own `NSWorkspace.shared.open(url)` (`WorkspaceActions.swift:9` on origin/main) | Same as the row above: **Inferred** updated, **Must test**. Harmless either way: the spec counts that open in `last_opened_at` itself. |
| File > Open inside Preview (or another app's open panel) | **Silent.** A non-Apple observation [F6] says opening an `NSDocument` (macOS 10.13+) updates `com.apple.lastuseddate#PS`. **Must test.** |
| Quick Look (Space) in Finder | **Silent.** **Must test**; the guess is "not updated", since Quick Look isn't an open. |
| Files carrying `com.apple.quarantine` | [F5] (non-Apple, 2015): some quarantined files don't get the date when opened from Finder. **Must test** whether screenshots ever carry it (ones saved by the system screenshot tool shouldn't). |

### Spotlight off, or the volume excluded

- **Silent.** No Apple source says whether `kMDItemLastUsedDate` exists without an index or on a volume in Spotlight's
  Privacy list.
- [F3] (DTS, Quinn): the `com.apple.lastuseddate#PS` extended attribute is "the backing store for higher-level
  APIs … In this specific case, you should use `NSMetadataItemLastUsedDateKey`", and "this is a UNIX `timespec`
  structure". So the date is stored **on the file** (as an extended attribute), not only in the Spotlight index.
  **DTS.** **Inferred:** the attribute survives with indexing off; whether `MDItemCopyAttribute` /
  `NSMetadataItem` still return it then is **Must test**.
- Quinn in [F3]: "You should not depending on the name and format of extended attributes unless they are explicitly
  documented … This is not the case here." So **don't read `com.apple.lastuseddate#PS` directly.** **DTS.**

### How the app reads it

There is **no `URLResourceKey`** for it: the key list [D9] has `contentAccessDateKey` and `addedToDirectoryDateKey`,
nothing for "last used" or "last opened". Two supported ways, both app-only (CoreServices / Foundation's
`NSMetadataItem`, neither exists in swift-corelibs-foundation):

1. `MDItemCreate(kCFAllocatorDefault, path as CFString)` [D7] ("The path must exist"; returns `NULL` "if there was a
   problem") then `MDItemCopyAttribute(item, kMDItemLastUsedDate)` [D6] → `CFDate` or `NULL`. macOS 10.4+.
2. `NSMetadataItem(url:)` [D8] (failable, macOS 10.9+) then `value(forAttribute: NSMetadataItemLastUsedDateKey)`
   (macOS 10.9+). DTS names this one [F3].

Both are fine on macOS 14. `NSMetadataItem` is the one DTS recommends and is more Swift-friendly.

`MDItemCopyAttribute` returns `NULL` "if there was a failure reading the attribute **or** the attribute does not
exist" [D6]. So **the API can't tell "never opened" from "can't tell"**. The spec's port (`.date` / `.never` /
`.unknown`) can't get `.never` vs `.unknown` from this call alone:
- `nil` item (`MDItemCreate`/`NSMetadataItem(url:)` failed) → `.unknown`;
- item, no date → "no record". Apple gives no way to know whether that means never opened or not tracked here.

The spec already lists both cases (rule: "never opened" = `.never` or `.unknown`, with a note for `.unknown`). The
listing result doesn't change; only the note does. Either drop `.never` and show "macOS has no record of an open"
for every file without a date, or **Must test** on a volume with indexing off: if no date ever comes back there,
mark `.unknown` by volume (but there's no documented API for "is this volume indexed"; `mdutil -s` is a CLI tool).

Other dates: `contentAccessDateKey` [D9] is the file access time, which the spec already rejects (Shotkeeper reads
every file itself). Don't use `kMDItemUsedDates`: [A1] doesn't list it. **Silent.**

### Answer to spec question 2

Read with `NSMetadataItem(url:)` + `NSMetadataItemLastUsedDateKey` (or `MDItemCreate` + `MDItemCopyAttribute`),
app layer, macOS 10.9+/10.4+, no `URLResourceKey`. Apple documents that Launch Services opens (Finder double-click,
`open`, LS calls) update it. NSWorkspace opens, including Shotkeeper's own: inferred yes. Quick Look in Finder,
an app's open panel, Spotlight off or an excluded volume: **needs a real-Mac test.** A missing date can't be told apart
from "not tracked", so the port gives "no record" for both, and the plan lists those files with a note, as the spec
already does.

---

## 3. Restoring from the Trash for in-app Undo

### The move back

- `FileManager.moveItem(at:to:)` [D3]: "If an item with the same name already exists at `dstURL`, this method stops
  the move attempt and returns an appropriate error." "If the source and destination of the move operation are not on
  the same volume, this method copies the item first and then removes it from its current location." [A2]: "Move
  operations between volumes behave the same as a copy operation."
- **Inferred:** `moveItem` checks the destination and then moves, so another file appearing between the check and
  the move isn't covered by its documented contract. Across volumes it copies and then removes the original.
  **Use the existing `renameNoReplace` primitive** [R1] (`renamex_np(RENAME_EXCL)`: atomic, fails with `EEXIST`
  when the name is taken, `EXDEV` across volumes and never copies). The Trash is inferred to be on the same volume
  (section 1), so `EXDEV` should not happen. If it does, report it and leave the file in the Trash; don't fall back to
  copy-and-delete.
- **Original folder gone:** `rename(2)` fails with `ENOENT` when the destination's parent doesn't exist. (POSIX; Apple's
  man page `rename(2)`, not re-read for this note.) **Inferred.** Undo must not create folders the user deleted
  (the spec doesn't say); report "The folder <name> no longer exists. The screenshot is still in the Trash." This is a
  new undo message the spec doesn't list.
- **Name taken:** `EEXIST` → the spec's `originalPathOccupied` message. **Fact** for `RENAME_EXCL`.
- `ENOENT` is ambiguous (missing source **or** missing destination folder). Check the source in the Trash first
  (below), then the destination folder, before choosing the message.

### Detecting that the Trash was emptied

- No Apple API reports "the Trash was emptied". **Silent.** Detection = the stored resulting URL no longer exists
  (`lstat` → `ENOENT`).
- The file may also have left the Trash because the user put it back (Finder's Put Back or a drag), moved it
  elsewhere, or because iCloud Drive or Finder's 30-day rule emptied it [S1]. The spec's `reconcileTrash` covers these
  by checking `trashed_from` for the fingerprint.
- **Don't treat `EPERM` as "gone".** If TCC blocks a lookup inside `~/.Trash` (section 4), `lstat` fails with `EPERM`,
  not `ENOENT` ([F2]: "If it was blocked by something else, it'll fail with `EPERM`"). Only `ENOENT` means gone; any
  other error means "can't check now", and the row is kept.

### Answer to spec question 3

Undo = `renameNoReplace(trashURL, originalPath)`: atomic, fails rather than replaces, never copies across volumes.
`EEXIST` → "a file is in its place"; source `ENOENT` → "Trash emptied / no longer in the Trash"; destination folder
missing → a new "folder no longer exists" message; `EPERM` → "can't reach the Trash", nothing else changes. Whether
a non-FDA app may `lstat` and `rename` a known path inside `~/.Trash`: **needs a real-Mac test** (section 4).

---

## 4. Sandbox and TCC

- Shotkeeper is not sandboxed and is ad-hoc signed [R3]. App Sandbox doesn't apply.
- Apple's list of TCC services for files [D11]: `SystemPolicyAllFiles` (Full Disk Access), `SystemPolicyDesktopFolder`,
  `…DocumentsFolder`, `…DownloadsFolder`, `…NetworkVolumes`, `…RemovableVolumes`, `…SysAdminFiles`,
  `…AppBundles`, `…AppData`, plus `FileProviderPresence`. **No Trash service.** [S2] names only Desktop, Downloads
  and Documents; [S3] describes Full Disk Access as "all files on your computer, including data from other apps".
  Neither mentions the Trash. **Silent** on the Trash.
- [F2] (DTS): "The exact list of file system locations protected by MAC is not documented and … can change over
  time." Failures from MAC return `EPERM`; prompts appear only in a GUI session; "If your code is unsigned, or signed
  ad hoc … you'll encounter excessive prompts" (relevant: Shotkeeper is ad-hoc signed, so each new build may
  re-prompt).
- [F4] (non-Apple, macOS 10.15 beta): `sudo ls ~/.Trash` fails with "Operation not permitted"; the answer points to
  Full Disk Access. So **listing** `~/.Trash` is TCC-protected (likely under Full Disk Access). **Forum (non-Apple).**
- Shotkeeper never needs to list the Trash: it keeps the resulting URL and only `lstat`s and renames that one path.
  Whether TCC allows that for a non-FDA app is **Silent** → **Must test**. Watching `~/Desktop` already needs the
  Desktop permission (`SystemPolicyDesktopFolder`); moving a Desktop file into `~/.Trash` with `trashItem` needs
  only that, as far as Apple says. **Silent** → **Must test**.
- Spec rule that follows: the clean-up walk must skip `~/.Trash` and every `.Trashes` (the spec already skips hidden
  folders), so no listing ever touches them.

---

## Must test on a real Mac (macOS 14, 15 and 26 if available; an ad-hoc-signed build without Full Disk Access)

1. **Put Back:** trash 1 file, then a batch of 20 with `trashItem` in a loop, with the Finder Trash window closed,
   then open. Count files where File > Put Back is enabled. Repeat with `recycle` once to confirm DTS's "same". If the
   batch loses Put Back with the window closed, record the minimal delay that fixes it (DTS and the poster: about
   2 s); the spec then decides between a delay and wording.
2. `resultingItemURL` is non-nil on every success in tests 1, 3, 4, 5.
3. **External disks** (APFS, HFS+, exFAT, FAT32): resulting URL path and volume; first trash on a disk with no
   `.Trashes`; Undo rename back.
4. **Network volume** (SMB): does `trashItem` throw, delete or move? The file must still exist after an error.
5. **iCloud Desktop:** a downloaded and an evicted (Optimize Mac Storage) file: resulting URL, Undo, re-sync.
6. **Clash:** two files with the same name trashed: both kept, second renamed, bytes intact.
7. **TCC:** without Full Disk Access, can the app `trashItem` a Desktop file, `lstat` the resulting URL, and rename it
   back? Does any prompt appear? Record the errno on failure.
8. **Last-used date:** for a fresh screenshot, read the date after: nothing; Quick Look in Finder; double-click in
   Finder; `open` in Terminal; Shotkeeper's Open; Preview's File > Open; a Shotkeeper Quick Look. Then a file on an
   external disk with Spotlight indexing off (`mdutil -i off`) and in Spotlight's Privacy list.
9. Do system screenshots ever carry `com.apple.quarantine` (`xattr -l`)?

## What this changes in the spec

- **Recommendation 11 stands, with two changes:** `FileManager.trashItem` in core `FileOrganizer`, because `recycle`
  has no Put Back advantage per Apple [F1].
  1. The default primitive must be inside `#if canImport(Darwin)`: `trashItem` doesn't exist in Linux Foundation
     [O2]. On Linux the default throws "no Trash on this system", as the spec already says.
  2. Put Back is best-effort for batches (open Apple bug r. 23153124). The confirmation and docs say Undo always works
     while the file is in the Trash and Put Back "usually" works; don't promise Put Back per file (story 38).
- **Undo uses `renameNoReplace`,** not `moveItem`, and treats `EPERM` as "can't check", never as "emptied".
- **New undo message:** "the original folder no longer exists" (Undo doesn't recreate folders).
- **`LastUsedDates`:** `.never` and `.unknown` can't be told apart from the API; the note reads "macOS has no record
  of an open" for both, unless test 8 shows a clean split by volume. Read via `NSMetadataItem` (DTS's choice); never
  read `com.apple.lastuseddate#PS`.
- **iCloud Drive files** leave the Trash after 30 days regardless of Finder settings [S1]. Worth a line in the
  confirmation for such files; `reconcileTrash` already copes.
