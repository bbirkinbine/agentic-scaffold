#!/usr/bin/env bash
# Bootstrap (or update) a Python project with the agentic-workflow
# scaffolding from the agentic-scaffold repo. Run from the project's root.
#
# Usage:
#   cd your-project
#   bash path/to/agentic-scaffold/python/bootstrap.sh            # first-time setup
#   bash path/to/agentic-scaffold/python/bootstrap.sh --update   # pull template improvements
#
# Two classes of file:
#   - PROJECT-OWNED  (CLAUDE.md, pyproject.toml, .gitignore,
#     docs/agent-handoff.md) — written once, then customized per project
#     (filled placeholders, real deps, ignores). NEVER overwritten, in
#     either mode.
#   - MANAGED  (everything else — the .claude/ tree, WORKFLOW.md,
#     AGENTS.md, .pre-commit-config.yaml, docs/specs/README.md, the
#     .github/ tree) — the agentic scaffolding itself. On first run it
#     is copied if absent; with --update it is overwritten so existing
#     projects pick up template improvements.
#
# What it copies:
#   - CLAUDE.md, WORKFLOW.md, AGENTS.md, pyproject.toml, .gitignore,
#     .pre-commit-config.yaml
#   - the .claude/ tree: settings.json + the branch-check SessionStart
#     hook + the block-destructive PreToolUse hook + the gate-on-stop
#     Stop hook + the specs-status PostToolUse hook (regenerates the
#     status dashboard in docs/specs/README.md) + the rules
#     (.claude/rules/: git-workflow, commit-style,
#     public-repo-hygiene, python-code, agent-legible-code) + the default
#     subagents (planner / test-first / reviewer /
#     reviewer-adversarial) + the default skills (python-module-split /
#     python-docstrings / dependency-hygiene) + the default slash
#     commands (product-spec, spec, specs-status, scope-check, clarify,
#     plan, test-first, analyze, review-check, review,
#     review-adversarial, security, performance)
#   - docs/specs/README.md — the specs convention + the live status
#     dashboard the specs-status hook keeps current
#   - docs/workflow-diagram.md — visual map of the agentic loop
#   - docs/parallel-agents.md — worktrees, agent teams, unattended runs
#   - docs/plugin-packaging.md — plugin/marketplace distribution path
#   - docs/serena-setup.md — optional serena MCP install/verify runbook
#   - docs/agent-handoff.md — operational runbook stub (project-owned)
#   - the .github/ tree: CI workflow, opt-in Claude review workflow
#     (.example, inert until renamed), PR template, issue forms
#
# What it also creates (only if absent):
#   - src/{{PACKAGE_NAME}}/__init__.py + tests/test_smoke.py — a starter
#     src-layout so mypy/pytest are green from the first run. Rename the
#     package dir when you fill placeholders.
#
# What it does NOT copy:
#   - bootstrap.sh, README.md (this directory's index),
#     subdir-CLAUDE.md.example (copied manually into each src/<area>/)
#   - anything under .claude/agents/optional/ (opt-in subagents that
#     each project enables per-need — see the Done message at the end)
#
# After a first run, read WORKFLOW.md (copied into the project root) —
# the source of truth for day-zero setup and the per-feature loop.

set -euo pipefail

MODE=install
for arg in "$@"; do
  case "$arg" in
    --update) MODE=update ;;
    -h | --help)
      echo "Usage: bootstrap.sh [--update]"
      echo "  (no args)  first-time setup — copies missing files, never overwrites"
      echo "  --update   refresh MANAGED files to the current template;"
      echo "             project-owned files (CLAUDE.md, pyproject.toml,"
      echo "             .gitignore) are left untouched"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $arg  (run with --help for usage)"
      exit 1
      ;;
  esac
done

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST_DIR="$(pwd)"

if [[ "$SRC_DIR" == "$DST_DIR" ]]; then
  echo "ERROR: refusing to bootstrap into the template directory itself."
  echo "       cd into the project's root before running this script."
  exit 1
fi

# Preflight: ripgrep is a workflow prerequisite — the placeholder walk,
# the .env leak check in the new-project checklist, and the agent's own
# searches all use `rg`. Claude Code ships a bundled `rg` shim inside its
# shell, but a plain terminal (where a human runs this script) does not,
# so the real binary must be installed.
if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: ripgrep (rg) not found — it is a workflow prerequisite."
  echo "       Install it:  brew install ripgrep"
  exit 1
fi

if [[ "$MODE" == update ]]; then
  echo "Updating MANAGED agentic-workflow scaffolding"
else
  echo "Bootstrapping Python agentic-workflow scaffolding"
fi
echo "  from: $SRC_DIR"
echo "  into: $DST_DIR"
echo

# copy: PROJECT-OWNED files. Written once, never overwritten — they are
# customized per project (filled placeholders, real deps, ignores).
copy() {
  local rel="$1"
  local src="$SRC_DIR/$rel"
  local dst="$DST_DIR/$rel"
  if [[ -e "$dst" ]]; then
    echo "  skip (project-owned, exists): $rel"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
  echo "  copied: $rel"
}

# sync: MANAGED files. Copied if absent; with --update, overwritten so
# the project tracks template improvements.
sync() {
  local rel="$1"
  local src="$SRC_DIR/$rel"
  local dst="$DST_DIR/$rel"
  local existed=0
  [[ -e "$dst" ]] && existed=1
  if [[ "$existed" == 1 && "$MODE" == install ]]; then
    echo "  skip (exists): $rel"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
  if [[ "$existed" == 1 ]]; then
    echo "  updated: $rel"
  else
    echo "  copied: $rel"
  fi
}

# --- project-owned: copied once, never overwritten ---
copy CLAUDE.md
copy pyproject.toml
copy .gitignore
copy docs/agent-handoff.md

# --- starter layout: a src/<package>/ and tests/, seeded so mypy/pytest
# and the PostToolUse hook are green from the first run. Created only when
# absent, so existing code is never touched. ---
if [[ -d "$DST_DIR/src" ]]; then
  echo "  skip (exists): src/"
else
  mkdir -p "$DST_DIR/src/{{PACKAGE_NAME}}"
  printf '"""{{PACKAGE_NAME}} package — rename this directory to your package name."""\n' \
    > "$DST_DIR/src/{{PACKAGE_NAME}}/__init__.py"
  echo "  created: src/{{PACKAGE_NAME}}/__init__.py"
fi
if [[ -d "$DST_DIR/tests" ]]; then
  echo "  skip (exists): tests/"
else
  mkdir -p "$DST_DIR/tests"
  printf 'def test_smoke() -> None:\n    """Placeholder so the suite is green; delete once you have real tests."""\n    assert True\n' \
    > "$DST_DIR/tests/test_smoke.py"
  echo "  created: tests/test_smoke.py"
fi

# --- managed: refreshed by --update ---
sync WORKFLOW.md
sync AGENTS.md
sync .pre-commit-config.yaml
sync .claude/settings.json
sync .claude/hooks/branch-check.sh
sync .claude/hooks/block-destructive.sh
sync .claude/hooks/gate-on-stop.sh
sync .claude/hooks/specs-status.sh
sync .claude/rules/git-workflow.md
sync .claude/rules/commit-style.md
sync .claude/rules/public-repo-hygiene.md
sync .claude/rules/python-code.md
sync .claude/rules/agent-legible-code.md
sync .claude/agents/planner.md
sync .claude/agents/test-first.md
sync .claude/agents/reviewer.md
sync .claude/agents/reviewer-adversarial.md
sync .claude/commands/product-spec.md
sync .claude/commands/spec.md
sync .claude/commands/specs-status.md
sync .claude/commands/scope-check.md
sync .claude/commands/clarify.md
sync .claude/commands/plan.md
sync .claude/commands/test-first.md
sync .claude/commands/analyze.md
sync .claude/commands/review-check.md
sync .claude/commands/review.md
sync .claude/commands/review-adversarial.md
sync .claude/commands/security.md
sync .claude/commands/performance.md
sync .claude/skills/python-module-split/SKILL.md
sync .claude/skills/python-docstrings/SKILL.md
sync .claude/skills/dependency-hygiene/SKILL.md
sync docs/specs/README.md
sync docs/workflow-diagram.md
sync docs/parallel-agents.md
sync docs/plugin-packaging.md
sync docs/serena-setup.md
sync .github/workflows/ci.yml
sync .github/workflows/claude-review.yml.example
sync .github/pull_request_template.md
sync .github/ISSUE_TEMPLATE/feature.yml
sync .github/ISSUE_TEMPLATE/bug.yml

# Intentionally NOT copied (opt-in per project):
#   .claude/agents/optional/security-reviewer.md     — for projects with a network
#     surface, auth, untrusted input, secrets, or external deserialization.
#   .claude/agents/optional/performance-reviewer.md  — for projects with a hot path,
#     DB queries on user-sized data, async code, migrations on large tables, or any
#     latency SLO.
#   See $SRC_DIR/.claude/agents/optional/ for what's available.

echo

if [[ "$MODE" == update ]]; then
  echo "Update complete. Review what changed:"
  echo "  git diff"
  echo
  echo "Project-owned files (CLAUDE.md, pyproject.toml, .gitignore,"
  echo "docs/agent-handoff.md) were left untouched. If the template's"
  echo "versions of those changed, merge by hand."
  exit 0
fi

echo "Done. Scaffolding and a starter src/ + tests/ layout are in place."
echo
echo "Read WORKFLOW.md next — it's in your project root and is the source"
echo "of truth for what to do: day-zero setup and the per-feature loop."
echo "This script doesn't repeat those steps, so they can't drift from the"
echo "docs. Companion docs, all copied into your project:"
echo "  WORKFLOW.md              — the steps, in order"
echo "  CLAUDE.md                — the rules the agent follows + slash commands"
echo "  docs/workflow-diagram.md — the same loop as a visual map"
echo
echo "Opt-in reviewers (security / performance) aren't installed by"
echo "default; WORKFLOW.md day zero says when. Enable one with:"
echo "  cp $SRC_DIR/.claude/agents/optional/<name>.md .claude/agents/"
echo
echo "Pull future template improvements:  bash $SRC_DIR/bootstrap.sh --update"
