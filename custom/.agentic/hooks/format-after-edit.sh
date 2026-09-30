#!/usr/bin/env bash
# Shared PostToolUse hook — format after edits, with optional strict checks.

set -euo pipefail

# Run from the project root (two levels above .agentic/hooks/) so the
# readiness guard and formatting target the project no matter what CWD the
# invoking client used. Bail quietly if resolution fails — a formatting
# hook must never fail the tool call over its own infrastructure.
# The tools are named only in .agentic/toolchain.sh.
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 0

TOOLCHAIN=.agentic/toolchain.sh
[ -x "$TOOLCHAIN" ] || exit 0
bash "$TOOLCHAIN" ready || exit 0

bash "$TOOLCHAIN" format

if [[ "${1:-}" == "--strict" ]]; then
  bash "$TOOLCHAIN" lint
  bash "$TOOLCHAIN" typecheck
fi
