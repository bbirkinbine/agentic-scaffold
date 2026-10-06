#!/usr/bin/env bash
# Smoke-test the TypeScript flavor end to end: bootstrap the core profile
# into a temp dir, assert the installed file set, fill the day-zero
# placeholder, run the full quality gate through the toolchain runner, and
# prove the gate goes red on a real defect with the step named — the output
# the Stop hook's block reason is built from. The profile-transition and
# migration cases live in scripts/smoke-test.sh; they exercise the shared
# bootstrap body and do not depend on the stack.
#
# Usage:
#   scripts/smoke-test-typescript.sh [--strict-hooks|--no-stop-gate]
#
# Requires: node, npm (network access for the first install).

set -euo pipefail

STRICT="${1:-}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

fail() {
  echo "TYPESCRIPT SMOKE FAIL: $*" >&2
  exit 1
}

git init -q
args=(--core)
[[ -n "$STRICT" ]] && args+=("$STRICT")
bash "$REPO_DIR/typescript/bootstrap.sh" "${args[@]}"

must() { [[ -e "$1" ]] || fail "expected file missing: $1"; }
must_not() { [[ ! -e "$1" ]] || fail "file should not be installed: $1"; }

# --- file set: the workflow surface plus this stack's files, none of Python's ---
for path in CLAUDE.md WORKFLOW.md AGENTS.md README.md \
  package.json tsconfig.json biome.json vitest.config.ts .nvmrc .gitignore \
  .pre-commit-config.yaml .agentic/toolchain.sh .agentic/scaffold-state \
  .agentic/hooks/format-after-edit.sh \
  .agentic/hooks/closeout-check.sh .agentic/hooks/block-destructive.sh \
  .claude/settings.json .claude/agents/reviewer.md .claude/agents/test-first.md \
  .claude/commands/review-check.md .claude/commands/test-first.md \
  .codex/config.toml .codex/hooks.json .codex/rules/safety.rules \
  .pi/settings.json .pi/extensions/agentic-hooks.ts \
  .pi/extensions/agentic-child-hooks.ts \
  .pi/agents/reviewer.md .pi/agents/test-first.md \
  .pi/prompts/review-check.md .pi/prompts/test-first.md docs/pi-agent.md \
  .agents/skills/review-check/SKILL.md .github/workflows/ci.yml \
  .github/dependabot.yml docs/specs/README.md docs/project-types.md \
  src/index.ts tests/index.test.ts; do
  must "$path"
done
for path in pyproject.toml .claude/skills src/'{{PACKAGE_NAME}}' tests/test_smoke.py; do
  must_not "$path"
done
[[ -x .agentic/toolchain.sh ]] || fail "toolchain.sh is not executable"
if [[ "$STRICT" == "--no-stop-gate" ]]; then
  must_not .agentic/hooks/gate-on-stop.sh
else
  must .agentic/hooks/gate-on-stop.sh
fi

printf '@AGENTS.md\n' | cmp -s - CLAUDE.md || fail "CLAUDE.md is not the @AGENTS.md import shim"
grep -q 'TypeScript 7 on Node 24' AGENTS.md || fail "AGENTS.md lacks the TypeScript stack block"
grep -q '# TypeScript code conventions' AGENTS.md || fail "AGENTS.md lacks the TypeScript standing rule"
grep -q '## Test-first' AGENTS.md || fail "AGENTS.md lacks the stack's test-first section"
grep -q 'External-reference provenance' AGENTS.md || fail "AGENTS.md lost the neutral provenance rule"
! grep -q '# Python code conventions' AGENTS.md || fail "AGENTS.md carries the Python rule"
! grep -q 'pytest' AGENTS.md || fail "AGENTS.md mentions pytest"
grep -Fxq 'PROFILE=core' .agentic/scaffold-state || fail "persisted profile is not core"
if [[ "$STRICT" == "--no-stop-gate" ]]; then
  ! grep -q 'gate-on-stop.sh' .claude/settings.json || fail "Claude Stop hook wired despite --no-stop-gate"
else
  grep -q 'gate-on-stop.sh' .claude/settings.json || fail "Claude Stop hook not wired"
fi
grep -q 'toolchain.sh' .github/workflows/ci.yml || fail "consumer CI does not call the runner"

# --- day-zero placeholder fill ---
sed -i.bak 's/{{PROJECT_NAME}}/smoketest/' package.json src/index.ts
rm -f package.json.bak src/index.ts.bak
git add -A
git -c user.email=smoke@example.com -c user.name=Smoke commit -qm "scaffold" --no-verify

# --- the quality gate a fresh project must pass, through the runner ---
bash .agentic/toolchain.sh ready || fail "ready check failed on a fresh project"
[[ "$(bash .agentic/toolchain.sh source-dirs)" == "src" ]] || fail "source-dirs is not src"
bash .agentic/toolchain.sh install
[[ -f package-lock.json ]] || fail "install did not produce a lockfile"
bash .agentic/toolchain.sh gate
bash .agentic/toolchain.sh test tests/index.test.ts >/dev/null

# --- the gate must go red on a real defect and name the failing step ---
printf 'export const broken: number = "not a number";\n' > src/broken.ts
gate_output="$(bash .agentic/toolchain.sh gate --quiet)" \
  && fail "gate stayed green on a type defect"
case "$gate_output" in
  failed:*typecheck*) ;;
  *) fail "quiet gate did not name typecheck; got: $gate_output" ;;
esac

# The Stop hook must turn that into a block decision while src/ is dirty.
if [[ "$STRICT" != "--no-stop-gate" ]]; then
  stop_output="$(printf '{"stop_hook_active":false}\n' | bash .agentic/hooks/gate-on-stop.sh)"
  printf '%s' "$stop_output" | grep -q '"decision":"block"' \
    || fail "Stop hook did not block a red gate; got: $stop_output"
  printf '%s' "$stop_output" | grep -q 'typecheck' \
    || fail "Stop hook block reason does not name the failing step"
fi

# A formatting defect must be caught by format-check and fixed by format.
rm -f src/broken.ts
printf 'export const   spaced=1\n' > src/spaced.ts
gate_output="$(bash .agentic/toolchain.sh gate --quiet)" \
  && fail "gate stayed green on a formatting defect"
case "$gate_output" in
  failed:*format-check*) ;;
  *) fail "quiet gate did not name format-check; got: $gate_output" ;;
esac
bash .agentic/toolchain.sh format >/dev/null
bash .agentic/toolchain.sh gate --quiet || fail "gate stayed red after formatting"
rm -f src/spaced.ts

# Clean tree: the Stop hook must allow the stop.
git checkout -q -- . && git clean -qfd src
if [[ "$STRICT" != "--no-stop-gate" ]]; then
  stop_output="$(printf '{"stop_hook_active":false}\n' | bash .agentic/hooks/gate-on-stop.sh 2>/dev/null || true)"
  [[ -z "$stop_output" ]] || fail "Stop hook emitted a decision on a clean tree: $stop_output"
fi

# --- close-out gate: silent on a chore branch, as in the Python flavor ---
CLOSEOUT_BRANCH=chore/bump-biome bash .agentic/hooks/closeout-check.sh >/dev/null 2>&1 \
  || fail "closeout gate fired on a chore branch"

echo "typescript smoke-test OK ${STRICT:-}"
