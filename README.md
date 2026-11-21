<img src="assets/icon.svg" width="64" height="64" alt="">

# Shotkeeper

Shotkeeper is a macOS 14+ menu-bar app. When you take a screenshot, it gives the file a short descriptive name, adds
a description and tags, and indexes it so you can search for it later. It does the same job as the app "Blinky". A
vision model does the analysis. The default is Cloudflare Workers AI's **Clairic**, which runs in your own Cloudflare
account. You can also use **Inkling 2 Mini** on your Mac (Shotkeeper installs and manages `mlx_lm.server` for it), or
any OpenAI-compatible server you run yourself.

Status: version 0.1.0, early. Read [Known limits](#known-limits) before relying on it.

## What it does

- **Watches the screenshot folder.** By default this is the folder macOS saves screenshots to
  (`defaults read com.apple.screencapture location`), or the Desktop if that is not set. You can pick another folder
  in Settings → General. A custom screenshot name prefix (`com.apple.screencapture name`) is recognized too.
- **Renames** each new screenshot to a short title (up to 60 characters from the model, then cleaned up for use as a
  filename). It only renames when the model's title confidence is at least the **Minimum title confidence** setting
  (default 0.50). For Clairic this is the average per-token probability of the title, not the probability of the
  whole title (which shrinks with length). Below that, the original name stays and the index records why. Renames and moves never replace an
  existing file: a name clash becomes "Title 2.png".
- **Finder tags and Spotlight comment:** up to 8 tags, plus the description (up to 240 characters) as the Finder
  comment. Both are written as extended attributes. You can turn this off with "Write Finder tags and comment".
- **Search window.** Press **⌥⌘S** from anywhere, or use the menu's Search… item. It opens a floating, Spotlight-style
  panel backed by a SQLite FTS5 index of the title, description, tags, visible text (`key_text`, up to 500
  characters), source app or site, and content type. With an empty query it shows your recent screenshots. Keys:
  - ↑ / ↓ select a result
  - Return opens it
  - ⌘C copies the image and its file URL
  - ⌘R reveals it in Finder
  - Esc closes the panel
- **Undo.** Every rename or move is written to an undo log (`undo.jsonl`). The menu item **Undo Last Rename** reverses
  the most recent one and updates the index to match.
- **Process Existing Screenshots** (menu item) queues screenshots that are already in the watched folder but are not
  in the index yet.
- **Pause for 10 Minutes** skips screenshots taken in that window: they are never analyzed and never indexed.
  **Pause** without a time limit only holds the queue. Screenshots taken while it is paused are processed after
  **Resume**.
- **Exclusion rules** (Settings → Exclusions): name matches a glob, name contains some text, or file is in a given
  folder. Screenshots that match a rule are never analyzed, renamed or indexed.
- **Organized folder** (optional): turn on "Move into the organized folder" to move each processed screenshot there.
  This is off by default.
- Other settings: requests per minute (default 30), longest image side sent to the model (default 1280 px), launch at
  login, and how long the local model server may sit idle before it stops (default 10 minutes).

App data lives in `~/Library/Application Support/Shotkeeper/`: `settings.json`, `index.sqlite` and `undo.jsonl`.

## Privacy

- **Clairic (cloud):** each screenshot is downscaled on your Mac (longest side 1280 px by default) and sent to
  Workers AI in **your own Cloudflare account**, using your API token. Shotkeeper has no server of its own and sends
  screenshots nowhere else. Cloudflare's model page for Clairic lists the model as "Zero data retention: Yes"
  ([saved copy](docs/research/clairic/model-page-2026-11-21.md), fetched 2026-11-21). That is Cloudflare's own
  statement; Shotkeeper cannot verify it. The setup window explains where screenshots go before you choose Clairic.
  The API token is stored in the macOS Keychain (service `dev.shotkeeper.Shotkeeper`), not in `settings.json`.
- **Local Inkling 2 Mini:** analysis runs in an `mlx_lm.server` process on your Mac that only listens on 127.0.0.1.
  Screenshots never leave the Mac. The internet is used only for the one-time install and model download.
- **Custom endpoint:** screenshots go to the URL you enter. If that server is on another machine, they leave your Mac.
- Screenshots that are excluded, or taken during a 10-minute pause, are not written to the index.

**Which backend to use** (the setup window recommends one based on your Mac's memory, following the rules in
`BackendRecommender`):

| Mac memory | Recommended | Also offered |
|---|---|---|
| under 16 GB | Clairic | custom endpoint |
| 16–23 GB | Clairic | "Use local anyway" with the 2-bit build (lower quality, high memory use), custom endpoint |
| 24–31 GB | Local Inkling 2 Mini, 3-bit | Clairic, 2-bit, custom endpoint |
| 32 GB and up | Local Inkling 2 Mini, 4-bit | Clairic, 3-bit, 2-bit, custom endpoint |

## Setup

On first launch the setup window opens. You can open it again later from Settings → Model → "Run setup again…".

### Clairic

1. Find your Cloudflare **account ID** in the Cloudflare dashboard.
2. Create an **API token** with **Workers AI – Read** and **Workers AI – Edit** permissions. See
   [Create an API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) and the
   [Workers AI REST API guide](https://developers.cloudflare.com/workers-ai/get-started/rest-api/), which is the page
   the app links to.
3. Enter both in the setup window, or later in Settings → Model. **Test connection** sends a generated 640×400 test
   image, never one of your files, and saves nothing until you confirm. The token is saved to the Keychain.

### Local Inkling 2 Mini

Choose the local option in setup and click **Install and download**. Shotkeeper then:

1. Creates a private Python environment under its Application Support folder. It uses `uv` if it finds it in
   Homebrew, `~/.local/bin` or `~/.cargo/bin`; otherwise a Homebrew Python 3.11 or newer. It does not install `uv`
   for you.
2. Installs mlx-lm from **unmerged pull request
   [ml-explore/mlx-lm#2086](https://github.com/ml-explore/mlx-lm/pull/2086)**, pinned to commit `0c4c991`. No released
   mlx-lm version supports Inkling 2 Mini as of 2026-11-21.
3. Downloads the chosen model with `hf download`, pinned to a fixed revision.
4. Starts `mlx_lm.server` on 127.0.0.1 when a screenshot needs it, and stops it after the idle timeout.

The model builds in the catalog (`Sources/ShotkeeperCore/Runtime/ModelCatalog.swift`). Sizes are from the Hugging Face
API on 2026-11-21; GB means 10^9 bytes.

| Build | Download | Offered from | Quality (from the model card) | Status |
|---|---|---|---|---|
| [`mlx-community/Inkling-2-Mini-4bit`](https://huggingface.co/mlx-community/Inkling-2-Mini-4bit) | 17.3 GB | 32 GB Macs | close to the original weights | card says to serve it with `mlx_lm.server` |
| [`VisualInference/Inkling-2-Mini-MLX-3bit`](https://huggingface.co/VisualInference/Inkling-2-Mini-MLX-3bit) | 13.5 GB | 24 GB Macs | +1.4% perplexity; peak memory 12.7–14.1 GiB | **experimental** |
| [`VisualInference/Inkling-2-Mini-MLX-2bit`](https://huggingface.co/VisualInference/Inkling-2-Mini-MLX-2bit) | 10.4 GB | 16 GB Macs (card: "16 GB (tight) or 18 GB") | +10% perplexity, weaker image recognition; peak 9.8–11.2 GiB | **experimental** |

The 2-bit and 3-bit builds are published for **mlx-vlm**, not mlx-lm. Nobody has checked whether the pinned mlx-lm
commit can load them, so the app labels them "Experimental build". If they do not load, the fallback would be
`mlx_vlm.server`, which Shotkeeper does not manage yet. Plan for the download size in free disk space, plus the
Python environment (its size has not been measured).

### Your own endpoint

Choose **Custom endpoint** and enter a base URL (for example `http://127.0.0.1:8080`), a model name, and an optional
API key (stored in the Keychain). Shotkeeper calls `POST <base>/v1/chat/completions` with the image as an `image_url`
part. The request format was researched for `llama-server` and `mlx_lm.server`
([notes](docs/research/openai-compatible-chat.md)). LM Studio and Ollama also offer OpenAI-compatible endpoints, but
Shotkeeper has not been tested against them.

## Install the CI build

CI builds the app on every push. To install it:

1. In the repository's GitHub **Actions** tab, open a green **CI** run and download the `Shotkeeper-unsigned`
   artifact. Artifacts are kept for 14 days.
2. Unzip it: GitHub wraps the artifact in a zip, and inside it is `Shotkeeper-unsigned.zip`, which holds
   `Shotkeeper.app`.
3. Remove the quarantine flag. The app is ad-hoc signed and not notarized, so Gatekeeper blocks it otherwise:
   ```sh
   xattr -dr com.apple.quarantine Shotkeeper.app
   ```
4. Move `Shotkeeper.app` to `/Applications`. **Launch at login** only works from there: `SMAppService` reports
   `notFound` for an app in any other location.
5. Open it. It has no Dock icon; look for its icon in the menu bar.

## Build from source

macOS app (needs Xcode with Swift 6):

```sh
brew install xcodegen
xcodegen generate --spec App/project.yml   # writes App/Shotkeeper.xcodeproj (gitignored)
open App/Shotkeeper.xcodeproj               # build and run the "Shotkeeper" scheme
```

To build from the command line, use the same command as CI:

```sh
xcodebuild build -project App/Shotkeeper.xcodeproj -scheme Shotkeeper -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Core library tests: run `swift test` at the repository root. This works on macOS and on Linux.

On a Linux machine without a host Swift toolchain, run `scripts/test-linux.sh`. It runs `swift test` in a Docker image
based on `swift:6.4.3-noble`, with no network. Use `scripts/test-linux.sh build` to build only.

Live analyzer call from the CLI. The image is sent as-is, without downscaling, so the cost is higher than the app's,
and Clairic rejects images over 4 MiB:

```sh
export CLOUDFLARE_ACCOUNT_ID=... CLOUDFLARE_API_TOKEN=...
swift run shotkeeper-cli analyze screenshot.png                      # Clairic (default)
swift run shotkeeper-cli analyze screenshot.png --backend local \
  --endpoint http://127.0.0.1:8080 --model mlx-community/Inkling-2-Mini-4bit
# Linux, via Docker (network enabled for this call only):
SHOTKEEPER_DOCKER_NETWORK=bridge scripts/test-linux.sh run shotkeeper-cli analyze screenshot.png
```

For a local server that needs a bearer token, set `SHOTKEEPER_LOCAL_API_KEY`.

## Cost (Clairic)

These numbers are **measured** from live calls on 2026-11-21 (three sample screenshots; the raw responses are in
`Tests/ShotkeeperCoreTests/Fixtures/clairic-live-2026-11-21-*.json`). What you are actually billed is reported in
`usage.input_tokens` in each response. Shotkeeper stores that number per screenshot in the index
(`billed_input_tokens`).

How a call is billed (only input tokens are billed; output tokens are free):

- **Image tokens.** Round each side to a multiple of 32, then `(w/32) × (h/32)`. A full-screen 16:10 Retina
  screenshot (2880×1800), downscaled to the default 1280 px long side, becomes 1280×800: **1,000 tokens** (live
  `usage.image_tokens`; the model page's 2 extra marker tokens do not show up in `usage`).
- **One image copy per field.** Every response so far satisfies
  `input_tokens = schema_tokens + 7 × image_tokens` exactly: each of Shotkeeper's 7 fields re-bills the image once.
  The docs say non-text fields share one pass; live, they did not, and a `list` field cost one copy per item. The
  first schema (tags as an 8-item list) billed the image 16 times: 19,448 tokens for one screenshot. Tags and source
  are now plain text fields. `usage.passes` counts decode steps (33 to 125 here), not billed image copies.
- **Schema tokens:** **1,242** per call for the current fields. No `state` text is sent.

| Sample (long side 1280) | Image tokens | Input tokens | Latency |
|---|---|---|---|
| Tweet, 1280×800 | 1,000 | 8,242 | 2.7 s |
| Code editor, 1280×831 | 1,040 | 8,522 | 5.6 s |
| Receipt (portrait), 591×1280 | 720 | 6,282 | 2.3 s |

A full-screen screenshot costs 1,242 + 7 × 1,000 = **8,242 input tokens**. For 1,000 of them, 8.24 M tokens:

| Price | Per 1,000 full-screen screenshots |
|---|---|
| Promo, $0.10 / M input tokens (until 2026-12-01) | 8.242 × $0.10 ≈ **$0.82** |
| Standard, $0.24 / M input tokens | 8.242 × $0.24 ≈ **$1.98** |

The earlier estimate from the docs ($0.46 promo / $1.11 standard) assumed 4 image copies per call and was about
1.8× too low. Screenshots of part of the screen that are smaller than 1280 px cost less, and retries count toward
`usage.input_tokens`. Setting the longest side to 1024 px cuts a full-screen screenshot to 1,242 + 7 × 640 = 5,722
tokens ($0.57 promo / $1.37 standard per 1,000), but small text gets harder to read. Each field costs about one image
copy, so dropping a field (for example `description`) would save roughly an eighth.

## Known limits

- **Clairic has been verified live on only three synthetic screenshots** (2026-11-21: a tweet, a code editor and a
  receipt). The request was accepted and parsed, and titles came back in sentence case. Small samples: tags can be
  sparse (one tag for the code screenshot), and US-style dates like `11/08/2026` came back invalid
  (`invalid_printed_temporal`), so no date was stored.
- **Clairic is a preview model.** Cloudflare's terms say they may stop offering it. The promo price ends 2026-12-01.
- **The macOS app has been built and unit-tested in CI (`macos-latest`) but never run on a real Mac.** None of the
  following has been tried: menu-bar rendering, window focus, the search panel's keys on a real keyboard, FSEvents on
  a real Desktop, Keychain prompts on an ad-hoc-signed build, launch at login (`SMAppService`), or the whole local
  runtime (uv install, `hf download` progress parsing, model loading).
- **The local runtime depends on an unmerged mlx-lm pull request** (#2086). The 2-bit and 3-bit builds are in
  mlx-vlm format and may need mlx-vlm instead of mlx-lm.
- **The build is unsigned and not notarized.** It is ad-hoc signed, and you have to remove the quarantine flag
  yourself.
- **The Finder comment may not show in Get Info.** It is written as an extended attribute, while Get Info reads
  comments from `.DS_Store`. Spotlight does index it.
- The index's content hash is size + modification time + the first 64 KiB of the file. It detects files Shotkeeper
  has already seen, but it is not a security hash.
- There is a single global search shortcut, ⌥⌘S, and it cannot be changed yet. If another app already uses it, the
  menu shows "Hotkey ⌥⌘S unavailable".

## Architecture

- **`Sources/ShotkeeperCore`**: Foundation only, and it builds and tests on Linux. It contains the Clairic and
  OpenAI-compatible analyzers, filename cleanup, file organizer (renames never replace a file), undo log, SQLite FTS5
  index, rate-limited processing queue, processing pipeline, settings, and the local-runtime planning code (model
  catalog, backend recommender, install/download/server command lines). It has no third-party dependencies.
- **`App/`**: the macOS app, defined in `App/project.yml` for XcodeGen and written in Swift 6 language mode. It
  contains `AppCoordinator`, the FSEvents folder watcher, ImageIO downscaling, the extended-attribute writer, Keychain
  storage, the global hotkey, the search panel, `SMAppService` launch at login, and the `mlx_lm.server` process
  manager.
- **Seams:** the core defines protocols that the app implements. The main one is `ScreenshotAnalyzer`, which turns an
  image into a title, description, tags and text. Clairic, local Inkling and a custom endpoint all sit behind it, and
  the pipeline reads the current analyzer for each screenshot, so switching backends takes effect immediately. The
  others are `ImagePreparer`, `FileMetadataWriter` and `CredentialStore`.
- **`Sources/shotkeeper-cli`**: a command-line tool for making one live analyzer call.

More detail:

- [docs/core-api.md](docs/core-api.md): core types and how the app connects them
- [docs/wiki/index.md](docs/wiki/index.md): dated record of decisions, including
  [architecture](docs/wiki/architecture.md), [model backend](docs/wiki/model-backend.md),
  [core](docs/wiki/core-implementation.md) and [app](docs/wiki/app-implementation.md) implementation, and
  [macOS CI](docs/wiki/macos-ci.md)
- [docs/research/model-backends.md](docs/research/model-backends.md): Clairic and Inkling 2 Mini facts, with sources
