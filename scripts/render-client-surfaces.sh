#!/usr/bin/env bash
# Render the generic templates and every stack flavor from shared sources.
#
# Sources:
#   generic/project-contract.md  the stack-neutral contract templates
#   shared/                      stack-neutral hooks and Codex policy
#   workflow/                    the loop: contract, commands, roles, standing
#                                rules, workflow hooks, client config, docs
#   stacks/<name>/               one toolchain: gate runner, manifest, rules,
#                                skills, project files, starter layout
#
# Output: <name>/ for every stacks/<name>/ (python/, typescript/, custom/).
# Each
# is generated whole and replaced on every run; a file added straight to a
# rendered directory disappears on the next render. Edit the sources, run
# this script, then commit sources and rendered output together.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_DIR="$REPO_DIR/workflow"
GENERIC_DIR="$REPO_DIR/generic"
SHARED_DIR="$REPO_DIR/shared"
STACKS_DIR="$REPO_DIR/stacks"

frontmatter_value() {
  local key="$1"
  local file="$2"
  sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -1
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

# --- per-stack rendering; every function takes the stack source dir and the
# build dir being assembled ---

# The canonical contract: the workflow contract with the stack's blocks
# spliced in at the markers, then every standing rule (workflow rules plus
# the stack's, sorted by file name) in the managed block.
render_project_contract() {
  local stack_dir="$1"
  local build="$2"
  local agents="$build/AGENTS.md"
  local rules=()
  local source

  awk -v stack_block="$stack_dir/contract-stack.md" \
      -v dont_touch="$stack_dir/contract-dont-touch.md" '
    /<!-- agentic-scaffold:stack -->/ {
      while ((getline line < stack_block) > 0) print line
      close(stack_block)
      next
    }
    /<!-- agentic-scaffold:stack-dont-touch -->/ {
      while ((getline line < dont_touch) > 0) print line
      close(dont_touch)
      next
    }
    { print }
  ' "$WORKFLOW_DIR/project-contract.md" > "$agents"

  while IFS= read -r source; do
    rules+=("$source")
  done < <(
    {
      ls "$WORKFLOW_DIR"/rules/*.md
      [[ -d "$stack_dir/rules" ]] && ls "$stack_dir"/rules/*.md
    } | awk -F/ '{ print $NF "\t" $0 }' | LC_ALL=C sort | cut -f2-
  )

  {
    printf '\n<!-- agentic-scaffold:standing-rules:start -->\n'
    printf '\n## Standing rules\n\n'
    printf 'These rules are authoritative for every client. They live here once\n'
    printf 'rather than in duplicate client-specific policy files. Do not\n'
    printf 'hand-edit this marked block;\n'
    printf '`bootstrap.sh --update` refreshes it while preserving content outside\n'
    printf 'the markers.\n'
    for source in "${rules[@]}"; do
      printf '\n---\n\n'
      markdown_body "$source"
    done
    printf '\n<!-- agentic-scaffold:standing-rules:end -->\n'
  } >> "$agents"

  printf '%s\n' '@AGENTS.md' > "$build/CLAUDE.md"
}

render_command() {
  local source="$1"
  local build="$2"
  local name description claude_target codex_target
  name="$(basename "$source" .md)"
  description="$(frontmatter_value description "$source")"
  claude_target="$build/.claude/commands/$name.md"
  codex_target="$build/.agents/skills/$name/SKILL.md"

  mkdir -p "$(dirname "$claude_target")" "$(dirname "$codex_target")"
  cp "$source" "$claude_target"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf '%s\n\n' '---'
    printf 'In these shared instructions, `$ARGUMENTS` means the arguments supplied with this skill invocation. Any `/<name>` cross-reference names another workflow; invoke the matching `$<name>` repository skill in Codex.\n\n'
    markdown_body "$source"
  } > "$codex_target"
}

render_skill() {
  local source="$1"
  local build="$2"
  local name
  name="$(basename "$(dirname "$source")")"
  mkdir -p "$build/.claude/skills/$name" "$build/.agents/skills/$name"
  cp "$source" "$build/.claude/skills/$name/SKILL.md"
  cp "$source" "$build/.agents/skills/$name/SKILL.md"
}

render_role() {
  local source="$1"
  local optional="$2"
  local build="$3"
  local name description sandbox claude_dir codex_dir
  local escaped_description body
  name="$(frontmatter_value name "$source")"
  description="$(frontmatter_value description "$source")"

  case "$name" in
    test-first | evaluator) sandbox="workspace-write" ;;
    *) sandbox="read-only" ;;
  esac

  claude_dir="$build/.claude/agents"
  codex_dir="$build/.codex/agents"
  if [[ "$optional" == 1 ]]; then
    claude_dir="$claude_dir/optional"
    codex_dir="$codex_dir/optional"
  fi
  mkdir -p "$claude_dir" "$codex_dir"
  cp "$source" "$claude_dir/$name.md"
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
  } > "$codex_dir/$name.toml"
}

# Hooks: byte-identical copies of shared/hooks/ and workflow/hooks/, plus the
# stack's gate runner. Kept byte-identical on purpose so the validator can
# cmp them and catch an edit made to the copy instead of the source; no
# provenance header is stamped in.
render_hooks() {
  local stack_dir="$1"
  local build="$2"
  local source
  mkdir -p "$build/.agentic/hooks"
  for source in "$SHARED_DIR"/hooks/*.sh "$WORKFLOW_DIR"/hooks/*.sh; do
    cp "$source" "$build/.agentic/hooks/$(basename "$source")"
  done
  cp "$stack_dir/toolchain.sh" "$build/.agentic/toolchain.sh"
  chmod +x "$build"/.agentic/hooks/*.sh "$build/.agentic/toolchain.sh"
}

render_client_config() {
  local build="$1"
  mkdir -p "$build/.claude" "$build/.codex/rules"
  cp "$WORKFLOW_DIR/client/claude/settings.json" "$build/.claude/settings.json"
  cp "$WORKFLOW_DIR"/client/codex/hooks*.json "$build/.codex/"
  cp "$SHARED_DIR/codex/config.toml" "$build/.codex/config.toml"
  cp "$SHARED_DIR/codex/safety.rules" "$build/.codex/rules/safety.rules"
}

# Workflow files that ship into a project as-is, and the stack's own
# project files (manifest, ignore rules, pre-commit, CI, Dependabot) laid
# over them. The stack wins on any path both provide.
render_project_files() {
  local stack_dir="$1"
  local build="$2"
  local entry
  for entry in WORKFLOW.md README.md.template subdir-AGENTS.md.example \
    subdir-CLAUDE.md.example; do
    cp "$WORKFLOW_DIR/$entry" "$build/$entry"
  done
  cp -R "$WORKFLOW_DIR/docs" "$build/docs"
  mkdir -p "$build/.github"
  cp -R "$WORKFLOW_DIR/github/." "$build/.github/"
  cp -R "$stack_dir/project/." "$build/"
  # A stack with no starter layout (custom: the project brings its own
  # source tree) has no starter/ to render.
  if [[ -d "$stack_dir/starter" ]]; then
    cp -R "$stack_dir/starter" "$build/starter"
  fi
  cp "$stack_dir/stack.sh" "$build/stack.sh"
  cp "$stack_dir/README.md" "$build/README.md"
}

render_bootstrap_wrapper() {
  local stack="$1"
  local build="$2"
  cat > "$build/bootstrap.sh" <<EOF
#!/usr/bin/env bash
# Rendered entry point for the ${stack} flavor. The body is
# scripts/bootstrap-stack.sh; edit that script or stacks/${stack}/ and re-run
# scripts/render-client-surfaces.sh. Usage is documented in the body:
#   bash path/to/agentic-scaffold/${stack}/bootstrap.sh --help
REPO_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "\$REPO_DIR/scripts/bootstrap-stack.sh" --stack ${stack} "\$@"
EOF
  chmod +x "$build/bootstrap.sh"
}

render_stack() {
  local stack="$1"
  local stack_dir="$STACKS_DIR/$stack"
  local out="$REPO_DIR/$stack"
  local build source
  build="$(mktemp -d)"

  render_project_contract "$stack_dir" "$build"
  for source in "$WORKFLOW_DIR"/commands/*.md; do
    render_command "$source" "$build"
  done
  if [[ -d "$stack_dir/skills" ]]; then
    for source in "$stack_dir"/skills/*/SKILL.md; do
      render_skill "$source" "$build"
    done
  fi
  for source in "$WORKFLOW_DIR"/roles/*.md; do
    render_role "$source" 0 "$build"
  done
  for source in "$WORKFLOW_DIR"/roles/optional/*.md; do
    render_role "$source" 1 "$build"
  done
  render_hooks "$stack_dir" "$build"
  render_client_config "$build"
  render_project_files "$stack_dir" "$build"
  render_bootstrap_wrapper "$stack" "$build"

  # Replace the rendered tree whole so removed sources cannot leave stale
  # commands, skills, agents, hooks, or docs behind.
  rm -rf "$out"
  mkdir -p "$out"
  cp -R "$build/." "$out/"
  rm -rf "$build"
  echo "Rendered $stack/ from workflow/ and stacks/$stack/."
}

render_generic_contract
for stack_dir in "$STACKS_DIR"/*/; do
  render_stack "$(basename "$stack_dir")"
done
echo "Rendered generic templates and every stack flavor."
