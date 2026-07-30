#!/usr/bin/env bash
# Shared PostToolUse hook — format after edits, with optional strict checks.

set -euo pipefail

# Run from the project root (two levels above .agentic/hooks/) so the
# src/-guard and formatting target the project no matter what CWD the
# invoking client used. Bail quietly if resolution fails — a formatting
# hook must never fail the tool call over its own infrastructure.
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 0

[ -d src ] && [ -d tests ] || exit 0

uv run ruff format .

if [[ "${1:-}" == "--strict" ]]; then
  uv run ruff check .
  uv run mypy src/
fi
