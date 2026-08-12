#!/usr/bin/env bash
# Install the lightweight, stack-neutral dual-client scaffold.
#
# Usage:
#   bash path/to/agentic-scaffold/generic/bootstrap.sh
#   bash path/to/agentic-scaffold/generic/bootstrap.sh --update
#
# Project-owned AGENTS.md and README.md are created once and never
# overwritten. CLAUDE.md is a one-line compatibility import of AGENTS.md
# when it is safe to create or migrate. Managed client config, hooks, rules,
# and the Codex guide are refreshed by --update.

set -euo pipefail

MODE="install"
case "${1:-}" in
  "") ;;
  --update) MODE="update" ;;
  -h | --help)
    sed -n '2,10p' "$0"
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1  (run with --help)" >&2
    exit 1
    ;;
esac

GENERIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$GENERIC_DIR/.." && pwd)"
SHARED_DIR="$REPO_DIR/shared"
DST_DIR="$(pwd)"

if [[ "$DST_DIR" == "$REPO_DIR" || "$DST_DIR" == "$GENERIC_DIR" ]]; then
  echo "ERROR: refusing to bootstrap into the scaffold source directory." >&2
  exit 1
fi

sync_from() {
  local source="$1"
  local target="$2"
  local destination="$DST_DIR/$target"
  local existed=0

  [[ -e "$destination" ]] && existed=1
  if [[ "$existed" == 1 && "$MODE" == "install" ]]; then
    echo "  skip (exists): $target"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  cp -R "$source" "$destination"
  if [[ "$existed" == 1 ]]; then
    echo "  updated: $target"
  else
    echo "  copied: $target"
  fi
}

hash_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

sync_config_from() {
  local source="$1"
  local target="$2"
  local destination="$DST_DIR/$target"
  local state_dir="$DST_DIR/.agentic/scaffold-state"
  local state_key="${target//\//__}"
  local state_file="$state_dir/$state_key.sha256"
  local current_hash recorded_hash

  if [[ ! -e "$destination" ]]; then
    mkdir -p "$(dirname "$destination")" "$state_dir"
    cp "$source" "$destination"
    hash_file "$destination" >"$state_file"
    echo "  copied: $target"
    return
  fi

  if [[ "$MODE" == "install" ]]; then
    echo "  skip (exists): $target"
    return
  fi

  current_hash="$(hash_file "$destination")"
  recorded_hash=""
  [[ -f "$state_file" ]] && recorded_hash="$(cat "$state_file")"

  if [[ -n "$recorded_hash" && "$current_hash" != "$recorded_hash" ]]; then
    echo "  skip (customized): $target"
    echo "    Merge scaffold updates manually; local configuration was preserved."
    return
  fi
  if [[ -z "$recorded_hash" ]] && ! cmp -s "$source" "$destination"; then
    echo "  skip (ownership unknown): $target"
    echo "    No prior scaffold hash exists; local configuration was preserved."
    return
  fi

  mkdir -p "$state_dir"
  cp "$source" "$destination"
  hash_file "$destination" >"$state_file"
  echo "  updated: $target"
}

copy_readme() {
  local destination="$DST_DIR/README.md"
  if [[ -e "$destination" ]]; then
    echo "  skip (project-owned, exists): README.md"
    return
  fi
  cp "$REPO_DIR/README.md.template" "$destination"
  echo "  copied: README.md.template -> README.md"
}

install_contracts() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"

  if [[ ! -e "$agents" && ! -e "$claude" ]]; then
    cp "$REPO_DIR/AGENTS.md.template" "$agents"
    cp "$REPO_DIR/CLAUDE.md.template" "$claude"
    echo "  copied: AGENTS.md + CLAUDE.md"
  elif [[ -e "$agents" && ! -e "$claude" ]]; then
    printf '%s\n' '@AGENTS.md' >"$claude"
    echo "  created: CLAUDE.md imports existing AGENTS.md"
  elif [[ ! -e "$agents" && -e "$claude" ]]; then
    if cmp -s <(printf '%s\n' '@AGENTS.md') "$claude"; then
      cp "$REPO_DIR/AGENTS.md.template" "$agents"
      echo "  repaired: CLAUDE.md imported a missing AGENTS.md; installed the template"
    else
      cp "$claude" "$agents"
      echo "  migrated: existing CLAUDE.md -> canonical AGENTS.md"
    fi
    printf '%s\n' '@AGENTS.md' >"$claude"
    echo "  created: CLAUDE.md import shim"
  else
    echo "  skip (project-owned, exist): AGENTS.md + CLAUDE.md"
  fi
}

migrate_legacy_pointer() {
  local agents="$DST_DIR/AGENTS.md"
  local claude="$DST_DIR/CLAUDE.md"

  [[ "$MODE" == "update" ]] || return 0
  [[ -f "$agents" && -f "$claude" ]] || return 0
  if grep -q 'authoritative content lives in `CLAUDE.md`' "$agents" \
    && grep -q 'portable fallback' "$agents"; then
    cp "$claude" "$agents"
    printf '%s\n' '@AGENTS.md' >"$claude"
    echo "  migrated: legacy pointer to canonical AGENTS.md + Claude import"
  elif cmp -s "$agents" "$claude"; then
    printf '%s\n' '@AGENTS.md' >"$claude"
    echo "  migrated: duplicate contracts to canonical AGENTS.md + Claude import"
  elif [[ "$(cat "$claude")" != '@AGENTS.md' ]]; then
    echo "  warning: project-owned AGENTS.md and CLAUDE.md differ; preserved both"
    echo "    Move shared policy into AGENTS.md, then set CLAUDE.md to: @AGENTS.md"
  fi
}

# The no-AI-attribution rule is stack-neutral, so it cannot ride on the
# Python flavor's pre-commit config. Wire the strip directly as a git
# commit-msg hook instead: it is the only enforcement point both clients
# share, since neither client's own hooks can see a commit message.
# A project that already manages commit-msg is left alone.
install_commit_msg_hook() {
  local git_dir hook
  git_dir="$(git -C "$DST_DIR" rev-parse --git-dir 2>/dev/null || true)"
  if [[ -z "$git_dir" ]]; then
    echo "  skip (not a git repo): commit-msg hook"
    return
  fi
  [[ "$git_dir" != /* ]] && git_dir="$DST_DIR/$git_dir"
  hook="$git_dir/hooks/commit-msg"

  if [[ -e "$hook" ]] && ! grep -q 'strip-ai-attribution' "$hook"; then
    echo "  skip (project-owned): commit-msg hook"
    echo "    Add: .agentic/hooks/strip-ai-attribution.sh \"\$1\""
    return
  fi

  mkdir -p "$(dirname "$hook")"
  cat >"$hook" <<'HOOK'
#!/usr/bin/env bash
# Managed by agentic-scaffold. Strips AI co-author trailers and
# generated-with footers so they never enter git history. AI assistance
# is acknowledged once in README.md.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
[[ -x "$root/.agentic/hooks/strip-ai-attribution.sh" ]] || exit 0
exec "$root/.agentic/hooks/strip-ai-attribution.sh" "$1"
HOOK
  chmod +x "$hook"
  echo "  installed: .git/hooks/commit-msg (strip-ai-attribution)"
}

if [[ "$MODE" == "update" ]]; then
  echo "Updating generic dual-client scaffolding"
else
  echo "Bootstrapping generic dual-client scaffolding"
fi
echo "  into: $DST_DIR"
echo

install_contracts
copy_readme

sync_config_from "$GENERIC_DIR/.claude/settings.json" ".claude/settings.json"
sync_config_from "$GENERIC_DIR/.codex/hooks.json" ".codex/hooks.json"
sync_config_from "$SHARED_DIR/codex/config.toml" ".codex/config.toml"
sync_from "$SHARED_DIR/codex/safety.rules" ".codex/rules/safety.rules"
sync_from "$SHARED_DIR/hooks/branch-check.sh" \
  ".agentic/hooks/branch-check.sh"
sync_from "$SHARED_DIR/hooks/block-destructive.sh" \
  ".agentic/hooks/block-destructive.sh"
sync_from "$SHARED_DIR/hooks/context-reminder.sh" \
  ".agentic/hooks/context-reminder.sh"
sync_from "$SHARED_DIR/hooks/statusline.sh" \
  ".agentic/hooks/statusline.sh"
sync_from "$SHARED_DIR/hooks/strip-ai-attribution.sh" \
  ".agentic/hooks/strip-ai-attribution.sh"
chmod +x "$DST_DIR"/.agentic/hooks/*.sh
sync_from "$GENERIC_DIR/docs/codex-cli.md" "docs/codex-cli.md"

install_commit_msg_hook

migrate_legacy_pointer

echo
if [[ "$MODE" == "update" ]]; then
  echo "Update complete. Review managed-file changes with: git diff"
else
  echo "Done. Fill every {{PLACEHOLDER}} in AGENTS.md and README.md."
  echo "CLAUDE.md imports AGENTS.md; keep shared policy in AGENTS.md."
  echo "For Codex, trust the project .codex layer and review hooks with /hooks."
fi
