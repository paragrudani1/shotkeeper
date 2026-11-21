#!/usr/bin/env bash
# CI helper: `swift test` for the package. SwiftPM errors with "no tests found" while
# Tests/ShotkeeperCoreTests has no Swift sources (true on main until the core tasks land), so in that case
# build the test target only and say so loudly. As soon as any test file exists, this is plain `swift test`.
set -euo pipefail
if find Tests -name '*.swift' -print -quit | grep -q .; then
  exec swift test "$@"
fi
echo "::warning title=No core tests::Tests/ contains no Swift test sources yet; ran 'swift build --build-tests' instead of 'swift test'."
exec swift build --build-tests "$@"
