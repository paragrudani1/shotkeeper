# Spotlight, Shortcuts (App Intents) and on-device OCR: research notes (gathered 2026-11-28)

These notes are for the specs approved 2026-11-28: copy the text in a screenshot from a search result, "Find screenshot of…" as
a Shortcuts action, and indexed screenshots in system search. Every fact below was read on **2026-11-28** from an Apple
primary source. Apple doc pages were read through their JSON form (`https://developer.apple.com/tutorials/data/<path>.json`),
which holds the same text as the HTML page at `https://developer.apple.com/<path>`. WWDC facts come from the transcript on
the session page.

Labels used below:
- **silent**: no Apple source says this either way.
- **inferred**: a conclusion drawn from the cited facts, not stated by Apple.
- **observed**: seen in this repository.

App facts (observed in `App/project.yml` and `App/Shotkeeper/Platform/XattrMetadataWriter.swift`, 2026-11-28):
- Deployment target macOS 14.0, Swift 6.
- `LSUIElement: true`, `ENABLE_APP_SANDBOX: NO`, `ENABLE_HARDENED_RUNTIME: NO`.
- `CODE_SIGN_IDENTITY: "-"` (ad hoc), no team. CI also passes `CODE_SIGNING_ALLOWED=NO`.
- No app extensions.
- The app already writes `com.apple.metadata:_kMDItemUserTags` and `com.apple.metadata:kMDItemFinderComment` as
  extended attributes.

## Sources

App Intents
- [AI1] App Intents framework: https://developer.apple.com/documentation/appintents
- [AI2] AppShortcutsProvider: https://developer.apple.com/documentation/appintents/appshortcutsprovider
- [AI3] App Shortcuts (collection): https://developer.apple.com/documentation/appintents/app-shortcuts
- [AI4] AppEntity: https://developer.apple.com/documentation/appintents/appentity
- [AI5] EntityQuery: https://developer.apple.com/documentation/appintents/entityquery
- [AI6] EntityStringQuery: https://developer.apple.com/documentation/appintents/entitystringquery
- [AI7] EntityPropertyQuery: https://developer.apple.com/documentation/appintents/entitypropertyquery
- [AI8] EnumerableEntityQuery: https://developer.apple.com/documentation/appintents/enumerableentityquery
- [AI9] IndexedEntity: https://developer.apple.com/documentation/appintents/indexedentity, and its `attributeSet`
  property: https://developer.apple.com/documentation/appintents/indexedentity/attributeset
- [AI10] Making app entities available in Spotlight:
  https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight
- [AI11] IntentFile: https://developer.apple.com/documentation/appintents/intentfile, and its `init(fileURL:filename:type:)`
- [AI12] FileEntity: https://developer.apple.com/documentation/appintents/fileentity
- [AI13] Adding parameters to an app intent:
  https://developer.apple.com/documentation/appintents/adding-parameters-to-an-app-intent
- [AI14] Creating your first app intent: https://developer.apple.com/documentation/appintents/creating-your-first-app-intent
- [AI15] Configuring the runtime behavior of your app intents:
  https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents
- [AI16] `supportedModes`: https://developer.apple.com/documentation/appintents/appintent/supportedmodes; `openAppWhenRun`:
  https://developer.apple.com/documentation/appintents/appintent/openappwhenrun
- [AI17] Verifying your App Intents implementation:
  https://developer.apple.com/documentation/appintents/verifying-your-app-intents-implementation
- [AI18] IndexedEntityQuery: https://developer.apple.com/documentation/appintents/indexedentityquery
- [AI19] Sample code "Accelerating app interactions with App Intents":
  https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents
- [AI20] IntentResult / ReturnsValue: https://developer.apple.com/documentation/appintents/intentresult,
  https://developer.apple.com/documentation/appintents/returnsvalue
- [W22a] WWDC22 10032 "Dive into App Intents": https://developer.apple.com/videos/play/wwdc2022/10032/
- [W22b] WWDC22 10170 "Implement App Shortcuts with App Intents": https://developer.apple.com/videos/play/wwdc2022/10170/
- [W23] WWDC23 10103 "Explore enhancements to App Intents": https://developer.apple.com/videos/play/wwdc2023/10103/
- [W24a] WWDC24 10134 "What's new in App Intents": https://developer.apple.com/videos/play/wwdc2024/10134/
- [W25a] WWDC25 244 "Get to know App Intents": https://developer.apple.com/videos/play/wwdc2025/244/
- [W25b] WWDC25 260 "Develop for Shortcuts and Spotlight with App Intents":
  https://developer.apple.com/videos/play/wwdc2025/260/
- [W25c] WWDC25 275 "Explore new advances in App Intents": https://developer.apple.com/videos/play/wwdc2025/275/

Core Spotlight and file metadata
- [CS1] Core Spotlight framework: https://developer.apple.com/documentation/corespotlight
- [CS2] CSSearchableIndex: https://developer.apple.com/documentation/corespotlight/cssearchableindex
- [CS3] CSSearchableItem: https://developer.apple.com/documentation/corespotlight/cssearchableitem
- [CS4] Adding your app's content to Spotlight indexes:
  https://developer.apple.com/documentation/corespotlight/adding-your-app-s-content-to-spotlight-indexes
- [CS5] CSSearchableItemAttributeSet: https://developer.apple.com/documentation/corespotlight/cssearchableitemattributeset,
  and its properties `contentURL`, `textContent`, `keywords`, `thumbnailURL`, `thumbnailData`, `contentType`,
  `displayName`, and `init(contentType:)` (each at `.../cssearchableitemattributeset/<name>`)
- [CS6] `expirationDate`: https://developer.apple.com/documentation/corespotlight/cssearchableitem/expirationdate;
  `isUpdate`: https://developer.apple.com/documentation/corespotlight/cssearchableitem/isupdate
- [CS7] Delete APIs: `deleteSearchableItems(withIdentifiers:completionHandler:)`,
  `deleteSearchableItems(withDomainIdentifiers:completionHandler:)`, `deleteAllSearchableItems(completionHandler:)`, and
  `indexSearchableItems(_:completionHandler:)`, all under https://developer.apple.com/documentation/corespotlight/cssearchableindex
- [CS8] `init(name:)` and `default()` on CSSearchableIndex
- [CS9] CSSearchableIndexDelegate: https://developer.apple.com/documentation/corespotlight/cssearchableindexdelegate;
  Regenerating your app's indexes on demand:
  https://developer.apple.com/documentation/corespotlight/regenerating-your-app-s-indexes-on-demand
- [CS10] CSSearchableItemActionType: https://developer.apple.com/documentation/corespotlight/cssearchableitemactiontype;
  CSSearchableItemActivityIdentifier: https://developer.apple.com/documentation/corespotlight/cssearchableitemactivityidentifier
- [CS11] NSApplicationDelegate `application(_:continue:restorationHandler:)`:
  https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:continue:restorationhandler:)
- [CS12] `indexAppEntities(_:priority:)`:
  https://developer.apple.com/documentation/corespotlight/cssearchableindex/indexappentities(_:priority:);
  `associateAppEntity(_:priority:)`:
  https://developer.apple.com/documentation/corespotlight/cssearchableitemattributeset/associateappentity(_:priority:)
- [CS13] CSImportExtension: https://developer.apple.com/documentation/corespotlight/csimportextension
- [MD1] `kMDItemFinderComment`: https://developer.apple.com/documentation/coreservices/kmditemfindercomment;
  `kMDItemTextContent`: https://developer.apple.com/documentation/coreservices/kmditemtextcontent; `kMDItemKeywords`:
  https://developer.apple.com/documentation/coreservices/kmditemkeywords
- [MD2] Archived "File Metadata Attributes Reference", common attributes:
  https://developer.apple.com/library/archive/documentation/CoreServices/Reference/MetadataAttributesRef/Reference/CommonAttrs.html
- [MD3] `URLResourceKey.tagNamesKey`: https://developer.apple.com/documentation/foundation/urlresourcekey/tagnameskey
- [SUP1] Apple Support, "Spotlight on your Mac" (Mac Pro user guide):
  https://support.apple.com/guide/mac-pro/spotlight-apd10f8d1038/mac. This is Apple first-party, but a user guide, not
  developer documentation.
- [SUP2] Apple Support, "Use tags to organize files on Mac":
  https://support.apple.com/guide/mac-help/tag-files-and-folders-mchlp15236/mac

Vision
- [V1] VNRecognizeTextRequest: https://developer.apple.com/documentation/vision/vnrecognizetextrequest, and its properties
  `recognitionLanguages`, `supportedRecognitionLanguages()`, `automaticallyDetectsLanguage`, `usesLanguageCorrection`,
  `customWords`, `minimumTextHeight`; `VNRecognizeTextRequestRevision3`
- [V2] RecognizeTextRequest (Swift API): https://developer.apple.com/documentation/vision/recognizetextrequest, and its
  `recognitionLevel` and `supportedRecognitionLanguages`
- [V3] Recognizing Text in Images: https://developer.apple.com/documentation/vision/recognizing-text-in-images
- [V4] VNRequestTextRecognitionLevel (`.fast`, `.accurate`):
  https://developer.apple.com/documentation/vision/vnrequesttextrecognitionlevel
- [V5] `VNRequest.usesCPUOnly`: https://developer.apple.com/documentation/vision/vnrequest/usescpuonly
- [V6] RecognizeDocumentsRequest: https://developer.apple.com/documentation/vision/recognizedocumentsrequest
- [V7] VisionKit ImageAnalyzer: https://developer.apple.com/documentation/visionkit/imageanalyzer
- [WV19] WWDC19 234 "Text Recognition in Vision Framework": https://developer.apple.com/videos/play/wwdc2019/234/
- [WV21] WWDC21 10041 "Extract document data using Vision": https://developer.apple.com/videos/play/wwdc2021/10041/
- [WV22] WWDC22 10024 "What's new in Vision": https://developer.apple.com/videos/play/wwdc2022/10024/
- [WV24] WWDC24 10163 "Discover Swift enhancements in the Vision framework":
  https://developer.apple.com/videos/play/wwdc2024/10163/
- [WV25] WWDC25 272 "Read documents using the Vision framework": https://developer.apple.com/videos/play/wwdc2025/272/

---

## 1. App Intents (Shortcuts actions, App Shortcuts, entities)

### Availability by macOS version
| API | macOS from | Source |
|---|---|---|
| App Intents framework, `AppIntent`, `AppShortcutsProvider`, `AppShortcut`, `AppEntity`, `EntityQuery`, `EntityStringQuery`, `EntityPropertyQuery`, `IntentFile`, `ReturnsValue` | 13.0 | [AI1] [AI2] [AI4] [AI5] [AI6] [AI7] [AI11] [AI20] |
| `EnumerableEntityQuery` | 14.0 | [AI8] |
| `IndexedEntity`, `IndexedEntity.attributeSet`, `CSSearchableIndex.indexAppEntities`, `associateAppEntity` | **15.0** | [AI9] [CS12] |
| `FileEntity` (entity that *is* a file, ID is `FileEntityIdentifier`) | **15.0** | [AI12] |
| Transferable `AppEntity` (Shortcuts converts the entity to an image, a file or text) | announced with the 2024 OS releases | [W24a]. Apple's docs give no separate availability line for "Transferable on AppEntity" (**silent**). **Inferred:** macOS 15. |
| `supportedModes` / `IntentModes` (replaces `openAppWhenRun`) | 26.0 | [AI16] |
| `openAppWhenRun` | 13.0, deprecated 26.0 | [AI16] |
| Running app actions from Spotlight on Mac | released with the 2025 OS releases (macOS 26) | [W25a] [W25b] |
| `IndexedEntityQuery` (Spotlight asks the app to reindex entities) | 27.0 | [AI18] |

What this means for a macOS 14 deployment target (**inferred**): an action that takes a String and returns screenshot
files works on 14 (`AppIntent` + `ReturnsValue<[IntentFile]>`). `IndexedEntity` and `FileEntity` need
`if #available(macOS 15, *)`. `IndexedEntityQuery` needs macOS 27.

### How Shortcuts finds the intents
- Discovery is static. "During compilation, the compiler generates information that Apple Intelligence, Siri, and other
  system features need to discover and use your intents, entities, and app enum types" [AI1].
- "Xcode will generate a metadata file inside your app or extension bundle during your build process" [W22a]. Another
  tool then generates "a Metadata.appIntents directory in your built product" [W23]. "After your app is installed, the
  system will use this data to understand your app's capabilities without needing to run your app" [W25a].
- App Shortcuts "are available as soon as someone installs your app, and you don't have to register them yourself" [AI3].
  The Apple sample still calls `updateAppShortcutParameters()` at launch to register them [AI19].
- Apple's check: "Build and run your app … Launch the Shortcuts app … Choose Apps … click your app's icon" [AI17].
- Values in intent metadata must be constants, because they are read at build time. For example, "an intent's title must
  be constant" [W25a].
- Where the code lives: "Code in your app bundle can run in either the foreground or background." Code in a framework
  or package needs an `AppIntentsPackage` signpost, or the system "doesn't automatically know about the code" [AI15].
  WWDC22 said "keep your App Intents types directly in the target or extension, not in a framework" [W22a]. Framework
  support came in 2023 [W23]; Swift packages and static libraries in 2025 [W25a]. **Inferred for Shotkeeper:**
  intents and entities belong in the `Shotkeeper` app target. ShotkeeperCore must not import AppIntents anyway, so it
  can keep the pure search logic.
- **Menu-bar / `LSUIElement` apps: silent.** No Apple page says whether an `LSUIElement` app is treated differently by
  Shortcuts discovery or intent execution. **Inferred:** discovery reads the bundle's `Metadata.appintents`, not the
  Dock presence, so it should work. This has to be tested on a real Mac.
- **Ad-hoc signing / unsigned builds: silent for App Intents.** No App Intents page names a signing requirement.
  Separately, Core Spotlight says it is "a programming error" to access a custom index "from an unsigned bundle" [CS2]
  (see §2). An ad-hoc signature is a signature, but Apple does not say whether "signed" there includes ad hoc
  (**silent**). Also note: CI builds with `CODE_SIGNING_ALLOWED=NO` (observed), so the CI artifact may be unsigned
  rather than ad-hoc signed. Check `codesign -dv` on the artifact before testing.
- Spotlight on Mac (macOS 26) shows an app's actions if the parameter summary "contain[s] all required parameters that
  don't have a default value", and if the intent is not hidden (`isDiscoverable` false or "assistant only") [W25b].

### App Shortcuts (Siri phrases) cannot take free text
- "Parameters are not meant for open-ended values. For example, it's not possible to gather an arbitrary string from the
  user in the initial utterance. So, my app couldn't support a phrase like 'Search my diary for X'" [W22b].
- Phrases use the `\(.applicationName)` token [W22b] [AI19]. Apple's guidance is to provide App Shortcuts for "usually
  between two and five intents, and not more than ten" [AI19].
- **Inferred:** "Find screenshot of `<text>`" works as a **Shortcuts action** with a `String` parameter, and in Spotlight
  on macOS 26 through its parameter summary. It cannot be a zero-setup Siri phrase with the search text inside it. An
  App Shortcut could open the search panel, or run the action and then ask for the text.

### Entities and queries
- `AppEntity`: the ID must be "unique and persistant because the system may save it in a shortcut" [AI4]. There is a
  "total size limit of 10 MB, including all child properties", and exceeding it can crash the app [AI4].
- `EntityQuery.entities(for:)` resolves IDs. If an entity "is no longer available, omit it from the returned array" [AI5].
- `EntityStringQuery` "adds … the ability to query instances by `String`" [AI6]. `EntityPropertyQuery` matches property
  comparators and receives a `limit` [AI7]. Either one makes Shortcuts generate a "Find" action [W23]. Use
  `EnumerableEntityQuery` only for short lists; for very large sets, "use EntityPropertyQuery so you can run the search
  on your end" [W23].
- On macOS 26, if entities are `IndexedEntity` and their properties carry `indexingKey`s, "the system [can]
  automatically generate a Find action" [W25b].

### Returning files or images to Shortcuts
- Supported parameter types include `IntentFile` and `URL`, and "App intent results support the same set of types" [AI13].
- `IntentFile(fileURL:filename:type:)` exists from macOS 13 [AI11]. **Inferred:** on macOS 14, return
  `some ReturnsValue<[IntentFile]>`, built from the screenshot URLs, so the next action (Save, Mail, Photos) gets the
  files.
- Transferable entities: "Siri and Shortcuts can convert your AppEntity and pass the new value to other AppIntents", for
  example as an image. The order of representations matters ("from highest fidelity to the lowest"). There are
  limitations, "because Xcode needs to understand your Transferable representation at compile time" [W24a].
- `FileEntity` (macOS 15): "Siri and Shortcuts can facilitate secure access to your file in other apps". Its
  `FileEntityIdentifier` "uses the URL's bookmark data, so if the file is moved or renamed the entity will still be
  valid" [W24a]. That suits Shotkeeper, because it renames and moves files (**inferred**).
- How Shortcuts treats an `IntentFile` that points at a user file in place (copy or reference, and the
  `removedOnCompletion` default) is not described in prose (**silent**; only the property names are listed in [AI11]).

### Running in the background vs bringing the app forward
- Without `supportedModes`, the system "typically" runs the intent in the background [AI15]. `OpenIntent` and
  `ShowInAppSearchResultsIntent` run in the foreground automatically [AI15]. Before macOS 26, use `openAppWhenRun` [AI16].
- Register dependencies early with `AppDependencyManager`, because "the system can run app intents soon after your app
  or app extension launches" [AI14].
- `perform()` runs on an arbitrary queue. UI work needs `@MainActor` [AI19].

---

## 2. Core Spotlight (indexed screenshots in system search)

### Basics
- Framework since macOS 10.13; `CSSearchableIndex` and `CSSearchableItem` since 10.11 [CS1] [CS2] [CS3].
- "The indexes you create using Core Spotlight remain on device … Devices don't share indexed data with Apple, or
  synchronize that data" [CS1].
- "You can index any content your app manages, including files" [CS1]. No Apple page says that an indexed file must be
  owned by the app (**silent**). For a file on disk, Apple says "provide a value for the [contentURL] attribute" [CS3].
- Use a **named** index (`CSSearchableIndex(name:)`) in production. `default()` is "only for prototyping or testing" and
  supports neither batches nor data protection [CS4] [CS8].
- **Signing:** "modify it only from your signed app or app extension. It's a programming error to access a custom index
  from multiple threads simultaneously or from an unsigned bundle" [CS2]. Apple does not say whether an ad-hoc
  signature counts as "signed" (**silent**). This is the biggest unknown for a non-notarized build. It needs a test on a
  real Mac with the actual artifact.
- Serialize all index access ("one thread or task at a time") [CS2]. Attribute sets are not thread-safe either [CS5].

### The attribute set for a screenshot
- `init(contentType: UTType)` (macOS 11+) [CS5].
- Apple's minimum: "provide values for the [title], [displayName], and [contentType] attributes" [CS3].
- `contentURL`: "The file URL of the content to index." It is used to deduplicate against iCloud Drive items with the
  same URL [CS5].
- `textContent` is documented only as "The textual content of the message" [CS5]. `keywords`: "An array of keywords"
  [CS5]. No length limit is documented for either (**silent**).
- `thumbnailURL` must be "a local file" URL [CS5]. `thumbnailData` takes image data [CS5]. Apple gives no size guidance
  beyond a link to an old guide (**silent**).
- `contentDescription` is used in Apple's examples [CS4] [AI10].

### Updating, deleting, expiry and limits
- Add or update: `indexSearchableItems(_:)`. Resubmitting the same `uniqueIdentifier` replaces the item. With
  `isUpdate = true` the item is updated in place ("set an attribute to `nil` to remove its value"), but an item that is
  not in the index yet is ignored [CS6] [CS7].
- Delete by ID, by domain identifier (recursive on dotted prefixes), or all items [CS7]. **Inferred:** use the index's
  row ID as `uniqueIdentifier`, so renames and moves are updates, not new items.
- Expiry: "The system automatically expires items after a period of time." Set `expirationDate` to keep an item longer.
  The default period is not given (**silent**) [CS4] [CS6].
- Batches: client state is limited to "250 bytes" [CS4]. No limit on item count, index size or field length is
  documented (**silent**).
- Reindexing: Apple recommends a CoreSpotlight Delegate app extension, so the system can ask for a rebuild while the app
  is not running [CS4] [CS9]. Without an extension, a delegate in the running app gets the calls [CS9]. Shotkeeper has
  no extensions today (observed). An extension adds a target, and its own signing questions.

### Opening a result
- Classic items: the app gets an `NSUserActivity` with `activityType == CSSearchableItemActionType`. Its `userInfo`
  carries `CSSearchableItemActivityIdentifier` = the item's `uniqueIdentifier` [CS10].
- On AppKit, that arrives in `NSApplicationDelegate.application(_:continue:restorationHandler:)` [CS11]. The text in
  [CS10] is written for iOS ("app delegate", Handoff). What an `LSUIElement` app sees on macOS is **silent**.
- Entity items (macOS 15+): with an `OpenIntent` for the entity, "Spotlight uses the intent to open the app and display
  the chosen landmark" [AI10]. With more than ten results, Spotlight can use a `ShowInAppSearchResultsIntent` "to launch
  your app and display the results in your custom search interface" [AI10]. That would match Shotkeeper's own search
  panel (**inferred**).
- An item indexed both as a `CSSearchableItem` and as an entity becomes two entries. Use `associateAppEntity` to avoid
  that [CS12].
- Whether Spotlight, for a `contentURL` item, offers to open the file itself (Finder default app) instead of the
  indexing app: **silent**.

### Do the Finder tags and comment already make screenshots findable?
- `kMDItemFinderComment` is a Spotlight metadata attribute, "Finder comments for this file" [MD1] [MD2].
  `URLResourceKey.tagNamesKey` is read-write tag names (macOS 10.9+) [MD3]. Finder can search for a tag by name [SUP2].
- The README already states (observed, not re-verified here) that Spotlight indexes the comment xattr while Get Info
  reads `.DS_Store`. Apple does not document that Spotlight imports `com.apple.metadata:*` xattrs (**silent**). The
  `_kMDItemUserTags` key is not in Apple's current or archived attribute reference (**silent**).
- `kMDItemTextContent` comes from "An application's Spotlight importer". Apps "are not able to read the value of this
  attribute directly" [MD1] [MD2]. An app cannot write it for a PNG it does not own the importer for (**inferred**).
- **Plain Spotlight already reads text in images:** "With Live Text, Spotlight can search for text in images (available
  in select languages)" [SUP1]. The guide gives neither a version history nor the languages (**silent**).
- **Inferred:** with the existing tags, comment and Live Text, plain macOS Spotlight already finds many screenshots by
  their words, tags and description, with no Core Spotlight code. What Core Spotlight adds is the model's title and
  description as the displayed result, results grouped under Shotkeeper, and opening into Shotkeeper. Whether the file
  result and a Core Spotlight item for the same file then show up twice is **silent** (`contentURL` dedup is documented
  only for iCloud Drive [CS5]).
- Spotlight File Import extensions (`CSImportExtension`) "don't provide functionality in macOS". Custom file types need
  a Spotlight importer plugin instead [CS1] [CS13]. That does not apply to PNG (**inferred**).

---

## 3. Vision text recognition (on-device OCR)

### APIs and availability
| API | macOS from | Source |
|---|---|---|
| `VNRecognizeTextRequest` | 10.15 | [V1] |
| `supportedRecognitionLanguages()` (instance) | 12.0 | [V1] |
| `automaticallyDetectsLanguage`, `VNRecognizeTextRequestRevision3` | 13.0 | [V1] |
| `RecognizeTextRequest` (Swift, async, struct) | **15.0** | [V2] |
| `RecognizeDocumentsRequest` (paragraphs, tables, lists, data detectors) | 26.0 | [V6] |
| VisionKit `ImageAnalyzer` (Live Text items) | 13.0 | [V7] |

**Inferred:** on macOS 14, use `VNRecognizeTextRequest` (revision 3). `RecognizeTextRequest` needs an `#available(macOS 15)`
branch. Apple gives no reason to prefer it beyond the Swift API style [WV24].

### On-device
- "all of Vision's processing happens on the user's device to enhance performance and user privacy" [V3]. "all of this
  happens on the device" [WV19]. "all vision APIs run entirely on-device" [WV25].
- Compute: `usesCPUOnly` is deprecated in macOS 14 [V5]. "Vision will remove CPU and GPU support for some requests on
  devices with a Neural Engine". Check with `supportedComputeDevices()` [WV24].

### Accuracy levels
- `.fast`: character detection plus "a small machine learning model", "similar to traditional optical character
  recognition". `.accurate`: "a neural network to find text in terms of strings and lines" [V3].
- `VNRecognizeTextRequest` "uses the accurate path by default" [V3].
- Trade-offs [WV19]: fast is "meant for real-time reading" and uses less memory. Accurate handles rotated and stylized
  text better and is "more likely to be used in an asynchronous fashion".
- Revision 3 "is the text recognizer that powers the amazing Live Text feature" [WV22].
- Optional language correction. Turning it off "provides performance benefits but less accurate results" [V1]. Not
  supported for Chinese [V3]. `customWords` only works with language correction on [V1].
- `minimumTextHeight` defaults to 1/32 of the image height. Raising it cuts memory and time but skips smaller text
  [V1]. **Inferred:** small UI text in a tall full-screen screenshot can be under 1/32 of the height, so this default
  matters for screenshots.

### Languages
- Apple publishes no fixed list. Query `supportedRecognitionLanguages()` per level and revision [V3] [WV21].
- Counts: "18 different languages, including Korean, Swedish, and Chinese" [WV24]. `RecognizeDocumentsRequest`: "26
  languages" [WV25]. Korean and Japanese were added in revision 3 [WV22].
- Default bias is English. `recognitionLanguages` is in priority order. For Chinese, `zh-Hant`/`zh-Hans` must come first,
  and English is the only language that can be paired with Chinese [V3].
- `automaticallyDetectsLanguage` is accurate-mode only, and "can occasionally get this wrong" [WV22].

### Speed per image
- **Silent.** Apple publishes no per-image timing. The WWDC19 demo used "a relatively old MacBook Pro" and said "the
  times that you see are not necessarily representative" [WV19]. This has to be measured on a real Mac with real
  screenshots.

### Is OCR needed for "copy the text"?
- The stored `key_text` is model output capped at 500 characters (README, observed). The model chooses it and may
  paraphrase it (observed in the README's schema description; not verified here).
- Vision returns the recognized strings with per-observation confidence and bounding boxes [V3]. **Inferred:** copying
  the full, verbatim text needs on-device OCR. Vision does it locally with no new data flow (it fits the privacy
  section). It could run at index time (and store the full text in FTS) or lazily when the user copies. The second
  avoids work and storage for screenshots nobody copies from.

---

## Gaps (silent everywhere checked)
- Whether an ad-hoc-signed (or CI-unsigned) build may use a named `CSSearchableIndex` without error, and whether its
  items show in macOS Spotlight.
- Whether Shortcuts lists intents from an `LSUIElement`, ad-hoc-signed, non-notarized app, and whether the app must be in
  `/Applications`.
- How a macOS `LSUIElement` app receives `CSSearchableItemActionType` activities.
- Core Spotlight item, field and thumbnail size limits; the default expiry period.
- Whether a Core Spotlight item and the file's own Spotlight result for the same `contentURL` show as two results.
- Vision timing per screenshot; the language list on macOS 14.
