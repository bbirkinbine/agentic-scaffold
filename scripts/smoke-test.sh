#!/usr/bin/env bash
# Smoke-test bootstrap.sh end to end: run one profile into a temp dir,
# assert the profile's file set, walk the day-zero placeholder fill the
# way WORKFLOW.md prescribes, and run the full quality gate (ruff lint +
# format, mypy, pytest). Proves a fresh project is green on day zero —
# the claim the starter src/ + tests/ layout exists to back.
#
# Usage:
#   scripts/smoke-test.sh <minimal|python-core|full> [--strict-hooks]
#
# Run locally before changing bootstrap.sh or the template pyproject;
# CI (.github/workflows/ci.yml) runs every profile on each push/PR.
# Requires: uv.

set -euo pipefail

PROFILE="${1:?usage: smoke-test.sh <minimal|python-core|full> [--strict-hooks]}"
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
must .claude/settings.json
must .claude/hooks/block-destructive.sh
must .claude/hooks/statusline.sh
must .claude/rules/git-workflow.md
must .claude/agents/reviewer.md
must .claude/commands/spec.md
must .claude/commands/review-check.md
must docs/specs/README.md
must docs/project-types.md
must .github/workflows/ci.yml
must "src/{{PACKAGE_NAME}}/__init__.py"
must tests/test_smoke.py

case "$PROFILE" in
  minimal)
    must_not .claude/skills/python-module-split/SKILL.md
    must_not .claude/commands/adr.md
    must_not .claude/agents/reviewer-adversarial.md
    must_not docs/adr/README.md
    must_not .github/dependabot.yml
    ;;
  python-core)
    must .claude/skills/python-module-split/SKILL.md
    must .claude/commands/adr.md
    must .claude/agents/reviewer-adversarial.md
    must .github/dependabot.yml
    must_not docs/parallel-agents.md
    must_not docs/llm-product.md
    must_not .claude/commands/security.md
    ;;
  full)
    must docs/parallel-agents.md
    must docs/evals.md
    must docs/llm-product.md
    must .claude/commands/security.md
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

# Strict hooks: Stop gate wired if and only if requested.
if [[ "$STRICT" == "--strict-hooks" ]]; then
  must .claude/hooks/gate-on-stop.sh
  if ! grep -q 'gate-on-stop.sh' .claude/settings.json; then
    echo "SMOKE FAIL: --strict-hooks set but settings.json has no Stop hook" >&2
    exit 1
  fi
else
  if grep -q 'gate-on-stop.sh' .claude/settings.json; then
    echo "SMOKE FAIL: Stop hook wired without --strict-hooks" >&2
    exit 1
  fi
fi

# Both settings variants (default file and the strict-hooks heredoc in
# bootstrap.sh) must carry the secrets read-deny and the status line —
# they are two copies of the same file and drift silently otherwise.
if ! grep -q '"deny"' .claude/settings.json; then
  echo "SMOKE FAIL: settings.json has no permissions deny list" >&2
  exit 1
fi
if ! grep -q 'statusline.sh' .claude/settings.json; then
  echo "SMOKE FAIL: settings.json has no statusLine wiring" >&2
  exit 1
fi

# The close-tasks-ride-in-the-PR rule must survive into every generated repo
# (git-workflow.md is MANAGED, CLAUDE.md is project-owned) so post-merge status
# flips don't become wasted cleanup PRs. Content-grep both, like the drift
# guards above.
if ! grep -q 'Close-tasks ride in the PR' .claude/rules/git-workflow.md; then
  echo "SMOKE FAIL: git-workflow.md lost the close-tasks-in-PR rule" >&2
  exit 1
fi
if ! grep -q 'close-tasks are part of this sweep' CLAUDE.md; then
  echo "SMOKE FAIL: CLAUDE.md lost the close-tasks docs-sync clause" >&2
  exit 1
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
