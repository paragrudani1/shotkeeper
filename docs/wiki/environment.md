# Environment

- 2026-11-21: development happens on a shared Linux production box (Hetzner, Ubuntu 24.04). No Xcode. Host rules: `/root/local-dev/AGENTS.md`.
- 2026-11-21: no host Swift. Core builds/tests run in Docker image `shotkeeper-dev-swift:6.4.3` (from `swift:6.4.3-noble` + `libsqlite3-dev`)
  via `scripts/test-linux.sh`. Containers use `--network none` unless a live call needs network.
- 2026-11-21: disk at 93–95% used. User rule: keep ≥15 GB free at all times; delete large downloads and any images added for experiments.
  The pre-existing `ghcr.io/ggml-org/llama.cpp:server-b11669` image is not ours; leave it.
- 2026-11-21: `gh` authenticated as paragrudani1 (fine-grained PAT). User authorized a PRIVATE repo `shotkeeper`.
- 2026-11-21: Cloudflare credentials were absent (env and `.env.local`) at session start; still absent when the analyzers landed,
  so no live Clairic call has run. `shotkeeper-cli analyze` is ready for one (`SHOTKEEPER_DOCKER_NETWORK=bridge scripts/test-linux.sh run shotkeeper-cli analyze <png>`).
- macOS app build/test happens only in GitHub Actions (`macos-latest`).
