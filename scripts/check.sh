#!/bin/bash
# Builds AND tests. Run before every commit -- `swift build` alone passing while
# the test target fails to compile is a real failure mode we have already hit.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "==> build"
swift build
echo "==> test"
swift test
echo "==> OK"
