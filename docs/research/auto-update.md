# Auto-update for an ad-hoc-signed Shotkeeper: research notes (gathered 2026-11-28)

Context: on 2026-11-28 Parag decided on auto-update with **no Apple Developer Program membership** (no Developer ID, no
notarization). The build stays ad-hoc signed (`codesign --force --deep --sign -` in `.github/workflows/ci.yml`, step
"Ad-hoc sign and zip the app"). These notes collect the facts that a spec needs.

Every source was read on 2026-11-28. Labels: facts are quoted or paraphrased from the source. **Source code** means read
in Sparkle's code at tag `2.10.1`. **Inferred** means a conclusion drawn from the sources that none of them states.
**Silent** means no primary source covers it. **Must test** means only a real Mac can answer it.

## Sources

Sparkle (the website text was read from its source repo, `sparkle-project/sparkle-project.github.io`, branch `master`):
- [S1] Documentation home: https://sparkle-project.org/documentation/
- [S2] Publishing an update: https://sparkle-project.org/documentation/publishing/
- [S3] Customizing Sparkle (Info.plist keys): https://sparkle-project.org/documentation/customization/
- [S4] Setting up Sparkle programmatically: https://sparkle-project.org/documentation/programmatic-setup/
- [S5] Sandboxing (code signing and XPC services): https://sparkle-project.org/documentation/sandboxing/
- [S6] Gentle update reminders: https://sparkle-project.org/documentation/gentle-reminders/
- [S7] Security and reliability: https://sparkle-project.org/documentation/security-and-reliability/
- [S8] Sparkle source at tag `2.10.1` (commit `ab7d71291238df6e0492143b120c9b696a35f603`), https://github.com/sparkle-project/Sparkle:
  `Sparkle/SUUpdateValidator.m`, `Autoupdate/SUCodeSigningVerifier.m`, `Autoupdate/SUPlainInstaller.m`,
  `InstallerLauncher/main.m`, `InstallerLauncher/SUInstallerLauncher.m`, `generate_appcast/main.swift`,
  `generate_appcast/Appcast.swift`, `sign_update/main.swift`, `generate_keys/main.swift`, `Package.swift`, `CHANGELOG`.
- [S9] Sparkle releases (GitHub API `repos/sparkle-project/Sparkle/releases`): latest stable **2.10.1** (2026-10-25);
  pre-release 2.11.0-beta.1 (2026-11-17). Both ship `Sparkle-<v>.tar.xz` and `Sparkle-for-Swift-Package-Manager.zip`.

Apple:
- [A1] TN3127 "Inside Code Signing: Requirements": https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- [A2] TN3137 "On Mac keychain APIs and implementations" (revised 2026-09-24): https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains
- [A3] TN2206 "macOS Code Signing In Depth" (archive): https://developer.apple.com/library/archive/technotes/tn2206/_index.html
- [A4] Code Signing Guide, "Code Signing Tasks" (archive, updated 2016-09-13): https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html
- [A5] Developer Forums thread 732869 (Quinn "The Eskimo!", Apple DTS, Jun 2023): https://developer.apple.com/forums/thread/732869
- [A6] Developer Forums thread 694323 (Apple DTS, Nov 2021): https://developer.apple.com/forums/thread/694323
- [A7] Developer Forums thread 740164 (Apple DTS, Oct 2023): https://developer.apple.com/forums/thread/740164
- [A8] Developer Forums thread 98484 (Apple DTS, Mar 2018): https://developer.apple.com/forums/thread/98484
- [A9] Developer Forums thread 98182 (Apple DTS, Mar 2018 and Aug 2022): https://developer.apple.com/forums/thread/98182
- [A10] SMAppService docs: https://developer.apple.com/documentation/servicemanagement/smappservice, `/mainapp`,
  `/register()`, `/status-swift.enum/requiresapproval`
- [A11] WWDC22 session 10096 "What's new in privacy" (transcript): https://developer.apple.com/videos/play/wwdc2022/10096/
- [A12] `NSUpdateSecurityPolicy`: https://developer.apple.com/documentation/bundleresources/information-property-list/nsupdatesecuritypolicy
- [A13] Apple Developer News, "Updates to runtime protection in macOS Sequoia" (2024-08-06): https://developer.apple.com/news/?id=saqachfa
- [A14] Apple Support "Safely open apps on your Mac": https://support.apple.com/en-us/102445
- [A15] Apple Platform Security, "Gatekeeper and runtime protection": https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web
- [A16] Mac User Guide, "Control access to files and folders on Mac": https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac
- [A17] `LSFileQuarantineEnabled`: https://developer.apple.com/documentation/bundleresources/information-property-list/lsfilequarantineenabled

GitHub:
- [G1] "Signing Xcode applications": https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- [G2] "Using secrets in GitHub Actions": https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
- [G3] "Security hardening for GitHub Actions": https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- [G4] "Linking to releases": https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
- [G5] REST "Get the latest release": https://docs.github.com/en/rest/releases/releases#get-the-latest-release
- [G6] "Managing environments for deployment": https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments

Repo facts (this checkout, 2026-11-28):
- [R1] `App/Shotkeeper/Platform/KeychainCredentialStore.swift:75`: queries are `kSecClassGenericPassword` + service +
  account, with no `kSecUseDataProtectionKeychain`. They therefore target the **file-based** keychain [A2].
- [R2] `App/project.yml`: `CODE_SIGN_IDENTITY: "-"`, `ENABLE_HARDENED_RUNTIME: NO`, `ENABLE_APP_SANDBOX: NO`,
  `CURRENT_PROJECT_VERSION: "1"` (fixed), `MARKETING_VERSION: "0.1.0"`, bundle ID `dev.shotkeeper.Shotkeeper`.
- [R3] The default watched folder is `~/Desktop` (`App/Shotkeeper/Platform/ScreenshotLocation.swift:26-30`).

---

## 1. Does Sparkle 2 work for an ad-hoc-signed, un-notarized app?

**Yes, as long as every update is EdDSA-signed and the new app is validly (ad-hoc) signed.** Sparkle never requires a
Developer ID or Team ID for a normal update. A Developer ID is needed only for *key rotation*.

### How Sparkle validates a downloaded app update (source code [S8] `SUUpdateValidator.m`, `SUCodeSigningVerifier.m`)
- The rule, from the comment above `validateUpdateForHost:`: the update "must meet any one of: old and new Ed(DSA)
  public keys are the same and valid (it allows change of Code Signing identity), or old and new Code Signing
  identity are the same and valid". In the code: `if (passedDSACheck || passedCodeSigning) return YES;`.
- `passedDSACheck` verifies the archive against the **old** app's `SUPublicEDKey` ("it's critical to check against the
  old public key, rather than the new key").
- `passedCodeSigning` runs `SecStaticCodeCheckValidityWithErrors(new, …, oldDesignatedRequirement)`, so the new app
  must satisfy the **old app's designated requirement**. An ad-hoc DR is its cdhash ([A1], see section 2). A new
  build never satisfies it, so for ad-hoc builds `passedCodeSigning` is always false and **EdDSA alone carries the
  trust** (inferred from the code plus [A1]).
- Sparkle counts an ad-hoc app as "code signed": `bundleAtURLIsCodeSigned` returns YES whenever
  `SecCodeCopyDesignatedRequirement` succeeds, and ad-hoc code "has a DR" [A1]. Two consequences in the code:
  - If the old app is signed and the update is not, Sparkle rejects the update ("Don't allow removal of code
    signing"). **Every release must be at least ad-hoc signed.**
  - When the EdDSA check passes but the code-signing match fails, the new app's signature must still be *valid*
    (`codeSignatureIsValidAtBundleURL`, no requirement), or the update is rejected ("…the app is also signed with…").
- With no `SUPublicEDKey` in the old app, an ad-hoc app has no valid path: the EdDSA check is skipped and the
  code-signing match fails. **EdDSA is mandatory for us** (inferred from the code).
- The Developer ID fallback (`codeSignatureIsValidAtDownloadURL:andMatchesDeveloperIDTeamFromOldBundleURL:`) only
  runs when EdDSA fails, and it fails immediately when the old app has no Team ID ("Note this will return nil for
  ad-hoc or unsigned binaries").

### Key loss and rotation
- [S1] "Sparkle allows rotating keys by issuing a new update that changes either your Apple code signing certificate
  or your EdDSA keys (but not both)" only "if you both code-sign your application with Apple's Developer ID program
  and include a public EdDSA key". [S1] also says: "If your keys are lost however, you can still sign new updates for
  Developer ID signed applications through key rotation."
- **For Shotkeeper:** losing the EdDSA private key, or leaking it and needing to replace it, means installed copies
  can **never** auto-update again. Users would have to reinstall by hand (inferred from [S1] plus the code above).
  The key needs a backup outside GitHub, because GitHub secrets cannot be read back.
- `generate_keys` stores the private key in the login keychain. `-x file` exports it and `-f file` imports it [S1].
  The exported file is the base64 of a 32-byte ed25519 seed ([S8] `generate_keys/main.swift`, `generatePublicKeyAndSeed`).

### The installer, its launcher and XPC (source code [S8])
- Sparkle's XPC services and helpers check their callers with `SUCodeSigningVerifier validateConnection:`. If the host
  has no Team ID, this returns `SUValidateConnectionStatusSetNoRequirementSuccess` and the connection is accepted
  (`InstallerLauncher/main.m`, `Autoupdate/AgentConnection.m`, `Downloader/main.m`). **The installer machinery runs
  for an ad-hoc host.**
- [S5]: "By default, Sparkle distributions include XPC Services and helper tools that are signed with an ad-hoc
  signature and Hardened Runtime enabled." Non-sandboxed apps do not use the XPC services. They are enabled only by
  `SUEnableInstallerLauncherService` / `SUEnableDownloaderService`, and [S5] says they "may" be removed to save space.
- **`--deep` warning.** [S5]: "please do not add `--deep` … when signing your application. This is a common source of
  Sandboxing errors." `SUInstallerLauncher.m` logs "Please make sure InstallerLauncher is not sandboxed and do not
  sign your app by passing --deep" when it cannot open the host bundle. Our CI signs with `--deep` (with no
  entitlements, so no sandbox entitlement gets spread around), so this is probably harmless here. Still, the release
  job should sign inside-out like [S5]: `Autoupdate`, `Updater.app` and the XPC services first, then
  `Sparkle.framework`, then the app. Use `-s -` and no `--deep`.
- [S1]: with Library Validation (Hardened Runtime) on, "the system may not let your application load Sparkle if you
  attempt to sign to run locally via an ad-hoc signature". **We have `ENABLE_HARDENED_RUNTIME: NO` [R2], so this
  does not apply. Keep it off.**

### Gatekeeper and quarantine on update
- **Sparkle removes quarantine from the new app itself.** `SUPlainInstaller.m`, `_performInitialInstallation…`
  calls `releaseItemFromQuarantineAtRootURL:` on the new bundle ("Release our new app from quarantine"), which walks
  the whole bundle. A failure is only logged. **The user does not have to run `xattr` again for each update**
  (source code). Must test on a real Mac that the relaunched update opens without a Gatekeeper dialog.
- A file is quarantined on creation only if the app that writes it opts in with `LSFileQuarantineEnabled` [A17].
  Shotkeeper does not set it [R2]. Either way Sparkle strips the attribute before installing.
- Gatekeeper's check is a first-open check: it "requests user approval before opening downloaded software for the
  first time" [A15].
- **The first install still needs the manual step.** On macOS 15+ users "will no longer be able to Control-click to
  override Gatekeeper" and must use System Settings > Privacy & Security [A13] ("Open Anyway" [A14]), or
  `xattr -dr com.apple.quarantine` as the README says today. Auto-update does not remove this first-install friction.
- `gktool scan` (Gatekeeper pre-warm, macOS 14.4+) and the atomic swap run only when "the update isn't code signed"
  (no Team ID) or the Team IDs match (`SUPlainInstaller.m`, `_canPerformSafeAtomicSwap`). An ad-hoc update has no
  Team ID, so both run (source code).
- **App Management (macOS 13+) protects notarized apps**: "Gatekeeper will now check the integrity of all notarized
  apps"; modification by another team "will block the modification and notify the user" [A11]; `NSUpdateSecurityPolicy`
  allows other Team IDs [A12]. Shotkeeper is not notarized and has no Team ID, so this should not apply (inferred).
  Apple does not cover non-notarized apps (silent). Must test on a real Mac.

---

## 2. What ad-hoc signing does to identity: Keychain, launch at login, privacy permissions

### How macOS identifies code
- [A1]: "Most code has a designated requirement (DR) which is how the code identifies itself … 'If you see me again,
  here's how you tell it's really me.'" macOS records the DR in its database of apps authorized for the microphone,
  and "each time your app tries to access the microphone, macOS checks that this version of the app satisfies the
  original DR."
- [A1]: "**Ad hoc signed code … has a DR but it's tied to that specific version of the code.** … macOS can't reliably
  track the identity of the code. … If you tweak the code and run it again, macOS repeats that prompt."
- [A1]: a requirement such as `cdhash H"…"` "is satisfied only by code with a specific cdhash value". Check a build with
  `codesign --display -r - Shotkeeper.app`. Every CI build changes the binary, so every release has a new cdhash
  (inferred).

### Keychain
- `SecItem` "defaults to targeting the file-based keychain" unless `kSecUseDataProtectionKeychain` or
  `kSecAttrSynchronizable` is set [A2]. Shotkeeper uses the file-based keychain [R1].
- "The file-based keychain uses your app's designated requirement (DR) to enforce access control" [A5].
- "If you create a keychain item with build N of your app and then access it with build N+1, you'll get an
  authorisation dialog because the system doesn't know that both builds are the same app" (Apple DTS on ad-hoc /
  "Sign to Run Locally", [A6]).
- **For Shotkeeper (inferred from [A1], [A5], [A6], [R1]):** after **every** update, the first read of each stored
  secret raises a keychain dialog: the Clairic token, the OpenRouter key, and the custom-endpoint key if one is set.
  That is up to 3 dialogs per update. The user can allow access, or deny it, and the backend then fails. What
  "Always Allow" does for the next update is silent. Probably nothing, because the next build has a new cdhash.
  Must test.
- Keychain items also carry a `partition_id` that the system sets to the caller's partition ("the keychain API
  hardcodes this to the caller partition_id", [A9]). Changing it later "requires the password of the User" [A9]. In
  [A8] a developer whose app was signed with a non-Apple certificate still got prompts after updates, and the
  partition gained a new cdhash. Apple DTS called its own DR-only explanation possibly "obsolete" ([A8], 2018).
- **The data protection keychain is not available to us.** It "must be authorized by a provisioning profile" [A2];
  "To use the data protection keychain your app must be signed with an App ID. Without that, you get this
  `errSecMissingEntitlement` error" (-34018) [A7]. DTS says a free Personal Team can get an App ID [A7]. That still
  needs an Apple account and a development profile, and was not researched for distribution to other Macs.

### Launch at login (`SMAppService.mainApp`)
- The docs only say that `mainApp` "corresponds to the main application as a login item", that `register()` makes it
  launch "on subsequent logins", and that `.requiresApproval` is also returned "if the user revokes consent" [A10].
- **Silent:** whether a registration survives a code-signature change, and how Background Task Management identifies
  an ad-hoc app. Must test on a real Mac: register on build N, update to N+1 with Sparkle, check
  `SMAppService.mainApp.status` and System Settings > General > Login Items, then log out and back in.

### Privacy permissions (TCC)
- TCC records the DR and checks later versions against it [A1]. With an ad-hoc DR, "macOS repeats that prompt" [A1].
- Shotkeeper watches `~/Desktop` by default [R3]. The Desktop is a Files & Folders location the user controls per app
  in Privacy & Security > Files & Folders [A16]. **Inferred:** after each update macOS may treat Shotkeeper as a new
  app for Desktop access and ask again, or list it twice. Any other TCC grant behaves the same way, for example the
  pasteboard prompt that `docs/wiki/workflow.md` mentions. Must test.

### Would a stable self-signed certificate fix this?
- TN2206 [A3]: "Many parts of macOS do not care about the identity of the signer. (Gatekeeper is a notable exception.)
  They care only whether the program is validly signed and stable. Stability is determined through the designated
  requirement (DR) mechanism, and does not depend on the nature of the certificate authority used. **The keychain
  system and parental controls are examples of such usage. Self-signed identities and homemade certificate
  authorities (CA) work by default for this case.**"
- [A4]: "Do not ship apps signed by self-signed certificates. … the user can only verify that two versions of your
  application came from the same source". Gatekeeper still treats the app as unidentified [A3], so the first-install
  quarantine step stays.
- The DR shape for a non-Apple certificate, as seen in [A8]: `identifier "<bundle id>" and certificate leaf = H"<hash>"`.
  It pins that one certificate, so **never rotate it**. [A3]: "the code signing and validation engines accept
  signatures made with expired certificates", so a long validity period is fine (Developer ID timestamps are the
  exception).
- **Not confirmed by any primary source:** that TCC and the keychain `partition_id` accept a self-signed DR without
  re-prompting. TCC is never named for self-signed DRs, and [A8] shows a non-Apple-CA app still prompting in 2018.
  Must test on a real Mac before relying on it: sign build N and build N+1 with the same certificate, store a
  token, grant Desktop access, update with Sparkle, and count the dialogs.
- **How to create it** (Parag, once, on a Mac):
  1. Keychain Access > Certificate Assistant > Create a Certificate. Choose Identity Type "Self Signed Root" and
     Certificate Type "Code Signing", tick "Let me override defaults", and set a long validity [A4]. TN2206 [A3] also
     describes an `openssl` route.
  2. Export the identity (certificate and private key) as a password-protected `.p12`. Keep an offline backup:
     losing it changes the DR again.
  3. Store the base64 of the `.p12` as a GitHub secret (`base64 -i cert.p12`), plus its password [G1].
- **How CI uses it** [G1], without a provisioning profile: decode into `$RUNNER_TEMP`; `security create-keychain`;
  `set-keychain-settings -lut 21600`; `unlock-keychain`; `security import … -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k`;
  `security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD"`; `security list-keychain -d user -s`.
  Then `codesign -s "<certificate name>" --keychain <path>` inside-out. Add a final `if: always()` step that runs
  `security delete-keychain` [G1].
- Sparkle accepts this setup either way. With the same certificate on both builds, `passedCodeSigning` becomes true as
  well as the EdDSA check (source code). EdDSA stays required, because rotating via code signing needs a Developer ID [S1].

---

## 3. Sparkle integration

- **Version:** 2.10.1, needs macOS 12+ ([S8] `Package.swift` `.macOS(.v12)`; `CHANGELOG` 2.10.0 "Bump minimum
  deployment target to macOS 12.0"). Shotkeeper targets 14.0. SPM URL `https://github.com/sparkle-project/Sparkle`
  [S1]. It is a binary target with a checksum ([S8] `Package.swift`). In XcodeGen it goes in `packages:` with `url` +
  `from`. This is inferred from how XcodeGen declares packages, not tested.
- **Tools in CI:** with SPM, `generate_appcast`, `sign_update` and `generate_keys` are in
  "`../artifacts/sparkle/Sparkle/bin/`" [S1]. With `-derivedDataPath "$DERIVED_DATA"` that is
  `$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/` (inferred). Another option is the `bin/` folder of
  the release tarball [S9].
- **Keys:** run `./bin/generate_keys` once on a Mac. It "will generate a private key and save it in your login
  Keychain" and prints the public key for `SUPublicEDKey` [S1]. Export with `generate_keys -x private-key-file` [S1].
  `--account` names the keychain item [S8]. Put the exported file's contents in a GitHub secret. Never run
  `generate_keys` in CI, where the key would end up in a log or artifact.
- **Signing in CI without a keychain:** `generate_appcast` has `--ed-key-file`: "'-' can be used to echo the EdDSA key
  from a 'secret' environment variable to the standard input stream. For example: `echo "$PRIVATE_KEY_SECRET" |
  ./generate_appcast --ed-key-file -`" ([S8] `generate_appcast/main.swift`). `sign_update` takes the same option as
  `-f`/`--ed-key-file` ([S8] `sign_update/main.swift`). The `-s <key>` argument is deprecated as "insecure" [S7].
- **`generate_appcast`:** "Signatures are automatically generated when you make an appcast using `generate_appcast`
  tool. This is the recommended method" [S2]. It also makes delta updates [S2]. Useful options ([S8]):
  `--download-url-prefix`, `--release-notes-url-prefix`, `--embed-release-notes`, `--link`, `--maximum-versions`
  (default 3 per branch), `--maximum-deltas` (default 5), `-o <appcast path>`. It reads the archives in a folder and
  validates each app's code signature with nested code. When old and new signatures differ it prints
  "Warning: found mismatch code signing identity between …" ([S8] `Appcast.swift`). Ad-hoc releases will always print
  this warning, and it is harmless (inferred).
- **Archive:** `ditto -c -k --sequesterRsrc --keepParent MyApp.app MyApp.zip`. Keep symlinks, or the framework
  signature breaks [S2]. Put nothing but the app in the zip [S1].
- **Appcast item** [S2]: `sparkle:version` (= `CFBundleVersion`), `sparkle:shortVersionString`,
  `sparkle:minimumSystemVersion` (three-part), and an `enclosure` with `url`, `sparkle:edSignature` and `length`.
  `CFBundleVersion` "must increase with each release" [S1]. Sparkle refuses downgrades ([S8] `SUPlainInstaller.m`
  "updates that downgrade version … are not allowed"). **`CURRENT_PROJECT_VERSION` is fixed at "1" today [R2]. The
  release job must set a rising number.**
- **Info.plist keys** [S3]: `SUFeedURL` (HTTPS [S1]), `SUPublicEDKey` (base64 public key, safe to commit).
  - `SUEnableAutomaticChecks`: if unset, Sparkle asks permission on the second launch [S3].
  - `SUScheduledCheckInterval`: default `86400` s, minimum 1 hour [S3].
  - `SUAutomaticallyUpdate`: default NO; silent download and install [S3].
  - `SUVerifyUpdateBeforeExtraction`: checks the EdDSA signature before unzipping, "if … you aren't likely to lose
    access to your private EdDSA key" [S3].
  - `SURequireSignedFeed` (2.9+): requires `SUVerifyUpdateBeforeExtraction` [S1].
- **UI in a menu-bar app** [S4]: create `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
  userDriverDelegate: nil)`. For the menu item, set its `target` to the controller and its action to
  `#selector(SPUStandardUpdaterController.checkForUpdates(_:))`. The controller then enables and disables it from
  `canCheckForUpdates`. In SwiftUI, use a `Button("Check for Updates…", action: updater.checkForUpdates)` disabled by
  `updater.publisher(for: \.canCheckForUpdates)`.
- **Background (Dock-less) apps** [S6]: Sparkle 2.2+ "will not let a scheduled update alert steal focus … with the one
  exception of when your application just launched"; such alerts are "presented behind other apps and windows".
  "Background (dockless) running apps may receive a log warning … At minimum, [`supportsGentleScheduledUpdateReminders`]
  needs to be implemented." [S6] has a worked example for a menu-bar app: a Dock badge plus a notification.
- **Testing a check soon:** `defaults delete <bundle-id> SULastCheckTime` [S1][S6].

---

## 4. Release flow for this repo (proposal built from the facts above)

1. **Trigger:** `on: push: tags: ['v*']` in a separate `release.yml`. Keep `pull_request` out of it. Never use
   `pull_request_target` with a checkout of PR code: such workflows "may have repository write access and access to
   referenced secrets" [G3]. Secrets "are not passed to the runner when a workflow is triggered from a forked
   repository" [G2].
2. **Secrets live in a GitHub environment** (e.g. `release`), limited to `v*` tags, optionally with a required reviewer
   ("These secrets are only available to workflow jobs that use the environment" and only after protection rules pass;
   environments are available for public repos on Free [G6]). Names:
   - `SPARKLE_ED_PRIVATE_KEY`: the `generate_keys -x` file contents.
   - Only if the self-signed route is chosen: `SIGNING_CERT_P12_BASE64`, `SIGNING_CERT_P12_PASSWORD`, and
     `KEYCHAIN_PASSWORD`, which "can be any new random string" [G1].
3. **Permissions:** keep the workflow default `contents: read`. Raise only the release job to `contents: write` [G3].
   Pin third-party actions to a full commit SHA [G3].
4. **Build:** the same steps as `macos-app`, with `MARKETING_VERSION=<tag without v>` and a rising
   `CURRENT_PROJECT_VERSION` (e.g. `github.run_number`, or a number derived from the tag). Sign inside-out without
   `--deep` (section 1). Run `codesign --verify --strict` (no `--deep`).
5. **Archive:** `ditto -c -k --sequesterRsrc --keepParent Shotkeeper.app Shotkeeper-<ver>.zip` [S2].
6. **Appcast:** put the zip in an empty folder. Seed it with the current `appcast.xml` from the latest release, so
   older items are kept; the exact merge behaviour must be checked in a dry run. Then run
   `echo "$SPARKLE_ED_PRIVATE_KEY" | generate_appcast --ed-key-file - --download-url-prefix
   https://github.com/<owner>/shotkeeper/releases/download/v<ver>/ -o appcast.xml <folder>` [S8]. Pass the key
   through an `env:` variable and stdin, never as an argument: "Command-line processes may be visible to other users"
   [G2].
7. **Publish:** `gh release create v<ver> Shotkeeper-<ver>.zip appcast.xml` (not a pre-release).
8. **Feed URL:** `SUFeedURL = https://github.com/<owner>/shotkeeper/releases/latest/download/appcast.xml`.
   - "the suffix is `/releases/latest/download/asset-name.zip`" for "your latest release asset that was manually
     uploaded" [G4].
   - "The latest release is the most recent non-prerelease, non-draft release, sorted by the created_at attribute" [G5].
     So a pre-release never reaches users, which makes pre-releases usable for testing.
   - **Not verified:** that Sparkle follows GitHub's redirect from `github.com` to the asset host. It uses URLSession,
     which follows redirects by default (inferred). Check in the first dry run.
   - Alternative: publish `appcast.xml` to GitHub Pages for a fixed URL that does not depend on the "latest" rule.
9. **Where secrets must never appear:** committed files (only `SUPublicEDKey` is public), workflow logs (no `echo` of
   values, no `set -x` around them), uploaded artifacts and caches (the temp keychain, `.p12` and key file stay in
   `$RUNNER_TEMP` and are deleted in an `if: always()` step [G1]), release assets, and command-line arguments [G2].
   GitHub masks registered secrets, but "Base64 only converts binary to text, and is not a substitute for actual
   encryption" [G2]. Treat the base64 `.p12` as the secret it is.
10. **Back up offline:** the EdDSA private key file and, if used, the `.p12`. Losing the EdDSA key ends auto-update for
    every installed copy (section 1).

---

## 5. Alternatives

Not needed: Sparkle works with ad-hoc builds when updates are EdDSA-signed (section 1). The pain comes from macOS
identity (Keychain, TCC, possibly launch at login), not from Sparkle, and any updater would hit the same thing.
Other updaters were not researched.

---

## Open items that only a real Mac can settle
1. Does the update relaunch without a Gatekeeper dialog (Sparkle strips quarantine)?
2. How many keychain dialogs does an update raise (ad-hoc vs. self-signed)? Does "Always Allow" carry over?
3. Does the Desktop (Files & Folders) grant survive an update (ad-hoc vs. self-signed)?
4. Does `SMAppService.mainApp` stay registered and approved after an update?
5. Does App Management stay out of the way for a non-notarized, Team-ID-less app?
