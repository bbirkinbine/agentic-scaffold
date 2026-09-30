#!/usr/bin/env bash
# Shared PreCompact reminder. Codex requires JSON; Claude Code accepts text.

set -euo pipefail

MESSAGE='When compacting, preserve: the active task or spec path (if any), the current branch name, the list of files modified this session, the failing/passing state of repository validation, and any unresolved decisions that require the human.'

if [[ "${1:-}" == "--codex" ]]; then
  printf '{"systemMessage":"%s"}\n' "$MESSAGE"
else
  printf '%s\n' "$MESSAGE"
fi
