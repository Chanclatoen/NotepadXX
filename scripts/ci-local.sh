#!/bin/bash
# Runs the GitHub Actions jobs queued for this repository on this Mac, then
# stops.
#
# Deliberately not installed as a launch agent: the runner is started when you
# want CI and exits when the work is done, rather than sitting in the
# background all day. Self-hosted minutes are not billed, so this costs
# nothing whatever the account's spending limit says.
#
#   ./scripts/ci-local.sh          take one queued job, then exit
#   ./scripts/ci-local.sh --watch  stay up and take jobs until Ctrl-C
set -euo pipefail

RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner-notepadxx}"
if [[ ! -x "$RUNNER_DIR/run.sh" ]]; then
  echo "error: no runner at $RUNNER_DIR" >&2
  echo "Register one with config.sh, or set RUNNER_DIR to where it lives." >&2
  exit 1
fi

cd "$RUNNER_DIR"
if [[ "${1:-}" == "--watch" ]]; then
  echo "==> taking jobs until Ctrl-C"
  exec ./run.sh
fi

echo "==> taking one queued job, then exiting"
exec ./run.sh --once
