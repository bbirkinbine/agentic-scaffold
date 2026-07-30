#!/usr/bin/env bash
# Render generic, Claude Code, and Codex adapters from shared sources.
#
# generic/project-contract.md owns the stack-neutral contract templates;
# shared/ owns stack-neutral hooks and Codex policy; python/workflow/ owns
# the Python contract, workflows, skills, role prompts, and standing rules.
# Run this script after changing a source file, then commit the source and
# rendered adapters.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_DIR="$REPO_DIR/python"
WORKFLOW_DIR="$PYTHON_DIR/workflow"
GENERIC_DIR="$REPO_DIR/generic"
SHARED_DIR="$REPO_DIR/shared"

frontmatter_value() {
  local key="$1"
  local file="$2"
  sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -1
}

prune_files() {
  local directory="$1"
  local pattern="$2"

  [[ -d "$directory" ]] || return 0
  find "$directory" -type f -name "$pattern" -delete
}

# Emit a source file with its YAML frontmatter removed. Frontmatter only
# counts when the file opens with `---`; a file without it is emitted whole.
# Counting `---` lines anywhere instead would silently render every
# frontmatter-less source (the standing rules) as an empty string, and would
# swallow horizontal rules in bodies that do have frontmatter.
markdown_body() {
  local file="$1"
  awk '
    NR == 1 && /^---[[:space:]]*$/ { in_frontmatter = 1; next }
    in_frontmatter && /^---[[:space:]]*$/ { in_frontmatter = 0; next }
    in_frontmatter { next }
    { print }
  ' "$file"
}

toml_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

render_generic_contract() {
  cp "$GENERIC_DIR/project-contract.md" "$REPO_DIR/AGENTS.md.template"
  printf '%s\n' '@AGENTS.md' > "$REPO_DIR/CLAUDE.md.template"
}

render_scaffold_contract() {
  # Codex does not follow a pointer from AGENTS.md into CLAUDE.md. Keep the
  # scaffold repository itself on the same model as generated projects:
  # AGENTS.md is complete, and CLAUDE.md is the authoring source copied here
  # so the existing project history remains easy to review.
  cp "$REPO_DIR/CLAUDE.md" "$REPO_DIR/AGENTS.md"
}

render_shared_surfaces() {
  local source

  # python/.agentic/hooks/ holds two kinds of file: byte-identical copies of
  # shared/hooks/ (rewritten here on every run) and Python-only hooks that
  # live there as sources. The copies are kept byte-identical on purpose so
  # validate-codex-adapters.sh can cmp them and catch an edit made to the
  # copy instead of the source; do not stamp a provenance header into them.
  mkdir -p "$PYTHON_DIR/.agentic/hooks" "$PYTHON_DIR/.codex/rules"
  for source in "$SHARED_DIR"/hooks/*.sh; do
    cp "$source" "$PYTHON_DIR/.agentic/hooks/$(basename "$source")"
    chmod +x "$PYTHON_DIR/.agentic/hooks/$(basename "$source")"
  done
  cp "$SHARED_DIR/codex/config.toml" "$PYTHON_DIR/.codex/config.toml"
  cp "$SHARED_DIR/codex/safety.rules" \
    "$PYTHON_DIR/.codex/rules/safety.rules"
}

render_project_contract() {
  local agents="$PYTHON_DIR/AGENTS.md"
  local claude="$PYTHON_DIR/CLAUDE.md"
  local source tmp
  tmp="$(mktemp)"

  cp "$WORKFLOW_DIR/project-contract.md" "$tmp"
  {
    printf '\n<!-- agentic-scaffold:standing-rules:start -->\n'
    printf '\n## Standing rules\n\n'
    printf 'These rules are authoritative for every client. They live here once\n'
    printf 'rather than in duplicate client-specific policy files. Do not\n'
    printf 'hand-edit this marked block;\n'
    printf '`bootstrap.sh --update` refreshes it while preserving content outside\n'
    printf 'the markers.\n'
    for source in "$WORKFLOW_DIR"/rules/*.md; do
      printf '\n---\n\n'
      markdown_body "$source"
    done
    printf '\n<!-- agentic-scaffold:standing-rules:end -->\n'
  } >> "$tmp"

  cp "$tmp" "$agents"
  printf '%s\n' '@AGENTS.md' > "$claude"
  rm -f "$tmp"
}

render_command() {
  local source="$1"
  local name description claude_target codex_target tmp
  name="$(basename "$source" .md)"
  description="$(frontmatter_value description "$source")"
  claude_target="$PYTHON_DIR/.claude/commands/$name.md"
  codex_target="$PYTHON_DIR/.agents/skills/$name/SKILL.md"
  tmp="$(mktemp)"

  mkdir -p "$(dirname "$claude_target")" "$(dirname "$codex_target")"
  cp "$source" "$claude_target"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf '%s\n\n' '---'
    printf 'In these shared instructions, `$ARGUMENTS` means the arguments supplied with this skill invocation. Any `/<name>` cross-reference names another workflow; invoke the matching `$<name>` repository skill in Codex.\n\n'
    markdown_body "$source"
  } > "$tmp"
  cp "$tmp" "$codex_target"
  rm -f "$tmp"
}

render_skill() {
  local source="$1"
  local name claude_target codex_target
  name="$(basename "$(dirname "$source")")"
  claude_target="$PYTHON_DIR/.claude/skills/$name/SKILL.md"
  codex_target="$PYTHON_DIR/.agents/skills/$name/SKILL.md"

  mkdir -p "$(dirname "$claude_target")" "$(dirname "$codex_target")"
  cp "$source" "$claude_target"
  cp "$source" "$codex_target"
}

render_role() {
  local source="$1"
  local optional="$2"
  local name description sandbox claude_dir codex_dir claude_target codex_target
  local escaped_description body tmp
  name="$(frontmatter_value name "$source")"
  description="$(frontmatter_value description "$source")"

  case "$name" in
    test-first | evaluator) sandbox="workspace-write" ;;
    *) sandbox="read-only" ;;
  esac

  claude_dir="$PYTHON_DIR/.claude/agents"
  codex_dir="$PYTHON_DIR/.codex/agents"
  if [[ "$optional" == 1 ]]; then
    claude_dir="$claude_dir/optional"
    codex_dir="$codex_dir/optional"
  fi
  claude_target="$claude_dir/$name.md"
  codex_target="$codex_dir/$name.toml"
  tmp="$(mktemp)"

  mkdir -p "$claude_dir" "$codex_dir"
  cp "$source" "$claude_target"
  escaped_description="$(printf '%s' "$description" | toml_escape)"
  body="$(markdown_body "$source")"
  {
    printf 'name = "%s"\n' "$name"
    printf 'description = "%s"\n' "$escaped_description"
    printf 'sandbox_mode = "%s"\n' "$sandbox"
    printf "developer_instructions = '''"
    printf '%s\n\n' \
      'Any /<name> workflow cross-reference in this shared role means the matching $<name> repository skill in Codex.'
    printf "%s\n'''\n" "$body"
  } > "$tmp"
  cp "$tmp" "$codex_target"
  rm -f "$tmp"
}

render_scaffold_contract
render_generic_contract
render_shared_surfaces
render_project_contract

# These directories are generated surfaces. Clear only the file types owned
# by this renderer so renamed or removed sources cannot leave discoverable
# stale commands, skills, agents, or legacy duplicate Claude rule adapters.
prune_files "$PYTHON_DIR/.claude/commands" '*.md'
prune_files "$PYTHON_DIR/.claude/skills" 'SKILL.md'
prune_files "$PYTHON_DIR/.claude/agents" '*.md'
prune_files "$PYTHON_DIR/.claude/rules" '*.md'
prune_files "$PYTHON_DIR/.agents/skills" 'SKILL.md'
prune_files "$PYTHON_DIR/.codex/agents" '*.toml'

for source in "$WORKFLOW_DIR"/commands/*.md; do
  render_command "$source"
done

for source in "$WORKFLOW_DIR"/skills/*/SKILL.md; do
  render_skill "$source"
done

for source in "$WORKFLOW_DIR"/roles/*.md; do
  render_role "$source" 0
done

for source in "$WORKFLOW_DIR"/roles/optional/*.md; do
  render_role "$source" 1
done

echo "Rendered generic, Claude Code, and Codex client surfaces."
