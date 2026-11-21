#!/usr/bin/env bash
# Build and test the Linux-portable core in the shotkeeper-dev Swift image. No host ports, no host toolchain.
# Usage: scripts/test-linux.sh [swift args...]   (default: `test`)
#   SCRATCH=.build/linux-foo scripts/test-linux.sh build   # separate scratch dir per concurrent caller
#   SHOTKEEPER_DOCKER_NETWORK=bridge scripts/test-linux.sh run shotkeeper-cli ...   # network only when a live call needs it
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="shotkeeper-dev-swift:6.4.3"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  printf 'FROM swift:6.4.3-noble\nRUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-dev && rm -rf /var/lib/apt/lists/*\n' \
    | docker build -q -t "$IMAGE" - >/dev/null
fi
SCRATCH="${SCRATCH:-.build/linux}"
[ $# -eq 0 ] && set -- test
exec docker run --rm --network "${SHOTKEEPER_DOCKER_NETWORK:-none}" \
  -e CLOUDFLARE_ACCOUNT_ID -e CLOUDFLARE_API_TOKEN \
  -v "$ROOT":/src -w /src "$IMAGE" swift "$1" --scratch-path "$SCRATCH" "${@:2}"
