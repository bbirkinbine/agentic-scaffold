#!/usr/bin/env bash
# Stop hook — refuse to end the turn while the local quality gate is red.
#
# Fires when the main session tries to finish responding. If src/ has
# pending changes and ruff/mypy/pytest don't all pass, it returns
# decision:block so Claude Code continues the turn instead of declaring
# done. This makes the /review-check discipline automatic: the session
# cannot stop on a broken build without a human seeing green first.
#
# See CLAUDE.md -> "Workflow expectations" (Verify).
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
# processed only on exit 0. We emit both the top-level form
# ({"decision":"block","reason":...}) and the current hookSpecificOutput
# form so the block works across Claude Code versions; emit nothing to
# allow the stop.
#
# NOT an unbounded guarantee: Claude Code overrides a Stop hook after 8
# consecutive blocks without progress (raise with
# CLAUDE_CODE_STOP_HOOK_BLOCK_CAP). This gate is one rung of the
# completion ladder — in-prompt checks below it, /goal and a fresh
# verification subagent above it. See WORKFLOW.md -> "The completion
# ladder".

set -uo pipefail

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
  reason="Quality gate is red (failed:${fails}). Per CLAUDE.md Verify phase, do not finish: fix the failures, or write the missing failing tests first, then re-run. Use /review-check for the verbose output."
  printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"Stop","decision":"block","reason":"%s"}}\n' "$reason" "$reason"
fi

exit 0
