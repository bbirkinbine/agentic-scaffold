#!/usr/bin/env bash
# Bootstrap the stack-neutral flavor into fresh and legacy temporary repos.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  echo "GENERIC SMOKE FAIL: $*" >&2
  exit 1
}

fresh="$WORK_DIR/fresh"
mkdir -p "$fresh"
git -C "$fresh" init -q
(
  cd "$fresh"
  bash "$REPO_DIR/generic/bootstrap.sh"
)

for path in \
  AGENTS.md \
  CLAUDE.md \
  README.md \
  .claude/settings.json \
  .codex/config.toml \
  .codex/hooks.json \
  .codex/rules/safety.rules \
  .agentic/hooks/branch-check.sh \
  .agentic/hooks/block-destructive.sh \
  .agentic/hooks/context-reminder.sh \
  .agentic/hooks/statusline.sh \
  .agentic/hooks/strip-ai-attribution.sh \
  docs/codex-cli.md; do
  [[ -e "$fresh/$path" ]] || fail "missing fresh-project file: $path"
done

[[ "$(cat "$fresh/CLAUDE.md")" == '@AGENTS.md' ]] \
  || fail "fresh CLAUDE.md does not import canonical AGENTS.md"
grep -q 'Hooks and guardrails' "$fresh/AGENTS.md" \
  || fail "fresh AGENTS.md is not the complete contract"

python3 - "$fresh" <<'PY'
import json
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
tomllib.loads((root / ".codex/config.toml").read_text())
json.loads((root / ".codex/hooks.json").read_text())
json.loads((root / ".claude/settings.json").read_text())
PY

for hook in "$fresh"/.agentic/hooks/*.sh; do
  [[ -x "$hook" ]] || fail "installed hook is not executable: $hook"
done

# The commit-msg hook is the only AI-attribution enforcement a stack-neutral
# project gets: there is no pre-commit config to hang it on, and neither
# client's own hooks can see a commit message. Assert it actually strips,
# rather than only that the file exists.
[[ -x "$fresh/.git/hooks/commit-msg" ]] \
  || fail "generic bootstrap did not install the commit-msg hook"
(
  cd "$fresh"
  git config user.email smoke@example.com
  git config user.name "Smoke Test"
  printf 'x\n' >attribution-fixture.txt
  git add attribution-fixture.txt
  git commit -q -m "$(printf 'Add fixture\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n\nGenerated with [Claude Code](https://claude.com/claude-code)')"
)
message="$(git -C "$fresh" log -1 --format=%B)"
if printf '%s' "$message" | grep -qi 'Co-Authored-By\|Generated with'; then
  fail "commit-msg hook left AI attribution in the commit message"
fi
printf '%s' "$message" | grep -q 'Add fixture' \
  || fail "commit-msg hook destroyed the commit subject"

if printf '%s\n' '{"tool_input":{"command":"git status"}}' \
  | bash "$fresh/.agentic/hooks/block-destructive.sh"; then
  :
else
  fail "destructive-command hook blocked a safe command"
fi

if printf '%s\n' '{"tool_input":{"command":"git clean -fd"}}' \
  | bash "$fresh/.agentic/hooks/block-destructive.sh" \
    >"$WORK_DIR/block.out" 2>"$WORK_DIR/block.err"; then
  fail "destructive-command hook allowed git clean"
fi
grep -q 'BLOCKED' "$WORK_DIR/block.err" \
  || fail "destructive-command hook returned no reason"

bash "$fresh/.agentic/hooks/context-reminder.sh" --codex \
  | python3 -m json.tool >/dev/null

printf '\nPROJECT-SPECIFIC CONTRACT SURVIVES\n' >>"$fresh/AGENTS.md"
printf '\nPROJECT README SURVIVES\n' >>"$fresh/README.md"
printf '\n# PROJECT CONFIG SURVIVES\n' >>"$fresh/.codex/config.toml"
printf '\n' >>"$fresh/.claude/settings.json"
printf '\n' >>"$fresh/.codex/hooks.json"
cp "$fresh/.claude/settings.json" "$WORK_DIR/custom-claude-settings.json"
cp "$fresh/.codex/hooks.json" "$WORK_DIR/custom-codex-hooks.json"
(
  cd "$fresh"
  bash "$REPO_DIR/generic/bootstrap.sh" --update >/dev/null
)
[[ "$(cat "$fresh/CLAUDE.md")" == '@AGENTS.md' ]] \
  || fail "update broke the Claude import shim"
grep -q 'PROJECT-SPECIFIC CONTRACT SURVIVES' "$fresh/AGENTS.md" \
  || fail "update overwrote the project contract"
grep -q 'PROJECT README SURVIVES' "$fresh/README.md" \
  || fail "update overwrote README.md"
grep -q 'PROJECT CONFIG SURVIVES' "$fresh/.codex/config.toml" \
  || fail "update overwrote customized Codex config"
cmp -s "$fresh/.claude/settings.json" "$WORK_DIR/custom-claude-settings.json" \
  || fail "update overwrote customized Claude settings"
cmp -s "$fresh/.codex/hooks.json" "$WORK_DIR/custom-codex-hooks.json" \
  || fail "update overwrote customized Codex hooks"

legacy="$WORK_DIR/legacy"
mkdir -p "$legacy"
git -C "$legacy" init -q
printf '%s\n' \
  '# AGENTS.md' \
  '' \
  'This portable fallback says the authoritative content lives in `CLAUDE.md`.' \
  >"$legacy/AGENTS.md"
printf '%s\n' \
  '# Existing project contract' \
  '' \
  'CUSTOM LEGACY POLICY SURVIVES' \
  >"$legacy/CLAUDE.md"
(
  cd "$legacy"
  bash "$REPO_DIR/generic/bootstrap.sh" --update >/dev/null
)
grep -q 'CUSTOM LEGACY POLICY SURVIVES' "$legacy/AGENTS.md" \
  || fail "legacy pointer migration overwrote customized policy"
[[ "$(cat "$legacy/CLAUDE.md")" == '@AGENTS.md' ]] \
  || fail "legacy pointer migration did not create the Claude import shim"
[[ -f "$legacy/.codex/config.toml" ]] \
  || fail "legacy update did not install Codex config"

claude_only="$WORK_DIR/claude-only"
mkdir -p "$claude_only"
printf '%s\n' '# Existing policy' '' 'CLAUDE-ONLY POLICY SURVIVES' \
  >"$claude_only/CLAUDE.md"
(
  cd "$claude_only"
  bash "$REPO_DIR/generic/bootstrap.sh" >/dev/null
)
grep -q 'CLAUDE-ONLY POLICY SURVIVES' "$claude_only/AGENTS.md" \
  || fail "Claude-only migration overwrote customized policy"
[[ "$(cat "$claude_only/CLAUDE.md")" == '@AGENTS.md' ]] \
  || fail "Claude-only migration did not create the import shim"

broken_import="$WORK_DIR/broken-import"
mkdir -p "$broken_import"
printf '%s\n' '@AGENTS.md' >"$broken_import/CLAUDE.md"
(
  cd "$broken_import"
  bash "$REPO_DIR/generic/bootstrap.sh" >/dev/null
)
grep -q 'Hooks and guardrails' "$broken_import/AGENTS.md" \
  || fail "missing AGENTS.md behind an import shim was not repaired"
[[ "$(cat "$broken_import/CLAUDE.md")" == '@AGENTS.md' ]] \
  || fail "repair changed the Claude import shim"

if command -v codex >/dev/null 2>&1; then
  rules="$fresh/.codex/rules/safety.rules"
  codex execpolicy check --rules "$rules" -- git commit -m test \
    | grep -q '"prompt"' || fail "generic commit rule did not prompt"
  codex execpolicy check --rules "$rules" -- git clean -fd \
    | grep -q '"forbidden"' || fail "generic git-clean rule was not forbidden"
fi

echo "generic smoke-test OK"
