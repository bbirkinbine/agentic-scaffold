#!/usr/bin/env bash
# Smoke-test bootstrap.sh end to end: run one profile into a temp dir,
# assert the profile's file set, walk the day-zero placeholder fill the
# way WORKFLOW.md prescribes, and run the full quality gate (ruff lint +
# format, mypy, pytest). Proves a fresh project is green on day zero —
# the claim the starter src/ + tests/ layout exists to back.
#
# Usage:
#   scripts/smoke-test.sh <minimal|python-core|full> [--strict-hooks|--default-hooks|--no-stop-gate]
#
# Run locally before changing bootstrap.sh or the template pyproject;
# CI (.github/workflows/ci.yml) runs every profile on each push/PR.
# Requires: uv.

set -euo pipefail

PROFILE="${1:?usage: smoke-test.sh <minimal|python-core|full> [--strict-hooks|--default-hooks|--no-stop-gate]}"
STRICT="${2:-}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

args=("--$PROFILE")
if [[ -n "$STRICT" ]]; then
  args+=("$STRICT")
fi
bash "$REPO_DIR/python/bootstrap.sh" "${args[@]}"

# --- file-set assertions per profile ---

must() {
  if [[ ! -e "$1" ]]; then
    echo "SMOKE FAIL ($PROFILE): expected file missing: $1" >&2
    exit 1
  fi
}
must_not() {
  if [[ -e "$1" ]]; then
    echo "SMOKE FAIL ($PROFILE): file should not be installed: $1" >&2
    exit 1
  fi
}

# Core surface, every profile.
must CLAUDE.md
must WORKFLOW.md
must AGENTS.md
must README.md
must pyproject.toml
must .pre-commit-config.yaml
must .agentic/scaffold-state
must .agentic/scaffold-managed-files
must .claude/settings.json
must .agentic/hooks/block-destructive.sh
must .agentic/hooks/statusline.sh
must .agentic/hooks/context-reminder.sh
must .agentic/hooks/format-after-edit.sh
must .claude/agents/reviewer.md
must .claude/commands/spec.md
must .codex/config.toml
must .codex/hooks.json
must .codex/rules/safety.rules
must .codex/agents/reviewer.toml
must .agents/skills/spec/SKILL.md
must .agents/skills/review-check/SKILL.md
must .claude/commands/review-check.md
must docs/specs/README.md
must docs/project-types.md
must docs/codex-cli.md
must .github/workflows/ci.yml
must "src/{{PACKAGE_NAME}}/__init__.py"
must tests/test_smoke.py

case "$PROFILE" in
  minimal)
    must_not .claude/agents/analyzer.md
    must_not .codex/agents/analyzer.toml
    must_not .claude/skills/python-module-split/SKILL.md
    must_not .agents/skills/python-module-split/SKILL.md
    must_not .claude/commands/adr.md
    must_not .agents/skills/adr/SKILL.md
    must_not .claude/agents/reviewer-adversarial.md
    must_not .codex/agents/reviewer-adversarial.toml
    must_not docs/adr/README.md
    must_not .github/dependabot.yml
    ;;
  python-core)
    must .claude/agents/analyzer.md
    must .codex/agents/analyzer.toml
    must .claude/skills/python-module-split/SKILL.md
    must .agents/skills/python-module-split/SKILL.md
    must .claude/commands/adr.md
    must .agents/skills/adr/SKILL.md
    must .claude/agents/reviewer-adversarial.md
    must .codex/agents/reviewer-adversarial.toml
    must .github/dependabot.yml
    must_not docs/parallel-agents.md
    must_not docs/llm-product.md
    must_not .claude/commands/security.md
    ;;
  full)
    must .claude/agents/analyzer.md
    must .codex/agents/analyzer.toml
    must docs/parallel-agents.md
    must docs/evals.md
    must docs/llm-product.md
    must .claude/commands/security.md
    must .agents/skills/security/SKILL.md
    must .github/workflows/claude-review.yml.example
    ;;
  *)
    echo "SMOKE FAIL: unknown profile: $PROFILE" >&2
    exit 1
    ;;
esac

# Opt-in agents are never auto-copied, in any profile.
must_not .claude/agents/security-reviewer.md
must_not .claude/agents/optional
must_not .codex/agents/security-reviewer.toml
must_not .codex/agents/optional

# Stop gate: on by default (and under --strict-hooks); absent if and only
# if --no-stop-gate was passed.
if [[ "$STRICT" == "--no-stop-gate" ]]; then
  must_not .agentic/hooks/gate-on-stop.sh
  if grep -q 'gate-on-stop.sh' .claude/settings.json; then
    echo "SMOKE FAIL: Claude Stop hook wired despite --no-stop-gate" >&2
    exit 1
  fi
  if grep -q 'gate-on-stop.sh' .codex/hooks.json; then
    echo "SMOKE FAIL: Codex Stop hook wired despite --no-stop-gate" >&2
    exit 1
  fi
else
  must .agentic/hooks/gate-on-stop.sh
  if ! grep -q 'gate-on-stop.sh' .claude/settings.json; then
    echo "SMOKE FAIL: Claude settings have no Stop hook (on by default)" >&2
    exit 1
  fi
  if ! grep -q 'gate-on-stop.sh' .codex/hooks.json; then
    echo "SMOKE FAIL: Codex hooks have no Stop hook (on by default)" >&2
    exit 1
  fi
fi

if [[ "$STRICT" == "--strict-hooks" ]]; then
  grep -q 'format-after-edit.sh --strict' .claude/settings.json \
    || { echo "SMOKE FAIL: Claude strict edit hook missing" >&2; exit 1; }
  grep -q 'format-after-edit.sh.*--strict' .codex/hooks.json \
    || { echo "SMOKE FAIL: Codex strict edit hook missing" >&2; exit 1; }
fi

# All three settings variants (default file, the strict-hooks heredoc, and
# the no-stop-gate heredoc in bootstrap.sh) must carry the secrets
# read-deny and the status line — they are copies of the same file and
# drift silently otherwise.
if ! grep -q '"deny"' .claude/settings.json; then
  echo "SMOKE FAIL: settings.json has no permissions deny list" >&2
  exit 1
fi
if ! grep -q '.agentic/hooks/statusline.sh' .claude/settings.json; then
  echo "SMOKE FAIL: settings.json has no statusLine wiring" >&2
  exit 1
fi
for secret_pattern in '".env" = "deny"' '"**/*.pem" = "deny"' '"**/*.key" = "deny"'; do
  if ! grep -Fq "$secret_pattern" .codex/config.toml; then
    echo "SMOKE FAIL: Codex permission profile lost secret deny: $secret_pattern" >&2
    exit 1
  fi
done

if ! printf '@AGENTS.md\n' | cmp -s - CLAUDE.md; then
  echo "SMOKE FAIL: CLAUDE.md is not the canonical @AGENTS.md import shim" >&2
  exit 1
fi
if ! grep -q '<!-- agentic-scaffold:standing-rules:start -->' AGENTS.md; then
  echo "SMOKE FAIL: canonical AGENTS.md has no managed standing-rules block" >&2
  exit 1
fi

# The close-tasks-ride-in-the-PR rule must survive in the canonical contract
# so post-merge status flips do not become wasted cleanup PRs.
if ! grep -q 'Close-tasks ride in the PR they belong to' AGENTS.md; then
  echo "SMOKE FAIL: AGENTS.md lost the close-tasks docs-sync clause" >&2
  exit 1
fi

state_must_equal() {
  local root="$1"
  local key="$2"
  local expected="$3"

  if ! grep -Fxq "$key=$expected" "$root/.agentic/scaffold-state"; then
    echo "SMOKE FAIL: expected persisted state $key=$expected in $root" >&2
    exit 1
  fi
}

state_must_equal "$WORK" PROFILE "$PROFILE"
case "$STRICT" in
  --strict-hooks)
    state_must_equal "$WORK" STRICT_HOOKS 1
    state_must_equal "$WORK" NO_STOP_GATE 0
    ;;
  --no-stop-gate)
    state_must_equal "$WORK" STRICT_HOOKS 0
    state_must_equal "$WORK" NO_STOP_GATE 1
    ;;
  *)
    state_must_equal "$WORK" STRICT_HOOKS 0
    state_must_equal "$WORK" NO_STOP_GATE 0
    ;;
esac

transition_must() {
  local root="$1"
  local rel="$2"

  if [[ ! -e "$root/$rel" ]]; then
    echo "SMOKE FAIL (transition): expected file missing: $rel" >&2
    exit 1
  fi
}

transition_must_not() {
  local root="$1"
  local rel="$2"

  if [[ -e "$root/$rel" ]]; then
    echo "SMOKE FAIL (transition): excluded scaffold file remains: $rel" >&2
    exit 1
  fi
}

run_profile_transition_matrix() {
  local root="$WORK/profile-transition"
  local custom_copy="$WORK/custom-security-command.md"
  local log="$WORK/profile-transition.log"

  mkdir -p "$root"
  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --minimal >/dev/null
  )
  state_must_equal "$root" PROFILE minimal
  transition_must_not "$root" .agents/skills/analyze/SKILL.md

  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --update --python-core >/dev/null
  )
  state_must_equal "$root" PROFILE python-core
  transition_must "$root" .agents/skills/analyze/SKILL.md
  transition_must_not "$root" .agents/skills/security/SKILL.md

  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --update --full >/dev/null
  )
  state_must_equal "$root" PROFILE full
  transition_must "$root" .agents/skills/security/SKILL.md
  transition_must "$root" docs/parallel-agents.md

  # A profile shrink removes unchanged scaffold-owned files but must preserve
  # an excluded file that the project customized after installation.
  printf '\nProject-local customization.\n' \
    >> "$root/.claude/commands/security.md"
  cp "$root/.claude/commands/security.md" "$custom_copy"
  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --update --minimal > "$log"
  )
  state_must_equal "$root" PROFILE minimal
  transition_must_not "$root" .agents/skills/analyze/SKILL.md
  transition_must_not "$root" .agents/skills/security/SKILL.md
  transition_must_not "$root" docs/parallel-agents.md
  transition_must "$root" docs/agent-handoff.md
  if ! cmp -s "$root/.claude/commands/security.md" "$custom_copy"; then
    echo "SMOKE FAIL (transition): customized excluded file was changed" >&2
    exit 1
  fi
  if ! grep -q 'preserving customized or unverified excluded file' "$log"; then
    echo "SMOKE FAIL (transition): customized-file preservation emitted no warning" >&2
    exit 1
  fi
}

run_strict_flagless_update() {
  local root="$WORK/strict-flagless"
  local log="$WORK/strict-flagless.log"
  local agents_copy="$WORK/strict-AGENTS.md"
  local claude_settings_copy="$WORK/strict-claude-settings.json"
  local codex_config_copy="$WORK/strict-codex-config.toml"
  local codex_hooks_copy="$WORK/strict-codex-hooks.json"

  mkdir -p "$root"
  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --python-core --strict-hooks >/dev/null
  )
  cp "$root/AGENTS.md" "$agents_copy"

  # Recreate the pre-import layout to prove its safe update migration.
  cp "$root/AGENTS.md" "$root/CLAUDE.md"

  # Trailing JSON/TOML whitespace is a valid, minimal project customization.
  # The checksum boundary must preserve all three files on update.
  printf '\n' >> "$root/.claude/settings.json"
  printf '\n' >> "$root/.codex/config.toml"
  printf '\n' >> "$root/.codex/hooks.json"
  cp "$root/.claude/settings.json" "$claude_settings_copy"
  cp "$root/.codex/config.toml" "$codex_config_copy"
  cp "$root/.codex/hooks.json" "$codex_hooks_copy"

  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --update > "$log"
  )

  state_must_equal "$root" PROFILE python-core
  state_must_equal "$root" STRICT_HOOKS 1
  state_must_equal "$root" NO_STOP_GATE 0
  if ! grep -q 'format-after-edit.sh --strict' "$root/.claude/settings.json"; then
    echo "SMOKE FAIL (update): flagless update lost persisted strict hooks" >&2
    exit 1
  fi
  if ! grep -q 'format-after-edit.sh.*--strict' "$root/.codex/hooks.json"; then
    echo "SMOKE FAIL (update): flagless update lost persisted Codex strict hooks" >&2
    exit 1
  fi
  if ! cmp -s "$root/.claude/settings.json" "$claude_settings_copy" ||
    ! cmp -s "$root/.codex/config.toml" "$codex_config_copy" ||
    ! cmp -s "$root/.codex/hooks.json" "$codex_hooks_copy"; then
    echo "SMOKE FAIL (update): customized client configuration was overwritten" >&2
    exit 1
  fi
  if [[ "$(grep -c 'preserving customized client config' "$log")" -ne 3 ]]; then
    echo "SMOKE FAIL (update): expected one preservation warning per client config" >&2
    exit 1
  fi
  if ! cmp -s "$root/AGENTS.md" "$agents_copy"; then
    echo "SMOKE FAIL (update): canonical project-owned AGENTS.md changed wholesale" >&2
    exit 1
  fi
  if ! printf '@AGENTS.md\n' | cmp -s - "$root/CLAUDE.md"; then
    echo "SMOKE FAIL (update): legacy context pair did not migrate to Claude import" >&2
    exit 1
  fi
}

run_preserved_stop_gate_update() {
  local client root config expected log

  for client in claude codex; do
    root="$WORK/no-stop-preserved-$client"
    expected="$WORK/no-stop-preserved-$client.json"
    log="$WORK/no-stop-preserved-$client.log"
    mkdir -p "$root"
    (
      cd "$root"
      bash "$REPO_DIR/python/bootstrap.sh" --minimal >/dev/null
    )

    if [[ "$client" == claude ]]; then
      config=".claude/settings.json"
    else
      config=".codex/hooks.json"
    fi

    # Valid trailing whitespace makes this client config project-owned while
    # retaining its scaffold Stop entry. The other client's stock config can
    # accept --no-stop-gate normally.
    printf '\n' >> "$root/$config"
    cp "$root/$config" "$expected"
    (
      cd "$root"
      bash "$REPO_DIR/python/bootstrap.sh" --update --no-stop-gate > "$log"
    )

    state_must_equal "$root" NO_STOP_GATE 1
    if ! cmp -s "$root/$config" "$expected"; then
      echo "SMOKE FAIL (update): customized $client hook config was overwritten" >&2
      exit 1
    fi
    if [[ ! -e "$root/.agentic/hooks/gate-on-stop.sh" ]]; then
      echo "SMOKE FAIL (update): preserved $client Stop hook targets a missing script" >&2
      exit 1
    fi
    if ! grep -q 'gate-on-stop\.sh' "$root/$config"; then
      echo "SMOKE FAIL (update): preserved $client config lost its Stop hook" >&2
      exit 1
    fi
    if ! grep -q $'\t.agentic/hooks/gate-on-stop.sh$' \
      "$root/.agentic/scaffold-managed-files"; then
      echo "SMOKE FAIL (update): retained Stop hook script is no longer managed" >&2
      exit 1
    fi
    if ! grep -q 'WARNING: retaining Stop gate script' "$log"; then
      echo "SMOKE FAIL (update): retained Stop hook script emitted no warning" >&2
      exit 1
    fi
  done
}

run_claude_only_contract_migration() {
  local root="$WORK/claude-only"
  local expected="$WORK/claude-only-contract.md"

  mkdir -p "$root"
  printf '# Existing project policy\n\nKeep this project-specific rule.\n' \
    > "$root/CLAUDE.md"
  cp "$root/CLAUDE.md" "$expected"

  (
    cd "$root"
    bash "$REPO_DIR/python/bootstrap.sh" --minimal >/dev/null
  )

  if ! cmp -s "$root/AGENTS.md" "$expected"; then
    echo "SMOKE FAIL (migration): Claude-only policy was not preserved in AGENTS.md" >&2
    exit 1
  fi
  if ! printf '@AGENTS.md\n' | cmp -s - "$root/CLAUDE.md"; then
    echo "SMOKE FAIL (migration): Claude-only project did not receive the import shim" >&2
    exit 1
  fi
}

# CI runs the profile rows separately. Keep the transition cases on one row
# each so the matrix covers lifecycle behavior without multiplying uv work.
if [[ "$PROFILE" == full && -z "$STRICT" ]]; then
  run_profile_transition_matrix
elif [[ "$PROFILE" == python-core && "$STRICT" == --strict-hooks ]]; then
  run_strict_flagless_update
elif [[ "$PROFILE" == minimal && -z "$STRICT" ]]; then
  run_preserved_stop_gate_update
  run_claude_only_contract_migration
fi

# --- day-zero placeholder fill (the steps WORKFLOW.md prescribes) ---
# sed -i.bak works on both BSD (macOS) and GNU sed.
sed -i.bak 's/{{PROJECT_NAME}}/smoketest/' pyproject.toml
mv 'src/{{PACKAGE_NAME}}' src/smoketest
sed -i.bak 's/{{PACKAGE_NAME}}/smoketest/' src/smoketest/__init__.py
rm -f pyproject.toml.bak src/smoketest/__init__.py.bak

# --- the quality gate a fresh project must pass ---
uv sync
uv run ruff check .
uv run ruff format --check .
uv run mypy src/
uv run pytest -q

echo "smoke-test OK: $PROFILE ${STRICT:-}"
