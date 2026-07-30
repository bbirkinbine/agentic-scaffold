#!/usr/bin/env bash
# Stop hook — refuse to end the turn while the local quality gate is red.
#
# Fires when the main session tries to finish responding. If src/ has
# pending changes and ruff/mypy/pytest don't all pass, it returns
# decision:block so the client continues the turn instead of declaring
# done. This makes the review-check discipline automatic: the session
# cannot stop on a broken build without a human seeing green first.
#
# See AGENTS.md -> "Workflow expectations" (Verify).
#
# Stop hooks have no matcher and fire on every turn end, so two guards keep
# this from nagging in normal conversation or looping forever:
#   1. loop guard   — if we are already continuing because of a prior block
#                     (stop_hook_active), step aside with a warning so a gate
#                     that genuinely can't pass surfaces to the human rather
#                     than looping.
#   2. change guard — do nothing if src/ has no pending changes this turn.
#
# decision control: a Stop hook reports its decision via JSON on stdout,
# processed only on exit 0. Both clients accept the same top-level form
# ({"decision":"block","reason":...}), so that is the only shape emitted.
# The Codex wiring passes --codex; the flag is accepted and ignored so
# both wirings can share this script. Emit nothing to allow the stop.
#
# NOT an unbounded guarantee: clients cap or guard repeated continuation.
# This gate is one rung of the
# completion ladder — in-prompt checks below it and a fresh verification
# subagent above it. See WORKFLOW.md -> "The completion ladder".

set -uo pipefail

# Run from the project root so the src/-guard, git, and uv all resolve
# regardless of the invoking client's CWD. Resolve it from this script's
# location (.agentic/hooks/ is two levels below the root); if that fails,
# allow the stop rather than blocking on hook infrastructure.
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 0

INPUT="$(cat)"

# 1. loop guard
if printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  echo "gate-on-stop: gate still red after a retry; leaving it for you to resolve." >&2
  exit 0
fi

# Only meaningful in an initialized project.
[ -d src ] && [ -d tests ] || exit 0

# 2. change guard — modified OR untracked files under src/ both count.
if [ -z "$(git status --porcelain -- src/ 2>/dev/null)" ]; then
  exit 0
fi

fails=""
uv run ruff check . >/dev/null 2>&1 || fails="${fails} ruff"
uv run mypy src/   >/dev/null 2>&1 || fails="${fails} mypy"
uv run pytest -q   >/dev/null 2>&1 || fails="${fails} pytest"

if [ -n "$fails" ]; then
  reason="Quality gate is red (failed:${fails}). Per AGENTS.md Verify phase, do not finish: fix the failures, or write the missing failing tests first, then re-run. Use the review-check workflow for verbose output."
  printf '{"decision":"block","reason":"%s"}\n' "$reason"
fi

exit 0
