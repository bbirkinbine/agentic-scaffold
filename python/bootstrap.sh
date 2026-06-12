#!/usr/bin/env bash
# Bootstrap (or update) a Python project with the agentic-workflow
# scaffolding from the agentic-scaffold repo. Run from the project's root.
#
# Usage:
#   cd ~/Downloads/src/new-project
#   bash ~/Downloads/src/agentic-scaffold/python/bootstrap.sh            # first-time setup
#   bash ~/Downloads/src/agentic-scaffold/python/bootstrap.sh --update   # pull template improvements
#
# Two classes of file:
#   - PROJECT-OWNED  (CLAUDE.md, pyproject.toml, .gitignore) — written
#     once, then customized per project (filled placeholders, real deps,
#     project-specific ignores). NEVER overwritten, in either mode.
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
#     Stop hook + the rules (.claude/rules/: git-workflow, commit-style,
#     public-repo-hygiene, python-code, agent-legible-code) + the default
#     subagents (planner / test-first / reviewer /
#     reviewer-adversarial) + the default skills (python-module-split /
#     python-docstrings / dependency-hygiene) + the default slash
#     commands (spec, specs-status, scope-check, clarify, plan,
#     test-first, analyze, review-check, review, review-adversarial,
#     security, performance)
#   - docs/specs/README.md — the specs convention
#   - docs/workflow-diagram.md — visual map of the agentic loop
#   - docs/parallel-agents.md — worktrees, agent teams, unattended runs
#   - docs/plugin-packaging.md — plugin/marketplace distribution path
#   - docs/serena-setup.md — optional serena MCP install/verify runbook
#   - docs/agent-handoff.md — operational runbook stub (project-owned)
#   - the .github/ tree: CI workflow, opt-in Claude review workflow
#     (.example, inert until renamed), PR template, issue forms
#
# What it does NOT copy:
#   - bootstrap.sh, README.md (this directory's index),
#     subdir-CLAUDE.md.example (copied manually into each src/<area>/)
#   - anything under .claude/agents/optional/ (opt-in subagents that
#     each project enables per-need — see the Done message at the end)
#
# After a first run:
#   1. Walk the {{PLACEHOLDER}} slots in CLAUDE.md, pyproject.toml.
#      Verify with: rg '\{\{' .
#   2. Walk ~/Downloads/src/agentic-scaffold/new-project-checklist.md
#      for the README.md acknowledgement, GitHub About sidebar, identity check.
#   3. uv sync && uv run pre-commit install

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

# --- managed: refreshed by --update ---
sync WORKFLOW.md
sync AGENTS.md
sync .pre-commit-config.yaml
sync .claude/settings.json
sync .claude/hooks/branch-check.sh
sync .claude/hooks/block-destructive.sh
sync .claude/hooks/gate-on-stop.sh
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
  echo "Project-owned files (CLAUDE.md, pyproject.toml, .gitignore) were left"
  echo "untouched. If the template's versions of those changed, merge by hand."
  exit 0
fi

echo "Done. Next steps:"
echo "  0. Read WORKFLOW.md — the loop walkthrough with worked examples."
echo "  1. Replace placeholders:  rg '\\{\\{' . | head"
echo "  2. Walk the rest of the new-project checklist:"
echo "     ~/Downloads/src/agentic-scaffold/new-project-checklist.md"
echo "  3. Install dev environment:"
echo "     uv sync && uv run pre-commit install"
echo "  4. Create the GitHub issue labels the issue forms reference"
echo "     (feature, bug, spec-needed, triage, ...)."
echo "  5. Write your first spec:  /spec <feature name>  (or by hand at"
echo "     docs/specs/0001-<feature>.md)"
echo "  6. For per-subdir CLAUDE.md files:"
echo "     cp $SRC_DIR/subdir-CLAUDE.md.example src/<area>/CLAUDE.md"
echo "  7. If this project has a network surface, auth, or processes"
echo "     untrusted input, add the opt-in security-reviewer:"
echo "     cp $SRC_DIR/.claude/agents/optional/security-reviewer.md \\"
echo "        .claude/agents/security-reviewer.md"
echo "  8. If this project has a hot path, async code, DB queries on"
echo "     user-sized data, or a latency SLO, add the opt-in"
echo "     performance-reviewer:"
echo "     cp $SRC_DIR/.claude/agents/optional/performance-reviewer.md \\"
echo "        .claude/agents/performance-reviewer.md"
echo
echo "Workflow loop (slash commands installed in .claude/commands/):"
echo "  /product-spec [name]   OPTIONAL — interview to create/refresh the"
echo "                         product-level spec docs/specs/0000-product.md"
echo "  /scope-check <desc>    OPTIONAL — five forcing questions before /spec"
echo "                         when goal/scope is ambiguous"
echo "  /spec <name>           create a spec under docs/specs/"
echo "  /clarify [spec]        OPTIONAL — interrogate the draft spec for"
echo "                         underspecified areas; writes answers back in"
echo "  /specs-status [filter] print the status table for all specs"
echo "  /plan                  invoke the planner subagent on the latest spec"
echo "  /test-first            invoke the test-first subagent"
echo "  /analyze [spec]        OPTIONAL — read-only spec/tests/diff consistency check"
echo "  /review-check          run the local quality gate (ruff, format, mypy, pytest)"
echo "  /review                invoke the reviewer subagent on the current diff"
echo "  /review-adversarial    invoke reviewer-adversarial on the same diff;"
echo "                         pair with /review on meaningful features"
echo "  /security              invoke security-reviewer (if installed)"
echo "  /performance           invoke performance-reviewer (if installed)"
echo
echo "To pull future template improvements into this project, re-run with:"
echo "  bash $SRC_DIR/bootstrap.sh --update"
