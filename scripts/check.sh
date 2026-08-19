#!/bin/bash
# Builds AND tests. Run before every commit -- `swift build` alone passing while
# the test target fails to compile is a real failure mode we have already hit.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "==> build (debug)"
swift build
echo "==> test"
swift test
# Release builds enable stricter checks; a Swift 6 concurrency error slipped
# through to CI once because this gate only built debug.
echo "==> build (release)"
swift build -c release
echo "==> OK"
