#!/bin/bash
# Points git at the versioned hooks in .githooks, so every clone gets them.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "hooks enabled: $(git config core.hooksPath)"
echo "pre-push will run ./scripts/check.sh (debug build, tests, release build)"
