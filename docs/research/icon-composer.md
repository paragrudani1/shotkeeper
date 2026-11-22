# Icon Composer `.icon` files: research notes (gathered 2026-11-22)

Used by `Sources/ShotkeeperCore/Brand/IconComposerBundle.swift` (generator of `App/Shotkeeper/AppIcon.icon`).
Facts are quoted from Apple unless they are marked "observed" (seen in our CI) or "community" (not Apple).

## Sources
- [A] Apple docs, "Creating your app icon using Icon Composer":
  https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer (read 2026-11-22).
- [B] WWDC25 session 361, "Create icons with Icon Composer": https://developer.apple.com/videos/play/wwdc2025/361/
  (transcript). Related: session 220, "Say hello to the new look of app icons".
- [C] Apple sample code "Landmarks: Building an app with Liquid Glass",
  https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass, download
  `https://docs-assets.developer.apple.com/published/7cb327e44540/LandmarksBuildingAnAppWithLiquidGlass.zip`, file
  `Landmarks/Landmarks/Resources/Landmarks App Icon.icon/` (zip entries dated 2026-10-20). This is the only
  authoritative `icon.json` found: written by Icon Composer, shipped by Apple. Not copied into this repo (Apple
  sample licence); the keys it uses are listed below.
- [D] Xcode 26 release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes
- [E] XcodeGen CHANGELOG 2.45.1: "Added built in `.icon` folder support for IconComposer #1600"
  (https://github.com/yonaskolb/XcodeGen/blob/master/CHANGELOG.md); issue #1556.
- [F] Community reports on the asset-catalog fallback (not Apple): Apple Developer Forums threads 794485 and 787576
  (https://developer.apple.com/forums/thread/794485, /787576), https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/
- [O] Our CI, run 44986298454 (Xcode 26.6, actool 26.6 build 24765, XcodeGen 2.46.0, `macos-latest`), step
  "Compile the Icon Composer icon (actool)".

## Package layout
- A folder named `<Name>.icon` with `icon.json` and an `Assets/` folder holding the layer images [C].
  Apple's docs never describe the internal layout; they call it "a single multilayer file" [A] / "the .icon
  file" [B]. Layout facts come from [C] only.
- Layer image types: "SVG or PNG" [A]; "choose the SVG format whenever possible. For layers that contain unsupported
  SVG features, choose PNG or another raster image format that Icon Composer supports" [A]. Apple does not list the
  unsupported SVG features (silent). Our layers use `path` with `stroke`, `stroke-linecap/linejoin="round"` and
  `fill`; actool 26.6 compiled them as `"AssetType" : "Vector"` with no warning [O].
- Canvas: "1024 x 1024 pixels for iPhone, iPad, and Mac, and 1088 x 1088 pixels for Apple Watch" [A];
  "Don't export the canvas mask because the system applies that automatically" [A]; "we never include the rounded
  rectangle or circle mask in our exports" [B]. So layer SVGs cover the whole 1024 canvas, without a margin.
  The Landmarks layers are `viewBox="0 0 1024 1024"` [C].
- Groups: "organize the layers ... into a maximum of four groups"; "The system renders the layers in the z-plane from
  the bottom to the top as they appear in the sidebar" [A]; "By default, it'll always be one, but you can go all the
  way up to four" [B]. "Give the layers meaningful names that include numbers (increment from back to front)" [A].
  In [C], `groups[0]` holds `landmarks-app-icon-layer-5` and the last group holds `layer-1`, so the array runs
  front to back (the sidebar order, top = front). Apple does not state this for `icon.json` (silent); it is
  inferred from [A] + [C].
- Background: "simple background colors and gradients get added directly in Icon Composer, so don't need to be
  exported" [B]; set it by selecting the canvas (the document) [B]. In [C] it is the document-level
  `"fill" : { "linear-gradient" : [ <color>, <color> ] }`.

## `icon.json` keys (all from [C]; Apple publishes no schema — silent)
- Document: `fill` (`{"solid": <color>}` or `{"linear-gradient": [<color>, <color>]}`), `groups` (array),
  `supported-platforms` (`{"circles": ["watchOS"], "squares": "shared"}` in [C]).
- Group: `layers` (array), `blend-mode` ("normal"), `blur-material` (0.5), `hidden` (bool), `lighting`
  ("individual"; the docs' Mode "Individual"/"Combined" [A]), `shadow` (`{"kind": "neutral", "opacity": 0.5}`),
  `specular` (bool), `translucency` (`{"enabled": bool, "value": 0.5}`).
- Layer: `image-name` (file in `Assets/`), `name`, `fill` ("automatic" or `{"solid"|"linear-gradient": ...}`),
  `fill-specializations` (array of `{"appearance": "dark", "value": ...}` plus a default `{"value": ...}`),
  `glass` (bool), `hidden` (bool), `opacity` (number).
- Color strings: `"<space>:r,g,b,a"` with 5 decimals, spaces seen: `srgb`, `extended-srgb`, `display-p3` [C].
- Formatting written by Icon Composer: 2-space indent, `"key" : value`, keys sorted alphabetically [C].
- Silent (not in [A], [B] or [C]): the accepted values of `supported-platforms` beyond the sample, whether a
  group can be named, the default of every omitted key, a gradient's direction key, specular "Inside/Outside" values
  (the docs list Off/Automatic/Inside/Outside [A], the sample only shows `false`).

## What we generate (`IconComposerBundle`)
- `fill.solid` = `srgb:0.34510,0.33725,0.83922,1.00000` (#5856D6) as the background (no layer), two groups
  (`2-sparkle.svg` in front, `1-corners.svg` behind), each one layer with only `image-name` and `name`; `supported-platforms`
  `{"squares": "shared"}` (no watchOS). Every other setting is omitted so Icon Composer's defaults apply
  ("Icon Composer automatically adds the Liquid Glass material to layers when you import graphics files, and it
  applies other default Liquid Glass settings to groups when you create them" [A]; specular "Automatic by
  default" [A]). The spec's 6% lighter top half is not reproduced: Apple says to remove background gradients from
  the artwork and leave lighting to the material [A].
- Group order: `groups` = [`2-sparkle`, `1-corners`]: front first, as inferred above. For our non-overlapping
  shapes the order has no visible effect; actool names the groups `AppIcon/Group` and `AppIcon/Group 2` [O].

## Appearances
- Icon Composer previews "default, dark, and mono"; "For mono, you can preview clear and tinted variants" [A].
  "six of our new appearances: Default, Dark, Clear light, Clear dark, Tinted light, and Tinted dark" with "the
  artwork producing all the appearances for clear and for tinted" [B]. "Setting at least one element of your icon to
  be white ... make sure it shows up strong" in mono [B] — our corners and sparkle are white.
- The compiled `Assets.car` holds renditions for `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua` and
  `ISAppearanceTintable` [O]. No public API renders a chosen appearance offscreen (silent), so CI cannot show
  dark/clear/tinted; `NSApp.applicationIconImage` looked the same in light and dark [O].

## Xcode, actool and the asset-catalog fallback
- Xcode: add the `.icon` to the project (not into the asset catalog) and set the target's App Icon to its name
  without the extension [A] — `ASSETCATALOG_COMPILER_APPICON_NAME`. XcodeGen 2.45.1+ adds the package as one
  resource [E]; observed as `lastKnownFileType = wrapper.icon`, `AppIcon.icon in Resources` [O].
- **Which icon wins:** "If you add an Icon Composer file to your Xcode project, it replaces any existing icon asset
  catalog that you previously used to represent your app icon. Xcode automatically generates a similar-looking
  version of the Liquid Glass icon for previous releases. If you want your existing icon to appear in previous
  releases, continue to use asset catalogs to represent your app icon." and "The latest version of Xcode uses the
  Icon Composer file instead of an existing `AppIcon` asset catalog in your project." [A]
- Xcode 26 release notes [D]: "Fixed: Icon Composer icons back deploy to older versions of iOS, macOS, and watchOS
  with inconsistent rendering"; "Fixed: Icon Composer icons added to macOS app targets do not display in Finder,
  Spotlight or Dock when deployed to older versions of macOS"; "Some developers may get an incorrect build warning
  from actool: 'Failed to generate flattened icon stack for icon named…' This can be safely ignored."
- Observed [O]: actool on `AppIcon.icon` alone, on `AppIcon.icon` + `Assets.xcassets` (the app target), and on both
  with `--enable-icon-stack-fallback-generation=disabled` produced the same `AppIcon.icns` (42,587 bytes, identical
  PNGs) and `Assets.car` (1,811,368 bytes): the AppIcon appiconset is ignored on every macOS version, and the
  undocumented flag does nothing in actool 26.6. Community reports [F] say the flag kept the appiconset as the
  pre-26 icon up to Xcode 26.0.1 and stopped working in 26.1, which matches.
- Partial Info.plist: `CFBundleIconFile = AppIcon` (the icns, read by macOS before 26) and `CFBundleIconName =
  AppIcon` (the asset in `Assets.car`) [O]. Apple's docs do not say which key each macOS version reads (silent).
- actool command line: Apple does not document actool flags (silent). CI uses the flags Xcode itself passes in the
  build log (`--app-icon AppIcon --target-device mac --minimum-deployment-target 14.0 --platform macosx ...`).
