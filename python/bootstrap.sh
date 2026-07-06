#!/usr/bin/env bash
# Bootstrap (or update) a Python project with the agentic-workflow
# scaffolding from the agentic-scaffold repo. Run from the project's root.
#
# Usage:
#   cd your-project
#   bash path/to/agentic-scaffold/python/bootstrap.sh [--minimal|--python-core|--full] [--strict-hooks] [--advanced-docs]
#   bash path/to/agentic-scaffold/python/bootstrap.sh --update [profile/options]
#
# Profiles:
#   --minimal      Thin starter: project context, workflow, core commands,
#                  core agents, specs convention, and CI.
#   --python-core  Default. The normal attended Python agentic workflow,
#                  without advanced/experimental doctrine docs.
#   --full         Everything in python-core plus optional-reviewer command
#                  stubs and advanced docs (parallel agents, plugin path,
#                  serena, evals). Optional reviewer agents are still not
#                  copied; enable them per project.
#
# Options:
#   --strict-hooks  Make Claude hooks enforce ruff check + mypy after edits
#                   and enable the Stop gate. Without this, edit hooks format
#                   only; /review-check and CI remain the hard gates.
#   --advanced-docs Copy advanced docs with any profile.
#
# Two classes of file:
#   - PROJECT-OWNED  (CLAUDE.md, pyproject.toml, .gitignore,
#     docs/agent-handoff.md, README.md) — written once, then customized
#     per project (filled placeholders, real deps, ignores). NEVER
#     overwritten, in either mode. README.md is laid down from
#     README.md.template (suffix dropped); keep its Acknowledgements
#     section — that is the single AI-attribution surface.
#   - MANAGED  (everything else — the .claude/ tree, WORKFLOW.md,
#     AGENTS.md, .pre-commit-config.yaml, docs/specs/README.md, the
#     .github/ tree) — the agentic scaffolding itself. On first run it
#     is copied if absent; with --update it is overwritten so existing
#     projects pick up template improvements.
#
# What profiles copy:
#   - All profiles: CLAUDE.md, README.md (from README.md.template),
#     WORKFLOW.md, AGENTS.md, pyproject.toml, .gitignore,
#     .pre-commit-config.yaml, default settings/hooks (format-only edit
#     hook, branch warning, destructive-command block, secrets read-deny,
#     status line, specs dashboard,
#     commit-message attribution strip), standing rules, docs/specs/README.md,
#     docs/project-types.md (the orientation map), CI, core commands
#     (spec / plan / test-first / review-check / review), and the core
#     agents those commands need.
#   - python-core and full: extra hooks, skills,
#     specs-status, product-spec, scope-check, clarify, adr, analyze,
#     review-adversarial, docs/adr/README.md, docs/workflow-diagram.md,
#     docs/agent-handoff.md, and Dependabot.
#   - full or --advanced-docs: docs/parallel-agents.md,
#     docs/plugin-packaging.md, docs/serena-setup.md, docs/evals.md.
#   - full only: command stubs for security / performance / eval and the
#     inert Claude PR-review workflow example.
#
# What it also creates (only if absent):
#   - src/{{PACKAGE_NAME}}/__init__.py + tests/test_smoke.py — a starter
#     src-layout so mypy/pytest are green from the first run. Rename the
#     package dir when you fill placeholders.
#
# What it does NOT copy:
#   - bootstrap.sh, README.md (this directory's own index — distinct from
#     README.md.template, which IS laid down as the project's README.md),
#     subdir-CLAUDE.md.example (copied manually into each src/<area>/)
#   - anything under .claude/agents/optional/ (opt-in subagents that
#     each project enables per-need — see the Done message at the end)
#
# After a first run, read WORKFLOW.md (copied into the project root) —
# the source of truth for day-zero setup and the per-feature loop.

set -euo pipefail

MODE=install
PROFILE=python-core
STRICT_HOOKS=0
STRICT_HOOKS_APPLIED=0
ADVANCED_DOCS=0

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--update] [--minimal|--python-core|--full] [--strict-hooks] [--advanced-docs]

Profiles:
  --minimal      Thin starter: context, workflow, core commands/agents, specs, CI
  --python-core  Default attended Python workflow without advanced docs
  --full         Full workflow surface plus advanced docs and optional command stubs

Options:
  --update         Refresh MANAGED files; project-owned files are left untouched
  --strict-hooks   Enable ruff check + mypy after edits and the Stop gate
  --advanced-docs  Copy advanced docs even when not using --full
EOF
}

for arg in "$@"; do
  case "$arg" in
    --update) MODE=update ;;
    --minimal) PROFILE=minimal ;;
    --python-core) PROFILE=python-core ;;
    --full)
      PROFILE=full
      ADVANCED_DOCS=1
      ;;
    --strict-hooks) STRICT_HOOKS=1 ;;
    --advanced-docs) ADVANCED_DOCS=1 ;;
    -h | --help)
      usage
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

SETTINGS_PREEXISTED=0
[[ -e "$DST_DIR/.claude/settings.json" ]] && SETTINGS_PREEXISTED=1

if [[ "$MODE" == update ]]; then
  echo "Updating MANAGED agentic-workflow scaffolding"
else
  echo "Bootstrapping Python agentic-workflow scaffolding"
fi
echo "  profile: $PROFILE"
echo "  strict hooks: $([[ "$STRICT_HOOKS" == 1 ]] && echo yes || echo no)"
echo "  advanced docs: $([[ "$ADVANCED_DOCS" == 1 ]] && echo yes || echo no)"
echo "  from: $SRC_DIR"
echo "  into: $DST_DIR"
echo

# ripgrep is used by the placeholder walk, public-repo hygiene checks, and
# agent searches. Warn instead of failing because the copy itself does not
# require it, and Claude Code may provide a bundled rg inside its shell.
if ! command -v rg >/dev/null 2>&1; then
  echo "WARNING: ripgrep (rg) not found. Bootstrap can continue, but install it"
  echo "         before running the placeholder and hygiene checks: brew install ripgrep"
  echo
fi

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

# copy_renamed: like copy() (PROJECT-OWNED, never overwritten), but the
# source and destination paths differ — used for a *.template file that
# drops its suffix in the project (README.md.template -> README.md).
copy_renamed() {
  local src_rel="$1"
  local dst_rel="$2"
  local src="$SRC_DIR/$src_rel"
  local dst="$DST_DIR/$dst_rel"
  if [[ -e "$dst" ]]; then
    echo "  skip (project-owned, exists): $dst_rel"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
  echo "  copied: $src_rel -> $dst_rel"
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

write_strict_settings() {
  local dst="$DST_DIR/.claude/settings.json"
  if [[ "$MODE" == install && "$SETTINGS_PREEXISTED" == 1 ]]; then
    echo "  skip strict hooks (existing settings): .claude/settings.json"
    echo "    Re-run with --update --strict-hooks or merge the strict hook settings by hand."
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cat > "$dst" <<'JSON'
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./**/.env)",
      "Read(./**/.env.*)",
      "Read(./**/*.pem)",
      "Read(./**/*.key)"
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash .claude/hooks/statusline.sh"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/branch-check.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/block-destructive.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -d src ] && [ -d tests ]; then uv run ruff format . && uv run ruff check . && uv run mypy src/; fi"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/specs-status.sh --hook"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'When compacting, preserve: the active spec path (docs/specs/NNNN-*.md), the current branch name, the list of files modified this session, the failing/passing state of the quality gate, and any unresolved [ask-user] review findings.'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/gate-on-stop.sh"
          }
        ]
      }
    ]
  }
}
JSON
  STRICT_HOOKS_APPLIED=1
  echo "  wrote strict hooks: .claude/settings.json"
}

# --- project-owned: copied once, never overwritten ---
copy CLAUDE.md
copy pyproject.toml
copy .gitignore
copy_renamed README.md.template README.md
if [[ "$PROFILE" != minimal ]]; then
  copy docs/agent-handoff.md
fi

# --- starter layout: a src/<package>/ and tests/, seeded so mypy/pytest
# and the quality gates are green from the first run. Created only when
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

# --- managed: profile-independent core ---
sync WORKFLOW.md
sync AGENTS.md
sync .pre-commit-config.yaml
sync .claude/settings.json
sync .claude/hooks/branch-check.sh
sync .claude/hooks/block-destructive.sh
sync .claude/hooks/statusline.sh
sync .claude/hooks/specs-status.sh
sync .claude/hooks/strip-ai-attribution.sh
sync .claude/rules/git-workflow.md
sync .claude/rules/commit-style.md
sync .claude/rules/public-repo-hygiene.md
sync .claude/rules/python-code.md
sync .claude/rules/agent-legible-code.md
sync .claude/agents/planner.md
sync .claude/agents/test-first.md
sync .claude/agents/reviewer.md
sync .claude/commands/spec.md
sync .claude/commands/plan.md
sync .claude/commands/test-first.md
sync .claude/commands/review-check.md
sync .claude/commands/review.md
sync docs/specs/README.md
sync docs/project-types.md
sync .github/workflows/ci.yml
sync .github/pull_request_template.md
sync .github/ISSUE_TEMPLATE/feature.yml
sync .github/ISSUE_TEMPLATE/bug.yml

# --- managed: default attended Python workflow ---
# gate-on-stop.sh is intentionally NOT copied here: the default settings.json
# wires no Stop hook, so the script would be inert. It is synced only in the
# --strict-hooks block below, where the Stop hook is actually wired.
if [[ "$PROFILE" != minimal ]]; then
  sync .claude/agents/reviewer-adversarial.md
  sync .claude/commands/product-spec.md
  sync .claude/commands/specs-status.md
  sync .claude/commands/scope-check.md
  sync .claude/commands/clarify.md
  sync .claude/commands/adr.md
  sync .claude/commands/analyze.md
  sync .claude/commands/review-adversarial.md
  sync .claude/skills/python-module-split/SKILL.md
  sync .claude/skills/python-docstrings/SKILL.md
  sync .claude/skills/dependency-hygiene/SKILL.md
  sync docs/adr/README.md
  sync docs/workflow-diagram.md
  sync .github/dependabot.yml

fi

if [[ "$STRICT_HOOKS" == 1 ]]; then
  sync .claude/hooks/gate-on-stop.sh
  write_strict_settings
fi

# --- managed: advanced docs and full command surface ---
if [[ "$PROFILE" == full || "$ADVANCED_DOCS" == 1 ]]; then
  sync docs/parallel-agents.md
  sync docs/plugin-packaging.md
  sync docs/serena-setup.md
  sync docs/evals.md
fi

if [[ "$PROFILE" == full ]]; then
  sync .claude/commands/security.md
  sync .claude/commands/performance.md
  sync .claude/commands/eval.md
  sync .github/workflows/claude-review.yml.example
fi

# Intentionally NOT copied (opt-in per project):
#   .claude/agents/optional/security-reviewer.md     — for projects with a network
#     surface, auth, untrusted input, secrets, or external deserialization.
#   .claude/agents/optional/performance-reviewer.md  — for projects with a hot path,
#     DB queries on user-sized data, async code, migrations on large tables, or any
#     latency SLO.
#   .claude/agents/optional/evaluator.md             — for projects whose product
#     contains an LLM/AI surface (summarizer, RAG answer, chatbot, agent trajectory);
#     authors and runs evals that judge output quality. See docs/evals.md.
#   See $SRC_DIR/.claude/agents/optional/ for what's available.

echo

if [[ "$MODE" == update ]]; then
  echo "Update complete. Review what changed:"
  echo "  git diff"
  echo
  echo "Project-owned files were left untouched. If the template's versions"
  echo "of those changed, merge by hand. Profile used: $PROFILE."
  exit 0
fi

echo "Done. Scaffolding and a starter src/ + tests/ layout are in place."
echo
case "$PROFILE" in
  minimal)
    echo "Profile: minimal. You have the core loop only; add --python-core or"
    echo "--full on a future --update if this project grows into the full workflow."
    ;;
  python-core)
    echo "Profile: python-core. Advanced docs and optional-reviewer command stubs"
    echo "were not installed; use --advanced-docs or --full if you need them."
    ;;
  full)
    echo "Profile: full. Advanced docs were installed. Optional reviewer agents"
    echo "still require an explicit copy from .claude/agents/optional/."
    ;;
esac
echo
if [[ "$STRICT_HOOKS_APPLIED" == 1 ]]; then
  echo "Strict hooks are enabled. Edit hooks run format + lint + mypy, and the"
  echo "Stop hook blocks ending a turn while the local gate is red."
elif [[ "$STRICT_HOOKS" == 1 ]]; then
  echo "Strict hooks were requested but not applied because .claude/settings.json"
  echo "already existed. Re-run with --update --strict-hooks or merge by hand."
else
  echo "Strict hooks are off. Edit hooks format only; /review-check and CI are"
  echo "the hard quality gates. Re-run with --strict-hooks to opt in."
fi
echo
echo "Read WORKFLOW.md next — it's in your project root and is the source"
echo "of truth for what to do: day-zero setup and the per-feature loop."
echo "Pull future template improvements:  bash $SRC_DIR/bootstrap.sh --update"
