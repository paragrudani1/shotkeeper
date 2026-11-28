# More capture types: screen recordings and clipboard screenshots (research, 2026-11-28)

For the feature Parag approved on 2026-11-28: "More capture types: screen recordings, and screenshots copied to the
clipboard instead of saved to a file." Every URL below was read on **2026-11-28** unless a line says otherwise.

Apple's developer documentation pages render with JavaScript. They were read through the JSON that backs each page:
`https://developer.apple.com/tutorials/data/documentation/<path>.json` is the same content as
`https://developer.apple.com/documentation/<path>`. The page URL is cited below. Availability ("macOS 15.4+") comes
from that JSON's `platforms` field.

Labels used: **Apple doc** = Apple developer docs or support pages. **Man page** = the `screencapture(1)` page that
ships with macOS. **Not documented** = searched and not found in a primary source; needs a test on a real Mac.

---

## 1. Screen recordings

### 1.1 How macOS names and saves them

| Fact | Source |
|---|---|
| ⇧⌘5 opens the Screenshot toolbar. It can record the whole screen, a selected area, or (macOS Tahoe 26 or later) one window. Stop with the menu-bar Stop button or ⌘⌃Esc. QuickTime Player's File > New Screen Recording (⌃⌘N) may open the same toolbar. | Apple doc: https://support.apple.com/en-us/102618 ("How to record the screen on Mac") |
| "When saving your recording automatically, your Mac uses the name "Screen Recording [date] at [time].mov"." | same page |
| "By default, recordings are saved to your desktop." Options > "Save to" changes it: "To change where the recording will be saved after you stop recording, choose a different "Save to" location." | same page |
| SDR records "using the H.264 video format", HDR "using the HEVC video format" (choice offered on supported Macs with macOS Tahoe 26 or later). System audio needs macOS 27 or later. | same page |
| "Screenshots are saved as .png files and screen recordings are saved as .mov files. Filenames begin with 'Screenshot' or 'Screen Recording' and include the date and time." One "Save to" setting covers screenshots and recordings. | Apple doc: https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac (Mac User Guide, macOS 27) |
| Floating thumbnail: it "floats in the bottom-right corner of the screen for a few seconds … before it's saved to the location you specified". "Swipe right to immediately save the file". Clicking it lets you "trim the recording". | same page |
| `screencapture -v` "Capture video recording of the screen"; `-V <seconds>` records for that long; `-c` "Force screen capture to go to the clipboard"; `-i`: "The control key will cause the screenshot to go to the clipboard." `-t <format>` covers images only ("default is png"). The page says the tool "is not very well documented to date". | Man page, read from the Xcode man-page mirror https://keith.github.io/xcode-man-pages/screencapture.1.html |

**What the docs say about when the file appears:** the Mac User Guide says the file is saved *after* the thumbnail
goes away (a few seconds after Stop, at once on a swipe, or later if the user opens the trim window). It does not say
how the file is written.

**Not documented (test on a real Mac before writing the spec):**
- Whether the `.mov` is written in place while recording, or written under a hidden or temporary name and renamed
  at the end. The code assumes screenshots arrive as a hidden temp file that is renamed
  (`App/Shotkeeper/Platform/FolderWatcher.swift`, `Sources/ShotkeeperCore/Files/ScreenshotDetector.swift`), but that
  assumption has no source cited.
- Whether `defaults write com.apple.screencapture name <prefix>` also renames recordings. Apple documents neither
  the `location` nor the `name` key; both come from community use, and only the "Save to" UI is documented.
- The localized "Screen Recording" prefixes. `ScreenshotDetector.defaultPrefixes` lists only screenshot words.
- What happens to the file after the user trims it in the thumbnail editor (same file, or a new write).

**How to tell a recording is finished (design proposal, built from the docs above):**
1. The name is final: not hidden, ends in `.mov`, prefix matches.
2. The size is unchanged across the existing `FolderWatcher` debounce.
3. AVFoundation opens it: `try await asset.load(.isPlayable, .duration)` succeeds and the duration is above zero.
   `load(_:isolation:)` is macOS 12+ (https://developer.apple.com/documentation/avfoundation/avasynchronouskeyvalueloading/load(_:isolation:)).
   The synchronous `AVAsset.duration` and `isPlayable` are deprecated since macOS 13
   (https://developer.apple.com/documentation/avfoundation/avasset/duration,
   https://developer.apple.com/documentation/avfoundation/avasset/isplayable).
   If an unfinished file is ever visible, a QuickTime file without its index usually fails to open. That failure is
   expected behaviour, not documented, so test it.

### 1.2 Pulling frames from a recording (AVFoundation, macOS 14+)

Sources: https://developer.apple.com/documentation/avfoundation/avassetimagegenerator and the member pages linked
from it.

- `AVAssetImageGenerator(asset:)` "generates images from a video asset" (macOS 10.7+).
- Async API (macOS 13+, so fine for the 14+ target):
  - `func image(at time: CMTime) async throws -> (image: CGImage, actualTime: CMTime)`
    (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/image(at:))
  - `func images(for times: [CMTime]) -> AVAssetImageGenerator.Images`, "An asynchronous sequence of images"
    (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/images(for:))
- `copyCGImage(at:actualTime:)` is synchronous and deprecated since macOS 15
  (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/copycgimage(at:actualtime:)). Don't use it.
- `maximumSize`: "The default value is zero, which generates images at the asset's unscaled dimensions. Setting a size
  scales images to fit their defined bounding boxes." (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/maximumsize)
  Setting it to the existing `maxImageLongSide` (1280) means frames need no second downscale.
- `requestedTimeToleranceBefore` / `After` default to `positiveInfinity`. Set both to `zero` "to request
  frame-accurate image generation; this may incur additional decoding delay."
  (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/requestedtimetolerancebefore)
  For a screen recording, nearest-keyframe frames (the default) are probably good enough and decode faster.
- `appliesPreferredTrackTransform` defaults to `false` (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/appliespreferredtracktransform).
  Screen recordings are not rotated, but set it to `true` for safety.
- `dynamicRangePolicy` (macOS 15+) defaults to `forceSDR`
  (https://developer.apple.com/documentation/avfoundation/avassetimagegenerator/dynamicrangepolicy-swift.property).
  On macOS 15+, HDR (HEVC) recordings therefore come out as SDR frames by default, which is what the PNG/JPEG upload
  path needs. The property does not exist on macOS 14, and the docs don't say what macOS 14 does with HDR frames.
- All of this is AVFoundation, which is not in Foundation. Under the AGENTS.md rule it stays in `App/` behind a seam
  (like `ImageIODownscaler`). Core can own the pure parts: which times to sample, and how many frames go to which
  backend.

### 1.3 Can the models take several images, or video, in one request?

| Backend | Several images | Video | Source |
|---|---|---|---|
| **Clairic** | **Yes, up to 4.** "Each request accepts up to four images (4 MiB each, 8 MiB combined)." Schema: `images` `maxItems: 4`, body ≤ 16 MiB. | **No.** No video input in the schema; only `images` (PNG/JPEG/WebP) and `documents` (PDF). | https://developers.cloudflare.com/workers-ai/models/clairic/ (live page re-read 2026-11-28; apart from formatting it matches `clairic/model-page-2026-11-21.md`) |
| **Inkling 2 Mini** (model card) | Card: "Image: Any pixel-based image input. For optimal performance, each image dimension should be between 40px to 4096px." The card doesn't say a count. The chat template turns *each* `image` / `input_image` / `image_url` part of a user message into its own image token, so several images per message are accepted. | **No.** Card: "accepts text and image inputs". The chat template raises "Unsupported content part type" for anything else ("video" is not handled). Video was used in training only. | https://huggingface.co/thinkingmachines/Inkling-2-Mini (README and `chat_template.jinja`, repo sha `c9d028302cd0f035fdf8e7e91f089a4ce94d2195`, last modified 2026-11-24) |
| **Inkling 2 Mini via OpenRouter** | Docs: "multiple images can be sent in separate content array entries. The number of images you can send in a single request varies per provider and per model." No limit is published for this model. | **No.** `input_modalities: ["text","image"]`. OpenRouter's video input (`input_video` / `video_url`, formats `video/mp4`, `video/mpeg`, `video/mov`, `video/webm`) works "Only [with] models with video processing capabilities". | https://openrouter.ai/docs/guides/overview/multimodal/image-understanding.md, https://openrouter.ai/docs/guides/overview/multimodal/videos.md, `GET https://openrouter.ai/api/v1/models` |
| **Local mlx_lm.server** | The same template applies, and `image_url` parts are accepted (`model-backends.md`). Not checked for more than one image. | No | `docs/research/model-backends.md` |

So: **no backend Shotkeeper uses accepts video.** Recordings have to be turned into still frames on the Mac.

**Cost (worked from the measured Clairic formula in `docs/wiki/clairic-field-schema.md`):** live,
`input_tokens = schema_tokens + k × image_tokens`, with k = 7 for the current scalar schema, and every pass re-bills
all the images. A 1280×800 frame costs 1,000 image tokens.
- One screenshot today: 1,242 + 7 × 1,000 = 8,242 tokens → $0.00082 promo / $0.00198 standard.
- A recording sent as **4 frames at 1280×800**: 1,242 + 7 × 4,000 = 29,242 tokens → **$0.0029 promo / $0.0070
  standard (about 3.5× a screenshot)**. Cost grows linearly with frame count, up to the cap of 4.
- A recording sent as **one 2×2 contact sheet at 1280×800** (four frames of 640×400 tiled into one image) costs
  the same as one screenshot. The catch: each frame has half the resolution, and small text was the reason
  `maxImageLongSide` stayed 1280.
- The promo price ends **2026-12-01** (the live page still says "$0.10 per M input tokens until December 1, 2026"),
  so the standard figures are the ones that apply when this ships.
- OpenRouter: how many prompt tokens one image costs is still undocumented (`openrouter.md`). Cost again grows with
  the number of images, but the factor needs a live call. Also, the endpoints list **has changed since
  2026-11-22**: `GET /api/v1/models/thinkingmachines/inkling-2-mini/endpoints` now lists six endpoints (Darkbloom,
  PrimeIntellect flex/fp4/fast, DeepInfra, io.net), and the model-level price is now $0.06/M input, $0.24/M output.
  This doesn't affect capture types, but `openrouter.md`, the `provider.only` pin and the ZDR checks are out of date.

---

## 2. Clipboard screenshots (⌃⇧⌘3 / ⌃⇧⌘4)

### 2.1 What macOS does

- "To send a screenshot to the clipboard, you can press Control in addition to the other keys", for example
  Control-Shift-Command-3. Another way: "Control-click the screenshot thumbnail … then choose Save to Clipboard".
  (Apple doc: https://support.apple.com/en-us/102646, "Take a screenshot on Mac", as quoted in Apple's search
  snippet; the Mac User Guide below says the same.)
- Mac User Guide: "To copy a screenshot so you can paste it somewhere … press and hold the Control key while you
  press the other keys." (https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac)
- No file is written, so the folder watcher never sees it.

**Pasteboard types: not documented.** Apple doesn't say which types `screencapture` writes to the general pasteboard
(PNG? TIFF? both?). AppKit defines `NSPasteboard.PasteboardType.png` ("PNG image data") and `.tiff` ("Tag Image File
Format (TIFF) data") (https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype). To find out, on
a real Mac: take ⌃⇧⌘4, then print `NSPasteboard.general.types` and the per-item types in a test build.

**Source marker: none documented.** Apple publishes no "this came from screencapture" type or flag. With nothing
from Apple, the possible signals are all heuristics:
- image types only, with no `.fileURL` (a copied file from Finder carries one);
- no text or HTML types (browsers and Preview usually add them when copying an image);
- arrival time close to a ⌃⇧⌘3/4 keypress (would need a key-event tap, which means Input Monitoring permission; too
  heavy).

None of these is reliable, and an image copied from another app can look the same. Check on a real Mac whether
screencapture adds any private type (e.g. a `com.apple.*` type) that could serve as a marker. Relying on an
undocumented type would go against the spirit of the "no guessing schemas" rule.

### 2.2 Watching the pasteboard

- **There is no change notification.** The NSPasteboard topic list
  (https://developer.apple.com/documentation/appkit/nspasteboard) has none. The only signal is `changeCount`: "increments
  each time the pasteboard ownership changes" (https://developer.apple.com/documentation/appkit/nspasteboard/changecount).
- Apple DTS (Quinn "The Eskimo!", Sep 2023): "Reading the pasteboard is easy; the hard part is knowing *when* to read
  it. I'm not sure what best practice is here, but I think that most folks just poll the `changeCount` property."
  (https://developer.apple.com/forums/thread/737659)
- So the design is a timer that polls `changeCount` (e.g. every 0.5–1 s on the main run loop) and does nothing until
  the count changes.

### 2.3 The pasteboard privacy prompt

**What Apple documents:**
- AppKit updates, April 2025: "Prepare your app for an upcoming feature in macOS that alerts a person using a device
  when your app programmatically reads the general pasteboard. The system shows the alert only if the pasteboard
  access wasn't a result of someone's input on a UI element that the system considers paste-related. … New `detect`
  methods in NSPasteboard and NSPasteboardItem make it possible for an app to examine the kinds of data on the
  pasteboard without actually reading them and showing the alert. NSPasteboard also adds an accessBehavior property…"
  Test switch: `defaults write <bundle_id> EnablePasteboardPrivacyDeveloperPreview -bool yes`.
  (https://developer.apple.com/documentation/updates/appkit)
- macOS 27.2 release notes, AppKit > Deprecations: "The `EnablePasteboardPrivacyDeveloperPreview` user default has
  been removed. (186955507)" (https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes)
- `NSPasteboard.accessBehavior` (macOS 15.4+): "The current pasteboard access behavior. The user can customize this
  behavior per-app in System Settings for any app that has triggered a pasteboard access alert in the past."
  (https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-86972)
- `NSPasteboard.AccessBehavior` cases (macOS 15.4+), quoted from
  https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum:
  - `.default`: "The default behavior for the General pasteboard is to ask upon programmatic access. All other
    pasteboards default to always allow access. If an app has never triggered a pasteboard access alert, its General
    pasteboard will report `.default` behavior. Such an app is not shown in the corresponding System Settings pane.
    Once programmatic pasteboard access triggers the first pasteboard access alert, the state automatically changes
    to `.ask`. At this point the app starts being shown in System Settings, where the user can toggle the behavior
    between `.ask`, `.alwaysAllow`, and `.alwaysDeny`."
  - `.ask`: "The system will notify the user and ask for permission before granting pasteboard access. However,
    access that is both user originated and paste related will always be allowed, and will not result in a
    notification."
  - `.alwaysAllow`: "The system will automatically allow all pasteboard access, without notifying the user."
  - `.alwaysDeny`: "The system will automatically deny all pasteboard access, without notifying the user." (Same
    exception for user-originated paste.)
- Detect methods that don't notify the user (all macOS 15.4+):
  - `detectedPatterns(for:)`: "Determines whether the first pasteboard item matches the specified patterns, without
    notifying the person using the app." (https://developer.apple.com/documentation/appkit/nspasteboard/detectedpatterns(for:))
    The patterns are text-only: email addresses, links, probable web search/URL, phone numbers, postal addresses,
    calendar events, money amounts, number, flight numbers, shipment tracking numbers
    (https://developer.apple.com/documentation/appkit/nspasteboard/detectedvalues). **Nothing for images.**
  - `detectedMetadata(for:)`: "only gives access to limited types of metadata and doesn't allow the app to access the
    contents. As a result, the system doesn't notify the person using the app"
    (https://developer.apple.com/documentation/appkit/nspasteboard/detectedmetadata(for:)). The only metadata is
    `contentType`, "The content type of a file … when the pasteboard contains a file URL"
    (https://developer.apple.com/documentation/appkit/nspasteboard/detectedmetadata). **That doesn't help for raw
    image data either.**
  - `NSPasteboardItem` has the same `detectedPatterns` / `detectedMetadata`, plus `detectedValues(for:)`, which
    "read[s] the contents if it finds a match" (https://developer.apple.com/documentation/appkit/nspasteboarditem).

**Not documented for macOS:**
- Whether reading `changeCount`, `types` or `pasteboardItems[i].types` triggers the alert. On iOS an Apple engineer
  said type checks are metadata and don't: "If it accesses UIPasteboard *metadata* however, it will not trigger the
  notification. Metadata access includes item count and individual item type." (Jun 2020,
  https://developer.apple.com/forums/thread/649996). The macOS docs only say "the kinds of data" can be examined
  with the detect methods. Whether `types` counts the same way on macOS is unverified. `changeCount` isn't covered
  on either OS.
- **Which macOS turns the alert on for everyone.** `accessBehavior` and the detect methods shipped in 15.4. The
  27.2 notes remove the developer-preview switch, but no release note fetched (15.4, 15.5, 26, 26.1, 26.2, 26.4,
  27, 27.2) says "the alert is now on by default". Treat it as **on from macOS 27.2** (the switch is gone and the
  `.default` text says "ask upon programmatic access"), and confirm on a 27.2 Mac.
- The exact alert wording and buttons. A developer who tested the preview (secondary source, May 2025) shows
  "<App> is trying to access the pasteboard", says the alert gives no reason, and says it has no "always allow"
  button (https://lapcatsoftware.com/articles/2025/5/3.html). Apple's docs say "always allow" can only be set
  later in System Settings. The Mac User Guide's Privacy & Security page lists no pasteboard entry for macOS 26 or 27
  (https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac, as seen in
  search snippets).
- Whether an app can explain itself in the alert (an Info.plist usage string). None is documented.

**What this means for the design:**
- Saving a clipboard screenshot means reading its image data in the background, which is not user-originated and
  not paste-related. On macOS 27.2+ (or wherever the alert is on), **every capture will show the alert** until the
  user sets Shotkeeper to "Always Allow" in System Settings. With `.alwaysDeny`, the reads fail silently.
- Read `accessBehavior` before reading data. On `.alwaysDeny`, stop and show the user how to change it. On
  `.default` or `.ask`, warn before the first read. Seeing `.default` means the alert has not been shown yet, not
  that reads are free.
- Use only `changeCount` (and `types`, if a Mac test shows it doesn't alert) to decide *whether* to read. Read data
  only when the change looks like an image with no file URL.
- macOS 14.0–15.3 has no `accessBehavior` at all (it needs 15.4), and no alert either. Gate it with
  `if #available(macOS 15.4, *)`.

### 2.4 Saving a copied image to disk

Facts that constrain this:
- The project rule "Never delete or overwrite a user file. Moves/renames must fail rather than replace" (AGENTS.md).
- Foundation `Data.WritingOptions.withoutOverwriting`: "attempts to write data to a file and fails with an error if
  the destination file already exists. You can't combine this constant with atomic because atomic allows the system
  to overwrite the original file." (https://developer.apple.com/documentation/foundation/nsdata/writingoptions/withoutoverwriting)
  Core already has `NoReplaceRename` (renamex_np `RENAME_EXCL` / `renameat2 RENAME_NOREPLACE`) for renames, and
  "Title 2.png" for clashes.
- macOS has no file name for a clipboard capture, because it never writes one.

Options the spec has to pick between:
- **Where:** (a) the watched screenshot folder, so the existing pipeline picks the file up; (b) a Shotkeeper-owned
  folder, e.g. `~/Library/Application Support/Shotkeeper/Clipboard/` or `~/Pictures/Shotkeeper/`; (c) only the
  organized folder. With (a), if the name matches `ScreenshotDetector`, the watcher queues the file a second time
  (dedupe needed). With (b), the files are app data, and that changes whether "undo" or "delete" may touch them.
- **Name:** imitate macOS ("Screenshot 2026-11-28 at 10.22.11.png", which also gives `captureDate(fromFilename:)` the
  real capture time for the consent check), or use a distinct prefix such as "Clipboard Screenshot …" so the user
  can tell what the app created. Either way, write with `withoutOverwriting` and retry with " 2" on `EEXIST`.
- **Format:** write the pasteboard's PNG bytes as-is when present. TIFF would need conversion through ImageIO (App
  side), and conversion is lossy only if done to JPEG.
- **Pasteboard:** leave it unchanged. Writing back to it (e.g. to add the file URL) changes `changeCount`, takes
  ownership, and could replace what the user meant to paste.
- **Index-only option:** analyse and index without keeping a file. But then search results have nothing to open,
  and the index assumes a file path.
- **Privacy/consent:** a clipboard image may be something the user copied from anywhere, not a screenshot (§2.1).
  Sending it to a cloud backend is a new kind of upload, and `UploadConsent` may need to treat it separately.

---

## Sources (all read 2026-11-28)

Apple:
- https://support.apple.com/en-us/102618 (record the screen)
- https://support.apple.com/en-us/102646 (take a screenshot; via Apple search snippet)
- https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac (Mac User Guide, macOS 27)
- https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac (search snippets only)
- https://developer.apple.com/documentation/updates/appkit (April 2025: macOS pasteboard privacy)
- https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes
- https://developer.apple.com/documentation/appkit/nspasteboard, `/changecount`, `/types`, `/pasteboarditems`,
  `/accessbehavior-86972`, `/accessbehavior-swift.enum`, `/detectedpatterns(for:)`, `/detectedmetadata(for:)`,
  `/detectedmetadata`, `/detectedvalues`, `/pasteboardtype`; https://developer.apple.com/documentation/appkit/nspasteboarditem
- https://developer.apple.com/documentation/avfoundation/avassetimagegenerator and `/image(at:)`, `/images(for:)`,
  `/copycgimage(at:actualtime:)`, `/maximumsize`, `/requestedtimetolerancebefore`, `/appliespreferredtracktransform`,
  `/dynamicrangepolicy-swift.property`
- https://developer.apple.com/documentation/avfoundation/avasynchronouskeyvalueloading/load(_:isolation:),
  https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously,
  https://developer.apple.com/documentation/avfoundation/avasset/duration, `/isplayable`
- https://developer.apple.com/documentation/foundation/nsdata/writingoptions/withoutoverwriting
- https://developer.apple.com/forums/thread/737659 (Apple DTS, changeCount polling)
- https://developer.apple.com/forums/thread/649996 (Apple engineer, iOS metadata vs data)
- `screencapture(1)` via https://keith.github.io/xcode-man-pages/screencapture.1.html (mirror of the man page in Xcode/macOS)

Model providers:
- https://developers.cloudflare.com/workers-ai/models/clairic/ (index.md form)
- https://huggingface.co/thinkingmachines/Inkling-2-Mini (README.md, chat_template.jinja, processor_config.json)
- https://openrouter.ai/docs/guides/overview/multimodal/image-understanding.md
- https://openrouter.ai/docs/guides/overview/multimodal/videos.md
- https://openrouter.ai/api/v1/models, https://openrouter.ai/api/v1/models/thinkingmachines/inkling-2-mini/endpoints

Secondary (context only, not relied on for facts):
- https://lapcatsoftware.com/articles/2025/5/3.html (developer test of the pasteboard alert, May 2025)
