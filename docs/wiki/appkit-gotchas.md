# AppKit gotchas for agents without a Mac

Lessons where green CI hid a real-Mac bug. Read this before writing panel, keyboard, pasteboard or drag code.
Nobody runs the app before merge, so these are found only by review. Sources: PR #5 review (2026-11-21),
fixed in `paragrudani1/shotkeeper@544e24a`.

- 2026-11-21: ⌘-key shortcuts handled in `NSWindow.sendEvent` may never arrive. AppKit offers ⌘ events to
  `performKeyEquivalent` and the main menu first, and SwiftUI adds a default Edit menu (Copy ⌘C) even to a
  menu-bar app. Handle ⌘ keys in `performKeyEquivalent`; keep `sendEvent` for unmodified keys. Return false
  for ⌘C when a text field has a selection so text copy still works.
- 2026-11-21: match shortcuts by ASCII character, else by physical key code. `charactersIgnoringModifiers` is
  Cyrillic on a Russian layout.
- 2026-11-21: keep the IME guard (`hasMarkedText`) on every key path, including Return, Space, arrows and Esc.
- 2026-11-21: `QLPreviewPanel` and other standard panels are not non-activating. A click in them activates
  Shotkeeper. Record `NSWorkspace.shared.frontmostApplication` when showing our panel and re-activate it on
  dismiss if `NSApp.isActive`. Quick Look finds its controller through the main window's responder chain; a
  panel with `canBecomeMain == false` needs `AppDelegate` to answer `acceptsPreviewPanelControl`.
- 2026-11-21: `NSPasteboard.writeObjects([image, url])` writes two items, and some apps paste both. Write one
  `NSPasteboardItem` with the original bytes (`.png`) plus `.fileURL`.
- 2026-11-21: SwiftUI `NSItemProvider(contentsOf:)` drags become file promises, which Slack desktop and Chrome
  often reject. Use an AppKit drag source that writes `public.file-url` and allows only `.copy`, so Finder can
  never move a user file (CODING_STANDARDS #1).
- 2026-11-21: a double-tap gesture attached before a single tap delays every single click by the double-click
  interval. `.textSelection(.enabled)` on a label lets a click take focus from the field.
- 2026-11-21: "every control works with the keyboard" in a panel that keeps focus in one field means every
  other control needs a key equivalent (e.g. ⌘1–7 for chips), or a recorded deviation.
- 2026-11-21 (PR 3 setup): with macOS's default "Keyboard navigation" off, Tab moves only between text fields
  and lists. SwiftUI `Button`s (also with a custom style), checkboxes and selectable cards are not in the Tab
  loop then, so `onKeyPress` on them never fires. Give the screen a `.defaultAction` (Return) and a
  `.cancelAction` (Esc) so it works without Tab, and check both settings of "Keyboard navigation" on a Mac.
- 2026-11-21 (PR 3 review fixes): a SwiftUI `Group` passes its modifiers to each child. `onChange` on a `Group`
  whose `if` is false has no child and never fires: put it on a real container (`VStack`).
