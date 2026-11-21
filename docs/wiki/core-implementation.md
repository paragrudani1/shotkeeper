# Core implementation decisions

Files/index/queue/pipeline/settings/runtime task, 2026-11-21. Commits: `8c40267` (files, queue, settings), `e0e553c` (index),
`f5ed705` (pipeline), `856f4b7` (runtime). API map: [../core-api.md](../core-api.md).

- 2026-11-21 (`8c40267`): Linux no-replace rename uses `renameat2` looked up with `dlsym` (Swift's Glibc module does not
  export it; `RENAME_NOREPLACE` = 1). Fallbacks: `link`+`unlink`, then an `O_CREAT|O_EXCL` placeholder for filesystems without
  hard links. No C shim target, so `Package.swift` is unchanged. Darwin uses `renamex_np(RENAME_EXCL)`; that branch is
  compiled only in macOS CI.
- 2026-11-21 (`8c40267`): `Files/_FilenameSanitizerStub.swift` stands in for the analyzers task's `FilenameSanitizer`.
  Delete it at merge. Core uses only `stem(from:maxLength:)`.
- 2026-11-21 (`8c40267`): queue holds instead of failing on `unauthorized`/`notConfigured` (`.error(message)` until
  `resume()`), so a bad token does not mark every screenshot failed. `unreachable` → `.offline` hold that uses no attempts.
- 2026-11-21 (`8c40267`): "pause" in `ExcludeRules` stores `pausedFrom` + `pausedUntil`. A screenshot is skipped if it
  was captured or is processed inside the window. Excluded/paused screenshots are not written to the index (privacy).
- 2026-11-21 (`e0e553c`): content hash = `v1:<size>:<mtime ms>:<FNV-1a 64 of first 64 KiB>`. Plain Foundation on Linux
  has no SHA-256 and core has no dependencies. Added an extra `note` column (not in the original column list) for "kept
  name: confidence 0.30 < 0.50" and non-fatal problems, so `last_error` stays for real failures.
- 2026-11-21 (`f5ed705`): processor appends the undo record right after a successful move, before the Finder and index
  writes (the brief listed it last). A later failure can then never leave a move that cannot be undone.
- 2026-11-21 (`856f4b7`): a real 3-bit MLX build exists: `VisualInference/Inkling-2-Mini-MLX-3bit` (24 GB Macs).
  Recommender: ≥ 24 GB → local 3-bit, ≥ 32 GB → local 4-bit, below → Clairic. **Open question:** the VisualInference
  2/3-bit cards target mlx-vlm, not mlx-lm. Loading them with the pinned mlx-lm commit is unverified, so the catalog marks
  them `verifiedWithMLXLM = false` and setup shows "Experimental build". Check on a Mac; fallback is `mlx_vlm.server`.
  Details: [../research/model-backends.md](../research/model-backends.md).
- 2026-11-21 (`856f4b7`): model downloads are pinned by revision into `runtime/models/<owner>--<name>`, and the server is
  launched on that local path with `HF_HUB_OFFLINE=1`. The server defaults to `--chat-template-args {"reasoning_effort":"none"}`.
