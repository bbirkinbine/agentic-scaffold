#!/usr/bin/env bash
# Bootstrap (or update) a Python project with the agentic-workflow
# scaffolding from the agentic-scaffold repo. Run from the project's root.
#
# Usage:
#   cd your-project
#   bash path/to/agentic-scaffold/python/bootstrap.sh [--minimal|--python-core|--full] [--strict-hooks|--default-hooks|--no-stop-gate] [--advanced-docs|--no-advanced-docs]
#   bash path/to/agentic-scaffold/python/bootstrap.sh --update [profile/options]
#
# Profiles:
#   --minimal      Thin starter: shared project context, core Claude/Codex
#                  workflows and agents, specs convention, and CI.
#   --python-core  Default. The normal attended Python agentic workflow,
#                  without advanced/experimental doctrine docs.
#   --full         Everything in python-core plus optional-reviewer command
#                  stubs and advanced docs (parallel agents, plugin path,
#                  serena, evals, llm-product, local-executor). Optional
#                  reviewer agents are
#                  still not copied; enable them per project.
#
# Options:
#   --strict-hooks  Make both clients enforce ruff check + mypy after edits.
#                   Without this, edit hooks format only; /review-check and
#                   CI remain the hard gates.
#   --no-stop-gate  Remove the Stop gate (on by default in every profile:
#                   the Stop hook blocks ending a turn while src/ is dirty
#                   and ruff/mypy/pytest are red). Incompatible with
#                   --strict-hooks, which requires the gate.
#   --default-hooks  Use format-only edit hooks plus the default Stop gate.
#                   This is the explicit way to move away from a previously
#                   persisted --strict-hooks or --no-stop-gate choice.
#   --advanced-docs Copy advanced docs with any profile.
#   --no-advanced-docs
#                   Remove the persisted advanced-docs option. Advanced docs
#                   remain inherent to --full.
#
# Two classes of file:
#   - PROJECT-OWNED  (AGENTS.md, pyproject.toml, .gitignore,
#     docs/agent-handoff.md, README.md) — written once, then customized
#     per project (filled placeholders, real deps, ignores). Never
#     overwritten wholesale. On --update, only the marked generated
#     standing-rules block in AGENTS.md is refreshed. CLAUDE.md is a tiny
#     @AGENTS.md import shim and remains scaffold-managed only while
#     unchanged. README.md is laid down from
#     README.md.template (suffix dropped); keep its Acknowledgements
#     section — that is the single AI-attribution surface.
#   - MANAGED  (everything else — .agentic/, .agents/, .claude/, .codex/,
#     WORKFLOW.md, .pre-commit-config.yaml, docs/specs/README.md, the
#     .github/ tree) — the agentic scaffolding itself. Bootstrap choices
#     and checksums are recorded under .agentic/ so a flagless --update
#     reuses the installed profile and hook mode, profile transitions can
#     remove unchanged scaffold-managed files, and customized client
#     configuration is preserved. On first run a managed file
#     is copied if absent; with --update it is overwritten so existing
#     projects pick up template improvements.
#
# What profiles copy:
#   - All profiles: canonical AGENTS.md + a CLAUDE.md @AGENTS.md import,
#     README.md (from README.md.template),
#     WORKFLOW.md, pyproject.toml, .gitignore,
#     .pre-commit-config.yaml, both client settings/hooks (format-only edit
#     hook, branch warning, destructive-command block, secrets read-deny,
#     status line, specs dashboard, Stop gate,
#     commit-message attribution strip), standing rules, docs/specs/README.md,
#     docs/project-types.md (the orientation map), CI, Claude slash commands,
#     Codex skills (spec / plan / test-first / review-check / review), and
#     both clients' core agents.
#   - python-core and full: extra hooks, skills,
#     specs-status, product-spec, scope-check, clarify, adr, analyze,
#     review-adversarial, docs/adr/README.md, docs/workflow-diagram.md,
#     docs/agent-handoff.md, and Dependabot.
#   - full or --advanced-docs: docs/parallel-agents.md,
#     docs/plugin-packaging.md, docs/serena-setup.md, docs/evals.md,
#     docs/llm-product.md, docs/local-executor.md.
#   - full only: command stubs for security / performance / eval / delegate
#     and the inert Claude PR-review workflow example.
#
# What it also creates (only if absent):
#   - src/{{PACKAGE_NAME}}/__init__.py + tests/test_smoke.py — a starter
#     src-layout so mypy/pytest are green from the first run. Rename the
#     package dir when you fill placeholders.
#
# What it does NOT copy:
#   - bootstrap.sh, README.md (this directory's own index — distinct from
#     README.md.template, which IS laid down as the project's README.md),
#     subdir-AGENTS.md.example and subdir-CLAUDE.md.example (copied
#     manually as canonical AGENTS.md + an @AGENTS.md Claude import in
#     each src/<area>/)
#   - anything under either client's agents/optional/ directory (opt-in
#     subagents that each project enables per-need)
#
# After a first run, read WORKFLOW.md (copied into the project root) —
# the source of truth for day-zero setup and the per-feature loop.

set -euo pipefail

MODE=install
PROFILE=python-core
PROFILE_EXPLICIT=0
STRICT_HOOKS=0
NO_STOP_GATE=0
HOOK_MODE_EXPLICIT=0
STRICT_FLAG_SEEN=0
DEFAULT_HOOKS_FLAG_SEEN=0
NO_STOP_FLAG_SEEN=0
ADVANCED_DOCS=0
ADVANCED_DOCS_EXPLICIT=0
STRICT_HOOKS_APPLIED=0
NO_STOP_GATE_APPLIED=0

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--update] [--minimal|--python-core|--full] [--strict-hooks|--default-hooks|--no-stop-gate] [--advanced-docs|--no-advanced-docs]

Profiles:
  --minimal      Thin starter: context, workflow, core commands/agents, specs, CI
  --python-core  Default attended Python workflow without advanced docs
  --full         Full workflow surface plus advanced docs and optional command stubs

Options:
  --update         Refresh MANAGED files; project-owned files are left untouched
  --strict-hooks   Enable ruff check + mypy after edits (Stop gate is on by default)
  --default-hooks  Use format-only edit hooks plus the default Stop gate
  --no-stop-gate   Remove the default Stop gate (incompatible with --strict-hooks)
  --advanced-docs  Copy advanced docs even when not using --full
  --no-advanced-docs
                    Clear a persisted advanced-docs option (except under --full)

A flagless --update reuses the profile, hook mode, and advanced-docs choice
recorded by the previous bootstrap. Pass an explicit profile or hook-mode
option to change that choice.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --update) MODE=update ;;
    --minimal)
      PROFILE=minimal
      PROFILE_EXPLICIT=1
      ;;
    --python-core)
      PROFILE=python-core
      PROFILE_EXPLICIT=1
      ;;
    --full)
      PROFILE=full
      PROFILE_EXPLICIT=1
      ;;
    --strict-hooks)
      STRICT_HOOKS=1
      NO_STOP_GATE=0
      HOOK_MODE_EXPLICIT=1
      STRICT_FLAG_SEEN=1
      ;;
    --default-hooks)
      STRICT_HOOKS=0
      NO_STOP_GATE=0
      HOOK_MODE_EXPLICIT=1
      DEFAULT_HOOKS_FLAG_SEEN=1
      ;;
    --no-stop-gate)
      STRICT_HOOKS=0
      NO_STOP_GATE=1
      HOOK_MODE_EXPLICIT=1
      NO_STOP_FLAG_SEEN=1
      ;;
    --advanced-docs)
      ADVANCED_DOCS=1
      ADVANCED_DOCS_EXPLICIT=1
      ;;
    --no-advanced-docs)
      ADVANCED_DOCS=0
      ADVANCED_DOCS_EXPLICIT=1
      ;;
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

if ((STRICT_FLAG_SEEN + DEFAULT_HOOKS_FLAG_SEEN + NO_STOP_FLAG_SEEN > 1)); then
  echo "ERROR: --strict-hooks, --default-hooks, and --no-stop-gate are mutually exclusive."
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST_DIR="$(pwd)"

if [[ "$SRC_DIR" == "$DST_DIR" ]]; then
  echo "ERROR: refusing to bootstrap into the template directory itself."
  echo "       cd into the project's root before running this script."
  exit 1
fi

STATE_FILE="$DST_DIR/.agentic/scaffold-state"
MANAGED_FILES_FILE="$DST_DIR/.agentic/scaffold-managed-files"
PREVIOUS_PROFILE=""
PREVIOUS_STRICT_HOOKS=0
PREVIOUS_NO_STOP_GATE=0
PREVIOUS_ADVANCED_DOCS=0
CLAUDE_SETTINGS_HASH=""
CODEX_CONFIG_HASH=""
CODEX_HOOKS_HASH=""

read_bootstrap_state() {
  local key value

  [[ -f "$STATE_FILE" ]] || return 1
  while IFS='=' read -r key value; do
    case "$key" in
      PROFILE)
        case "$value" in
          minimal | python-core | full) PREVIOUS_PROFILE="$value" ;;
        esac
        ;;
      STRICT_HOOKS)
        [[ "$value" == 0 || "$value" == 1 ]] && PREVIOUS_STRICT_HOOKS="$value"
        ;;
      NO_STOP_GATE)
        [[ "$value" == 0 || "$value" == 1 ]] && PREVIOUS_NO_STOP_GATE="$value"
        ;;
      ADVANCED_DOCS)
        [[ "$value" == 0 || "$value" == 1 ]] && PREVIOUS_ADVANCED_DOCS="$value"
        ;;
      CLAUDE_SETTINGS_HASH) CLAUDE_SETTINGS_HASH="$value" ;;
      CODEX_CONFIG_HASH) CODEX_CONFIG_HASH="$value" ;;
      CODEX_HOOKS_HASH) CODEX_HOOKS_HASH="$value" ;;
    esac
  done < "$STATE_FILE"
  [[ -n "$PREVIOUS_PROFILE" ]]
}

infer_existing_state() {
  local scaffold_seen=0

  if [[ -e "$DST_DIR/WORKFLOW.md" || -e "$DST_DIR/.agentic/hooks" ||
    -e "$DST_DIR/.claude/commands/spec.md" ||
    -e "$DST_DIR/.agents/skills/spec/SKILL.md" ]]; then
    scaffold_seen=1
  fi

  if [[ -e "$DST_DIR/.claude/commands/security.md" ||
    -e "$DST_DIR/.agents/skills/security/SKILL.md" ||
    -e "$DST_DIR/.github/workflows/claude-review.yml.example" ]]; then
    PREVIOUS_PROFILE=full
  elif [[ -e "$DST_DIR/.claude/commands/analyze.md" ||
    -e "$DST_DIR/.agents/skills/analyze/SKILL.md" ||
    -e "$DST_DIR/.github/dependabot.yml" ]]; then
    PREVIOUS_PROFILE=python-core
  elif [[ "$scaffold_seen" == 1 ]]; then
    PREVIOUS_PROFILE=minimal
  else
    # Preserve the historical default when --update is run against a project
    # that predates state tracking and has no reliable profile markers.
    PREVIOUS_PROFILE=python-core
  fi

  if grep -Eq -- 'format-after-edit\.sh[^"]*--strict' \
    "$DST_DIR/.claude/settings.json" "$DST_DIR/.codex/hooks.json" \
    2>/dev/null; then
    PREVIOUS_STRICT_HOOKS=1
  elif ! grep -q 'gate-on-stop.sh' \
    "$DST_DIR/.claude/settings.json" "$DST_DIR/.codex/hooks.json" \
    2>/dev/null &&
    [[ ! -e "$DST_DIR/.agentic/hooks/gate-on-stop.sh" ]]; then
    PREVIOUS_NO_STOP_GATE=1
  fi

  # Full inherently includes these docs. Record the independent option only
  # when the inferred profile itself would not have installed them.
  if [[ "$PREVIOUS_PROFILE" != full ]] &&
    [[ -e "$DST_DIR/docs/parallel-agents.md" ||
      -e "$DST_DIR/docs/plugin-packaging.md" ||
      -e "$DST_DIR/docs/llm-product.md" ]]; then
    PREVIOUS_ADVANCED_DOCS=1
  fi
}

if [[ "$MODE" == update ]]; then
  if read_bootstrap_state; then
    echo "Using recorded bootstrap choices from .agentic/scaffold-state"
  else
    infer_existing_state
    echo "WARNING: no usable .agentic/scaffold-state; inferred existing choices"
    echo "         (profile=$PREVIOUS_PROFILE, strict=$PREVIOUS_STRICT_HOOKS,"
    echo "         no-stop=$PREVIOUS_NO_STOP_GATE, advanced-docs=$PREVIOUS_ADVANCED_DOCS)."
  fi

  if [[ "$PROFILE_EXPLICIT" == 0 ]]; then
    PROFILE="$PREVIOUS_PROFILE"
  fi
  if [[ "$HOOK_MODE_EXPLICIT" == 0 ]]; then
    STRICT_HOOKS="$PREVIOUS_STRICT_HOOKS"
    NO_STOP_GATE="$PREVIOUS_NO_STOP_GATE"
  fi
  if [[ "$ADVANCED_DOCS_EXPLICIT" == 0 ]]; then
    ADVANCED_DOCS="$PREVIOUS_ADVANCED_DOCS"
  fi
fi

if [[ "$STRICT_HOOKS" == 1 && "$NO_STOP_GATE" == 1 ]]; then
  echo "ERROR: --strict-hooks and --no-stop-gate are incompatible."
  echo "       Strict hooks include the Stop gate; drop one of the two flags."
  exit 1
fi

EFFECTIVE_ADVANCED_DOCS="$ADVANCED_DOCS"
[[ "$PROFILE" == full ]] && EFFECTIVE_ADVANCED_DOCS=1

RUNTIME_DIR="$(mktemp -d)"
NEXT_MANAGED_FILES="$RUNTIME_DIR/scaffold-managed-files"
: > "$NEXT_MANAGED_FILES"
cleanup_runtime() {
  rm -rf "$RUNTIME_DIR"
}
trap cleanup_runtime EXIT

if [[ "$MODE" == update ]]; then
  echo "Updating MANAGED agentic-workflow scaffolding"
else
  echo "Bootstrapping Python agentic-workflow scaffolding"
fi
echo "  profile: $PROFILE"
echo "  strict hooks: $([[ "$STRICT_HOOKS" == 1 ]] && echo yes || echo no)"
echo "  stop gate: $([[ "$NO_STOP_GATE" == 1 ]] && echo no || echo yes)"
echo "  advanced docs: $([[ "$EFFECTIVE_ADVANCED_DOCS" == 1 ]] && echo yes || echo no)"
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

content_hash() {
  local path="$1"

  if command -v shasum >/dev/null 2>&1; then
    printf 'sha256:%s\n' "$(shasum -a 256 "$path" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256:%s\n' "$(sha256sum "$path" | awk '{print $1}')"
  elif command -v openssl >/dev/null 2>&1; then
    printf 'sha256:%s\n' "$(openssl dgst -sha256 "$path" | awk '{print $NF}')"
  else
    # POSIX fallback. A later host with SHA-256 available will conservatively
    # preserve the file because the algorithms differ.
    printf 'cksum:%s\n' "$(cksum "$path" | awk '{print $1 \":\" $2}')"
  fi
}

record_managed_file() {
  local rel="$1"
  local path="$DST_DIR/$rel"

  [[ -f "$path" ]] || return 0
  printf '%s\t%s\n' "$(content_hash "$path")" "$rel" >> "$NEXT_MANAGED_FILES"
}

previous_managed_hash() {
  local rel="$1"

  [[ -f "$MANAGED_FILES_FILE" ]] || return 0
  awk -F '\t' -v rel="$rel" '$2 == rel { print $1; exit }' \
    "$MANAGED_FILES_FILE"
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
  record_managed_file "$rel"
}

matches_known_scaffold_config() {
  local rel="$1"
  local path="$2"

  case "$rel" in
    .claude/settings.json)
      cmp -s "$path" "$SRC_DIR/.claude/settings.json" ||
        cmp -s "$path" "$RUNTIME_DIR/settings.strict.json" ||
        cmp -s "$path" "$RUNTIME_DIR/settings.no-stop.json"
      ;;
    .codex/config.toml)
      cmp -s "$path" "$SRC_DIR/.codex/config.toml"
      ;;
    .codex/hooks.json)
      cmp -s "$path" "$SRC_DIR/.codex/hooks.json" ||
        cmp -s "$path" "$SRC_DIR/.codex/hooks.strict.json" ||
        cmp -s "$path" "$SRC_DIR/.codex/hooks.no-stop.json"
      ;;
    *) return 1 ;;
  esac
}

# sync_protected_config updates a client configuration file only while its
# recorded content is unchanged. Existing installations without state get a
# conservative one-time stock-variant comparison. Once customization is
# detected, the state records that ownership boundary and future updates keep
# preserving the file until the user removes it or reconciles it manually.
sync_protected_config() {
  local rel="$1"
  local src="$2"
  local hash_var="$3"
  local dst="$DST_DIR/$rel"
  local recorded_hash current_hash new_hash
  local safe_to_update=0

  recorded_hash="${!hash_var}"
  LAST_PROTECTED_APPLIED=0

  if [[ ! -e "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    new_hash="$(content_hash "$dst")"
    printf -v "$hash_var" '%s' "$new_hash"
    LAST_PROTECTED_APPLIED=1
    echo "  copied: $rel"
    return
  fi

  current_hash="$(content_hash "$dst")"
  if [[ "$MODE" == install ]]; then
    if matches_known_scaffold_config "$rel" "$dst"; then
      printf -v "$hash_var" '%s' "$current_hash"
      if cmp -s "$dst" "$src"; then
        LAST_PROTECTED_APPLIED=1
      fi
    else
      printf -v "$hash_var" 'custom:%s' "$current_hash"
    fi
    echo "  skip (existing client config): $rel"
    return
  fi

  if cmp -s "$dst" "$src"; then
    safe_to_update=1
  elif [[ "$recorded_hash" != custom:* && -n "$recorded_hash" &&
    "$current_hash" == "$recorded_hash" ]]; then
    safe_to_update=1
  elif [[ -z "$recorded_hash" ]] &&
    matches_known_scaffold_config "$rel" "$dst"; then
    safe_to_update=1
  fi

  if [[ "$safe_to_update" == 1 ]]; then
    cp "$src" "$dst"
    new_hash="$(content_hash "$dst")"
    printf -v "$hash_var" '%s' "$new_hash"
    LAST_PROTECTED_APPLIED=1
    echo "  updated: $rel"
  else
    printf -v "$hash_var" 'custom:%s' "$current_hash"
    echo "  WARNING: preserving customized client config: $rel"
    echo "           Merge scaffold changes manually; its recorded choices still persist."
  fi
}

client_config_references_stop_gate() {
  grep -q 'gate-on-stop\.sh' "$DST_DIR/.claude/settings.json" 2>/dev/null ||
    grep -q 'gate-on-stop\.sh' "$DST_DIR/.codex/hooks.json" 2>/dev/null
}

prune_managed_file() {
  local rel="$1"
  local dst="$DST_DIR/$rel"
  local recorded_hash current_hash
  local safe_to_remove=0

  [[ -e "$dst" ]] || return 0
  recorded_hash="$(previous_managed_hash "$rel")"
  current_hash="$(content_hash "$dst")"

  if [[ -n "$recorded_hash" && "$current_hash" == "$recorded_hash" ]]; then
    safe_to_remove=1
  elif [[ -f "$SRC_DIR/$rel" ]] && cmp -s "$dst" "$SRC_DIR/$rel"; then
    # Best effort for installations created before the managed-file manifest.
    safe_to_remove=1
  fi

  if [[ "$safe_to_remove" == 1 ]]; then
    rm -f "$dst"
    echo "  removed (excluded by selected profile): $rel"
  else
    echo "  WARNING: preserving customized or unverified excluded file: $rel"
  fi
}

migrate_legacy_rules_into() {
  local target="$1"
  local rule base stock_hash rule_hash custom_header=0

  # Remove known byte-identical legacy stock rules because their current
  # equivalents are already in the canonical standing-rules block. Preserve
  # every customized or unknown rule by moving its body into AGENTS.md before
  # deleting the client-specific copy.
  for rule in "$DST_DIR"/.claude/rules/*.md; do
    [[ -f "$rule" ]] || continue
    base="$(basename "$rule")"
    case "$base" in
      agent-legible-code.md)
        stock_hash='sha256:3b0cec64cb3f76487e2dba58d98c5ebc3badea79b5e188881fbdeabf5bf3e63b'
        ;;
      commit-style.md)
        stock_hash='sha256:4edc46d105c3843cf6189d311a1447fb5c52f8cbb44fbeda0fd17d7703ee5fd2'
        ;;
      git-workflow.md)
        stock_hash='sha256:09186626c1fa3dd5d1af810f6305a017ede966a06ac3ba699e6d3ae713c7fb06'
        ;;
      public-repo-hygiene.md)
        stock_hash='sha256:a387a55f07dde76041b7245a628dd16bdabc65a5a26c23f96cb25a0f8a4498d6'
        ;;
      python-code.md)
        stock_hash='sha256:90ce90a70ff5b0c902d0b904f98d25976f28da945d3915818a851aa3574f98bf'
        ;;
      *)
        stock_hash=''
        ;;
    esac
    rule_hash="$(content_hash "$rule")"
    if [[ -n "$stock_hash" && "$rule_hash" == "$stock_hash" ]]; then
      rm -f "$rule"
      echo "  removed: legacy stock Claude rule $base"
      continue
    fi
    if [[ "$custom_header" == 0 ]]; then
      printf '\n## Project-local migrated rules\n' >> "$target"
      custom_header=1
    fi
    {
      printf '\n---\n\n'
      awk '
        NR == 1 && /^---[[:space:]]*$/ { in_frontmatter = 1; next }
        in_frontmatter && /^---[[:space:]]*$/ { in_frontmatter = 0; next }
        in_frontmatter { next }
        { print }
      ' "$rule"
    } >> "$target"
    rm -f "$rule"
    echo "  migrated: project-specific Claude rule $base into AGENTS.md"
  done
  rmdir "$DST_DIR/.claude/rules" 2>/dev/null || true
}

migrate_legacy_contract() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"
  local tmp

  [[ "$MODE" == update ]] || return 0
  [[ -f "$agents" && -f "$claude" ]] || return 0
  grep -q 'authoritative content lives in `CLAUDE.md`' "$agents" || return 0
  grep -q 'portable fallback' "$agents" || return 0

  tmp="$(mktemp)"
  cp "$claude" "$tmp"
  if ! grep -Fq '<!-- agentic-scaffold:standing-rules:start -->' "$tmp"; then
    printf '\n' >> "$tmp"
    sed -n \
      '/<!-- agentic-scaffold:standing-rules:start -->/,/<!-- agentic-scaffold:standing-rules:end -->/p' \
      "$SRC_DIR/AGENTS.md" >> "$tmp"
  fi
  migrate_legacy_rules_into "$tmp"
  cp "$tmp" "$agents"
  printf '@AGENTS.md\n' > "$claude"
  rm -f "$tmp"
  echo "  migrated: legacy pointer/full pair to canonical AGENTS.md + Claude import"
}

migrate_duplicate_contract() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"
  local tmp

  [[ "$MODE" == update ]] || return 0
  [[ -f "$agents" && -f "$claude" ]] || return 0
  cmp -s "$agents" "$claude" || return 0

  tmp="$(mktemp)"
  cp "$agents" "$tmp"
  if ! grep -Fq '<!-- agentic-scaffold:standing-rules:start -->' "$tmp"; then
    printf '\n' >> "$tmp"
    sed -n \
      '/<!-- agentic-scaffold:standing-rules:start -->/,/<!-- agentic-scaffold:standing-rules:end -->/p' \
      "$SRC_DIR/AGENTS.md" >> "$tmp"
  fi
  migrate_legacy_rules_into "$tmp"
  cp "$tmp" "$agents"
  printf '@AGENTS.md\n' > "$claude"
  rm -f "$tmp"
  echo "  migrated: duplicate contracts to canonical AGENTS.md + Claude import"
}

migrate_stray_claude_rules() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"
  local tmp first_rule

  [[ "$MODE" == update ]] || return 0
  [[ -f "$agents" && -f "$claude" ]] || return 0
  cmp -s <(printf '@AGENTS.md\n') "$claude" || return 0
  first_rule="$(find "$DST_DIR/.claude/rules" -maxdepth 1 -type f -name '*.md' \
    -print -quit 2>/dev/null || true)"
  [[ -n "$first_rule" ]] || return 0

  tmp="$(mktemp)"
  cp "$agents" "$tmp"
  migrate_legacy_rules_into "$tmp"
  cp "$tmp" "$agents"
  rm -f "$tmp"
  echo "  migrated: remaining Claude-specific rules into canonical AGENTS.md"
}

migrate_claude_only_contract() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"

  [[ ! -e "$agents" && -f "$claude" ]] || return 0
  if cmp -s <(printf '@AGENTS.md\n') "$claude"; then
    echo "  WARNING: CLAUDE.md imports missing AGENTS.md; installing the scaffold contract"
    return 0
  fi

  cp "$claude" "$agents"
  echo "  migrated: existing CLAUDE.md content to canonical AGENTS.md"
}

sync_claude_import() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"
  local desired="$RUNTIME_DIR/CLAUDE.md"

  printf '@AGENTS.md\n' > "$desired"
  if [[ ! -e "$claude" ]]; then
    cp "$desired" "$claude"
    echo "  copied: CLAUDE.md (@AGENTS.md import)"
    return
  fi
  if [[ -f "$agents" ]] && cmp -s "$claude" "$agents"; then
    cp "$desired" "$claude"
    echo "  migrated: byte-identical AGENTS.md / CLAUDE.md pair to @AGENTS.md import"
    return
  fi
  if [[ "$MODE" == install ]]; then
    echo "  skip (existing client context): CLAUDE.md"
    return
  fi
  if cmp -s "$claude" "$desired"; then
    cp "$desired" "$claude"
    echo "  updated: CLAUDE.md (@AGENTS.md import)"
  else
    echo "  WARNING: preserving customized CLAUDE.md"
    echo "           Canonical policy is in AGENTS.md; reconcile this file manually."
  fi
}

refresh_managed_contract_rules() {
  local agents="$DST_DIR/AGENTS.md"
  local before block after tmp
  local start='<!-- agentic-scaffold:standing-rules:start -->'
  local end='<!-- agentic-scaffold:standing-rules:end -->'

  [[ "$MODE" == update ]] || return 0
  [[ -f "$agents" ]] || return 0
  grep -Fq "$start" "$agents" || return 0
  grep -Fq "$end" "$agents" || return 0

  before="$(mktemp)"
  block="$(mktemp)"
  after="$(mktemp)"
  tmp="$(mktemp)"
  awk -v marker="$start" 'index($0, marker) { exit } { print }' \
    "$agents" > "$before"
  sed -n "/$start/,/$end/p" "$SRC_DIR/AGENTS.md" > "$block"
  awk -v marker="$end" 'seen { print } index($0, marker) { seen = 1 }' \
    "$agents" > "$after"
  {
    cat "$before"
    cat "$block"
    cat "$after"
  } > "$tmp"
  cp "$tmp" "$agents"
  rm -f "$before" "$block" "$after" "$tmp"
  echo "  refreshed: managed standing rules in AGENTS.md"
}

render_strict_settings() {
  local dst="$1"
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
    "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/statusline.sh"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/branch-check.sh"
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
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/block-destructive.sh"
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
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/format-after-edit.sh --strict"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/specs-status.sh --hook"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/context-reminder.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/gate-on-stop.sh"
          }
        ]
      }
    ]
  }
}
JSON
}

# render_no_stop_settings: the default settings minus the Stop hook, for
# --no-stop-gate. A third copy of the settings file (with the default file
# and the strict heredoc above); the smoke test greps all variants for the
# secrets read-deny and status line so they can't drift silently.
render_no_stop_settings() {
  local dst="$1"
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
    "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/statusline.sh"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/branch-check.sh"
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
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/block-destructive.sh"
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
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/format-after-edit.sh"
          }
        ]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/specs-status.sh --hook"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR:-.}\"/.agentic/hooks/context-reminder.sh"
          }
        ]
      }
    ]
  }
}
JSON
}

render_strict_settings "$RUNTIME_DIR/settings.strict.json"
render_no_stop_settings "$RUNTIME_DIR/settings.no-stop.json"

# --- project-owned: copied once, never overwritten ---
# Preserve a pre-existing Claude-only project contract before the canonical
# AGENTS.md copy step. sync_claude_import() replaces the duplicate with the
# supported one-line Claude import after all managed files are installed.
migrate_claude_only_contract
copy AGENTS.md
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
sync .pre-commit-config.yaml

CLAUDE_SETTINGS_SOURCE="$SRC_DIR/.claude/settings.json"
CODEX_HOOKS_SOURCE="$SRC_DIR/.codex/hooks.json"
if [[ "$STRICT_HOOKS" == 1 ]]; then
  CLAUDE_SETTINGS_SOURCE="$RUNTIME_DIR/settings.strict.json"
  CODEX_HOOKS_SOURCE="$SRC_DIR/.codex/hooks.strict.json"
elif [[ "$NO_STOP_GATE" == 1 ]]; then
  CLAUDE_SETTINGS_SOURCE="$RUNTIME_DIR/settings.no-stop.json"
  CODEX_HOOKS_SOURCE="$SRC_DIR/.codex/hooks.no-stop.json"
fi

sync_protected_config \
  .claude/settings.json "$CLAUDE_SETTINGS_SOURCE" CLAUDE_SETTINGS_HASH
CLAUDE_SETTINGS_APPLIED="$LAST_PROTECTED_APPLIED"
sync_protected_config \
  .codex/config.toml "$SRC_DIR/.codex/config.toml" CODEX_CONFIG_HASH
sync_protected_config \
  .codex/hooks.json "$CODEX_HOOKS_SOURCE" CODEX_HOOKS_HASH
CODEX_HOOKS_APPLIED="$LAST_PROTECTED_APPLIED"
if [[ "$STRICT_HOOKS" == 1 && "$CLAUDE_SETTINGS_APPLIED" == 1 &&
  "$CODEX_HOOKS_APPLIED" == 1 ]]; then
  STRICT_HOOKS_APPLIED=1
elif [[ "$NO_STOP_GATE" == 1 && "$CLAUDE_SETTINGS_APPLIED" == 1 &&
  "$CODEX_HOOKS_APPLIED" == 1 ]]; then
  NO_STOP_GATE_APPLIED=1
fi

sync .codex/rules/safety.rules
sync .agentic/hooks/branch-check.sh
sync .agentic/hooks/block-destructive.sh
sync .agentic/hooks/context-reminder.sh
sync .agentic/hooks/format-after-edit.sh
sync .agentic/hooks/statusline.sh
sync .agentic/hooks/specs-status.sh
sync .agentic/hooks/closeout-check.sh
sync .agentic/hooks/strip-ai-attribution.sh
# The Stop gate is on by default. --no-stop-gate omits it only when both
# protected client configs accepted their no-Stop variants. A customized
# config may be preserved with its Stop entry, in which case its target must
# remain installed until the project removes that entry.
if [[ "$NO_STOP_GATE" == 0 ]] || client_config_references_stop_gate; then
  sync .agentic/hooks/gate-on-stop.sh
  if [[ "$NO_STOP_GATE" == 1 ]]; then
    echo "  WARNING: retaining Stop gate script: .agentic/hooks/gate-on-stop.sh"
    echo "           A preserved client config still references it; remove that entry by hand."
  fi
fi
# Standing policy lives once in canonical AGENTS.md. Claude imports that file
# through CLAUDE.md; there is no duplicate .claude/rules adapter layer.
sync .claude/agents/planner.md
sync .codex/agents/planner.toml
sync .claude/agents/test-first.md
sync .codex/agents/test-first.toml
sync .claude/agents/reviewer.md
sync .codex/agents/reviewer.toml
sync .claude/commands/spec.md
sync .agents/skills/spec/SKILL.md
sync .claude/commands/plan.md
sync .agents/skills/plan/SKILL.md
sync .claude/commands/test-first.md
sync .agents/skills/test-first/SKILL.md
sync .claude/commands/review-check.md
sync .agents/skills/review-check/SKILL.md
sync .claude/commands/review.md
sync .agents/skills/review/SKILL.md
sync docs/specs/README.md
sync docs/project-types.md
sync docs/codex-cli.md
sync .github/workflows/ci.yml
sync .github/pull_request_template.md
sync .github/ISSUE_TEMPLATE/feature.yml
sync .github/ISSUE_TEMPLATE/bug.yml

# --- managed: default attended Python workflow ---
if [[ "$PROFILE" != minimal ]]; then
  sync .claude/agents/analyzer.md
  sync .codex/agents/analyzer.toml
  sync .claude/agents/reviewer-adversarial.md
  sync .codex/agents/reviewer-adversarial.toml
  sync .claude/commands/product-spec.md
  sync .agents/skills/product-spec/SKILL.md
  sync .claude/commands/specs-status.md
  sync .agents/skills/specs-status/SKILL.md
  sync .claude/commands/scope-check.md
  sync .agents/skills/scope-check/SKILL.md
  sync .claude/commands/clarify.md
  sync .agents/skills/clarify/SKILL.md
  sync .claude/commands/adr.md
  sync .agents/skills/adr/SKILL.md
  sync .claude/commands/analyze.md
  sync .agents/skills/analyze/SKILL.md
  sync .claude/commands/review-adversarial.md
  sync .agents/skills/review-adversarial/SKILL.md
  sync .claude/skills/python-module-split/SKILL.md
  sync .agents/skills/python-module-split/SKILL.md
  sync .claude/skills/python-docstrings/SKILL.md
  sync .agents/skills/python-docstrings/SKILL.md
  sync .claude/skills/dependency-hygiene/SKILL.md
  sync .agents/skills/dependency-hygiene/SKILL.md
  sync docs/adr/README.md
  sync docs/workflow-diagram.md
  sync .github/dependabot.yml
fi

# --- managed: advanced docs and full command surface ---
if [[ "$EFFECTIVE_ADVANCED_DOCS" == 1 ]]; then
  sync docs/parallel-agents.md
  sync docs/plugin-packaging.md
  sync docs/serena-setup.md
  sync docs/evals.md
  sync docs/llm-product.md
  sync docs/local-executor.md
fi

if [[ "$PROFILE" == full ]]; then
  sync .claude/commands/security.md
  sync .agents/skills/security/SKILL.md
  sync .claude/commands/performance.md
  sync .agents/skills/performance/SKILL.md
  sync .claude/commands/eval.md
  sync .agents/skills/eval/SKILL.md
  sync .claude/commands/delegate.md
  sync .agents/skills/delegate/SKILL.md
  sync .github/workflows/claude-review.yml.example
fi

prune_profile_transition() {
  local rel
  local previous_has_advanced=0
  local selected_has_advanced=0
  local core_files=(
    .claude/agents/analyzer.md
    .codex/agents/analyzer.toml
    .claude/agents/reviewer-adversarial.md
    .codex/agents/reviewer-adversarial.toml
    .claude/commands/product-spec.md
    .agents/skills/product-spec/SKILL.md
    .claude/commands/specs-status.md
    .agents/skills/specs-status/SKILL.md
    .claude/commands/scope-check.md
    .agents/skills/scope-check/SKILL.md
    .claude/commands/clarify.md
    .agents/skills/clarify/SKILL.md
    .claude/commands/adr.md
    .agents/skills/adr/SKILL.md
    .claude/commands/analyze.md
    .agents/skills/analyze/SKILL.md
    .claude/commands/review-adversarial.md
    .agents/skills/review-adversarial/SKILL.md
    .claude/skills/python-module-split/SKILL.md
    .agents/skills/python-module-split/SKILL.md
    .claude/skills/python-docstrings/SKILL.md
    .agents/skills/python-docstrings/SKILL.md
    .claude/skills/dependency-hygiene/SKILL.md
    .agents/skills/dependency-hygiene/SKILL.md
    docs/adr/README.md
    docs/workflow-diagram.md
    .github/dependabot.yml
  )
  local full_files=(
    .claude/commands/security.md
    .agents/skills/security/SKILL.md
    .claude/commands/performance.md
    .agents/skills/performance/SKILL.md
    .claude/commands/eval.md
    .agents/skills/eval/SKILL.md
    .claude/commands/delegate.md
    .agents/skills/delegate/SKILL.md
    .github/workflows/claude-review.yml.example
  )
  local advanced_files=(
    docs/parallel-agents.md
    docs/plugin-packaging.md
    docs/serena-setup.md
    docs/evals.md
    docs/llm-product.md
    docs/local-executor.md
  )

  [[ "$MODE" == update ]] || return 0

  if [[ "$PROFILE_EXPLICIT" == 1 && "$PREVIOUS_PROFILE" != "$PROFILE" &&
    "$PROFILE" == minimal ]]; then
    for rel in "${core_files[@]}"; do
      prune_managed_file "$rel"
    done
  fi
  if [[ "$PROFILE_EXPLICIT" == 1 && "$PREVIOUS_PROFILE" != "$PROFILE" &&
    "$PREVIOUS_PROFILE" == full && "$PROFILE" != full ]]; then
    for rel in "${full_files[@]}"; do
      prune_managed_file "$rel"
    done
  fi

  if [[ "$PREVIOUS_PROFILE" == full || "$PREVIOUS_ADVANCED_DOCS" == 1 ]]; then
    previous_has_advanced=1
  fi
  if [[ "$EFFECTIVE_ADVANCED_DOCS" == 1 ]]; then
    selected_has_advanced=1
  fi
  if [[ "$previous_has_advanced" == 1 && "$selected_has_advanced" == 0 &&
    ("$ADVANCED_DOCS_EXPLICIT" == 1 ||
      ("$PROFILE_EXPLICIT" == 1 && "$PREVIOUS_PROFILE" != "$PROFILE")) ]]; then
    for rel in "${advanced_files[@]}"; do
      prune_managed_file "$rel"
    done
  fi
}

write_bootstrap_state() {
  local state_tmp="$RUNTIME_DIR/scaffold-state"
  local manifest_tmp="$RUNTIME_DIR/scaffold-managed-files.sorted"

  mkdir -p "$DST_DIR/.agentic"
  {
    printf '# agentic-scaffold bootstrap state v1\n'
    printf 'PROFILE=%s\n' "$PROFILE"
    printf 'STRICT_HOOKS=%s\n' "$STRICT_HOOKS"
    printf 'NO_STOP_GATE=%s\n' "$NO_STOP_GATE"
    printf 'ADVANCED_DOCS=%s\n' "$ADVANCED_DOCS"
    printf 'CLAUDE_SETTINGS_HASH=%s\n' "$CLAUDE_SETTINGS_HASH"
    printf 'CODEX_CONFIG_HASH=%s\n' "$CODEX_CONFIG_HASH"
    printf 'CODEX_HOOKS_HASH=%s\n' "$CODEX_HOOKS_HASH"
  } > "$state_tmp"
  cp "$state_tmp" "$STATE_FILE"

  LC_ALL=C sort -u "$NEXT_MANAGED_FILES" > "$manifest_tmp"
  cp "$manifest_tmp" "$MANAGED_FILES_FILE"
  echo "  recorded: .agentic/scaffold-state + scaffold-managed-files"
}

prune_profile_transition
if [[ "$MODE" == update && "$NO_STOP_GATE" == 1 ]] &&
  ! client_config_references_stop_gate; then
  prune_managed_file .agentic/hooks/gate-on-stop.sh
fi

# Intentionally NOT copied (opt-in per project):
#   .claude/agents/optional/security-reviewer.md     — for projects with a network
#   .codex/agents/optional/security-reviewer.toml    — matching Codex adapter
#     surface, auth, untrusted input, secrets, or external deserialization.
#   .claude/agents/optional/performance-reviewer.md  — for projects with a hot path,
#   .codex/agents/optional/performance-reviewer.toml — matching Codex adapter
#     DB queries on user-sized data, async code, migrations on large tables, or any
#     latency SLO.
#   .claude/agents/optional/evaluator.md             — for projects whose product
#   .codex/agents/optional/evaluator.toml            — matching Codex adapter
#     contains an LLM/AI surface (summarizer, RAG answer, chatbot, agent trajectory);
#     authors and runs evals that judge output quality. See docs/evals.md.
#   See $SRC_DIR/.claude/agents/optional/ for what's available.

migrate_legacy_contract
migrate_duplicate_contract
sync_claude_import
migrate_stray_claude_rules
refresh_managed_contract_rules
write_bootstrap_state

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
    echo "still require explicit copies from both clients' agents/optional/."
    ;;
esac
echo
if [[ "$STRICT_HOOKS_APPLIED" == 1 ]]; then
  echo "Strict hooks are enabled. Edit hooks run format + lint + mypy, and the"
  echo "Stop hook blocks ending a turn while the local gate is red."
elif [[ "$STRICT_HOOKS" == 1 ]]; then
  echo "Strict hooks were selected, but customized client hook configuration was"
  echo "preserved. Merge the strict hook entries by hand where the warning named it."
elif [[ "$NO_STOP_GATE_APPLIED" == 1 ]]; then
  echo "Stop gate removed (--no-stop-gate). Edit hooks format only; /review-check"
  echo "and CI are the hard quality gates."
elif [[ "$NO_STOP_GATE" == 1 ]]; then
  echo "--no-stop-gate was selected, but customized client hook configuration was"
  echo "preserved. Remove the Stop entry by hand where the warning named it."
else
  echo "Stop gate is on (default): the Stop hook blocks ending a turn while src/"
  echo "has pending changes and ruff/mypy/pytest are red. Edit hooks format only;"
  echo "add --strict-hooks for lint + mypy after every edit, or --no-stop-gate to"
  echo "remove the gate."
fi
echo
echo "Read WORKFLOW.md next — it's in your project root and is the source"
echo "of truth for what to do: day-zero setup and the per-feature loop."
echo "For Codex, review and trust the project .codex layer and hooks, then use"
echo "the workflow skills as \$spec, \$plan, \$test-first, and \$review-check."
echo "Pull future template improvements:  bash $SRC_DIR/bootstrap.sh --update"
